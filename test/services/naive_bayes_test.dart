import 'package:civinex_ai/core/constants/enums.dart';
import 'package:civinex_ai/services/ai/ai_provider.dart';
import 'package:civinex_ai/services/ai/naive_bayes_provider.dart';
import 'package:flutter_test/flutter_test.dart';

AiInput _in(String t, {IncidentCategory? cat, bool safety = false}) => AiInput(
    description: t, userCategory: cat, peopleAffected: 1, safetyRiskFlag: safety);

void main() {
  final nb = NaiveBayesProvider();

  // Held-out sentences NOT present in the training corpus.
  const heldOut = <String, IncidentCategory>{
    'There is a huge pothole outside our house and the tar is damaged': IncidentCategory.roadDamage,
    'garbage heap and rubbish not collected near the bus stand': IncidentCategory.waste,
    'the lane is flooded with knee deep water after rain': IncidentCategory.flooding,
    'drain blocked with plastic and sewage overflowing': IncidentCategory.blockedDrain,
    'water pipe leaking and no water in taps': IncidentCategory.waterLeak,
    'the street light is not working and the road is dark at night': IncidentCategory.streetlight,
    'traffic jam at the signal junction every evening': IncidentCategory.traffic,
    'no ramp for wheelchair at the footpath': IncidentCategory.accessibility,
    'smoke and dust pollution from the burning plant': IncidentCategory.environment,
  };

  test('trains on the built-in sample and reports its size', () {
    expect(nb.trainingExamples, greaterThan(90));
    expect(nb.vocabularySize, greaterThan(200));
  });

  test('held-out sentences (written by the project author, so an optimistic check only)', () async {
    var right = 0;
    for (final e in heldOut.entries) {
      final s = await nb.analyze(_in(e.key));
      if (s.category == e.value) right++;
    }
    expect(right, greaterThanOrEqualTo(8), reason: 'got $right of ${heldOut.length}');
  });

  test('returns a probability and alternatives; probabilities sum to 1', () async {
    final s = await nb.analyze(_in('big pothole on the road with cracked tar'));
    expect(s.providerId, NaiveBayesProvider.modelId);
    expect(s.confidence, isNotNull);
    expect(s.confidence!, inInclusiveRange(0.0, 1.0));
    expect(s.alternatives.length, 2);
    final p = nb.predict('big pothole on the road with cracked tar');
    expect(p.ranked.fold<double>(0, (a, b) => a + b.$2), closeTo(1.0, 1e-9));
    expect(s.explanation, contains('estimated probability'));
  });

  test('unknown words fall back to the labelled rule engine with no probability', () async {
    final s = await nb.analyze(_in('zzz qqq xyzzy'));
    expect(s.providerId, 'rule-based-local');
    expect(s.confidence, isNull);
    expect(s.needsHumanReview, isTrue);
  });

  test('ambiguous text is flagged for human review', () async {
    final s = await nb.analyze(_in('something is wrong here please check it today'));
    expect(s.needsHumanReview, isTrue);
  });

  test('reporter category is kept when plausible, flagged when contradicted', () async {
    final kept = await nb.analyze(
        _in('the whole street is flooded and water is standing after heavy rain',
            cat: IncidentCategory.flooding));
    expect(kept.category, IncidentCategory.flooding);
    final odd = await nb.analyze(
        _in('streetlight bulb is dead and the lane is dark', cat: IncidentCategory.waste));
    expect(odd.needsHumanReview, isTrue);
    expect(odd.category, IncidentCategory.streetlight);
  });

  test('safety words and flag raise the safety risk', () async {
    final s = await nb.analyze(_in('exposed wire hanging near the street light'));
    expect(s.safetyRisk, isTrue);
  });
}
