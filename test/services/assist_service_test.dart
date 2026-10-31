import 'dart:convert';

import 'package:civinex_ai/core/constants/enums.dart';
import 'package:civinex_ai/core/errors/app_exceptions.dart';
import 'package:civinex_ai/services/assist_service.dart';
import 'package:civinex_ai/services/prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  Prefs prefsWith(String? url) {
    final p = Prefs.memory();
    if (url != null) p.set(AssistService.urlKey, url);
    return p;
  }

  test('is off until a server address is saved', () async {
    final svc = AssistService(prefsWith(null));
    expect(svc.isConfigured, isFalse);
    await expectLater(svc.suggest('pothole on main road'), throwsA(isA<ValidationException>()));
  });

  test('parses a suggestion and sends the password header', () async {
    late http.Request seen;
    final client = MockClient((req) async {
      seen = req;
      return http.Response(
          jsonEncode({'category': 'roadDamage', 'priority': 'high', 'department': 'dept_roads', 'summary': 's', 'reason': 'r'}), 200);
    });
    final prefs = prefsWith('http://192.168.1.2:8787/');
    await prefs.set(AssistService.tokenKey, 'pw');
    final r = await AssistService(prefs, client: client).suggest('big pothole near bus stand');
    expect(r.category, IncidentCategory.roadDamage);
    expect(r.priority, Priority.high);
    expect(seen.url.toString(), 'http://192.168.1.2:8787/suggest');
    expect(seen.headers['X-Assist-Token'], 'pw');
    expect(r.departmentId, Departments.roads);
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body['description'], 'big pothole near bus stand');
    expect((body['departments'] as Map).keys, contains(Departments.roads));
  });

  test('ignores a department the app does not know', () async {
    final client = MockClient((_) async => http.Response(
        jsonEncode({'category': 'waste', 'priority': 'low', 'department': 'dept_made_up', 'summary': 's', 'reason': 'r'}),
        200));
    final r = await AssistService(prefsWith('http://h:1'), client: client).suggest('rubbish pile on road');
    expect(r.departmentId, isNull);
  });

  test('rejects an unknown category and shows server errors', () async {
    final bad = MockClient((_) async => http.Response(jsonEncode({'category': 'xyz', 'priority': 'low'}), 200));
    await expectLater(AssistService(prefsWith('http://h:1'), client: bad).suggest('some text here'),
        throwsA(isA<ValidationException>()));
    final err = MockClient((_) async => http.Response(jsonEncode({'error': 'Too many requests.'}), 429));
    await expectLater(
        AssistService(prefsWith('http://h:1'), client: err).briefing({'total': 1}),
        throwsA(predicate((e) => e is ValidationException && e.message.contains('Too many'))));
  });
}
