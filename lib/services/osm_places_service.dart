import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/errors/app_exceptions.dart';
import '../core/utils/geo.dart';
import '../domain/models/service_place.dart';
import 'geocoding_service.dart';

/// Finds hospitals, police stations, workshops and so on around a point using
/// OpenStreetMap data (the free Overpass API; no key). It is community-made
/// data, so some places are missing, and it needs internet. Called only when
/// someone searches, never in the background.
class OsmPlacesService {
  OsmPlacesService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _endpoint = 'https://overpass-api.de/api/interpreter';

  /// Builds the Overpass query for [kinds] within [radiusM] of the point.
  static String buildQuery(double lat, double lon, Iterable<ServiceKind> kinds, int radiusM) {
    final parts = <String>[];
    for (final k in kinds) {
      for (final (key, value) in k.osmTags) {
        final filter = value.contains('|') ? '["$key"~"^($value)\$"]' : '["$key"="$value"]';
        parts.add('nwr$filter(around:$radiusM,$lat,$lon);');
      }
    }
    return '[out:json][timeout:25];(${parts.join()});out center tags 150;';
  }

  /// Turns the Overpass answer into places, nearest first. Unnamed places get
  /// their kind as the name. Pure function, tested without the network.
  static List<ServicePlace> parse(Object? json, double lat, double lon) {
    if (json is! Map || json['elements'] is! List) return const [];
    final out = <ServicePlace>[];
    for (final e in json['elements'] as List) {
      if (e is! Map || e['tags'] is! Map) continue;
      final tags = Map<String, Object?>.from(e['tags'] as Map);
      final plat = (e['lat'] ?? (e['center'] is Map ? e['center']['lat'] : null)) as num?;
      final plon = (e['lon'] ?? (e['center'] is Map ? e['center']['lon'] : null)) as num?;
      if (plat == null || plon == null) continue;
      final kind = _kindOf(tags);
      if (kind == null) continue;
      String? t(String k) {
        final v = tags[k];
        return v is String && v.trim().isNotEmpty ? v.trim() : null;
      }

      final address = [
        t('addr:housenumber'),
        t('addr:street'),
        t('addr:suburb') ?? t('addr:neighbourhood'),
        t('addr:city'),
      ].whereType<String>().join(', ');
      final d = distanceMeters(lat, lon, plat.toDouble(), plon.toDouble());
      out.add(ServicePlace(
        id: 'osm:${e['type']}${e['id']}',
        name: t('name') ?? t('name:en') ?? kind.label,
        kind: kind,
        phone: t('phone') ?? t('contact:phone'),
        address: address.isEmpty ? null : address,
        hours: t('opening_hours'),
        latitude: plat.toDouble(),
        longitude: plon.toDouble(),
        distanceMeters: d,
      ));
    }
    out.sort((a, b) => a.distanceMeters!.compareTo(b.distanceMeters!));
    return out;
  }

  static ServiceKind? _kindOf(Map<String, Object?> tags) {
    for (final k in ServiceKind.values) {
      for (final (key, value) in k.osmTags) {
        final v = tags[key];
        if (v is String && RegExp('^($value)\$').hasMatch(v)) return k;
      }
    }
    return null;
  }

  /// Searches around the point. Throws a readable message when it cannot.
  Future<List<ServicePlace>> around(double lat, double lon,
      {Iterable<ServiceKind>? kinds, int radiusM = 5000}) async {
    final wanted = (kinds == null || kinds.isEmpty)
        ? ServiceKind.values.where((k) => k.osmTags.isNotEmpty)
        : kinds.where((k) => k.osmTags.isNotEmpty);
    try {
      final res = await _client.post(
        Uri.parse(_endpoint),
        headers: {'User-Agent': GeocodingService.userAgent},
        body: {'data': buildQuery(lat, lon, wanted, radiusM)},
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode == 429 || res.statusCode == 504) {
        throw const _Busy();
      }
      if (res.statusCode != 200) throw StateError('status ${res.statusCode}');
      return parse(jsonDecode(res.body), lat, lon);
    } on _Busy {
      throw const ValidationException(['The OpenStreetMap server is busy. Try again in a minute.']);
    } catch (_) {
      throw const ValidationException(
          ['Could not load places from OpenStreetMap. Check your internet connection.']);
    }
  }
}

class _Busy implements Exception {
  const _Busy();
}
