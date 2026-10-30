import 'package:latlong2/latlong.dart';

import '../../domain/models/incident.dart';

/// Default view when there is nothing to show: central Kerala.
const keralaCenter = LatLng(10.0, 76.3);

List<Incident> mappable(Iterable<Incident> incidents) =>
    incidents.where((i) => i.hasCoordinates).toList();

LatLng centerFor(Iterable<Incident> incidents) {
  final pts = mappable(incidents).toList();
  if (pts.isEmpty) return keralaCenter;
  final lat = pts.map((i) => i.latitude!).reduce((a, b) => a + b) / pts.length;
  final lng = pts.map((i) => i.longitude!).reduce((a, b) => a + b) / pts.length;
  return LatLng(lat, lng);
}

/// Zoom that roughly fits the spread of points (no map controller needed).
double zoomFor(Iterable<Incident> incidents) {
  final pts = mappable(incidents).toList();
  if (pts.length < 2) return pts.isEmpty ? 7.5 : 14;
  final lats = pts.map((i) => i.latitude!);
  final lngs = pts.map((i) => i.longitude!);
  final span = [
    lats.reduce((a, b) => a > b ? a : b) - lats.reduce((a, b) => a < b ? a : b),
    lngs.reduce((a, b) => a > b ? a : b) - lngs.reduce((a, b) => a < b ? a : b),
  ].reduce((a, b) => a > b ? a : b);
  if (span < 0.01) return 14;
  if (span < 0.05) return 12;
  if (span < 0.2) return 10;
  if (span < 1) return 8.5;
  return 7;
}
