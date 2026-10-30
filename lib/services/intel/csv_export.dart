import '../../core/constants/enums.dart';
import '../../domain/models/incident.dart';
import 'performance.dart';

/// Builds CSV text. Cells starting with = + - @ are prefixed with an
/// apostrophe so spreadsheets do not run them as formulas.
class CsvExport {
  static String cell(Object? v) {
    var s = v?.toString() ?? '';
    if (s.isNotEmpty && '=+-@\t\r'.contains(s[0])) s = "'$s";
    if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
      s = '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String _row(List<Object?> r) => r.map(cell).join(',');

  /// No reporter identity and no free text: only operational fields.
  static String incidents(List<Incident> list, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final b = StringBuffer(_row([
      'id', 'category', 'department', 'priority', 'status', 'created', 'sla_due',
      'overdue', 'escalation_level', 'latitude', 'longitude', 'linked_to', 'ai_source',
      'ai_confidence_percent', 'data_source',
    ]))..writeln();
    for (final i in list) {
      b.writeln(_row([
        i.id,
        i.category.label,
        Departments.nameOf(i.departmentId),
        i.priority.label,
        i.status.label,
        i.createdAt.toIso8601String(),
        i.slaDueAt?.toIso8601String(),
        i.isOverdue(t) ? 'yes' : 'no',
        i.escalationLevel,
        i.latitude,
        i.longitude,
        i.duplicateOfId,
        i.aiProvider,
        i.aiConfidence == null ? '' : (i.aiConfidence! * 100).round(),
        i.dataSource,
      ]));
    }
    return b.toString();
  }

  static String departments(List<DepartmentStats> stats) {
    final b = StringBuffer(_row([
      'department', 'total', 'open', 'resolved', 'overdue', 'escalated',
      'avg_response_hours', 'avg_resolution_hours', 'sla_compliance_percent',
      'avg_rating', 'ratings',
    ]))..writeln();
    String n(double? v, [int d = 1]) => v == null ? '' : v.toStringAsFixed(d);
    for (final s in stats) {
      b.writeln(_row([
        Departments.nameOf(s.departmentId), s.total, s.open, s.resolved, s.overdue, s.escalated,
        n(s.avgResponseHours), n(s.avgResolutionHours),
        s.slaCompliance == null ? '' : (s.slaCompliance! * 100).round(),
        n(s.avgRating), s.ratings,
      ]));
    }
    return b.toString();
  }
}
