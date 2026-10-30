import '../../core/constants/enums.dart';
import '../../core/utils/geo.dart';
import '../../domain/models/incident.dart';
import 'ai_provider.dart';

/// Suggests likely duplicates from category, distance, age and text overlap.
/// Suggestions only; a person decides whether to link reports.
class DuplicateDetector {
  const DuplicateDetector({this.radiusMeters = 150, this.maxAge = const Duration(days: 14)});
  final double radiusMeters;
  final Duration maxAge;

  static Set<String> _tokens(String s) => s
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.length > 3)
      .toSet();

  static double textSimilarity(String a, String b) {
    final ta = _tokens(a), tb = _tokens(b);
    if (ta.isEmpty || tb.isEmpty) return 0;
    return ta.intersection(tb).length / ta.union(tb).length;
  }

  List<DuplicateMatch> find({
    required IncidentCategory category,
    required String description,
    required String locationText,
    double? latitude,
    double? longitude,
    required DateTime now,
    required Iterable<Incident> existing,
  }) {
    final out = <DuplicateMatch>[];
    for (final i in existing) {
      if (!i.status.isOpen || i.category != category) continue;
      if (now.difference(i.createdAt) > maxAge) continue;

      var score = 0.0;
      final why = <String>['same category'];
      var locationMatched = false;

      if (latitude != null && longitude != null && i.hasCoordinates) {
        final d = distanceMeters(latitude, longitude, i.latitude!, i.longitude!);
        if (d <= radiusMeters) {
          score += 0.5 * (1 - d / radiusMeters) + 0.2;
          why.add('${d.round()} m away');
          locationMatched = true;
        }
      } else if (locationText.trim().isNotEmpty &&
          textSimilarity(locationText, i.locationText) >= 0.5) {
        score += 0.4;
        why.add('similar location text');
        locationMatched = true;
      }
      if (!locationMatched) continue;

      final sim = textSimilarity(description, i.description);
      if (sim > 0) {
        score += 0.3 * sim;
        why.add('${(sim * 100).round()}% word overlap');
      }
      if (score >= 0.45) out.add(DuplicateMatch(i, score.clamp(0, 1), why));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out.take(3).toList();
  }
}
