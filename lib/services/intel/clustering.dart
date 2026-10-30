import '../../core/constants/enums.dart';
import '../../core/utils/geo.dart';
import '../../domain/models/incident.dart';

/// A group of nearby reports.
class Cluster {
  Cluster(Incident first)
      : latitude = first.latitude!,
        longitude = first.longitude!,
        items = [first];
  double latitude, longitude;
  final List<Incident> items;
  int get count => items.length;

  void add(Incident i) {
    items.add(i);
    // running centroid
    final n = items.length;
    latitude += (i.latitude! - latitude) / n;
    longitude += (i.longitude! - longitude) / n;
  }

  /// Heat weight: higher priority counts more.
  double get weight => items.fold<double>(0, (a, i) => a + 1 + i.priority.index * 0.5);

  IncidentCategory get dominantCategory {
    final c = <IncidentCategory, int>{};
    for (final i in items) {
      c[i.category] = (c[i.category] ?? 0) + 1;
    }
    return (c.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  }
}

/// Greedy distance clustering: a report joins the first cluster whose centre
/// is within [radiusMeters], otherwise it starts a new cluster. Simple and
/// deterministic; reports without coordinates are skipped.
class GeoClusterer {
  const GeoClusterer({this.radiusMeters = 250});
  final double radiusMeters;

  List<Cluster> cluster(Iterable<Incident> incidents) {
    final sorted = incidents.where((i) => i.hasCoordinates).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final out = <Cluster>[];
    for (final i in sorted) {
      Cluster? home;
      var best = double.infinity;
      for (final c in out) {
        final d = distanceMeters(c.latitude, c.longitude, i.latitude!, i.longitude!);
        if (d <= radiusMeters && d < best) {
          best = d;
          home = c;
        }
      }
      if (home == null) {
        out.add(Cluster(i));
      } else {
        home.add(i);
      }
    }
    out.sort((a, b) => b.weight.compareTo(a.weight));
    return out;
  }

  /// Heat intensity 0..1 per cluster, relative to the busiest cluster.
  static List<({Cluster cluster, double intensity})> heat(List<Cluster> clusters) {
    if (clusters.isEmpty) return [];
    final max = clusters.map((c) => c.weight).reduce((a, b) => a > b ? a : b);
    return [for (final c in clusters) (cluster: c, intensity: c.weight / max)];
  }
}
