import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Turns coordinates into a readable address using OpenStreetMap's free
/// Nominatim service. Only called when a person taps a location button, as
/// their usage policy requires (no bulk or background use, identifying
/// User-Agent). Needs internet; returns null when it cannot answer, and the
/// person can type the address instead.
class GeocodingService {
  GeocodingService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const userAgent = 'CIVINEX-AI/0.1 (Vyuham 26 hackathon app)';

  Future<String?> reverse(double latitude, double longitude) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': latitude.toStringAsFixed(6),
        'lon': longitude.toStringAsFixed(6),
        'zoom': '18',
        'addressdetails': '1',
      });
      final res = await _client
          .get(uri, headers: {'User-Agent': userAgent, 'Accept-Language': 'en'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      return parse(jsonDecode(res.body));
    } catch (_) {
      return null;
    }
  }

  /// Finds a place by name inside Kerala (OpenStreetMap Nominatim). Only called when
  /// the person submits a search. Returns null when nothing is found or offline.
  Future<({double latitude, double longitude, String name})?> search(String query) async {
    final q = query.trim();
    if (q.length < 3) return null;
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'q': q,
        'countrycodes': 'in',
        'viewbox': '74.5,13.0,77.7,8.0', // Kerala (left, top, right, bottom)
        'bounded': '1',
        'limit': '1',
      });
      final res = await _client
          .get(uri, headers: {'User-Agent': userAgent, 'Accept-Language': 'en'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      return parseSearch(jsonDecode(res.body));
    } catch (_) {
      return null;
    }
  }

  static ({double latitude, double longitude, String name})? parseSearch(Object? json) {
    if (json is! List || json.isEmpty || json.first is! Map) return null;
    final m = json.first as Map;
    final lat = double.tryParse('${m['lat']}');
    final lon = double.tryParse('${m['lon']}');
    if (lat == null || lon == null) return null;
    final name = '${m['display_name'] ?? ''}'.split(',').take(2).join(',').trim();
    return (latitude: lat, longitude: lon, name: name.isEmpty ? 'that area' : name);
  }

  /// Builds "Road, Area, City" from a Nominatim reverse result.
  static String? parse(Object? json) {
    if (json is! Map) return null;
    final a = json['address'];
    if (a is Map) {
      String? pick(List<String> keys) {
        for (final k in keys) {
          final v = a[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
        return null;
      }

      final road = pick(['road', 'pedestrian', 'footway', 'residential']);
      final area = pick(['neighbourhood', 'suburb', 'quarter', 'hamlet']);
      final city = pick(['city', 'town', 'village', 'municipality', 'county']);
      final parts = <String>[
        ?road,
        ?area,
        ?city,
      ];
      final seen = <String>{};
      final unique = parts.where(seen.add).toList();
      if (unique.isNotEmpty) return unique.join(', ');
    }
    final name = json['display_name'];
    if (name is String && name.trim().isNotEmpty) {
      final t = name.trim();
      return t.length > 90 ? '${t.substring(0, 90)}…' : t;
    }
    return null;
  }
}
