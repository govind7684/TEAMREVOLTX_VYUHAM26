import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/security/permissions.dart';
import '../../core/utils/validators.dart';
import '../../domain/models/incident.dart';
import '../../domain/models/road.dart';
import '../../domain/models/user.dart';
import '../../services/ai/ai_provider.dart';
import '../../services/ai/duplicate_detector.dart';
import '../../services/road_classifier.dart';
import 'incident_repository.dart';

/// RoadVision works on the same incident records as every other screen. It
/// only adds a small details table and repair photos. Staff only, and every
/// call re-checks department access through [IncidentRepository].
class RoadRepository {
  RoadRepository(
    this._db, {
    required this._incidents,
    this._classifier = const RoadClassifier(),
    this._detector = const DuplicateDetector(),
    DateTime Function()? clock,
  })  : _now = clock ?? DateTime.now;

  final Database _db;
  final IncidentRepository _incidents;
  final RoadClassifier _classifier;
  final DuplicateDetector _detector;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  int get _ts => _now().millisecondsSinceEpoch;

  void _staff(AppUser u) {
    if (!u.isStaff) throw const PermissionDeniedException('Staff access only.');
  }

  /// Loads a visible road damage report or throws NotFound / Validation.
  Future<Incident> _road(AppUser actor, String id) async {
    _staff(actor);
    final i = await _incidents.getVisible(actor, id);
    if (i.category != IncidentCategory.roadDamage) {
      throw const ValidationException(['This is not a road damage report.']);
    }
    return i;
  }

  Future<Incident> _manageable(AppUser actor, String id) async {
    final i = await _road(actor, id);
    if (!Permissions.canManage(actor, i)) {
      throw const PermissionDeniedException('You cannot manage this report.');
    }
    return i;
  }

  // ---------------------------------------------------------------- reading

  /// Open road damage reports the actor may see, worst first: priority score,
  /// then severity, then oldest. Reports closed as duplicates are left out.
  Future<List<RoadReport>> priorityList(AppUser actor) async {
    _staff(actor);
    final all = await _incidents.listVisible(actor);
    final roads = all.where((i) => i.category == IncidentCategory.roadDamage).toList();
    await _backfill(roads);
    final out = <RoadReport>[];
    for (final i in roads) {
      if (!i.status.isOpen || i.duplicateOfId != null) continue;
      out.add(await _hydrate(i));
    }
    out.sort((a, b) {
      final p = b.incident.priorityScore.compareTo(a.incident.priorityScore);
      if (p != 0) return p;
      final s = b.details.severity.rank.compareTo(a.details.severity.rank);
      if (s != 0) return s;
      return a.incident.createdAt.compareTo(b.incident.createdAt);
    });
    return out;
  }

  Future<RoadReport> getReport(AppUser actor, String id) async {
    final i = await _road(actor, id);
    await _backfill([i]);
    return _hydrate(i);
  }

