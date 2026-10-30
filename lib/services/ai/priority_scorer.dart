import '../../core/constants/enums.dart';

class PriorityConfig {
  const PriorityConfig({
    this.mediumAt = 3,
    this.highAt = 6,
    this.criticalAt = 9,
  });
  final int mediumAt, highAt, criticalAt;
}

class PriorityResult {
  const PriorityResult(this.priority, this.score, this.reasons);
  final Priority priority;
  final int score;
  final List<String> reasons;
  String get reasonText => reasons.join('; ');
}

/// Hours allowed to resolve a report, by priority. Illustrative defaults; set
/// real service levels with the department.
class Sla {
  static const hours = {
    Priority.critical: 24,
    Priority.high: 72,
    Priority.medium: 168,
    Priority.low: 336,
  };
  static DateTime due(DateTime createdAt, Priority p) =>
      createdAt.add(Duration(hours: hours[p]!));
  static String label(Priority p) {
    final h = hours[p]!;
    return h < 48 ? '$h hours' : '${h ~/ 24} days';
  }
}

/// Explainable additive score. Every point comes with a stated reason.
class PriorityScorer {
  const PriorityScorer([this.config = const PriorityConfig()]);
  final PriorityConfig config;

  PriorityResult score({
    required IncidentCategory category,
    required bool safetyRisk,
    required int peopleAffected,
    required Duration unresolvedFor,
    required int similarReports,
    int locationPoints = 0,
    String? locationReason,
    int recurrences = 0,
    int reporterCount = 1,
  }) {
    var s = 0;
    final r = <String>[];

    s += category.baseSeverity;
    r.add('+${category.baseSeverity} base severity for ${category.label}');

    if (safetyRisk) {
      s += 4;
      r.add('+4 immediate safety risk');
    }
    if (peopleAffected >= 100) {
      s += 3;
      r.add('+3 about $peopleAffected people affected');
    } else if (peopleAffected >= 20) {
      s += 2;
      r.add('+2 about $peopleAffected people affected');
    } else if (peopleAffected >= 5) {
      s += 1;
      r.add('+1 several people affected');
    }
    if (unresolvedFor.inDays >= 7) {
      s += 2;
      r.add('+2 unresolved for ${unresolvedFor.inDays} days');
    } else if (unresolvedFor.inDays >= 3) {
      s += 1;
      r.add('+1 unresolved for ${unresolvedFor.inDays} days');
    }
    if (similarReports >= 3) {
      s += 2;
      r.add('+2 repeated reports nearby ($similarReports)');
    } else if (similarReports >= 1) {
      s += 1;
      r.add('+1 similar report nearby');
    }

    if (locationPoints > 0 && locationReason != null) {
      s += locationPoints;
      r.add(locationReason);
    }
    if (reporterCount >= 10) {
      s += 3;
      r.add('+3 reported by $reporterCount citizens');
    } else if (reporterCount >= 4) {
      s += 2;
      r.add('+2 reported by $reporterCount citizens');
    } else if (reporterCount >= 2) {
      s += 1;
      r.add('+1 reported by $reporterCount citizens');
    }
    if (recurrences >= 3) {
      s += 2;
      r.add('+2 recurring fault: $recurrences earlier reports at this spot');
    } else if (recurrences >= 1) {
      s += 1;
      r.add('+1 happened here before ($recurrences earlier report${recurrences == 1 ? '' : 's'})');
    }

    final p = s >= config.criticalAt
        ? Priority.critical
        : s >= config.highAt
            ? Priority.high
            : s >= config.mediumAt
                ? Priority.medium
                : Priority.low;
    return PriorityResult(p, s, r);
  }
}
