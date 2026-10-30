import 'package:civinex_ai/domain/models/road.dart';
import 'package:civinex_ai/services/road_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

RoadAssessment _c(String text, {int people = 1, bool safety = false}) =>
    const RoadClassifier().classify(description: text, peopleAffected: people, safetyRisk: safety);

void main() {
  test('pothole text is a Pothole', () {
    final a = _c('There is a pothole near the bus stop');
    expect(a.type, RoadDamageType.pothole);
    expect(a.severity, RoadSeverity.moderate);
    expect(a.needsReview, isFalse);
  });

  test('cracks are Damaged surface; "small" makes it Minor', () {
    final a = _c('Small cracks on the surface near the gate');
    expect(a.type, RoadDamageType.damagedSurface);
    expect(a.severity, RoadSeverity.minor);
  });

  test('fallen tree and debris is an Obstruction', () {
    expect(_c('Fallen tree and debris on the road').type, RoadDamageType.obstruction);
  });

  test('no keywords or mixed types become Uncertain and flagged for review', () {
    final none = _c('Something odd happened here yesterday');
    expect(none.type, RoadDamageType.uncertain);
    expect(none.needsReview, isTrue);
    // One pothole keyword and one surface keyword: a tie, so left Uncertain.
    final mixed = _c('pothole and cracked');
    expect(mixed.type, RoadDamageType.uncertain);
    expect(mixed.needsReview, isTrue);
  });

  test('danger words, safety flag or many people make it Severe', () {
    expect(_c('Very deep pothole, a bike skidded').severity, RoadSeverity.severe);
    expect(_c('pothole here', safety: true).severity, RoadSeverity.severe);
    expect(_c('pothole here', people: 150).severity, RoadSeverity.severe);
  });

  test('conflicting size words are flagged for review', () {
    final a = _c('Small but deep pothole');
    expect(a.severity, RoadSeverity.severe);
    expect(a.needsReview, isTrue);
  });

  test('keywords match at word starts only ("start" is not "tar")', () {
    expect(_c('I start my walk here').type, RoadDamageType.uncertain);
  });

  test('every result explains itself', () {
    expect(_c('pothole').reasons, isNotEmpty);
  });
}
