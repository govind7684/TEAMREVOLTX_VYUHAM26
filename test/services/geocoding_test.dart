import 'dart:convert';

import 'package:civinex_ai/services/geocoding_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('builds "road, area, city" from a Nominatim reply', () {
    final text = GeocodingService.parse({
      'display_name': 'ignored',
      'address': {
        'road': 'Kowdiar Road',
        'suburb': 'Kowdiar',
        'city': 'Thiruvananthapuram',
        'state': 'Kerala',
      },
    });
    expect(text, 'Kowdiar Road, Kowdiar, Thiruvananthapuram');
  });

  test('drops repeated names and tolerates missing parts', () {
    expect(GeocodingService.parse({'address': {'road': 'MG Road', 'suburb': 'MG Road', 'town': 'Kochi'}}),
        'MG Road, Kochi');
    expect(GeocodingService.parse({'address': {'village': 'Vellanad'}}), 'Vellanad');
  });

  test('returns null for junk', () {
    expect(GeocodingService.parse(null), isNull);
    expect(GeocodingService.parse('x'), isNull);
    expect(GeocodingService.parse({'error': 'Unable to geocode'}), isNull);
  });

  test('sends an identifying User-Agent and the coordinates', () async {
    late http.Request seen;
    final svc = GeocodingService(
        client: MockClient((req) async {
      seen = req;
      return http.Response(jsonEncode({'address': {'road': 'Test Rd', 'city': 'Kochi'}}), 200);
    }));
    expect(await svc.reverse(9.9312, 76.2673), 'Test Rd, Kochi');
    expect(seen.headers['User-Agent'], GeocodingService.userAgent);
    expect(seen.url.host, 'nominatim.openstreetmap.org');
    expect(seen.url.queryParameters['lat'], '9.931200');
    expect(seen.url.queryParameters['lon'], '76.267300');
  });

  test('network or server failure gives null, never an exception', () async {
    expect(await GeocodingService(client: MockClient((_) async => http.Response('', 503))).reverse(9, 76), isNull);
    expect(await GeocodingService(client: MockClient((_) async => throw Exception('offline'))).reverse(9, 76), isNull);
  });

  test('area search parses the first hit and stays inside Kerala', () async {
    late Uri seen;
    final svc = GeocodingService(
        client: MockClient((req) async {
      seen = req.url;
      return http.Response(
          jsonEncode([
            {'lat': '8.5241', 'lon': '76.9366', 'display_name': 'Kowdiar, Thiruvananthapuram, Kerala, India'}
          ]),
          200);
    }));
    final hit = await svc.search('Kowdiar');
    expect(hit!.latitude, closeTo(8.5241, 1e-6));
    expect(hit.name, 'Kowdiar, Thiruvananthapuram');
    expect(seen.queryParameters['bounded'], '1');
    expect(seen.queryParameters['countrycodes'], 'in');
    expect(await svc.search('ab'), isNull); // too short, no request
    expect(GeocodingService.parseSearch([]), isNull);
    expect(GeocodingService.parseSearch('x'), isNull);
  });
}
