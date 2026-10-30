import '../../core/constants/enums.dart';
import 'ai_provider.dart';

/// Deterministic keyword classifier. This is NOT a trained model and
/// reports no confidence percentage; it only lists the rules that matched.
class RuleBasedProvider implements AiProvider {
  @override
  String get id => 'rule-based-local';

  @override
  String get description =>
      'Keyword rules running on this device. Not a machine-learning model.';

  static const keywords = <IncidentCategory, List<String>>{
    IncidentCategory.roadDamage: ['pothole', 'road', 'crack', 'tar', 'asphalt', 'sinkhole', 'surface'],
    IncidentCategory.waste: ['garbage', 'waste', 'trash', 'dump', 'litter', 'rubbish', 'plastic'],
    IncidentCategory.flooding: ['flood', 'waterlog', 'inundat', 'overflow', 'submerged', 'knee-deep'],
    IncidentCategory.blockedDrain: ['drain', 'clog', 'sewer', 'manhole', 'blocked'],
    IncidentCategory.waterLeak: ['leak', 'pipe', 'burst', 'no water', 'water supply', 'tap'],
    IncidentCategory.streetlight: ['streetlight', 'street light', 'lamp', 'dark', 'bulb'],
    IncidentCategory.traffic: ['traffic', 'jam', 'congestion', 'signal', 'junction'],
    IncidentCategory.accessibility: ['ramp', 'wheelchair', 'footpath', 'pavement', 'accessib', 'blind'],
    IncidentCategory.environment: ['heat', 'tree', 'pollution', 'smoke', 'dust', 'noise'],
  };

  static const safetyWords = [
    'accident', 'injur', 'electric', 'live wire', 'exposed wire', 'collapse',
    'fire', 'danger', 'child', 'children', 'fell', 'open manhole', 'sinkhole',
    'deep', 'drown', 'urgent', 'emergency',
  ];

  @override
  Future<AiSuggestion> analyze(AiInput input) async {
    final text = input.description.toLowerCase();
    final scores = <IncidentCategory, List<String>>{};
    keywords.forEach((cat, words) {
      final hits = words.where(text.contains).toList();
      if (hits.isNotEmpty) scores[cat] = hits;
    });

    final reasons = <String>[];
    final review = <String>[];
    IncidentCategory category;
    var matched = <String>[];

    if (scores.isEmpty) {
      category = input.userCategory ?? IncidentCategory.other;
      reasons.add('No category keywords matched; using '
          '${input.userCategory == null ? 'the default "Other"' : 'the category you chose'}.');
      review.add('no keywords matched');
    } else {
      final ranked = scores.entries.toList()
        ..sort((a, b) => b.value.length.compareTo(a.value.length));
      category = ranked.first.key;
      matched = ranked.first.value;
      reasons.add('Matched keywords for ${category.label}: ${matched.join(', ')}.');
      if (ranked.length > 1 && ranked[1].value.length == ranked.first.value.length) {
        review.add('description fits more than one category '
            '(${ranked[1].key.label})');
      }
      // A reporter's own pick wins when it is among the matched categories.
      if (input.userCategory != null && scores.containsKey(input.userCategory)) {
        category = input.userCategory!;
        matched = scores[category]!;
        reasons.add('Kept your chosen category, which the text supports.');
      } else if (input.userCategory != null && input.userCategory != category) {
        review.add('chosen category (${input.userCategory!.label}) differs from text');
      }
    }

    final safety = input.safetyRiskFlag ||
        safetyWords.any(text.contains);
    if (safety) {
      reasons.add(input.safetyRiskFlag
          ? 'Reporter flagged an immediate safety risk.'
          : 'Text mentions possible safety words.');
      review.add('possible safety risk');
    }
    if (input.description.trim().length < 25) {
      review.add('very short description');
    }
    if (input.hasPhoto) {
      reasons.add('A photo is attached but images are not analysed by this provider.');
    }

    return AiSuggestion(
      category: category,
      categoryReasons: reasons,
      providerId: id,
      matchedKeywords: matched,
      needsHumanReview: review.isNotEmpty,
      reviewReasons: review,
      safetyRisk: safety,
    );
  }
}
