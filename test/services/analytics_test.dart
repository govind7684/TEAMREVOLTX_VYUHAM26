import 'package:civinex_ai/core/constants/enums.dart';
import 'package:civinex_ai/domain/models/incident.dart';
import 'package:civinex_ai/services/analytics.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 30, 12);

Incident _i(
  String id, {
  IncidentCategory cat = IncidentCategory.roadDamage,
  IncidentStatus status = IncidentStatus.submitted,
  Priority prio = Priority.low,
  int daysAgo = 0,
  int resolvedAfterDays = 0,
  bool review = false,
}) {
  final created = _now.subtract(Duration(days: daysAgo));
  return Incident(
    id: id, reporterId: 'u', category: cat, description: 'd', locationText: 'l',
    peopleAffected: 1, safetyRisk: false, priority: prio, priorityScore: 1,
    priorityReasons: '', aiProvider: 'x', aiExplanation: '', needsHumanReview: review,
    departmentId: cat.departmentId, status: status, createdAt: created,
    updatedAt: created.add(Duration(days: resolvedAfterDays)), isDemo: false,
    dataSource: 'test',
  );
}

void main() {
  test('empty input gives zeros and a friendly summary', () {
    final r = Analytics.compute(const [], now: _now);
    expect(r.total, 0);
    expect(r.avgResolutionDays, isNull);
    expect(r.summary.single, contains('nothing to summarise'));
  });

  test('counts open, resolved and other closed states', () {
    final r = Analytics.compute([
      _i('a'),
      _i('b', status: IncidentStatus.inProgress),
      _i('c', status: IncidentStatus.resolved, resolvedAfterDays: 2),
      _i('d', status: IncidentStatus.rejected),
      _i('e', status: IncidentStatus.withdrawn),
    ], now: _now);
    expect(r.total, 5);
    expect(r.open, 2);
    expect(r.resolved, 1);
    expect(r.closedOther, 2);
  });

  test('open by priority ignores closed reports', () {
    final r = Analytics.compute([
      _i('a', prio: Priority.high),
      _i('b', prio: Priority.high, status: IncidentStatus.resolved),
      _i('c', prio: Priority.critical),
    ], now: _now);
    expect(r.openByPriority[Priority.high], 1);
    expect(r.openByPriority[Priority.critical], 1);
    expect(r.openByPriority[Priority.low], 0);
  });

  test('daily trend buckets by creation day and ignores older reports', () {
    final r = Analytics.compute([
      _i('a', daysAgo: 0),
      _i('b', daysAgo: 0),
      _i('c', daysAgo: 3),
      _i('d', daysAgo: Analytics.trendDays - 1),
      _i('e', daysAgo: Analytics.trendDays), // outside the window
    ], now: _now);
    expect(r.dailyCreated.length, Analytics.trendDays);
    expect(r.dailyCreated.last, 2);
    expect(r.dailyCreated[Analytics.trendDays - 1 - 3], 1);
    expect(r.dailyCreated.first, 1);
    expect(r.dailyCreated.fold<int>(0, (a, b) => a + b), 4);
  });

  test('overdue, review and average resolution time', () {
    final r = Analytics.compute([
      _i('a', daysAgo: 8),
      _i('b', daysAgo: 2, review: true),
      _i('c', status: IncidentStatus.resolved, daysAgo: 10, resolvedAfterDays: 4),
      _i('d', status: IncidentStatus.resolved, daysAgo: 10, resolvedAfterDays: 2),
    ], now: _now);
    expect(r.overdueOpen, 1);
    expect(r.needsReview, 1);
    expect(r.avgResolutionDays, closeTo(3.0, 1e-9));
  });

  test('department workload and summary mention busiest department', () {
    final r = Analytics.compute([
      _i('a', cat: IncidentCategory.flooding),
      _i('b', cat: IncidentCategory.blockedDrain),
      _i('c', cat: IncidentCategory.roadDamage),
    ], now: _now);
    expect(r.byDepartment[Departments.drainage]!.open, 2);
    expect(r.summary.any((s) => s.contains('Drainage & Flood Response')), isTrue);
    expect(r.summary.any((s) => s.contains('Most common category')), isTrue);
  });

  test('weekly trend sentence reflects direction', () {
    final up = Analytics.compute([
      _i('a', daysAgo: 1), _i('b', daysAgo: 2), _i('c', daysAgo: 10),
    ], now: _now);
    expect(up.summary.any((s) => s.contains('up from 1')), isTrue);
  });
}
