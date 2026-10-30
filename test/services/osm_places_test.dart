import 'package:civinex_ai/domain/models/service_place.dart';
import 'package:civinex_ai/services/osm_places_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('query asks for the chosen kinds around the point', () {
    final q = OsmPlacesService.buildQuery(8.5, 76.9, [ServiceKind.hospital, ServiceKind.tyre], 4000);
    expect(q, contains('"amenity"="hospital"'));
    expect(q, contains('"shop"="tyres"'));
    expect(q, contains('around:4000,8.5,76.9'));
    expect(q, startsWith('[out:json]'));
  });

  test('parses places, uses centres for areas, sorts nearest first, names unnamed ones', () {
    final json = {
      'elements': [
        {
          'type': 'node', 'id': 1, 'lat': 8.51, 'lon': 76.91,
          'tags': {'amenity': 'pharmacy', 'name': 'City Pharmacy', 'phone': '+91 471 000000'}
        },
        {
          'type': 'way', 'id': 2, 'center': {'lat': 8.5001, 'lon': 76.9001},
          'tags': {'amenity': 'hospital', 'name': 'General Hospital', 'opening_hours': '24/7'}
        },
        {'type': 'node', 'id': 3, 'lat': 8.52, 'lon': 76.92, 'tags': {'shop': 'tyres'}},
        {'type': 'node', 'id': 4, 'lat': 8.5, 'lon': 76.9, 'tags': {'amenity': 'bench'}},
        {'type': 'node', 'id': 5, 'tags': {'amenity': 'police'}},
      ]
    };
    final r = OsmPlacesService.parse(json, 8.5, 76.9);
    expect(r.map((p) => p.name), ['General Hospital', 'City Pharmacy', 'Tyre / puncture']);
    expect(r.first.hours, '24/7');
    expect(r[1].phone, '+91 471 000000');
    expect(r.every((p) => !p.staff), isTrue);
  });

  test('bad answers give an empty list', () {
    expect(OsmPlacesService.parse(null, 0, 0), isEmpty);
    expect(OsmPlacesService.parse({'elements': 'x'}, 0, 0), isEmpty);
  });
}
