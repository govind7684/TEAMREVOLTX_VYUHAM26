import 'dart:math';

import '../domain/models/flood.dart';

/// Transparent threshold rules. This is an unvalidated estimate from a few
/// numbers, not a forecast, and rainfall alone cannot predict flooding.
class FloodRiskEstimator {
  static const rainWindow = Duration(hours: 3);
  static const levelWindow = Duration(hours: 6);

  static int _rank(double v, double watch, double warning, double severe) {
    if (v >= severe) return 3;
    if (v >= warning) return 2;
    if (v >= watch) return 1;
    return 0;
  }

  static FloodRiskAssessment estimate({
    required Iterable<RainfallReading> readings,
    required int recentFloodReports,
    required FloodConfig config,
    required DateTime now,
  }) {
    final reasons = <String>[];
    var usesSim = false;

    // Rain: sum per station over the last 3 h (assumes one reading per hour
    // per station), then take the worst station.
    final rainByStation = <String, double>{};
    final rainReadings = readings.where((r) =>
        !r.recordedAt.isAfter(now) && now.difference(r.recordedAt) < rainWindow);
    for (final r in rainReadings) {
      rainByStation[r.stationName] = (rainByStation[r.stationName] ?? 0) + r.rainfallMm;
      if (r.source == ReadingSource.simulated) usesSim = true;
    }
    String? worstStation;
    double? rain3h;
    rainByStation.forEach((k, v) {
      if (rain3h == null || v > rain3h!) {
        rain3h = v;
        worstStation = k;
      }
    });

    // Water level: latest level per station within 6 h, worst station.
    final latestLevel = <String, RainfallReading>{};
    final levelReadings = readings.where((r) =>
        r.waterLevelCm != null &&
        !r.recordedAt.isAfter(now) &&
        now.difference(r.recordedAt) < levelWindow);
    for (final r in levelReadings) {
      final cur = latestLevel[r.stationName];
      if (cur == null || r.recordedAt.isAfter(cur.recordedAt)) {
        latestLevel[r.stationName] = r;
      }
    }
    RainfallReading? worstLevel;
    for (final r in latestLevel.values) {
      if (worstLevel == null || r.waterLevelCm! > worstLevel.waterLevelCm!) worstLevel = r;
      if (r.source == ReadingSource.simulated) usesSim = true;
    }

    var rank = 0;
    if (rain3h != null) {
      final rr = _rank(rain3h!, config.rainWatch, config.rainWarning, config.rainSevere);
      rank = max(rank, rr);
      reasons.add('Rain over the last 3 hours at $worstStation: '
          '${rain3h!.toStringAsFixed(0)} mm'
          '${rr > 0 ? ' (${FloodRiskLevel.values[rr].label} threshold '
              '${[config.rainWatch, config.rainWarning, config.rainSevere][rr - 1].toStringAsFixed(0)} mm)' : ' (below the Watch threshold of ${config.rainWatch.toStringAsFixed(0)} mm)'}.');
    }
    if (worstLevel != null) {
      final lv = worstLevel.waterLevelCm!;
      final lr = _rank(lv, config.levelWatch, config.levelWarning, config.levelSevere);
      rank = max(rank, lr);
      reasons.add('Water level at ${worstLevel.stationName}: ${lv.toStringAsFixed(0)} cm'
          '${lr > 0 ? ' (${FloodRiskLevel.values[lr].label} threshold '
              '${[config.levelWatch, config.levelWarning, config.levelSevere][lr - 1].toStringAsFixed(0)} cm)' : ' (below the Watch threshold of ${config.levelWatch.toStringAsFixed(0)} cm)'}.');
    }
    if (recentFloodReports >= config.reportBump && rank < 3) {
      rank += 1;
      reasons.add('$recentFloodReports open flooding or drain reports in the last 24 hours '
          '(escalation at ${config.reportBump}): raised one step.');
    } else if (recentFloodReports > 0) {
      reasons.add('$recentFloodReports open flooding or drain report'
          '${recentFloodReports == 1 ? '' : 's'} in the last 24 hours.');
    }

    final hasRecent = rain3h != null || worstLevel != null;
    if (!hasRecent) {
      reasons.add('No rainfall or water-level readings in the recent window. '
          'This does NOT mean there is no risk.');
    }

    return FloodRiskAssessment(
      level: FloodRiskLevel.values[rank],
      reasons: reasons,
      rain3hMm: rain3h,
      maxWaterLevelCm: worstLevel?.waterLevelCm,
      recentFloodReports: recentFloodReports,
      hasRecentReadings: hasRecent,
      usesSimulatedData: usesSim,
    );
  }

  static List<String> recommendedActions(FloodRiskLevel level) {
    switch (level) {
      case FloodRiskLevel.normal:
        return const ['No action suggested by the rules. Keep recording readings.'];
      case FloodRiskLevel.watch:
        return const [
          'Inspect drains at known waterlogging spots.',
          'Review open flooding and blocked-drain reports.',
        ];
      case FloodRiskLevel.warning:
        return const [
          'Prioritise clearing blocked drains and culverts.',
          'Plan traffic management for low-lying roads.',
          'Confirm conditions on the ground before acting.',
        ];
      case FloodRiskLevel.severe:
        return const [
          'Escalate to the administrator now.',
          'Follow official alerts from the state disaster management authority and the '
              'India Meteorological Department.',
          'Use official emergency channels. CIVINEX AI is not an emergency system.',
        ];
    }
  }
}
