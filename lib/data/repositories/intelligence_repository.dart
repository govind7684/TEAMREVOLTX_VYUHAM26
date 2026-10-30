import 'package:sqflite/sqflite.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exceptions.dart';
import '../../domain/models/incident.dart';
import '../../domain/models/user.dart';
import '../../domain/models/workflow.dart';
import '../../services/intel/clustering.dart';
import '../../services/intel/csv_export.dart';
import '../../services/intel/performance.dart';
import '../../services/intel/recurrence.dart';
import 'incident_repository.dart';
import 'workflow_repository.dart';

class IntelSnapshot {
  const IntelSnapshot({
    required this.now,
    required this.incidents,
    required this.times,
    required this.feedback,
    required this.departments,
    required this.recurring,
    required this.insights,
    required this.clusters,
    required this.summary,
  });
  final DateTime now;
  final List<Incident> incidents;
  final Map<String, IncidentTimes> times;
  final List<FeedbackEntry> feedback;
  final List<DepartmentStats> departments;
  final List<RecurringFault> recurring;
  final List<MaintenanceInsight> insights;
  final List<Cluster> clusters;
  final List<String> summary;

  List<Incident> get overdue =>
      incidents.where((i) => i.duplicateOfId == null && i.isOverdue(now)).toList();
}

/// Reads what staff are allowed to see and runs the pure analytics over it.
class IntelligenceRepository {
  IntelligenceRepository(this._db,
      {required IncidentRepository incidents,
      required WorkflowRepository workflow,
      DateTime Function()? clock})
      : _incidents = incidents,
        _workflow = workflow,
        _now = clock ?? DateTime.now;

  final Database _db;
  final IncidentRepository _incidents;
  final WorkflowRepository _workflow;
  final DateTime Function() _now;

  Future<IntelSnapshot> snapshot(AppUser actor) async {
    if (!actor.isStaff) throw const PermissionDeniedException('Staff access only.');
    final now = _now();
    final all = await _incidents.listVisible(actor);
    final times = <String, IncidentTimes>{};
    final rows = await _db.rawQuery('''
      SELECT incident_id,
        MIN(CASE WHEN status IN ('assigned','inProgress') THEN created_at END) AS first_resp,
        MAX(CASE WHEN status = 'resolved' THEN created_at END) AS resolved
      FROM status_history GROUP BY incident_id''');
    for (final r in rows) {
      DateTime? d(Object? v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);
      times[r['incident_id'] as String] =
          IncidentTimes(firstResponseAt: d(r['first_resp']), resolvedAt: d(r['resolved']));
    }
    final feedback = await _workflow.allFeedback(actor);
    const calc = PerformanceCalculator();
    final depts = calc.byDepartment(incidents: all, times: times, feedback: feedback, now: now);
    const rec = RecurrenceAnalyzer();
    final recurring = rec.detect(all, now);
    final parents = all.where((i) => i.duplicateOfId == null).toList();
    final clusters = const GeoClusterer().cluster(parents.where((i) => i.status.isOpen));
    final hotLines = [
      if (clusters.isNotEmpty && clusters.first.count >= 2)
        'Busiest area: ${clusters.first.count} open problems within 250 m of '
            '${clusters.first.items.first.locationText}.',
      if (recurring.isNotEmpty)
        '${recurring.length} recurring fault location${recurring.length == 1 ? '' : 's'} detected.',
    ];
    return IntelSnapshot(
      now: now,
      incidents: all,
      times: times,
      feedback: feedback,
      departments: depts,
      recurring: recurring,
      insights: rec.insights(all, now),
      clusters: clusters,
      summary: DailySummary.generate(
          now: now, incidents: all, times: times, departments: depts, hotspotLines: hotLines),
    );
  }

  /// CSV text for download. Logged in the audit trail.
  Future<String> exportIncidentsCsv(AppUser actor) async {
    final s = await snapshot(actor);
    await _db.insert('audit_log', {
      'actor_id': actor.id,
      'action': 'export',
      'detail': 'incidents csv (${s.incidents.length} rows)',
      'created_at': _now().millisecondsSinceEpoch,
    });
    return CsvExport.incidents(s.incidents, now: s.now);
  }

  Future<String> exportPerformanceCsv(AppUser actor) async {
    final s = await snapshot(actor);
    await _db.insert('audit_log', {
      'actor_id': actor.id,
      'action': 'export',
      'detail': 'department performance csv',
      'created_at': _now().millisecondsSinceEpoch,
    });
    return CsvExport.departments(s.departments);
  }

  /// Open reports per module, for the module hub badges.
  Map<IncidentCategory, int> openByCategory(List<Incident> list) {
    final m = <IncidentCategory, int>{};
    for (final i in list.where((i) => i.status.isOpen && i.duplicateOfId == null)) {
      m[i.category] = (m[i.category] ?? 0) + 1;
    }
    return m;
  }
}
