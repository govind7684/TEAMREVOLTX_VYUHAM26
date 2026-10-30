import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/security/permissions.dart';
import '../../core/utils/validators.dart';
import '../../domain/models/incident.dart';
import '../../domain/models/user.dart';
import '../../services/ai/ai_provider.dart';
import '../../services/ai/duplicate_detector.dart';
import '../../core/utils/geo.dart';
import '../../services/ai/image_analyzer.dart';
import '../../services/photo_check.dart';
import '../../services/ai/location_importance.dart';
import '../../services/ai/priority_scorer.dart';

class SubmitResult {
  const SubmitResult(this.incident, this.duplicates, {this.linkedTo, this.reporterCount = 1});
  final Incident incident;
  final List<DuplicateMatch> duplicates;

  /// Parent report this one was linked to, if any.
  final String? linkedTo;
  final int reporterCount;
}

/// The one incident repository shared by every screen. Every method checks
/// permissions itself, so hiding buttons in the UI is never the only guard.
class IncidentRepository {
  IncidentRepository(
    this._db, {
    required AiProvider ai,
    PriorityScorer scorer = const PriorityScorer(),
    DuplicateDetector detector = const DuplicateDetector(),
    DateTime Function()? clock,
  })  : _ai = ai,
        _scorer = scorer,
        _detector = detector,
        _now = clock ?? DateTime.now;

  final Database _db;
  final AiProvider _ai;
  final PriorityScorer _scorer;
  final DuplicateDetector _detector;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  int get _ts => _now().millisecondsSinceEpoch;

  // ---------------------------------------------------------------- reading

