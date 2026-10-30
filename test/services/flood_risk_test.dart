import 'package:civinex_ai/domain/models/flood.dart';
import 'package:civinex_ai/services/flood_risk.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 30, 12);

RainfallReading _r(String station, double mm,
    {double? level, int minutesAgo = 0, ReadingSource src = ReadingSource.manual}) {
  return RainfallReading(
    id: '$station-$mm-$minutesAgo',
    stationName: station,
    rainfallMm: mm,
    waterLevelCm: level,
    recordedAt: _now.subtract(Duration(minutes: minutesAgo)),
    source: src,
    isDemo: false,
  );
}

FloodRiskAssessment _est(List<RainfallReading> r, {int reports = 0, FloodConfig? cfg}) =>
    FloodRiskEstimator.estimate(
        readings: r,
        recentFloodReports: reports,
        config: cfg ?? const FloodConfig(),
        now: _now);

void main() {
  group('FloodRiskEstimator', () {
    test('no readings is Normal but says so is not proof of safety', () {
      final a = _est([]);
      expect(a.level, FloodRiskLevel.normal);
      expect(a.hasRecentReadings, isFalse);
      expect(a.reasons.join(' '), contains('does NOT mean'));
    });

    test('rain is summed per station over 3 h and worst station wins', () {
      final a = _est([
        _r('A', 20, minutesAgo: 10),
        _r('A', 20, minutesAgo: 70), // A total 40 -> Watch
        _r('B', 25, minutesAgo: 10), // B total 25
      ]);
      expect(a.rain3hMm, 40);
      expect(a.level, FloodRiskLevel.watch);
    });

    test('readings older than 3 hours are ignored for rain', () {
      final a = _est([_r('A', 200, minutesAgo: 181)]);
      expect(a.rain3hMm, isNull);
      expect(a.level, FloodRiskLevel.normal);
    });

    test('water level uses latest reading per station', () {
      final a = _est([
        _r('A', 0, level: 160, minutesAgo: 120), // old high level
        _r('A', 0, level: 40, minutesAgo: 10), // latest, below Watch
      ]);
      expect(a.maxWaterLevelCm, 40);
      expect(a.level, FloodRiskLevel.normal);
    });

    test('thresholds map to Watch / Warning / Severe', () {
      expect(_est([_r('A', 30)]).level, FloodRiskLevel.watch);
      expect(_est([_r('A', 60)]).level, FloodRiskLevel.warning);
      expect(_est([_r('A', 100)]).level, FloodRiskLevel.severe);
      expect(_est([_r('A', 0, level: 100)]).level, FloodRiskLevel.warning);
    });

    test('open flood reports raise the level one step, capped at Severe', () {
      expect(_est([], reports: 3).level, FloodRiskLevel.watch);
      expect(_est([_r('A', 60)], reports: 3).level, FloodRiskLevel.severe);
      expect(_est([_r('A', 100)], reports: 10).level, FloodRiskLevel.severe);
      expect(_est([], reports: 2).level, FloodRiskLevel.normal);
    });

    test('simulated data is flagged', () {
      final a = _est([_r('A', 5, src: ReadingSource.simulated)]);
      expect(a.usesSimulatedData, isTrue);
      expect(_est([_r('A', 5)]).usesSimulatedData, isFalse);
    });

    test('custom thresholds are honoured', () {
      const cfg = FloodConfig(rainWatch: 5, rainWarning: 10, rainSevere: 20);
      expect(_est([_r('A', 12)], cfg: cfg).level, FloodRiskLevel.warning);
    });

    test('future-dated readings are ignored', () {
      final a = _est([_r('A', 200, minutesAgo: -30)]);
      expect(a.hasRecentReadings, isFalse);
    });
  });

  group('FloodConfig', () {
    test('validation rejects non-increasing thresholds', () {
      expect(const FloodConfig().validate(), isEmpty);
      expect(const FloodConfig(rainWatch: 60, rainWarning: 60).validate(), isNotEmpty);
      expect(const FloodConfig(levelSevere: 10).validate(), isNotEmpty);
      expect(const FloodConfig(reportBump: 0).validate(), isNotEmpty);
    });

    test('json round trip', () {
      const c = FloodConfig(rainWatch: 11, reportBump: 5);
      final back = FloodConfig.fromJson(c.toJson());
      expect(back.rainWatch, 11);
      expect(back.reportBump, 5);
      expect(back.levelWarning, const FloodConfig().levelWarning);
    });
  });
}
