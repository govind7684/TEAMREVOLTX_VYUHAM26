import 'package:civinex_ai/core/constants/enums.dart';
import 'package:civinex_ai/domain/models/incident.dart';
import 'package:civinex_ai/features/map/map_utils.dart';
import 'package:flutter_test/flutter_test.dart';

Incident _at(String id, double? lat, double? lng) {
  final t = DateTime(2026, 10, 1);
  return Incident(
    id: id, reporterId: 'u', category: IncidentCategory.roadDamage, description: 'd',
    locationText: 'l', latitude: lat, longitude: lng, peopleAffected: 1,
    safetyRisk: false, priority: Priority.low, priorityScore: 1, priorityReasons: '',
    aiProvider: 'x', aiExplanation: '', needsHumanReview: false,
    departmentId: Departments.roads, status: IncidentStatus.submitted,
    createdAt: t, updatedAt: t, isDemo: false, dataSource: 'test',
  );
}

void main() {
  test('mappable drops incidents without coordinates', () {
    final list = [_at('a', 9.9, 76.3), _at('b', null, null)];
    expect(mappable(list).map((i) => i.id), ['a']);
  });

  test('centerFor falls back to Kerala center when nothing is mappable', () {
    expect(centerFor([_at('b', null, null)]), keralaCenter);
    expect(centerFor(const []), keralaCenter);
  });

  test('centerFor averages the points', () {
    final c = centerFor([_at('a', 10.0, 76.0), _at('b', 12.0, 78.0)]);
    expect(c.latitude, closeTo(11.0, 1e-9));
    expect(c.longitude, closeTo(77.0, 1e-9));
  });

  test('zoomFor is tighter for close points than spread-out points', () {
    final close = zoomFor([_at('a', 9.9800, 76.3000), _at('b', 9.9810, 76.3010)]);
    final far = zoomFor([_at('a', 8.5, 76.9), _at('b', 11.5, 75.8)]);
    expect(close, greaterThan(far));
    expect(zoomFor(const []), lessThan(10));
  });
}
