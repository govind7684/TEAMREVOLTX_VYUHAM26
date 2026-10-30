import 'package:civinex_ai/core/constants/enums.dart';
import 'package:civinex_ai/domain/models/incident.dart';
import 'package:civinex_ai/services/credits.dart';
import 'package:civinex_ai/services/photo_check.dart';
import 'package:flutter_test/flutter_test.dart';

final _day = DateTime(2026, 10, 1, 10);

Incident _i(
  String id, {
  IncidentStatus status = IncidentStatus.submitted,
  DateTime? at,
  String? origin,
  String? check,
  String? dupOf,
  bool dupVerified = true,
}) {
  final t = at ?? _day;
  return Incident(
    id: id, reporterId: 'u', category: IncidentCategory.values.first, description: 'd',
    locationText: 'l', peopleAffected: 1, safetyRisk: false, priority: Priority.low,
    priorityScore: 1, priorityReasons: '', aiProvider: 'x', aiExplanation: '',
    needsHumanReview: false, departmentId: 'd', status: status, createdAt: t, updatedAt: t,
    isDemo: false, dataSource: 'test', photoOrigin: origin, photoCheck: check,
    duplicateOfId: dupOf, dupVerified: dupVerified,
  );
}

void main() {
  test('no reports gives zero points and Newcomer', () {
    final c = Credits.compute(const []);
    expect(c.total, 0);
    expect(c.level, 'Newcomer');
    expect(c.toNext, 50);
  });

  test('a plain report earns the report points only', () {
    expect(Credits.compute([_i('a')]).total, Credits.perReport);
  });

  test('a live photo earns a bonus, a flagged one does not', () {
    final live = PhotoCheck(origin: 'camera', capturedAt: _day, ai: 'real_photo').toJson();
    final bad = PhotoCheck(origin: 'camera', capturedAt: _day, ai: 'illustration_or_ai').toJson();
    expect(Credits.compute([_i('a', origin: 'camera', check: live)]).total,
        Credits.perReport + Credits.liveBonus);
    expect(Credits.compute([_i('a', origin: 'camera', check: bad)]).total, Credits.perReport);
    expect(Credits.compute([_i('a', origin: 'gallery')]).total, Credits.perReport);
  });

  test('staff action and resolution add points, feedback adds more', () {
    final r = _i('a', status: IncidentStatus.resolved);
    expect(Credits.compute([r]).total,
        Credits.perReport + Credits.acceptedBonus + Credits.resolvedBonus);
    expect(Credits.compute([r], feedbackFor: {'a'}).total,
        Credits.perReport + Credits.acceptedBonus + Credits.resolvedBonus + Credits.feedbackBonus);
  });

  test('rejected and withdrawn reports earn nothing', () {
    expect(Credits.compute([
      _i('a', status: IncidentStatus.rejected),
      _i('b', status: IncidentStatus.withdrawn),
    ]).total, 0);
  });

  test('only the first three reports a day earn report points', () {
    final list = [for (var n = 0; n < 6; n++) _i('r$n', at: _day.add(Duration(minutes: n)))];
    expect(Credits.compute(list).total, Credits.perReport * Credits.dailyCap);
    final spread = [for (var n = 0; n < 4; n++) _i('s$n', at: _day.add(Duration(days: n)))];
    expect(Credits.compute(spread).total, Credits.perReport * 4);
  });

  test('a confirmed duplicate earns the smaller bonus; an unconfirmed one nothing', () {
    expect(Credits.compute([_i('a', dupOf: 'x', dupVerified: true)]).total, Credits.confirmedSame);
    expect(Credits.compute([_i('a', dupOf: 'x', dupVerified: false)]).total, 0);
  });

  test('levels move up with points', () {
    expect(Credits.levelFor(49).$1, 'Newcomer');
    expect(Credits.levelFor(50).$1, 'Active citizen');
    expect(Credits.levelFor(400).$1, 'City champion');
  });
}
