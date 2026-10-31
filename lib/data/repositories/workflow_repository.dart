import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/security/permissions.dart';
import '../../core/utils/geo.dart';
import '../../core/utils/validators.dart';
import '../../domain/models/incident.dart';
import '../../domain/models/road.dart';
import '../../domain/models/user.dart';
import '../../domain/models/workflow.dart';
import '../../services/ai/priority_scorer.dart';
import 'incident_repository.dart';

/// Assignment, escalation, supporters, feedback, notes, evidence and
/// department management. Sits on the same database as [IncidentRepository]
/// and re-checks permissions on every call.
class WorkflowRepository {
  WorkflowRepository(this._db, {required this._incidents, DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  final Database _db;
  final IncidentRepository _incidents;
  final DateTime Function() _now;
  static const _uuid = Uuid();
  int get _ts => _now().millisecondsSinceEpoch;

  /// Days after "Resolved" before an unanswered report is closed automatically.
  static const autoCloseDays = 7;

  // ---------------------------------------------------------------- helpers

  void _staff(AppUser u) {
    if (!u.isStaff) throw const PermissionDeniedException('Staff access only.');
  }

  void _admin(AppUser u) {
    if (u.role != UserRole.admin) {
      throw const PermissionDeniedException('Administrators only.');
    }
  }

  Future<Incident> _manageable(AppUser actor, String id) async {
    _staff(actor);
    final i = await _incidents.getVisible(actor, id);
    if (!Permissions.canManage(actor, i)) {
      throw const PermissionDeniedException('You cannot manage this report.');
    }
    return i;
  }

  Future<void> _history(DatabaseExecutor db, String id, IncidentStatus s, String actor, String note) =>
      db.insert('status_history', {
        'incident_id': id,
        'status': s.name,
        'actor_id': actor,
        'note': note,
        'created_at': _ts,
      });

  Future<void> _audit(DatabaseExecutor db, String actor, String action, String detail) =>
      db.insert('audit_log',
          {'actor_id': actor, 'action': action, 'detail': detail, 'created_at': _ts});

  Future<void> _notify(DatabaseExecutor db, String userId, String title, String body, String? inc) =>
      db.insert('notifications', {
        'id': _uuid.v4(),
        'user_id': userId,
        'title': title,
        'body': body,
        'incident_id': inc,
        'is_read': 0,
        'created_at': _ts,
      });

  Future<void> _notifyAdmins(DatabaseExecutor db, String title, String body, String? inc) async {
    final admins = await db.query('users', where: "role = 'admin' AND is_active = 1");
    for (final a in admins) {
      await _notify(db, a['id'] as String, title, body, inc);
    }
  }

  // ------------------------------------------------------------ departments

  Future<List<({String id, String name})>> listDepartments() async {
    final rows = await _db.query('departments', orderBy: 'name');
    final out = rows.map((r) => (id: r['id'] as String, name: r['name'] as String)).toList();
    for (final d in out) {
      Departments.register(d.id, d.name);
    }
    return out;
  }

  Future<String> addDepartment(AppUser admin, String name) async {
    _admin(admin);
    final n = name.trim();
    if (n.length < 3 || n.length > 60) {
      throw const ValidationException(['Department name must be 3 to 60 characters.']);
    }
    final slug = n.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    final id = 'dept_$slug';
    final exists = await _db.query('departments',
        where: 'id = ? OR LOWER(name) = ?', whereArgs: [id, n.toLowerCase()]);
    if (exists.isNotEmpty) throw const ValidationException(['That department already exists.']);
    await _db.transaction((txn) async {
      await txn.insert('departments', {'id': id, 'name': n});
      await _audit(txn, admin.id, 'department_added', '$id: $n');
    });
    Departments.register(id, n);
    return id;
  }

  Future<void> renameDepartment(AppUser admin, String id, String name) async {
    _admin(admin);
    final n = name.trim();
    if (n.length < 3 || n.length > 60) {
      throw const ValidationException(['Department name must be 3 to 60 characters.']);
    }
    final c = await _db.update('departments', {'name': n}, where: 'id = ?', whereArgs: [id]);
    if (c == 0) throw const NotFoundException();
    await _audit(_db, admin.id, 'department_renamed', '$id: $n');
    Departments.register(id, n);
  }

  /// Moves an officer to another department. Their existing open assignments
  /// are released so they never hold another department's cases.
  Future<void> moveOfficer(AppUser admin, String userId, String departmentId) async {
    _admin(admin);
    final u = await _db.query('users', where: "id = ? AND role = 'officer'", whereArgs: [userId]);
    if (u.isEmpty) throw const NotFoundException('Officer not found.');
    final d = await _db.query('departments', where: 'id = ?', whereArgs: [departmentId]);
    if (d.isEmpty) throw const NotFoundException('Department not found.');
    await _db.transaction((txn) async {
      await txn.update('users', {'department_id': departmentId}, where: 'id = ?', whereArgs: [userId]);
      await txn.rawUpdate(
          "UPDATE incidents SET assigned_officer_id = NULL, "
          "status = CASE WHEN status IN ('assigned') THEN 'underReview' ELSE status END, "
          "updated_at = ? WHERE assigned_officer_id = ? AND status IN ('assigned','inProgress','underReview','submitted')",
          [_ts, userId]);
      await txn.update('assignments', {'state': 'reassigned', 'responded_at': _ts},
          where: "officer_id = ? AND state IN ('pending','accepted')", whereArgs: [userId]);
      await _audit(txn, admin.id, 'officer_moved', '$userId -> $departmentId');
    });
  }

  /// Sends a report to a different department (administrator).
  Future<void> reassignDepartment({
    required AppUser admin,
    required String incidentId,
    required String departmentId,
    required String reason,
  }) async {
    _admin(admin);
    final i = await _incidents.getVisible(admin, incidentId);
    if (reason.trim().length < 5) {
      throw const ValidationException(['Give a reason (at least 5 characters).']);
    }
    final d = await _db.query('departments', where: 'id = ?', whereArgs: [departmentId]);
    if (d.isEmpty) throw const NotFoundException('Department not found.');
    if (!i.status.isOpen) {
      throw const ValidationException(['Only open reports can be re-routed.']);
    }
    await _db.transaction((txn) async {
      await txn.rawUpdate(
          "UPDATE incidents SET department_id = ?, assigned_officer_id = NULL, updated_at = ?, "
          "status = CASE WHEN status IN ('assigned','inProgress') THEN 'underReview' ELSE status END "
          "WHERE id = ? OR duplicate_of_id = ?",
          [departmentId, _ts, incidentId, incidentId]);
      await txn.update('assignments', {'state': 'reassigned', 'responded_at': _ts},
          where: "incident_id = ? AND state IN ('pending','accepted')", whereArgs: [incidentId]);
      await _history(txn, incidentId, IncidentStatus.underReview, admin.id,
          'Re-routed to ${Departments.nameOf(departmentId)}: ${reason.trim()}');
      await _audit(txn, admin.id, 'department_reassigned',
          '$incidentId: ${i.departmentId} -> $departmentId. ${reason.trim()}');
      await _notify(txn, i.reporterId, 'Report re-routed',
          '$incidentId is now with ${Departments.nameOf(departmentId)}.', incidentId);
    });
  }

  // ------------------------------------------------------------ assignments

  Future<List<Assignment>> assignmentsFor(AppUser actor, String incidentId) async {
    await _manageable(actor, incidentId);
    final rows = await _db.rawQuery('''
      SELECT a.*, o.name AS officer_name, b.name AS by_name
      FROM assignments a JOIN users o ON o.id = a.officer_id JOIN users b ON b.id = a.assigned_by
      WHERE a.incident_id = ? ORDER BY a.created_at, a.rowid''', [incidentId]);
    return rows.map(_assignment).toList();
  }

  /// Pending and accepted assignments of the signed-in officer, open cases only.
  Future<List<({Assignment assignment, Incident incident})>> myAssignments(AppUser officer) async {
    _staff(officer);
    final rows = await _db.rawQuery('''
      SELECT a.*, o.name AS officer_name, b.name AS by_name
      FROM assignments a JOIN users o ON o.id = a.officer_id JOIN users b ON b.id = a.assigned_by
      WHERE a.officer_id = ? AND a.state IN ('pending','accepted') ORDER BY a.created_at DESC''',
        [officer.id]);
    final out = <({Assignment assignment, Incident incident})>[];
    for (final r in rows) {
      final inc = await _db.query('incidents', where: 'id = ?', whereArgs: [r['incident_id']]);
      if (inc.isEmpty) continue;
      final i = Incident.fromMap(inc.first);
      if (!i.status.isOpen || i.assignedOfficerId != officer.id) continue;
      out.add((assignment: _assignment(r), incident: i));
    }
    return out;
  }

  Assignment _assignment(Map<String, Object?> r) => Assignment(
        id: r['id'] as String,
        incidentId: r['incident_id'] as String,
        officerId: r['officer_id'] as String,
        officerName: r['officer_name'] as String,
        assignedByName: r['by_name'] as String,
        state: AssignmentState.values.byName(r['state'] as String),
        reason: r['reason'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        respondedAt: r['responded_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['responded_at'] as int),
      );

  /// Assigns or reassigns a report to an officer of its department. The
  /// officer must accept or reject (with a reason) unless they assign
  /// themselves.
  Future<void> assign({
    required AppUser actor,
    required String incidentId,
    required String officerId,
    String? note,
  }) async {
    final i = await _manageable(actor, incidentId);
    if (!i.status.isOpen) throw const ValidationException(['This report is already closed.']);
    if (i.isLinkedChild) {
      throw ValidationException(['Assign the parent report ${i.duplicateOfId} instead.']);
    }
    final o = await _db.query('users',
        where: "id = ? AND role = 'officer' AND is_active = 1", whereArgs: [officerId]);
    if (o.isEmpty) throw const NotFoundException('Officer not found or disabled.');
    final officer = AppUser.fromMap(o.first);
    if (officer.departmentId != i.departmentId) {
      throw const ValidationException(
          ['That officer belongs to a different department. Re-route the report first.']);
    }
    final self = officerId == actor.id;
    final id = _uuid.v4();
    await _db.transaction((txn) async {
      await txn.update('assignments', {'state': 'reassigned', 'responded_at': _ts},
          where: "incident_id = ? AND state IN ('pending','accepted')", whereArgs: [incidentId]);
      await txn.insert('assignments', {
        'id': id,
        'incident_id': incidentId,
        'officer_id': officerId,
        'assigned_by': actor.id,
        'state': self ? 'accepted' : 'pending',
        'reason': note?.trim(),
        'created_at': _ts,
        'responded_at': self ? _ts : null,
      });
      await txn.update('incidents', {'assigned_officer_id': officerId, 'updated_at': _ts},
          where: 'id = ? OR duplicate_of_id = ?', whereArgs: [incidentId, incidentId]);
      await _history(txn, incidentId, i.status, actor.id,
          '${i.assignedOfficerId == null ? 'Assigned' : 'Reassigned'} to ${officer.name}'
          '${self ? ' (self-assigned)' : ' (awaiting acceptance)'}'
          '${note == null || note.trim().isEmpty ? '' : ': ${note.trim()}'}');
      await _audit(txn, actor.id, 'assignment', '$incidentId -> ${officer.email}');
      if (!self) {
        await _notify(txn, officerId, 'New assignment',
            '$incidentId (${i.category.label}) was assigned to you. Please accept or reject it.',
            incidentId);
      }
    });
    if (i.status == IncidentStatus.submitted || i.status == IncidentStatus.underReview) {
      await _incidents.changeStatus(
          actor: actor, incidentId: incidentId, to: IncidentStatus.assigned,
          note: 'Assigned to ${officer.name}');
    }
  }

  // ----------------------------------------------------------------- merging

  /// Staff merge report [childId] into the main report [parentId]: they are
  /// then tracked, assigned and closed together, and every citizen is counted.
  /// Reports the child already had linked move to the new main report.
  Future<void> mergeReports({
    required AppUser actor,
    required String childId,
    required String parentId,
    String? note,
  }) async {
    if (childId == parentId) {
      throw const ValidationException(['A report cannot be merged into itself.']);
    }
    final child = await _manageable(actor, childId);
    final parent = await _manageable(actor, parentId);
    if (!child.status.isOpen || !parent.status.isOpen) {
      throw const ValidationException(['Only open reports can be merged.']);
    }
    if (parent.duplicateOfId != null) {
      throw ValidationException(['Merge into the main report ${parent.duplicateOfId} instead.']);
    }
    if (actor.role != UserRole.admin && child.departmentId != parent.departmentId) {
      throw const ValidationException(
          ['Reports of different departments can only be merged by an administrator.']);
    }
    final why = (note ?? '').trim();
    await _db.transaction((txn) async {
      await txn.update(
          'incidents', {'duplicate_of_id': parentId, 'dup_verified': 1, 'updated_at': _ts},
          where: 'duplicate_of_id = ?', whereArgs: [childId]);
      await txn.update('assignments', {'state': 'reassigned', 'responded_at': _ts},
          where: "incident_id = ? AND state IN ('pending','accepted')", whereArgs: [childId]);
      await txn.update(
          'incidents',
          {
            'duplicate_of_id': parentId,
            'dup_verified': 1,
            'dup_score': null,
            'department_id': parent.departmentId,
            'assigned_officer_id': parent.assignedOfficerId,
            'updated_at': _ts,
          },
          where: 'id = ?',
          whereArgs: [childId]);
      await _history(txn, childId, child.status, actor.id,
          'Merged into $parentId by ${actor.name}${why.isEmpty ? '' : ': $why'}');
      await _history(txn, parentId, parent.status, actor.id,
          '$childId was merged into this report${why.isEmpty ? '' : ': $why'}');
      await _audit(txn, actor.id, 'reports_merged', '$childId -> $parentId');
      await _notify(txn, child.reporterId, 'Report merged',
          'Your report $childId is about the same problem as $parentId. They are now tracked together.',
          childId);
      await _incidents.rescoreParent(txn, parentId, actor.id);
    });
  }

  /// Staff confirm that a linked report really is a duplicate.
  Future<void> confirmDuplicate({required AppUser actor, required String childId}) async {
    final c = await _manageable(actor, childId);
    if (c.duplicateOfId == null) throw const ValidationException(['This report is not linked.']);
    await _db.transaction((txn) async {
      await txn.update('incidents', {'dup_verified': 1, 'updated_at': _ts},
          where: 'id = ?', whereArgs: [childId]);
      await _history(txn, childId, c.status, actor.id,
          'Duplicate of ${c.duplicateOfId} confirmed by ${actor.name}');
      await _audit(txn, actor.id, 'duplicate_confirmed', '$childId -> ${c.duplicateOfId}');
    });
  }

  /// Staff undo a link or merge. The report becomes its own report again.
  Future<void> unlinkDuplicate({required AppUser actor, required String childId}) async {
    final c = await _manageable(actor, childId);
    final parentId = c.duplicateOfId;
    if (parentId == null) throw const ValidationException(['This report is not linked.']);
    await _db.transaction((txn) async {
      await txn.update(
          'incidents',
          {
            'duplicate_of_id': null,
            'dup_verified': 1,
            'dup_score': null,
            'assigned_officer_id': null,
            'updated_at': _ts,
          },
          where: 'id = ?',
          whereArgs: [childId]);
      await _history(txn, childId, c.status, actor.id,
          'Unlinked from $parentId by ${actor.name}; handled as its own report');
      await _history(txn, parentId, c.status, actor.id, '$childId was unlinked from this report');
      await _audit(txn, actor.id, 'duplicate_unlinked', '$childId from $parentId');
      await _incidents.rescoreParent(txn, parentId, actor.id);
    });
  }

  static const _routingKey = 'auto_routing';

  /// Automatic routing is ON unless an administrator switched it off.
  Future<bool> routingEnabled() async {
    final r = await _db.query('app_settings', where: 'key = ?', whereArgs: [_routingKey], limit: 1);
    return r.isEmpty || r.first['value'] != '0';
  }

  Future<void> setRoutingEnabled(AppUser actor, bool on) async {
    if (actor.role != UserRole.admin) {
      throw const PermissionDeniedException('Only administrators can change routing.');
    }
    await _db.transaction((txn) async {
      await txn.insert('app_settings', {'key': _routingKey, 'value': on ? '1' : '0'},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await _audit(txn, actor.id, on ? 'auto_routing_on' : 'auto_routing_off', '');
    });
  }

  /// Automatic routing. The category already decides the department; this picks
  /// the officer of that department with the fewest open cases (ties by name),
  /// skipping anyone who already rejected this report, and assigns it. Runs on
  /// an administrator's device; a report nobody can take stays in the admin
  /// queue. Returns how many reports were assigned.
  Future<int> autoRoute(AppUser admin) async {
    if (admin.role != UserRole.admin || !await routingEnabled()) return 0;
    final rows = await _db.query('incidents',
        where: "status IN ('submitted','underReview') AND assigned_officer_id IS NULL "
            'AND duplicate_of_id IS NULL',
        orderBy: 'created_at');
    var n = 0;
    for (final r in rows) {
      final id = r['id'] as String;
      final rejected = (await _db.query('assignments',
              columns: ['officer_id'],
              where: "incident_id = ? AND state = 'rejected'",
              whereArgs: [id]))
          .map((e) => e['officer_id'] as String)
          .toSet();
      final officers = await _db.rawQuery('''
        SELECT u.id, (SELECT COUNT(*) FROM incidents i WHERE i.assigned_officer_id = u.id
                        AND i.status NOT IN ('resolved','closed','rejected')) AS load
        FROM users u
        WHERE u.role = 'officer' AND u.is_active = 1 AND u.department_id = ?
        ORDER BY load, u.name''', [r['department_id']]);
      final pick = officers.where((o) => !rejected.contains(o['id'])).firstOrNull;
      if (pick == null) continue;
      try {
        await assign(
            actor: admin,
            incidentId: id,
            officerId: pick['id'] as String,
            note: 'Automatic routing: officer with the fewest open cases');
        n++;
      } catch (_) {/* leave it for the administrator */}
    }
    return n;
  }

  /// Officer accepts, or rejects with a reason. A rejected case goes back to
  /// review and administrators are told.
  Future<void> respond({
    required AppUser officer,
    required String incidentId,
    required bool accept,
    String? reason,
  }) async {
    _staff(officer);
    final i = await _incidents.getVisible(officer, incidentId);
    if (i.assignedOfficerId != officer.id) {
      throw const PermissionDeniedException('This case is not assigned to you.');
    }
    final rows = await _db.query('assignments',
        where: "incident_id = ? AND officer_id = ? AND state = 'pending'",
        whereArgs: [incidentId, officer.id]);
    if (rows.isEmpty) throw const ValidationException(['There is nothing waiting for your answer.']);
    if (!accept && (reason?.trim().length ?? 0) < 5) {
      throw const ValidationException(['Give a reason (at least 5 characters) when rejecting.']);
    }
    await _db.transaction((txn) async {
      await txn.update(
          'assignments',
          {
            'state': accept ? 'accepted' : 'rejected',
            'reason': accept ? rows.first['reason'] : reason!.trim(),
            'responded_at': _ts,
          },
          where: 'id = ?',
          whereArgs: [rows.first['id']]);
      await _history(txn, incidentId, i.status, officer.id,
          accept ? 'Assignment accepted by ${officer.name}'
                 : 'Assignment rejected by ${officer.name}: ${reason!.trim()}');
      await _audit(txn, officer.id, accept ? 'assignment_accepted' : 'assignment_rejected',
          '$incidentId${accept ? '' : ': ${reason!.trim()}'}');
      if (!accept) {
        await txn.update('incidents', {'assigned_officer_id': null, 'updated_at': _ts},
            where: 'id = ? OR duplicate_of_id = ?', whereArgs: [incidentId, incidentId]);
        await _notifyAdmins(txn, 'Assignment rejected',
            '${officer.name} rejected $incidentId: ${reason!.trim()}', incidentId);
      }
    });
    if (!accept && i.status == IncidentStatus.assigned) {
      await _incidents.changeStatus(
          actor: officer, incidentId: incidentId, to: IncidentStatus.underReview,
          note: 'Returned for reassignment');
    }
  }

  /// Picks the active officer of the department with the fewest open cases.
  Future<AppUser?> leastLoadedOfficer(String departmentId) async {
    final rows = await _db.rawQuery('''
      SELECT u.*, (SELECT COUNT(*) FROM incidents i WHERE i.assigned_officer_id = u.id
                   AND i.status IN ('assigned','inProgress','underReview','submitted')
                   AND i.duplicate_of_id IS NULL) AS load
      FROM users u WHERE u.role = 'officer' AND u.is_active = 1 AND u.department_id = ?
      ORDER BY load, u.name LIMIT 1''', [departmentId]);
    return rows.isEmpty ? null : AppUser.fromMap(rows.first);
  }

  Future<AppUser> autoAssign(AppUser actor, String incidentId) async {
    final i = await _manageable(actor, incidentId);
    final o = await leastLoadedOfficer(i.departmentId);
    if (o == null) {
      throw const ValidationException(['No active officer in this department.']);
    }
    await assign(actor: actor, incidentId: incidentId, officerId: o.id,
        note: 'Automatic assignment to the least-loaded officer');
    return o;
  }

  // ---------------------------------------------------- resources/escalation

  Future<void> requestResources(AppUser actor, String incidentId, String description) async {
    final i = await _manageable(actor, incidentId);
    if (description.trim().length < 5) {
      throw const ValidationException(['Describe what is needed (at least 5 characters).']);
    }
    await _db.transaction((txn) async {
      await txn.insert('resource_requests', {
        'id': _uuid.v4(),
        'incident_id': incidentId,
        'requested_by': actor.id,
        'description': description.trim(),
        'state': 'open',
        'created_at': _ts,
      });
      await _history(txn, incidentId, i.status, actor.id,
          'Resources requested: ${description.trim()}');
      await _audit(txn, actor.id, 'resource_request', '$incidentId: ${description.trim()}');
      await _notifyAdmins(txn, 'Resource request',
          '${actor.name} needs resources for $incidentId: ${description.trim()}', incidentId);
    });
  }

  Future<List<ResourceRequest>> resourceRequests(AppUser actor, {String? incidentId}) async {
    _staff(actor);
    final rows = await _db.rawQuery('''
      SELECT r.*, u.name AS who, i.department_id AS dept FROM resource_requests r
      JOIN users u ON u.id = r.requested_by JOIN incidents i ON i.id = r.incident_id
      ${incidentId == null ? '' : 'WHERE r.incident_id = ?'}
      ORDER BY r.created_at DESC''', [?incidentId]);
    return rows
        .where((r) => actor.role == UserRole.admin || r['dept'] == actor.departmentId)
        .map((r) => ResourceRequest(
              id: r['id'] as String,
              incidentId: r['incident_id'] as String,
              requestedByName: r['who'] as String,
              description: r['description'] as String,
              state: ResourceState.values.byName(r['state'] as String),
              decisionNote: r['decision_note'] as String?,
              createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
            ))
        .toList();
  }

  Future<void> decideResources(AppUser admin, String requestId, bool approve, String note) async {
    _admin(admin);
    final r = await _db.query('resource_requests', where: "id = ? AND state = 'open'", whereArgs: [requestId]);
    if (r.isEmpty) throw const NotFoundException('Request not found or already decided.');
    await _db.transaction((txn) async {
      await txn.update(
          'resource_requests',
          {'state': approve ? 'approved' : 'declined', 'decision_note': note.trim(), 'decided_at': _ts},
          where: 'id = ?',
          whereArgs: [requestId]);
      await _audit(txn, admin.id, approve ? 'resource_approved' : 'resource_declined',
          '${r.first['incident_id']}: ${note.trim()}');
      await _notify(txn, r.first['requested_by'] as String,
          approve ? 'Resources approved' : 'Resources declined',
          '${r.first['incident_id']}: ${note.trim()}', r.first['incident_id'] as String);
    });
  }

  /// Officer escalates an unresolved case to administrators.
  Future<void> escalate(AppUser actor, String incidentId, String reason) async {
    final i = await _manageable(actor, incidentId);
    if (!i.status.isOpen) throw const ValidationException(['This report is already closed.']);
    if (reason.trim().length < 5) {
      throw const ValidationException(['Give a reason (at least 5 characters).']);
    }
    if (i.escalationLevel >= 3) {
      throw const ValidationException(['This report is already at the highest escalation level.']);
    }
    await _db.transaction((txn) async {
      await txn.update('incidents',
          {'escalated': 1, 'escalation_level': i.escalationLevel + 1, 'updated_at': _ts},
          where: 'id = ?', whereArgs: [incidentId]);
      await _history(txn, incidentId, i.status, actor.id,
          'Escalated (level ${i.escalationLevel + 1}) by ${actor.name}: ${reason.trim()}');
      await _audit(txn, actor.id, 'escalation', '$incidentId: ${reason.trim()}');
      await _notifyAdmins(txn, 'Case escalated',
          '$incidentId escalated by ${actor.name}: ${reason.trim()}', incidentId);
    });
  }

  // ------------------------------------------------------------------ notes

  Future<void> addNote(AppUser actor, String incidentId, String body) async {
    await _manageable(actor, incidentId);
    if (body.trim().length < 2 || body.length > 1000) {
      throw const ValidationException(['Notes must be 2 to 1000 characters.']);
    }
    await _db.insert('internal_notes', {
      'id': _uuid.v4(),
      'incident_id': incidentId,
      'author_id': actor.id,
      'body': body.trim(),
      'created_at': _ts,
    });
  }

  /// Internal notes are never shown to citizens.
  Future<List<InternalNote>> notes(AppUser actor, String incidentId) async {
    await _manageable(actor, incidentId);
    final rows = await _db.rawQuery('''
      SELECT n.body, n.created_at, u.name FROM internal_notes n JOIN users u ON u.id = n.author_id
      WHERE n.incident_id = ? ORDER BY n.created_at DESC''', [incidentId]);
    return rows
        .map((r) => InternalNote(r['name'] as String, r['body'] as String,
            DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int)))
        .toList();
  }

  // --------------------------------------------------------------- evidence

  Future<void> addEvidence({
    required AppUser actor,
    required String incidentId,
    required PhotoKind kind,
    required String path,
    required int sizeBytes,
  }) async {
    final i = await _manageable(actor, incidentId);
    if (!i.status.isOpen && i.status != IncidentStatus.resolved) {
      throw const ValidationException(['Photos cannot be added to this report any more.']);
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
      await _history(txn, incidentId, i.status, actor.id,
          '${kind == PhotoKind.before ? 'Before' : 'After (resolution evidence)'} photo added');
      await _audit(txn, actor.id, 'evidence_added', '$incidentId: ${kind.name}');
    });
  }

  /// Before/after photos. Citizens may see them for their own reports, and for
  /// the parent report their duplicate is linked to.
  Future<List<RepairPhoto>> evidence(AppUser user, String incidentId) async {
    final i = await _incidents.getVisible(user, incidentId);
    final ids = [incidentId, if (i.duplicateOfId != null) i.duplicateOfId!];
    final rows = await _db.rawQuery('''
      SELECT p.*, u.name AS who FROM repair_photos p JOIN users u ON u.id = p.added_by
      WHERE p.incident_id IN (${ids.map((_) => '?').join(',')}) ORDER BY p.created_at''', ids);
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

  // ------------------------------------------------- nearby and supporters

  /// Open reports near a point, in the limited form a citizen may see.
  Future<List<PublicIncident>> nearby(AppUser user,
      {required double latitude, required double longitude, double radiusMeters = 1500}) async {
    final rows = await _db.query('incidents',
        where: 'duplicate_of_id IS NULL AND latitude IS NOT NULL AND status NOT IN (?,?,?)',
        whereArgs: ['withdrawn', 'rejected', 'closed']);
    final out = <PublicIncident>[];
    for (final r in rows) {
      final i = Incident.fromMap(r);
      final d = distanceMeters(latitude, longitude, i.latitude!, i.longitude!);
      if (d > radiusMeters) continue;
      out.add(await _public(user, i, d));
    }
    out.sort((a, b) => a.distanceMeters!.compareTo(b.distanceMeters!));
    return out;
  }

  /// Every open report in the city, in the same limited form, newest first.
  /// Needs no GPS, so anyone can see what is being reported around them.
  Future<List<PublicIncident>> openCityWide(AppUser user, {int limit = 200}) async {
    final rows = await _db.query('incidents',
        where: 'duplicate_of_id IS NULL AND status NOT IN (?,?,?)',
        whereArgs: ['withdrawn', 'rejected', 'closed'],
        orderBy: 'created_at DESC',
        limit: limit);
    final out = <PublicIncident>[];
    for (final r in rows) {
      out.add(await _public(user, Incident.fromMap(r), null));
    }
    return out;
  }

  /// The limited public view of one report: no description, name or photo, and
  /// coordinates rounded to about 100 m.
  Future<PublicIncident> _public(AppUser user, Incident i, double? distance) async {
    final mine = await _db.query('incident_supporters',
        where: 'incident_id = ? AND user_id = ?', whereArgs: [i.id, user.id]);
    return PublicIncident(
      id: i.id,
      category: i.category,
      status: i.status,
      areaText: _coarse(i.locationText),
      latitude: i.latitude == null ? null : double.parse(i.latitude!.toStringAsFixed(3)),
      longitude: i.longitude == null ? null : double.parse(i.longitude!.toStringAsFixed(3)),
      distanceMeters: distance,
      citizens: await _count(i.id),
      supportedByMe: mine.isNotEmpty || i.reporterId == user.id,
      createdAt: i.createdAt,
    );
  }

  Future<int> _count(String id) => _incidents.reporterCount(id);

  /// Keeps only the first part of the location text (street/area), which is
  /// what a neighbour needs to recognise the problem.
  String _coarse(String text) {
    final first = text.split(RegExp(r'[,;\n]')).first.trim();
    return first.length > 40 ? '${first.substring(0, 40)}…' : first;
  }

  /// "I have this problem too." One vote per citizen; not for your own report.
  Future<int> support(AppUser citizen, String incidentId) async {
    if (citizen.role != UserRole.citizen) {
      throw const PermissionDeniedException('Only citizens can support a report.');
    }
    final rows = await _db.query('incidents', where: 'id = ?', whereArgs: [incidentId]);
    if (rows.isEmpty) throw const NotFoundException();
    final i = Incident.fromMap(rows.first);
    if (i.duplicateOfId != null || !i.status.isOpen) {
      throw const ValidationException(['This report is not open for support.']);
    }
    if (i.reporterId == citizen.id) {
      throw const ValidationException(['You already reported this problem.']);
    }
    final dup = await _db.query('incident_supporters',
        where: 'incident_id = ? AND user_id = ?', whereArgs: [incidentId, citizen.id]);
    if (dup.isNotEmpty) throw const ValidationException(['You already supported this report.']);
    await _db.transaction((txn) async {
      await txn.insert('incident_supporters',
          {'incident_id': incidentId, 'user_id': citizen.id, 'created_at': _ts});
      await _history(txn, incidentId, i.status, citizen.id, 'A citizen confirmed the same problem');
      await _incidents.rescoreParent(txn, incidentId, citizen.id);
      await _notify(txn, i.reporterId, 'Others see it too',
          'Another citizen confirmed $incidentId.', incidentId);
    });
    return _count(incidentId);
  }

  // --------------------------------------------------------------- feedback

  /// Ids of reports this person has given feedback on (used for credit points).
  Future<Set<String>> feedbackIncidentIds(AppUser citizen) async {
    final rows = await _db.query('feedback',
        columns: ['incident_id'], where: 'user_id = ?', whereArgs: [citizen.id]);
    return {for (final r in rows) r['incident_id'] as String};
  }

  /// Citizen verification after resolution. Confirming closes the report; if
  /// the problem is not fixed the report is reopened for review.
  Future<void> submitFeedback({
    required AppUser citizen,
    required String incidentId,
    required int rating,
    String? comment,
    required bool confirmedFixed,
  }) async {
    final i = await _incidents.getVisible(citizen, incidentId);
    if (i.reporterId != citizen.id) {
      throw const PermissionDeniedException('Only the reporter can give feedback.');
    }
    if (i.status != IncidentStatus.resolved) {
      throw const ValidationException(['Feedback is possible once a report is resolved.']);
    }
    if (rating < 1 || rating > 5) throw const ValidationException(['Rating must be 1 to 5.']);
    if ((comment?.length ?? 0) > 500) throw const ValidationException(['Comment is too long.']);
    final done = await _db.query('feedback', where: 'incident_id = ?', whereArgs: [incidentId]);
    if (done.isNotEmpty) throw const ValidationException(['Feedback was already given.']);
    await _db.transaction((txn) async {
      await txn.insert('feedback', {
        'id': _uuid.v4(),
        'incident_id': incidentId,
        'user_id': citizen.id,
        'rating': rating,
        'comment': comment?.trim().isEmpty ?? true ? null : comment!.trim(),
        'confirmed_fixed': confirmedFixed ? 1 : 0,
        'created_at': _ts,
      });
      if (confirmedFixed) {
        await txn.update('incidents', {'status': 'closed', 'updated_at': _ts},
            where: 'id = ?', whereArgs: [incidentId]);
        await _history(txn, incidentId, IncidentStatus.closed, citizen.id,
            'Citizen confirmed the fix (rating $rating/5). Report closed.');
      } else {
        await txn.update('incidents', {'status': 'underReview', 'updated_at': _ts},
            where: 'id = ?', whereArgs: [incidentId]);
        await _history(txn, incidentId, IncidentStatus.underReview, citizen.id,
            'Citizen says it is NOT fixed (rating $rating/5). Reopened for review.');
        final officers = await txn.query('users',
            where: "role = 'officer' AND is_active = 1 AND department_id = ?",
            whereArgs: [i.departmentId]);
        for (final o in officers) {
          await _notify(txn, o['id'] as String, 'Report reopened',
              '$incidentId was reported as not fixed.', incidentId);
        }
        await _notifyAdmins(txn, 'Report reopened', '$incidentId was reported as not fixed.', incidentId);
      }
      await _audit(txn, citizen.id, 'feedback', '$incidentId: $rating/5 fixed=$confirmedFixed');
    });
  }

  Future<FeedbackEntry?> feedbackFor(AppUser user, String incidentId) async {
    await _incidents.getVisible(user, incidentId);
    final r = await _db.query('feedback', where: 'incident_id = ?', whereArgs: [incidentId]);
    if (r.isEmpty) return null;
    return _fb(r.first, null);
  }

  FeedbackEntry _fb(Map<String, Object?> r, String? dept) => FeedbackEntry(
        incidentId: r['incident_id'] as String,
        rating: r['rating'] as int,
        comment: r['comment'] as String?,
        confirmedFixed: (r['confirmed_fixed'] as int) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        departmentId: dept,
      );

  /// All feedback with its department, for analytics. Staff only; officers
  /// get their own department.
  Future<List<FeedbackEntry>> allFeedback(AppUser actor) async {
    _staff(actor);
    final rows = await _db.rawQuery('''
      SELECT f.*, i.department_id AS dept FROM feedback f JOIN incidents i ON i.id = f.incident_id''');
    return rows
        .where((r) => actor.role == UserRole.admin || r['dept'] == actor.departmentId)
        .map((r) => _fb(r, r['dept'] as String?))
        .toList();
  }

  // ------------------------------------------------------------ maintenance

  /// Housekeeping that runs when staff open the app: sets missing deadlines,
  /// assigns unassigned reports to the least-loaded officer, escalates
  /// overdue reports and closes resolved reports nobody answered for
  /// [autoCloseDays] days. Safe to run repeatedly. Administrators act on the
  /// whole city, officers on their department.
  Future<MaintenanceReport> runMaintenance(AppUser actor) async {
    _staff(actor);
    final now = _now();
    var backfilled = 0, assigned = 0, escalated = 0, closed = 0;
    final scope = actor.role == UserRole.admin ? '' : 'AND department_id = ?';
    final args = actor.role == UserRole.admin ? <Object?>[] : [actor.departmentId];

    // 1. SLA deadlines for reports that have none (older data).
    final noSla = await _db.query('incidents',
        where: 'sla_due_at IS NULL $scope', whereArgs: args);
    for (final r in noSla) {
      final i = Incident.fromMap(r);
      await _db.update('incidents',
          {'sla_due_at': Sla.due(i.createdAt, i.priority).millisecondsSinceEpoch},
          where: 'id = ?', whereArgs: [i.id]);
      backfilled++;
    }

    // 2. Auto-assign open parent reports that have no officer.
    // Only on an administrator's phone, so two phones never assign the same
    // report; and only while automatic routing is switched on.
    final open = actor.role == UserRole.admin && await routingEnabled()
        ? await _db.query('incidents',
            where: "status IN ('submitted','underReview') AND assigned_officer_id IS NULL "
                'AND duplicate_of_id IS NULL $scope',
            whereArgs: args,
            orderBy: 'priority_score DESC, created_at')
        : <Map<String, Object?>>[];
    for (final r in open) {
      final i = Incident.fromMap(r);
      final o = await leastLoadedOfficer(i.departmentId);
      if (o == null) continue;
      try {
        await assign(
            actor: actor,
            incidentId: i.id,
            officerId: o.id,
            note: 'Automatic assignment to the least-loaded officer');
        assigned++;
      } catch (_) {/* leave for manual handling */}
    }

    // 3. Escalate overdue open parents.
    final overdue = await _db.query('incidents',
        where: "status IN ('submitted','underReview','assigned','inProgress') "
            'AND duplicate_of_id IS NULL AND sla_due_at IS NOT NULL AND sla_due_at < ? $scope',
        whereArgs: [now.millisecondsSinceEpoch, ...args]);
    for (final r in overdue) {
      final i = Incident.fromMap(r);
      final window = i.slaDueAt!.difference(i.createdAt);
      final late = now.difference(i.slaDueAt!);
      final level = late >= window ? 2 : 1;
      if (i.escalationLevel >= level) continue;
      await _db.transaction((txn) async {
        await txn.update('incidents',
            {'escalated': 1, 'escalation_level': level, 'updated_at': _ts},
            where: 'id = ?', whereArgs: [i.id]);
        await _history(txn, i.id, i.status, actor.id,
            'Automatically escalated to level $level: past its ${Sla.label(i.priority)} deadline '
            '(due ${i.slaDueAt!.toIso8601String().substring(0, 10)})');
        await _audit(txn, actor.id, 'auto_escalation', '${i.id} level $level');
        await _notifyAdmins(txn, 'Overdue: escalated',
            '${i.id} is past its deadline (level $level).', i.id);
        if (i.assignedOfficerId != null) {
          await _notify(txn, i.assignedOfficerId!, 'Your case is overdue',
              '${i.id} passed its deadline and was escalated.', i.id);
        }
      });
      escalated++;
    }

    // 4. Auto-close resolved reports with no citizen answer.
    final resolved = await _db.rawQuery('''
      SELECT i.*, (SELECT MAX(h.created_at) FROM status_history h
                   WHERE h.incident_id = i.id AND h.status = 'resolved') AS resolved_at
      FROM incidents i WHERE i.status = 'resolved' ${scope.replaceFirst('AND ', 'AND i.')}''', args);
    for (final r in resolved) {
      final at = r['resolved_at'] as int?;
      if (at == null) continue;
      if (now.difference(DateTime.fromMillisecondsSinceEpoch(at)).inDays < autoCloseDays) continue;
      final fb = await _db.query('feedback', where: 'incident_id = ?', whereArgs: [r['id']]);
      if (fb.isNotEmpty) continue;
      await _db.transaction((txn) async {
        await txn.update('incidents', {'status': 'closed', 'updated_at': _ts},
            where: 'id = ?', whereArgs: [r['id']]);
        await _history(txn, r['id'] as String, IncidentStatus.closed, actor.id,
            'Closed automatically: no citizen response for $autoCloseDays days after resolution');
        await _audit(txn, actor.id, 'auto_close', r['id'] as String);
      });
      closed++;
    }

    return MaintenanceReport(
        slaBackfilled: backfilled, autoAssigned: assigned, escalated: escalated, autoClosed: closed);
  }
}
