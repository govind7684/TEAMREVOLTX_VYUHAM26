import '../../core/constants/enums.dart';
import '../../domain/models/incident.dart';

class AiInput {
  const AiInput({
    required this.description,
    this.userCategory,
    this.latitude,
    this.longitude,
    required this.peopleAffected,
    required this.safetyRiskFlag,
    this.hasPhoto = false,
  });
  final String description;
  final IncidentCategory? userCategory;
  final double? latitude;
  final double? longitude;
  final int peopleAffected;
  final bool safetyRiskFlag;
  final bool hasPhoto;
}

class AiSuggestion {
  const AiSuggestion({
    required this.category,
    required this.categoryReasons,
    required this.providerId,
    required this.matchedKeywords,
    required this.needsHumanReview,
    required this.reviewReasons,
    required this.safetyRisk,
    this.confidence,
    this.alternatives = const [],
  });
  final IncidentCategory category;

  /// Model probability (0..1) of [category]. Null when the provider is rule
  /// based, because rules have no probability and none is invented.
  final double? confidence;

  /// Next most likely categories with their probabilities (model only).
  final List<(IncidentCategory, double)> alternatives;
  final List<String> categoryReasons;

  /// Identifies the engine that produced this. Never a model name unless a
  /// real model ran.
  final String providerId;
  final List<String> matchedKeywords;
  final bool needsHumanReview;
  final List<String> reviewReasons;
  final bool safetyRisk;

  String get alternativesText => alternatives
      .map((a) => '${a.$1.label} ${(a.$2 * 100).round()}%')
      .join(', ');

  String get explanation => [
        ...categoryReasons,
        if (reviewReasons.isNotEmpty) 'Needs human review: ${reviewReasons.join('; ')}',
      ].join(' ');
}

/// Contract for text classification. A local ML provider can be added later
/// by implementing this interface; the app never needs a paid API.
abstract class AiProvider {
  String get id;
  String get description;
  Future<AiSuggestion> analyze(AiInput input);
}

class DuplicateMatch {
  const DuplicateMatch(this.incident, this.score, this.reasons);
  final Incident incident;
  final double score;
  final List<String> reasons;
}