  Future<List<Incident>> listVisible(AppUser user, {IncidentStatus? status}) async {
    final where = <String>[];
    final args = <Object?>[];
    switch (user.role) {
      case UserRole.citizen:
        where.add('reporter_id = ?');
        args.add(user.id);
      case UserRole.officer:
        where.add('department_id = ?');
        args.add(user.departmentId);
      case UserRole.admin:
        break;
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status.name);
    }
    final rows = await _db.query(
      'incidents',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC',
    );
    return rows.map(Incident.fromMap).toList();
  }

  /// Open incidents sorted by priority score then age. Staff only.
  Future<List<Incident>> priorityQueue(AppUser staff) async {
    if (!staff.isStaff) {
      throw const PermissionDeniedException('Staff access only.');
    }
    final all = await listVisible(staff);
    final open = all.where((i) => i.status.isOpen && !i.isLinkedChild).toList()
      ..sort((a, b) {
        final c = b.priorityScore.compareTo(a.priorityScore);
        return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
      });
    return open;
  }

  Future<Incident> getVisible(AppUser user, String id) async {
    final rows = await _db.query('incidents', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) throw const NotFoundException();
    final i = Incident.fromMap(rows.first);
    // Same message as not-found so IDs cannot be probed.
    if (!Permissions.canView(user, i)) throw const NotFoundException();
    return i;
  }

  Future<List<StatusEvent>> history(AppUser user, String id) async {
    await getVisible(user, id);
    final rows = await _db.rawQuery('''
      SELECT h.status, h.note, h.created_at, u.name AS actor, u.id AS actor_id, u.role AS actor_role
      FROM status_history h JOIN users u ON u.id = h.actor_id
      WHERE h.incident_id = ? ORDER BY h.id''', [id]);
    return rows
        .map((r) => StatusEvent(
              status: IncidentStatus.values.byName(r['status'] as String),
              // A citizen never sees another citizen's name on a shared report.
              actorName: user.role == UserRole.citizen &&
                      r['actor_role'] == 'citizen' &&
                      r['actor_id'] != user.id
                  ? 'Another citizen'
                  : r['actor'] as String,
              note: r['note'] as String?,
              at: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
            ))
        .toList();
  }

  // ------------------------------------------------------------- submitting

  /// Preview of what the AI engine would suggest, without saving anything.
  Future<AiSuggestion> suggest(AiInput input) => _ai.analyze(input);

  Future<SubmitResult> submit({
    required AppUser reporter,
    required String description,
    required String locationText,
    IncidentCategory? category,
    double? latitude,
    double? longitude,
    String? photoPath,
    int peopleAffected = 1,
    bool safetyRisk = false,
    IncidentCategory? photoShows,
    ImageFinding? photoFinding,
    PhotoCheck? photoCheck,
  }) async {
    final errors = Validators.report(
      description: description,
      locationText: locationText,
      latitude: latitude,
      longitude: longitude,
      peopleAffected: peopleAffected,
    );
    if (errors.isNotEmpty) throw ValidationException(errors);

    final suggestion = await _ai.analyze(AiInput(
      description: description,
      userCategory: category,
      latitude: latitude,
      longitude: longitude,
      peopleAffected: peopleAffected,
      safetyRiskFlag: safetyRisk,
      hasPhoto: photoPath != null,
    ));

    final now = _now();
    final existing = await _openRecent(suggestion.category);
    final dupes = _detector.find(
      category: suggestion.category,
      description: description,
      locationText: locationText,
      latitude: latitude,
      longitude: longitude,
      now: now,
      existing: existing.where((e) => e.duplicateOfId == null),
    );
    // Only a strong match is linked automatically; staff still verify it.
    final parent = dupes.isNotEmpty && dupes.first.score >= autoLinkScore
        ? dupes.first.incident
        : null;

    final recurrences = await _recurrenceCount(_db,
        category: suggestion.category,
        latitude: latitude,
        longitude: longitude,
        locationText: locationText,
        before: now);
    final loc = LocationImportance.assess(locationText);
    final reportersAfter = parent == null ? 1 : (await reporterCount(parent.id)) + 1;

    final prio = _scorer.score(
      category: suggestion.category,
      safetyRisk: suggestion.safetyRisk,
      peopleAffected: peopleAffected,
      unresolvedFor: Duration.zero,
      similarReports: dupes.length,
      locationPoints: loc.points,
      locationReason: loc.reason,
      recurrences: recurrences,
      reporterCount: reportersAfter,
    );
    var priority = prio.priority;
    if (parent != null && parent.priority.index > priority.index) priority = parent.priority;

    final id = 'CVX-${now.year}-${_uuid.v4().substring(0, 6).toUpperCase()}';
    final isDemoUser = reporter.isDemo;
    final ts = now.millisecondsSinceEpoch;
    final deptId = parent?.departmentId ?? suggestion.category.departmentId;
    final due = parent?.slaDueAt ?? Sla.due(now, priority);

    String? imgLabel;
    double? imgConf;
    String? imgSource;
    var imgVerified = false;
    if (photoFinding != null) {
      imgLabel = photoFinding.label ?? photoFinding.category.label;
      imgConf = photoFinding.isHuman ? null : photoFinding.confidence;
      imgSource = photoFinding.source;
      imgVerified = photoFinding.isHuman;
    } else if (photoShows != null && photoPath != null) {
      imgLabel = photoShows.label;
      imgSource = ImageAnalyzer.humanSource;
      imgVerified = true;
    }

    await _db.transaction((txn) async {
      await txn.insert('incidents', {
        'id': id,
        'reporter_id': reporter.id,
        'category': suggestion.category.name,
        'description': description.trim(),
        'location_text': locationText.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'photo_path': photoPath,
        'people_affected': peopleAffected,
        'safety_risk': suggestion.safetyRisk ? 1 : 0,
        'priority': priority.name,
        'priority_score': prio.score,
        'priority_reasons': prio.reasonText,
        'ai_provider': suggestion.providerId,
        'ai_explanation': suggestion.explanation,
        'needs_human_review':
            (suggestion.needsHumanReview || photoCheck?.verdict == PhotoVerdict.suspicious) ? 1 : 0,
        'department_id': deptId,
        'status': IncidentStatus.submitted.name,
        'created_at': ts,
        'updated_at': ts,
        'is_demo': isDemoUser ? 1 : 0,
        'data_source': isDemoUser ? 'demo-account' : 'user-submitted',
        'ai_confidence': suggestion.confidence,
        'ai_alternatives': suggestion.alternatives.isEmpty ? null : suggestion.alternativesText,
        'image_label': imgLabel,
        'image_confidence': imgConf,
        'image_source': imgSource,
        'image_verified': imgVerified ? 1 : 0,
        'sla_due_at': due.millisecondsSinceEpoch,
        'duplicate_of_id': parent?.id,
        'dup_verified': parent == null ? 1 : 0,
        'dup_score': parent == null ? null : dupes.first.score,
        'photo_origin': photoPath == null ? null : (photoCheck?.origin ?? 'gallery'),
        'photo_check': photoPath == null ? null : photoCheck?.toJson(),
      });
      await _addHistory(txn, id, IncidentStatus.submitted, reporter.id, 'Report submitted');
      if (photoCheck != null && photoPath != null) {
        await _addHistory(txn, id, IncidentStatus.submitted, reporter.id,
            'Photo check: ${photoCheck.verdict.label}. ${photoCheck.aiLabel}.');
      }
      await _addHistory(
          txn,
          id,
          IncidentStatus.submitted,
          reporter.id,
          'AI analysis: ${suggestion.category.label} '
          '(${suggestion.confidence == null ? 'rule-based, no probability' : '${(suggestion.confidence! * 100).round()}% model estimate'}); '
          'priority ${priority.label}; routed to ${Departments.nameOf(deptId)}');
      if (parent != null) {
        await _addHistory(txn, id, IncidentStatus.submitted, reporter.id,
            'Duplicate check: linked to ${parent.id} '
            '(${(dupes.first.score * 100).round()}% match, awaiting staff confirmation)');
        await _addHistory(txn, parent.id, parent.status, reporter.id,
            'Another citizen reported the same problem. Now $reportersAfter citizens.');
        await txn.insert('audit_log', {
          'actor_id': reporter.id,
          'action': 'duplicate_linked',
          'detail': '$id -> ${parent.id} (${(dupes.first.score * 100).toStringAsFixed(0)}%)',
          'created_at': ts,
        });
        await rescoreParent(txn, parent.id, reporter.id);
      } else {
        await _addHistory(txn, id, IncidentStatus.submitted, reporter.id,
            dupes.isEmpty
                ? 'Duplicate check: no similar open report found'
                : 'Duplicate check: similar report(s) found, left for staff to compare');
      }
      await _notify(
          txn,
          reporter.id,
          'Report submitted',
          parent == null
              ? 'Your report $id was received and sent to ${Departments.nameOf(deptId)}.'
              : 'Your report $id matches an existing report (${parent.id}). '
                  'It is tracked together with it, so $reportersAfter citizens are now counted.',
          id);
      if (priority.index >= Priority.high.index && parent == null) {
        final officers = await txn.query('users',
            where: "role = 'officer' AND department_id = ? AND is_active = 1",
            whereArgs: [deptId]);
        for (final o in officers) {
          await _notify(txn, o['id'] as String, '${priority.label} priority report',
              '$id: ${suggestion.category.label} at ${locationText.trim()}', id);
        }
      }
    });
    return SubmitResult(await getVisible(reporter, id), dupes,
        linkedTo: parent?.id, reporterCount: reportersAfter);
  }

  /// Matches at or above this score are linked to the earlier report
  /// automatically (staff still confirm or unlink). Below it they are only
  /// suggested.
  static const autoLinkScore = 0.75;

  /// How many citizens report this problem: the first reporter, reporters of
  /// linked duplicate reports, and citizens who pressed "support".
  Future<int> reporterCount(String parentId) => _reporterCount(_db, parentId);

  static Future<int> _reporterCount(DatabaseExecutor db, String parentId) async {
    final rows = await db.rawQuery('''
      SELECT COUNT(DISTINCT u) AS n FROM (
        SELECT reporter_id AS u FROM incidents WHERE id = ?
        UNION SELECT reporter_id FROM incidents WHERE duplicate_of_id = ?
        UNION SELECT user_id FROM incident_supporters WHERE incident_id = ?
      )''', [parentId, parentId, parentId]);
    return (rows.first['n'] as int?) ?? 1;
  }

  /// Earlier reports of the same kind at (about) the same spot, any status.
  /// Used for the recurrence factor. Looks back 180 days.
  static Future<int> _recurrenceCount(
    DatabaseExecutor db, {
    required IncidentCategory category,
    double? latitude,
    double? longitude,
    required String locationText,
    required DateTime before,
    String? excludeId,
    double radiusMeters = 100,
  }) async {
    final since = before.subtract(const Duration(days: 180)).millisecondsSinceEpoch;
    final rows = await db.query('incidents',
        where: 'category = ? AND created_at >= ? AND created_at < ? AND duplicate_of_id IS NULL',
        whereArgs: [category.name, since, before.millisecondsSinceEpoch]);
    var n = 0;
    for (final r in rows) {
      final i = Incident.fromMap(r);
      if (i.id == excludeId) continue;
      // Open ones are duplicates (handled elsewhere); recurrence = fixed before, came back.
      if (i.status.isOpen) continue;
      if (i.status == IncidentStatus.rejected || i.status == IncidentStatus.withdrawn) continue;
      if (latitude != null && longitude != null && i.hasCoordinates) {
        if (distanceMeters(latitude, longitude, i.latitude!, i.longitude!) <= radiusMeters) n++;
      } else if (DuplicateDetector.textSimilarity(locationText, i.locationText) >= 0.6) {
        n++;
      }
    }
    return n;
  }

  /// Recomputes a parent's priority after its reporter count changed, unless
  /// a person overrode the priority.
  Future<void> rescoreParent(DatabaseExecutor txn, String parentId, String actorId) async {
    final rows = await txn.query('incidents', where: 'id = ?', whereArgs: [parentId]);
    if (rows.isEmpty) return;
    final p = Incident.fromMap(rows.first);
    if (p.priorityOverridden || !p.status.isOpen) return;
    final n = await _reporterCount(txn, parentId);
    final loc = LocationImportance.assess(p.locationText);
    final rec = await _recurrenceCount(txn,
        category: p.category,
        latitude: p.latitude,
        longitude: p.longitude,
        locationText: p.locationText,
        before: p.createdAt,
        excludeId: p.id);
    final r = _scorer.score(
      category: p.category,
      safetyRisk: p.safetyRisk,
      peopleAffected: p.peopleAffected,
      unresolvedFor: _now().difference(p.createdAt),
      similarReports: n - 1,
      locationPoints: loc.points,
      locationReason: loc.reason,
      recurrences: rec,
      reporterCount: n,
    );
    if (r.priority == p.priority && r.score == p.priorityScore) return;
    await txn.update(
        'incidents',
        {
          'priority': r.priority.name,
          'priority_score': r.score,
          'priority_reasons': r.reasonText,
          'sla_due_at': Sla.due(p.createdAt, r.priority).millisecondsSinceEpoch,
          'updated_at': _ts,
        },
        where: 'id = ?',
        whereArgs: [parentId]);
    if (r.priority.index > p.priority.index) {
      await _addHistory(txn, parentId, p.status, actorId,
          'Priority raised to ${r.priority.label} automatically ($n citizens reporting)');
      final officers = await txn.query('users',
          where: "role = 'officer' AND department_id = ? AND is_active = 1",
          whereArgs: [p.departmentId]);
      for (final o in officers) {
        await _notify(txn, o['id'] as String, 'Priority raised: ${r.priority.label}',
            '$parentId now has $n citizens reporting it.', parentId);
      }
    }
  }

  /// Staff confirm or reject an automatic duplicate link.
  Future<void> verifyDuplicate({
    required AppUser actor,
    required String childId,
    required bool confirm,
    String? note,
  }) async {
    final child = await getVisible(actor, childId);
    if (!Permissions.canManage(actor, child)) {
      throw const PermissionDeniedException('You cannot manage this report.');
    }
    final parentId = child.duplicateOfId;
    if (parentId == null) {
      throw const ValidationException(['This report is not linked to another report.']);
    }
    await _db.transaction((txn) async {
      await txn.update(
          'incidents',
          {
            'dup_verified': 1,
            if (!confirm) 'duplicate_of_id': null,
            'updated_at': _ts,
          },
          where: 'id = ?',
          whereArgs: [childId]);
      await _addHistory(txn, childId, child.status, actor.id,
          confirm ? 'Duplicate link to $parentId confirmed by staff'
                  : 'Duplicate link to $parentId removed by staff${note == null ? '' : ': $note'}');
      await txn.insert('audit_log', {
        'actor_id': actor.id,
        'action': confirm ? 'duplicate_confirmed' : 'duplicate_unlinked',
        'detail': '$childId <-> $parentId',
        'created_at': _ts,
      });
      await rescoreParent(txn, parentId, actor.id);
    });
  }

  /// Linked duplicate reports under a parent. Staff only.
  Future<List<Incident>> linkedReports(AppUser actor, String parentId) async {
    final p = await getVisible(actor, parentId);
    if (!actor.isStaff || !Permissions.canManage(actor, p)) return [];
    final rows = await _db.query('incidents',
        where: 'duplicate_of_id = ?', whereArgs: [parentId], orderBy: 'created_at');
    return rows.map(Incident.fromMap).toList();
  }

  /// Finds reports that other phones filed about the same problem. Each citizen's
  /// phone only knows their own reports, so this runs on an administrator's
  /// phone, where everything arrives. A strong match is linked to the older
  /// report and left "awaiting confirmation"; staff confirm or unlink it.
  /// Returns how many reports were linked.
  Future<int> linkDuplicates(AppUser actor) async {
    if (actor.role != UserRole.admin) return 0;
    final rows = await _db.query('incidents',
        where: "status IN ('submitted','underReview','assigned','inProgress') "
            'AND duplicate_of_id IS NULL',
        orderBy: 'created_at');
    final open = rows.map(Incident.fromMap).toList();
    var linked = 0;
    for (var k = 1; k < open.length; k++) {
      final i = open[k];
      if (i.duplicateOfId != null) continue;
      final older = open.take(k).where((p) =>
          p.duplicateOfId == null && p.category == i.category && p.id != i.id);
      final found = _detector.find(
        category: i.category,
        description: i.description,
        locationText: i.locationText,
        latitude: i.latitude,
        longitude: i.longitude,
        now: i.createdAt,
        existing: older,
      );
      if (found.isEmpty || found.first.score < autoLinkScore) continue;
      final parent = found.first.incident;
      final ts = _now().millisecondsSinceEpoch;
      await _db.transaction((txn) async {
        await txn.update(
            'incidents',
            {
              'duplicate_of_id': parent.id,
              'dup_verified': 0,
              'dup_score': found.first.score,
              'assigned_officer_id': parent.assignedOfficerId,
              'updated_at': ts,
            },
            where: 'id = ?',
            whereArgs: [i.id]);
        await txn.update('assignments', {'state': 'reassigned', 'responded_at': ts},
            where: "incident_id = ? AND state IN ('pending','accepted')", whereArgs: [i.id]);
        await _addHistory(txn, i.id, i.status, actor.id,
            'Duplicate check: linked to ${parent.id} '
            '(${(found.first.score * 100).round()}% match, awaiting staff confirmation)');
        await _addHistory(txn, parent.id, parent.status, actor.id,
            'Another citizen reported the same problem (${i.id}).');
        await txn.insert('audit_log', {
          'actor_id': actor.id,
          'action': 'duplicate_linked',
          'detail': '${i.id} -> ${parent.id} (${(found.first.score * 100).toStringAsFixed(0)}%)',
          'created_at': ts,
        });
        await rescoreParent(txn, parent.id, actor.id);
      });
      linked++;
    }
    return linked;
  }

  /// A person confirms or corrects what the photo shows.
  Future<void> verifyPhotoFinding({
    required AppUser actor,
    required String incidentId,
    required IncidentCategory shows,
  }) async {
    final i = await getVisible(actor, incidentId);
    if (!Permissions.canManage(actor, i)) {
      throw const PermissionDeniedException('You cannot manage this report.');
    }
    if (i.photoPath == null) {
      throw const ValidationException(['This report has no photo.']);
    }
    await _db.transaction((txn) async {
      await txn.update(
          'incidents',
          {
            'image_label': shows.label,
            'image_source': ImageAnalyzer.humanSource,
            'image_verified': 1,
            'updated_at': _ts,
          },
          where: 'id = ?',
          whereArgs: [incidentId]);
      await txn.insert('audit_log', {
        'actor_id': actor.id,
        'action': 'photo_verified',
        'detail': '$incidentId: photo shows ${shows.label}',
        'created_at': _ts,
      });
    });
  }

  Future<List<Incident>> _openRecent(IncidentCategory c) async {
    final rows = await _db.query('incidents',
        where: 'category = ?', whereArgs: [c.name], orderBy: 'created_at DESC', limit: 200);
    return rows.map(Incident.fromMap).toList();
  }

  // ------------------------------------------------------ citizen modifying

  Future<void> withdraw(AppUser user, String id) async {
    final i = await getVisible(user, id);
    if (!Permissions.canCitizenModify(user, i)) {
      throw const PermissionDeniedException(
          'This report can no longer be withdrawn because staff have started work on it.');
    }
    await _db.transaction((txn) async {
      await txn.update('incidents',
          {'status': IncidentStatus.withdrawn.name, 'updated_at': _ts},
          where: 'id = ?', whereArgs: [id]);
      await _addHistory(txn, id, IncidentStatus.withdrawn, user.id, 'Withdrawn by reporter');
    });
  }

  // --------------------------------------------------------- staff actions

  Future<void> changeStatus({
    required AppUser actor,
    required String incidentId,
    required IncidentStatus to,
    String? note,
    String? rejectionReason,
  }) async {
    final i = await getVisible(actor, incidentId);
    if (!Permissions.canManage(actor, i)) {
      throw const PermissionDeniedException('You cannot manage this report.');
    }
    if (!Permissions.isValidTransition(i.status, to)) {
      throw ValidationException(
          ['Cannot change from ${i.status.label} to ${to.label}.']);
    }
    if (to == IncidentStatus.rejected && (rejectionReason?.trim().length ?? 0) < 5) {
      throw const ValidationException(
          ['Give a reason (at least 5 characters) when rejecting a report.']);
    }
    if (to == IncidentStatus.resolved && (note?.trim().length ?? 0) < 5) {
      throw const ValidationException(
          ['Add a short resolution note before marking as resolved.']);
    }
    // A human decision is required for rejection; emergencies need a second look.
    if (to == IncidentStatus.rejected &&
        i.priority == Priority.critical &&
        actor.role != UserRole.admin) {
      throw const PermissionDeniedException(
          'Critical reports can only be rejected by an administrator.');
    }

    await _db.transaction((txn) async {
      await txn.update(
        'incidents',
        {
          'status': to.name,
          'updated_at': _ts,
          if (to == IncidentStatus.assigned || to == IncidentStatus.inProgress)
            'assigned_officer_id': i.assignedOfficerId ?? actor.id,
          if (to == IncidentStatus.resolved) 'resolution_note': note!.trim(),
          if (to == IncidentStatus.rejected) 'rejection_reason': rejectionReason!.trim(),
        },
        where: 'id = ?',
        whereArgs: [incidentId],
      );
      await _addHistory(txn, incidentId, to, actor.id,
          to == IncidentStatus.rejected ? rejectionReason!.trim() : note?.trim());
      await txn.insert('audit_log', {
        'actor_id': actor.id,
        'action': 'status_change',
        'detail': '$incidentId: ${i.status.name} -> ${to.name}',
        'created_at': _ts,
      });
      await _cascadeToLinked(txn, i, to, note, rejectionReason, actor.id);
      await _notify(
        txn,
        i.reporterId,
        to == IncidentStatus.resolved ? 'Issue resolved' : 'Status changed',
        '$incidentId is now ${to.label}.'
            '${to == IncidentStatus.rejected ? ' Reason: ${rejectionReason!.trim()}' : ''}',
        incidentId,
      );
    });
  }

  /// Linked duplicate reports follow their parent, so every citizen who
  /// reported the problem sees the same progress.
  Future<void> _cascadeToLinked(DatabaseExecutor txn, Incident parent,
      IncidentStatus to, String? note, String? rejectionReason, String actorId) async {
    final kids = await txn.query('incidents',
        where: 'duplicate_of_id = ?', whereArgs: [parent.id]);
    for (final k in kids) {
      final c = Incident.fromMap(k);
      if (!c.status.isOpen) continue;
      await txn.update(
          'incidents',
          {
            'status': to.name,
            'updated_at': _ts,
            if (to == IncidentStatus.assigned || to == IncidentStatus.inProgress)
              'assigned_officer_id': parent.assignedOfficerId ?? actorId,
            if (to == IncidentStatus.resolved) 'resolution_note': note!.trim(),
            if (to == IncidentStatus.rejected) 'rejection_reason': rejectionReason!.trim(),
          },
          where: 'id = ?',
          whereArgs: [c.id]);
      await _addHistory(txn, c.id, to, actorId, 'Follows ${parent.id}: ${to.label}');
      await _notify(txn, c.reporterId, 'Status changed',
          '${c.id} (same problem as ${parent.id}) is now ${to.label}.', c.id);
    }
  }

  /// Officer override of the AI suggestion (category/department/priority).
  Future<void> overrideSuggestion({
    required AppUser actor,
    required String incidentId,
    IncidentCategory? category,
    Priority? priority,
    required String reason,
  }) async {
    final i = await getVisible(actor, incidentId);
    if (!Permissions.canManage(actor, i)) {
      throw const PermissionDeniedException('You cannot manage this report.');
    }
    if (reason.trim().length < 5) {
      throw const ValidationException(['Explain why you are overriding the suggestion.']);
    }
    await _db.transaction((txn) async {
      await txn.update(
        'incidents',
        {
          if (category != null) 'category': category.name,
          if (category != null) 'department_id': category.departmentId,
          if (priority != null) 'priority': priority.name,
          if (priority != null) 'priority_overridden': 1,
          if (priority != null)
            'sla_due_at': Sla.due(i.createdAt, priority).millisecondsSinceEpoch,
          'needs_human_review': 0,
          'updated_at': _ts,
        },
        where: 'id = ?',
        whereArgs: [incidentId],
      );
      await txn.insert('audit_log', {
        'actor_id': actor.id,
        'action': 'ai_override',
        'detail': '$incidentId: ${category?.name ?? '-'} / ${priority?.name ?? '-'}. ${reason.trim()}',
        'created_at': _ts,
      });
    });
  }

  // --------------------------------------------------- notifications/audit

  Future<List<AppNotification>> notifications(AppUser user) async {
    final rows = await _db.query('notifications',
        where: 'user_id = ?', whereArgs: [user.id], orderBy: 'created_at DESC');
    return rows
        .map((r) => AppNotification(
              id: r['id'] as String,
              title: r['title'] as String,
              body: r['body'] as String,
              incidentId: r['incident_id'] as String?,
              isRead: (r['is_read'] as int) == 1,
              createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
            ))
        .toList();
  }

  Future<void> markAllRead(AppUser user) => _db.update(
      'notifications', {'is_read': 1},
      where: 'user_id = ?', whereArgs: [user.id]);

  Future<List<AuditEntry>> auditLog(AppUser actor) async {
    if (!Permissions.canViewAudit(actor)) {
      throw const PermissionDeniedException('Only administrators can view the audit log.');
    }
    final rows = await _db.rawQuery('''
      SELECT a.action, a.detail, a.created_at, u.name AS actor
      FROM audit_log a JOIN users u ON u.id = a.actor_id
      ORDER BY a.id DESC LIMIT 200''');
    return rows
        .map((r) => AuditEntry(
              actorName: r['actor'] as String,
              action: r['action'] as String,
              detail: r['detail'] as String,
              at: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
            ))
        .toList();
  }

  // ---------------------------------------------------------------- helpers

  Future<void> _addHistory(DatabaseExecutor txn, String incidentId,
      IncidentStatus s, String actorId, String? note) {
    return txn.insert('status_history', {
      'incident_id': incidentId,
      'status': s.name,
      'actor_id': actorId,
      'note': note,
      'created_at': _ts,
    });
  }

  Future<void> _notify(DatabaseExecutor txn, String userId, String title,
      String body, String? incidentId) {
    return txn.insert('notifications', {
      'id': _uuid.v4(),
      'user_id': userId,
      'title': title,
      'body': body,
      'incident_id': incidentId,
      'is_read': 0,
      'created_at': _ts,
    });
  }
}
