import '../domain/models/road.dart';

class RoadAssessment {
  const RoadAssessment({
    required this.type,
    required this.severity,
    required this.reasons,
    required this.needsReview,
  });
  final RoadDamageType type;
  final RoadSeverity severity;
  final List<String> reasons;
  final bool needsReview;
}

/// Keyword rules over the report text. NOT a computer-vision model: photos are
/// stored but never analysed here. If a real local image model is added later,
/// it should run alongside this and be labelled with its own source name.
class RoadClassifier {
  const RoadClassifier();

  static const _obstruction = [
    'fallen tree', 'tree fell', 'tree has fallen', 'debris', 'obstruct', 'barrier',
    'boulder', 'landslide', 'construction material', 'encroach', 'blocked road',
    'road blocked', 'stuck',
  ];
  static const _pothole = ['pothole', 'crater', 'hole in the road', 'hole in road', 'sinkhole'];
  static const _surface = [
    'crack', 'uneven', 'broken', 'peeling', 'worn', 'rut', 'erosion', 'washed away',
    'subsidence', 'surface', 'tar', 'asphalt', 'gravel',
  ];
  static const _severe = [
    'deep', 'large', 'huge', 'big', 'sinkhole', 'accident', 'injur', 'skid', 'crash',
    'fell', 'dangerous', 'multiple', 'collapse',
  ];
  static const _minor = ['small', 'minor', 'tiny', 'hairline', 'slight'];

  static List<String> _hits(String text, List<String> words) =>
      words.where((w) => RegExp('\\b${RegExp.escape(w)}').hasMatch(text)).toList();

  RoadAssessment classify({
    required String description,
    required int peopleAffected,
    required bool safetyRisk,
  }) {
    final text = description.toLowerCase();
    final reasons = <String>[];
    var review = false;

    final ob = _hits(text, _obstruction);
    final ph = _hits(text, _pothole);
    final su = _hits(text, _surface);

    RoadDamageType type;
    final counts = {
      RoadDamageType.obstruction: ob,
      RoadDamageType.pothole: ph,
      RoadDamageType.damagedSurface: su,
    }..removeWhere((_, v) => v.isEmpty);

    if (counts.isEmpty) {
      type = RoadDamageType.uncertain;
      reasons.add('No road damage keywords found, so the type is Uncertain.');
      review = true;
    } else {
      final best = counts.values.map((v) => v.length).reduce((a, b) => a > b ? a : b);
      final top = counts.entries.where((e) => e.value.length == best).toList();
      if (top.length > 1) {
        type = RoadDamageType.uncertain;
        reasons.add('The text matches more than one type '
            '(${top.map((e) => e.key.label).join(', ')}), so it is left Uncertain.');
        review = true;
      } else {
        type = top.single.key;
        reasons.add('Matched ${type.label.toLowerCase()} keywords: ${top.single.value.join(', ')}.');
      }
    }

    final severeHits = _hits(text, _severe);
    final minorHits = _hits(text, _minor);
    RoadSeverity severity;
    if (safetyRisk || peopleAffected >= 100 || severeHits.isNotEmpty) {
      severity = RoadSeverity.severe;
      reasons.add('Severe because of: ${[
        if (safetyRisk) 'reporter flagged a safety risk',
        if (peopleAffected >= 100) '$peopleAffected people affected',
        if (severeHits.isNotEmpty) 'words like ${severeHits.join(', ')}',
      ].join('; ')}.');
      if (minorHits.isNotEmpty) {
        reasons.add('The text also contains minor wording (${minorHits.join(', ')}); please check.');
        review = true;
      }
    } else if (minorHits.isNotEmpty) {
      severity = RoadSeverity.minor;
      reasons.add('Minor because of words like ${minorHits.join(', ')}.');
    } else {
      severity = RoadSeverity.moderate;
      reasons.add('No strong size or danger words, so the default is Moderate.');
    }

    return RoadAssessment(type: type, severity: severity, reasons: reasons, needsReview: review);
  }
}
