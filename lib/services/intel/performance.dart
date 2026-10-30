import '../../core/constants/enums.dart';
import '../../domain/models/incident.dart';
import '../../domain/models/workflow.dart';

/// Timestamps pulled from the status history.
class IncidentTimes {
  const IncidentTimes({this.firstResponseAt, this.resolvedAt});
  final DateTime? firstResponseAt, resolvedAt;
}

class DepartmentStats {
  const DepartmentStats({
    required this.departmentId,
    required this.total,
    required this.open,
    required this.resolved,
    required this.overdue,
    required this.escalated,
    this.avgResponseHours,
    this.avgResolutionHours,
    this.slaCompliance,
    this.avgRating,
    this.fixedConfirmedShare,
    required this.ratings,
  });
  final String departmentId;
  final int total, open, resolved, overdue, escalated, ratings;
  final double? avgResponseHours, avgResolutionHours;

  /// Share (0..1) of resolved reports that were resolved by their deadline.
  final double? slaCompliance;
  final double? avgRating;

  /// Of citizens who answered, the share who said it was really fixed.
  final double? fixedConfirmedShare;
}

class PerformanceCalculator {
  const PerformanceCalculator();

  List<DepartmentStats> byDepartment({
    required List<Incident> incidents,
    required Map<String, IncidentTimes> times,
    required List<FeedbackEntry> feedback,
    required DateTime now,
  }) {
    // Linked duplicates are the same problem as their parent: count once.
    final parents = incidents.where((i) => i.duplicateOfId == null).toList();
    final ids = parents.map((i) => i.departmentId).toSet().toList()..sort();
    final out = <DepartmentStats>[];
    for (final d in ids) {
      final mine = parents.where((i) => i.departmentId == d).toList();
      final resp = <double>[], res = <double>[];
      var met = 0, resolvedCount = 0;
      for (final i in mine) {
        final t = times[i.id];
        if (t?.firstResponseAt != null) {
          resp.add(t!.firstResponseAt!.difference(i.createdAt).inMinutes / 60);
        }
        if (t?.resolvedAt != null) {
          resolvedCount++;
          res.add(t!.resolvedAt!.difference(i.createdAt).inMinutes / 60);
          if (i.slaDueAt != null && !t.resolvedAt!.isAfter(i.slaDueAt!)) met++;
        }
      }
      final fb = feedback.where((f) => f.departmentId == d).toList();
      double? avg(List<double> l) => l.isEmpty ? null : l.reduce((a, b) => a + b) / l.length;
      out.add(DepartmentStats(
        departmentId: d,
        total: mine.length,
        open: mine.where((i) => i.status.isOpen).length,
        resolved: mine.where((i) => i.status == IncidentStatus.resolved || i.status == IncidentStatus.closed).length,
        overdue: mine.where((i) => i.isOverdue(now)).length,
        escalated: mine.where((i) => i.escalated && i.status.isOpen).length,
        avgResponseHours: avg(resp),
        avgResolutionHours: avg(res),
        slaCompliance: resolvedCount == 0 ? null : met / resolvedCount,
        avgRating: fb.isEmpty ? null : fb.map((f) => f.rating).reduce((a, b) => a + b) / fb.length,
        fixedConfirmedShare: fb.isEmpty ? null : fb.where((f) => f.confirmedFixed).length / fb.length,
        ratings: fb.length,
      ));
    }
    return out;
  }
}

/// Plain-language city summary built from fixed templates over the data. It is
/// NOT written by a language model, and the UI says so.
class DailySummary {
  static const method =
      'Generated from fixed text templates over the figures below. Not written by a language model.';

  static List<String> generate({
    required DateTime now,
    required List<Incident> incidents,
    required Map<String, IncidentTimes> times,
    required List<DepartmentStats> departments,
    required List<String> hotspotLines,
  }) {
    final parents = incidents.where((i) => i.duplicateOfId == null).toList();
    final dayAgo = now.subtract(const Duration(hours: 24));
    final fresh = parents.where((i) => i.createdAt.isAfter(dayAgo)).toList();
    final resolvedToday = parents.where((i) {
      final r = times[i.id]?.resolvedAt;
      return r != null && r.isAfter(dayAgo);
    }).length;
    final open = parents.where((i) => i.status.isOpen).toList();
    final critical = open.where((i) => i.priority == Priority.critical).length;
    final overdue = open.where((i) => i.isOverdue(now)).length;
    final lines = <String>[];

    if (parents.isEmpty) {
      return ['No reports have been filed yet, so there is nothing to summarise.'];
    }
    lines.add('In the last 24 hours ${fresh.length} new '
        '${fresh.length == 1 ? 'problem was' : 'problems were'} reported and $resolvedToday '
        '${resolvedToday == 1 ? 'was' : 'were'} resolved.');
    lines.add('${open.length} ${open.length == 1 ? 'case is' : 'cases are'} open: '
        '$critical critical, $overdue past deadline.');
    if (fresh.isNotEmpty) {
      final c = <IncidentCategory, int>{};
      for (final i in fresh) {
        c[i.category] = (c[i.category] ?? 0) + 1;
      }
      final top = (c.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first;
      lines.add('Most new reports: ${top.key.label} (${top.value}).');
    }
    final worst = departments.where((d) => d.overdue > 0).toList()
      ..sort((a, b) => b.overdue.compareTo(a.overdue));
    if (worst.isNotEmpty) {
      lines.add('${Departments.nameOf(worst.first.departmentId)} has the most overdue cases '
          '(${worst.first.overdue}).');
    }
    final rated = departments.where((d) => d.avgRating != null).toList();
    if (rated.isNotEmpty) {
      final all = rated.fold<double>(0, (a, d) => a + d.avgRating! * d.ratings);
      final n = rated.fold<int>(0, (a, d) => a + d.ratings);
      lines.add('Citizen satisfaction so far: ${(all / n).toStringAsFixed(1)} out of 5 from $n responses.');
    }
    lines.addAll(hotspotLines);
    return lines;
  }
}