  /// Creates classification rows for road reports that do not have one yet
  /// (new reports, demo data, data from before RoadVision existed).
  Future<void> _backfill(List<Incident> roads) async {
    if (roads.isEmpty) return;
    final have = (await _db.query('road_details', columns: ['incident_id']))
        .map((r) => r['incident_id'] as String)
        .toSet();
    final missing = roads.where((i) => !have.contains(i.id)).toList();
    if (missing.isEmpty) return;
    await _db.transaction((txn) async {
      for (final i in missing) {
        final a = _classifier.classify(
          description: i.description,
          peopleAffected: i.peopleAffected,
          safetyRisk: i.safetyRisk,
        );
        await txn.insert(
          'road_details',
          {
            'incident_id': i.id,
            'damage_type': a.type.name,
            'damage_source': RoadSource.rules,
            'severity': a.severity.name,
            'severity_source': RoadSource.rules,
            'updated_at': _ts,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<RoadReport> _hydrate(Incident i) async {
    final d = await _db.query('road_details',
        where: 'incident_id = ?', whereArgs: [i.id], limit: 1);
    String? assignee;
    if (i.assignedOfficerId != null) {
      final u = await _db.query('users',
          columns: ['name'], where: 'id = ?', whereArgs: [i.assignedOfficerId], limit: 1);
      assignee = u.isEmpty ? null : u.first['name'] as String;
    }
    Future<int> count(String sql, List<Object?> args) async =>
        (await _db.rawQuery(sql, args)).first['c'] as int;
    final dupes = await count(
        'SELECT COUNT(*) c FROM incidents WHERE duplicate_of_id = ?', [i.id]);
    final before = await count(
        "SELECT COUNT(*) c FROM repair_photos WHERE incident_id = ? AND kind = 'before'",
        [i.id]);
    final after = await count(
        "SELECT COUNT(*) c FROM repair_photos WHERE incident_id = ? AND kind = 'after'",
        [i.id]);
    return RoadReport(
      incident: i,
      details: RoadDetails.fromMap(d.first),
      assigneeName: assignee,
      linkedDuplicates: dupes,
      beforePhotos: before + (i.photoPath != null ? 1 : 0),
      afterPhotos: after,
    );
  }

  Future<List<RepairPhoto>> photos(AppUser actor, String incidentId) async {
    await _road(actor, incidentId);
    final rows = await _db.rawQuery('''
      SELECT p.id, p.kind, p.path, p.created_at, u.name AS who
      FROM repair_photos p JOIN users u ON u.id = p.added_by
      WHERE p.incident_id = ? ORDER BY p.created_at, p.rowid''', [incidentId]);
    return rows
        .map((r) => RepairPhoto(
              id: r['id'] as String,
              kind: PhotoKind.values.byName(r['kind'] as String),
              path: r['path'] as String,
              addedByName: r['who'] as String,
              createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
            ))
        .toList();
  }

  // ---------------------------------------------------- classification edit

  Future<void> updateClassification({
    required AppUser actor,
    required String incidentId,
    RoadDamageType? type,
    RoadSeverity? severity,
    required String reason,
  }) async {
    await _manageable(actor, incidentId);
    if (type == null && severity == null) {
      throw const ValidationException(['Choose a damage type or severity to change.']);
    }
    if (reason.trim().length < 5) {
      throw const ValidationException(['Explain the change (at least 5 characters).']);
    }
    await _backfillOne(incidentId);
    await _db.transaction((txn) async {
      await txn.update(
        'road_details',
        {
          if (type != null) 'damage_type': type.name,
          if (type != null) 'damage_source': RoadSource.officer,
          if (severity != null) 'severity': severity.name,
          if (severity != null) 'severity_source': RoadSource.officer,
          'updated_at': _ts,
        },
        where: 'incident_id = ?',
        whereArgs: [incidentId],
      );
      await txn.insert('audit_log', {
        'actor_id': actor.id,
        'action': 'road_classification_changed',
        'detail': '$incidentId: ${type?.name ?? '-'} / ${severity?.name ?? '-'}. ${reason.trim()}',
        'created_at': _ts,
      });
    });
  }

  Future<void> _backfillOne(String id) async {
    final rows = await _db.query('incidents', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isNotEmpty) await _backfill([Incident.fromMap(rows.first)]);
  }

  // -------------------------------------------------------------- duplicates

  /// Suggestions only. A person decides whether to link anything.
  Future<List<DuplicateMatch>> duplicateSuggestions(AppUser actor, String incidentId) async {
    final i = await _road(actor, incidentId);
    final rows = await _db.query('incidents',
        where: "category = 'roadDamage' AND id != ? AND duplicate_of_id IS NULL",
        whereArgs: [incidentId]);
    final visible = rows
        .map(Incident.fromMap)
        .where((o) => Permissions.canView(actor, o))
        .toList();
    return _detector.find(
      category: IncidentCategory.roadDamage,
      description: i.description,
      locationText: i.locationText,
      latitude: i.latitude,
      longitude: i.longitude,
      now: _now(),
      existing: visible,
    );
  }

  /// Closes [incidentId] as a duplicate of [ofId] (a human decision, with the
  /// reporter notified through the normal status-change path).
  Future<void> markDuplicate({
    required AppUser actor,
    required String incidentId,
    required String ofId,
    String note = '',
  }) async {
    final i = await _manageable(actor, incidentId);
    if (incidentId == ofId) {
      throw const ValidationException(['A report cannot be a duplicate of itself.']);
    }
    if (!i.status.isOpen) {
      throw const ValidationException(['Only open reports can be closed as duplicates.']);
    }
    final target = await _road(actor, ofId);
    if (!target.status.isOpen || target.duplicateOfId != null) {
      throw const ValidationException(
          ['The report to keep must be open and not itself a duplicate.']);
    }
    await _incidents.changeStatus(
      actor: actor,
      incidentId: incidentId,
      to: IncidentStatus.rejected,
      rejectionReason: 'Duplicate of $ofId.${note.trim().isEmpty ? '' : ' ${note.trim()}'}',
    );
    await _db.transaction((txn) async {
      await txn.update('incidents', {'duplicate_of_id': ofId, 'updated_at': _ts},
          where: 'id = ?', whereArgs: [incidentId]);
      await txn.insert('audit_log', {
        'actor_id': actor.id,
        'action': 'road_duplicate_linked',
        'detail': '$incidentId closed as duplicate of $ofId',
        'created_at': _ts,
      });
    });
  }

  // -------------------------------------------------------------- assignment

  Future<void> assignOfficer({
    required AppUser actor,
    required String incidentId,
    required String officerId,
  }) async {
    final i = await _manageable(actor, incidentId);
    if (!i.status.isOpen) {
      throw const ValidationException(['Only open reports can be assigned.']);
    }
    final rows = await _db.query('users',
        where: "id = ? AND role = 'officer' AND is_active = 1 AND department_id = ?",
        whereArgs: [officerId, i.departmentId],
        limit: 1);
    if (rows.isEmpty) {
      throw ValidationException(
          ['Choose an active officer in ${Departments.nameOf(i.departmentId)}.']);
    }
    final name = rows.first['name'] as String;
    await _db.transaction((txn) async {
      await txn.update('incidents', {'assigned_officer_id': officerId, 'updated_at': _ts},
          where: 'id = ?', whereArgs: [incidentId]);
      await txn.insert('audit_log', {
        'actor_id': actor.id,
        'action': 'road_assigned',
        'detail': '$incidentId assigned to $name',
        'created_at': _ts,
      });
      if (officerId != actor.id) {
        await txn.insert('notifications', {
          'id': _uuid.v4(),
          'user_id': officerId,
          'title': 'Repair assigned to you',
          'body': '$incidentId: ${i.locationText}',
          'incident_id': incidentId,
          'is_read': 0,
          'created_at': _ts,
        });
      }
    });
    if (i.status == IncidentStatus.submitted || i.status == IncidentStatus.underReview) {
      await _incidents.changeStatus(
        actor: actor,
        incidentId: incidentId,
        to: IncidentStatus.assigned,
        note: 'Assigned to $name',
      );
    }
  }

  // ------------------------------------------------------------------ photos

  /// Records a before/after photo. The caller copies the file into private
  /// app storage first and passes the stored path and its size.
  Future<void> addRepairPhoto({
    required AppUser actor,
    required String incidentId,
    required PhotoKind kind,
    required String path,
    required int sizeBytes,
  }) async {
    final i = await _manageable(actor, incidentId);
    if (i.status == IncidentStatus.rejected || i.status == IncidentStatus.withdrawn) {
      throw const ValidationException(['Photos cannot be added to a closed or withdrawn report.']);
    }
    final problem = Validators.photoFile(path, sizeBytes);
    if (problem != null) throw ValidationException([problem]);
    await _db.transaction((txn) async {
      await txn.insert('repair_photos', {
        'id': _uuid.v4(),
        'incident_id': incidentId,
        'kind': kind.name,
        'path': path,
        'added_by': actor.id,
        'created_at': _ts,
      });
      await txn.insert('audit_log', {
        'actor_id': actor.id,
        'action': 'road_photo_added',
        'detail': '$incidentId: ${kind.name} photo',
        'created_at': _ts,
      });
    });
  }
}
