enum ReadingSource { manual, simulated }

class RainfallReading {
  const RainfallReading({
    required this.id,
    required this.stationName,
    required this.rainfallMm,
    this.waterLevelCm,
    required this.recordedAt,
    required this.source,
    required this.isDemo,
  });

  final String id;
  final String stationName;

  /// Rain that fell in the hour ending at [recordedAt], in millimetres.
  final double rainfallMm;

  /// Water level in cm above whatever local reference the person uses.
  final double? waterLevelCm;
  final DateTime recordedAt;
  final ReadingSource source;
  final bool isDemo;

  factory RainfallReading.fromMap(Map<String, Object?> m) => RainfallReading(
        id: m['id'] as String,
        stationName: m['station_name'] as String,
        rainfallMm: (m['rainfall_mm'] as num).toDouble(),
        waterLevelCm: (m['water_level_cm'] as num?)?.toDouble(),
        recordedAt: DateTime.fromMillisecondsSinceEpoch(m['recorded_at'] as int),
        source: ReadingSource.values.byName(m['source'] as String),
        isDemo: (m['is_demo'] as int) == 1,
      );
}

/// Unsaved reading produced by the simulator.
class ReadingDraft {
  const ReadingDraft(this.stationName, this.rainfallMm, this.waterLevelCm, this.recordedAt);
  final String stationName;
  final double rainfallMm;
  final double? waterLevelCm;
  final DateTime recordedAt;
}

/// Thresholds for the rule-based estimate. The defaults are illustrative
/// placeholders, NOT calibrated for any Kerala location. An administrator
/// should set them from local knowledge.
class FloodConfig {
  const FloodConfig({
    this.rainWatch = 30,
    this.rainWarning = 60,
    this.rainSevere = 100,
    this.levelWatch = 50,
    this.levelWarning = 100,
    this.levelSevere = 150,
    this.reportBump = 3,
  });

  /// Rain summed over the last 3 hours at one station (mm).
  final double rainWatch, rainWarning, rainSevere;

  /// Water level (cm).
  final double levelWatch, levelWarning, levelSevere;

  /// This many open flood or drain reports in 24 h raises the level by one step.
  final int reportBump;

  List<String> validate() {
    final e = <String>[];
    if (rainWatch <= 0 || rainWatch >= rainWarning || rainWarning >= rainSevere) {
      e.add('Rain thresholds must be positive and increase: watch < warning < severe.');
    }
    if (levelWatch <= 0 || levelWatch >= levelWarning || levelWarning >= levelSevere) {
      e.add('Water level thresholds must be positive and increase: watch < warning < severe.');
    }
    if (reportBump < 1 || reportBump > 50) {
      e.add('Report count for escalation must be between 1 and 50.');
    }
    return e;
  }

  Map<String, Object?> toJson() => {
        'rainWatch': rainWatch,
        'rainWarning': rainWarning,
        'rainSevere': rainSevere,
        'levelWatch': levelWatch,
        'levelWarning': levelWarning,
        'levelSevere': levelSevere,
        'reportBump': reportBump,
      };

  factory FloodConfig.fromJson(Map<String, Object?> j) {
    const d = FloodConfig();
    double n(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return FloodConfig(
      rainWatch: n('rainWatch', d.rainWatch),
      rainWarning: n('rainWarning', d.rainWarning),
      rainSevere: n('rainSevere', d.rainSevere),
      levelWatch: n('levelWatch', d.levelWatch),
      levelWarning: n('levelWarning', d.levelWarning),
      levelSevere: n('levelSevere', d.levelSevere),
      reportBump: (j['reportBump'] as num?)?.toInt() ?? d.reportBump,
    );
  }
}

enum FloodRiskLevel {
  normal('Normal'),
  watch('Watch'),
  warning('Warning'),
  severe('Severe');

  const FloodRiskLevel(this.label);
  final String label;
}

class FloodRiskAssessment {
  const FloodRiskAssessment({
    required this.level,
    required this.reasons,
    required this.rain3hMm,
    required this.maxWaterLevelCm,
    required this.recentFloodReports,
    required this.hasRecentReadings,
    required this.usesSimulatedData,
  });

  final FloodRiskLevel level;
  final List<String> reasons;

  /// Highest 3-hour rain total at any station, or null with no recent readings.
  final double? rain3hMm;
  final double? maxWaterLevelCm;
  final int recentFloodReports;
  final bool hasRecentReadings;
  final bool usesSimulatedData;
}
