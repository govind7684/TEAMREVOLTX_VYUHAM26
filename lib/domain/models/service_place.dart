import 'package:flutter/material.dart';

/// Kinds of place in the city services directory, with the OpenStreetMap tags
/// that find them automatically.
enum ServiceKind {
  hospital('Hospital', Icons.local_hospital_outlined, [('amenity', 'hospital')]),
  clinic('Clinic / doctor', Icons.medical_services_outlined, [('amenity', 'clinic|doctors')]),
  pharmacy('Pharmacy', Icons.medication_outlined, [('amenity', 'pharmacy')]),
  police('Police', Icons.local_police_outlined, [('amenity', 'police')]),
  fire('Fire station', Icons.fire_truck_outlined, [('amenity', 'fire_station')]),
  workshop('Vehicle workshop', Icons.build_outlined, [('shop', 'car_repair|motorcycle_repair')]),
  tyre('Tyre / puncture', Icons.tire_repair, [('shop', 'tyres')]),
  fuel('Fuel station', Icons.local_gas_station_outlined, [('amenity', 'fuel')]),
  other('Other', Icons.place_outlined, []);

  const ServiceKind(this.label, this.icon, this.osmTags);
  final String label;
  final IconData icon;

  /// (key, value-regex) pairs; a place matches if any pair matches.
  final List<(String, String)> osmTags;
}

/// A place a citizen can look up. [staff] places were entered by an officer or
/// administrator; the others come from OpenStreetMap, which may be incomplete.
class ServicePlace {
  const ServicePlace({
    required this.id,
    required this.name,
    required this.kind,
    this.city = '',
    this.phone,
    this.address,
    this.hours,
    this.latitude,
    this.longitude,
    this.staff = false,
    this.distanceMeters,
  });

  final String id, name, city;
  final ServiceKind kind;
  final String? phone, address, hours;
  final double? latitude, longitude;
  final bool staff;
  final double? distanceMeters;

  ServicePlace withDistance(double m) => ServicePlace(
      id: id, name: name, kind: kind, city: city, phone: phone, address: address,
      hours: hours, latitude: latitude, longitude: longitude, staff: staff, distanceMeters: m);

  factory ServicePlace.fromMap(Map<String, Object?> m) => ServicePlace(
        id: m['id'] as String,
        name: m['name'] as String,
        kind: ServiceKind.values.where((k) => k.name == m['kind']).firstOrNull ?? ServiceKind.other,
        city: (m['city'] as String?) ?? '',
        phone: m['phone'] as String?,
        address: m['address'] as String?,
        hours: m['hours'] as String?,
        latitude: (m['latitude'] as num?)?.toDouble(),
        longitude: (m['longitude'] as num?)?.toDouble(),
        staff: true,
      );
}
