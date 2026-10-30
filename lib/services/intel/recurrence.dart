import '../../core/constants/enums.dart';
import '../../domain/models/incident.dart';
import 'clustering.dart';

/// A place where the same kind of fault keeps coming back.
class RecurringFault {
  const RecurringFault({
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.reports,
    required this.fixedBefore,
    required this.firstAt,
    required this.lastAt,
    required this.meanIntervalDays,
    required this.locationText,
  });
  final IncidentCategory category;
  final double latitude, longitude;
  final int reports;

  /// Earlier reports here that were resolved or closed, then the fault returned.
  final int fixedBefore;
  final DateTime firstAt, lastAt;
  final double? meanIntervalDays;
  final String locationText;
}

/// What kind of statement an insight is. Only [statisticalTrend] and
/// [statisticalProjection] exist: no forecasting model is trained in this app,
/// and the UI says so.
enum InsightKind { statisticalTrend, statisticalProjection }

class MaintenanceInsight {
  const MaintenanceInsight(this.kind, this.title, this.detail);
  final InsightKind kind;
  final String title, detail;
  String get kindLabel => kind == InsightKind.statisticalTrend
      ? 'Statistical trend (counts, not a prediction)'
      : 'Simple projection (average gap, not a trained model)';
}

class RecurrenceAnalyzer {
  const RecurrenceAnalyzer({this.radiusMeters = 100, this.window = const Duration(days: 180)});
  final double radiusMeters;
  final Duration window;

  /// Locations with three or more reports of one category in the window, or
  /// two where the first had already been fixed once.
  List<RecurringFault> detect(Iterable<Incident> incidents, DateTime now) {
    final recent = incidents.where((i) =>
        i.hasCoordinates &&
        i.duplicateOfId == null &&
        i.status != IncidentStatus.withdrawn &&
        i.status != IncidentStatus.rejected &&
        now.difference(i.createdAt) <= window);
    final out = <RecurringFault>[];
    for (final cat in IncidentCategory.values) {
      final clusters = GeoClusterer(radiusMeters: radiusMeters)
          .cluster(recent.where((i) => i.category == cat));
      for (final c in clusters) {
        final fixed = c.items
            .where((i) => i.status == IncidentStatus.resolved || i.status == IncidentStatus.closed)
            .length;
        if (c.count < 3 && !(c.count >= 2 && fixed >= 1)) continue;
        final times = c.items.map((i) => i.createdAt).toList()..sort();
        double? mean;
        if (times.length >= 2) {
          mean = times.last.difference(times.first).inHours / 24 / (times.length - 1);
        }
        out.add(RecurringFault(
          category: cat,
          latitude: c.latitude,
          longitude: c.longitude,
          reports: c.count,
          fixedBefore: fixed,
          firstAt: times.first,
          lastAt: times.last,
          meanIntervalDays: mean,
          locationText: c.items.first.locationText,
        ));
      }
    }
    out.sort((a, b) => b.reports.compareTo(a.reports));
    return out;
  }

  List<MaintenanceInsight> insights(Iterable<Incident> incidents, DateTime now) {
    final out = <MaintenanceInsight>[];
    final list = incidents.where((i) => i.duplicateOfId == null).toList();

    // Trend: last 30 days vs the 30 before, per category.
    for (final cat in IncidentCategory.values) {
      final cur = list.where((i) => i.category == cat && now.difference(i.createdAt).inDays < 30).length;
      final prev = list
          .where((i) =>
              i.category == cat &&
              now.difference(i.createdAt).inDays >= 30 &&
              now.difference(i.createdAt).inDays < 60)
          .length;
      if (cur + prev < 3 || cur == prev) continue;
      final dir = cur > prev ? 'up' : 'down';
      out.add(MaintenanceInsight(
        InsightKind.statisticalTrend,
        '${cat.label}: reports $dir',
        '$cur in the last 30 days against $prev in the 30 days before. '
        'Counts only; small numbers can change by chance.',
      ));
    }

    // Projection for recurring locations with a regular gap.
    for (final r in detect(list, now).where((r) => r.reports >= 3 && r.meanIntervalDays != null)) {
      final gap = r.meanIntervalDays!;
      if (gap < 1) continue;
      final next = r.lastAt.add(Duration(hours: (gap * 24).round()));
      out.add(MaintenanceInsight(
        InsightKind.statisticalProjection,
        '${r.category.label} near ${r.locationText}',
        '${r.reports} reports, about one every ${gap.toStringAsFixed(0)} days. If that gap '
        'continues, another report is likely around ${next.toIso8601String().substring(0, 10)}. '
        'Consider a permanent repair or inspection rather than another patch.',
      ));
    }
    return out;
  }
}
