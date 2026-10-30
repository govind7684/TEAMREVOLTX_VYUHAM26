import 'package:civinex_ai/core/constants/enums.dart';
import 'package:civinex_ai/domain/models/incident.dart';
import 'package:civinex_ai/services/ai/ai_provider.dart';
import 'package:civinex_ai/services/ai/duplicate_detector.dart';
import 'package:civinex_ai/services/ai/priority_scorer.dart';
import 'package:civinex_ai/services/ai/rule_based_provider.dart';
import 'package:flutter_test/flutter_test.dart';

Incident _inc(String id, IncidentCategory c, String desc, String loc,
    {double? lat, double? lng, DateTime? at, IncidentStatus s = IncidentStatus.submitted}) {
  final t = at ?? DateTime(2026, 10, 1);
  return Incident(
    id: id, reporterId: 'u', category: c, description: desc, locationText: loc,
    latitude: lat, longitude: lng, peopleAffected: 1, safetyRisk: false,
    priority: Priority.low, priorityScore: 1, priorityReasons: '', aiProvider: 'x',
    aiExplanation: '', needsHumanReview: false, departmentId: c.departmentId,
    status: s, createdAt: t, updatedAt: t, isDemo: false, dataSource: 'test',
  );
}

void main() {
  group('RuleBasedProvider', () {
    final p = RuleBasedProvider();
    AiInput input(String d, {IncidentCategory? cat, bool safety = false}) => AiInput(
        description: d, userCategory: cat, peopleAffected: 1, safetyRiskFlag: safety);

    test('classifies flooding text and names matched keywords', () async {
      final s = await p.analyze(input('Heavy waterlogging, road flooded near the school'));
      expect(s.category, IncidentCategory.flooding);
      expect(s.matchedKeywords, isNotEmpty);
      expect(s.providerId, 'rule-based-local');
    });

    test('unmatched text falls back to Other and needs review', () async {
      final s = await p.analyze(input('Something is wrong here, please check it soon'));
      expect(s.category, IncidentCategory.other);
      expect(s.needsHumanReview, isTrue);
    });

    test('safety words set safety risk and review flag', () async {
      final s = await p.analyze(input('Exposed wire hanging near the lamp post'));
      expect(s.safetyRisk, isTrue);
      expect(s.needsHumanReview, isTrue);
    });

    test('user category kept when supported by text', () async {
      final s = await p.analyze(
          input('Pothole and blocked drain on the same road', cat: IncidentCategory.blockedDrain));
      expect(s.category, IncidentCategory.blockedDrain);
    });
  });

  group('PriorityScorer', () {
    const scorer = PriorityScorer();
    test('minor issue is low', () {
      final r = scorer.score(
          category: IncidentCategory.waste, safetyRisk: false, peopleAffected: 1,
          unresolvedFor: Duration.zero, similarReports: 0);
      expect(r.priority, Priority.low);
    });
    test('safety + many people + flooding is critical, with reasons', () {
      final r = scorer.score(
          category: IncidentCategory.flooding, safetyRisk: true, peopleAffected: 150,
          unresolvedFor: Duration.zero, similarReports: 0);
      expect(r.priority, Priority.critical);
      expect(r.reasons.length, greaterThanOrEqualTo(3));
    });
    test('age increases score', () {
      int s(int days) => scorer
          .score(category: IncidentCategory.roadDamage, safetyRisk: false, peopleAffected: 1,
              unresolvedFor: Duration(days: days), similarReports: 0)
          .score;
      expect(s(8), greaterThan(s(0)));
    });
    test('thresholds are configurable', () {
      const strict = PriorityScorer(PriorityConfig(mediumAt: 1, highAt: 2, criticalAt: 3));
      final r = strict.score(
          category: IncidentCategory.roadDamage, safetyRisk: false, peopleAffected: 1,
          unresolvedFor: Duration.zero, similarReports: 0);
      expect(r.priority, Priority.high);
    });
  });

  group('DuplicateDetector', () {
    const d = DuplicateDetector();
    final now = DateTime(2026, 10, 5);
    test('finds nearby same-category report', () {
      final existing = [
        _inc('A', IncidentCategory.roadDamage, 'Big pothole on the road', 'Main road',
            lat: 9.9816, lng: 76.2999),
      ];
      final m = d.find(
          category: IncidentCategory.roadDamage, description: 'Large pothole on road',
          locationText: 'Main road', latitude: 9.9817, longitude: 76.3000,
          now: now, existing: existing);
      expect(m, hasLength(1));
    });
    test('ignores other categories, far away, resolved and old reports', () {
      final existing = [
        _inc('B', IncidentCategory.waste, 'pothole', 'x', lat: 9.9816, lng: 76.2999),
        _inc('C', IncidentCategory.roadDamage, 'pothole', 'x', lat: 10.5, lng: 76.2999),
        _inc('D', IncidentCategory.roadDamage, 'pothole', 'x',
            lat: 9.9816, lng: 76.2999, s: IncidentStatus.resolved),
        _inc('E', IncidentCategory.roadDamage, 'pothole', 'x',
            lat: 9.9816, lng: 76.2999, at: DateTime(2026, 8, 1)),
      ];
      final m = d.find(
          category: IncidentCategory.roadDamage, description: 'pothole',
          locationText: 'x', latitude: 9.9816, longitude: 76.2999,
          now: now, existing: existing);
      expect(m, isEmpty);
    });
  });
}
