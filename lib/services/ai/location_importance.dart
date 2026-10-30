/// How sensitive a place is, from words in the location text. This is a
/// keyword heuristic (no map data about real facilities is available offline),
/// so it can miss places and is shown to staff as a reason, never hidden.
class LocationImportance {
  const LocationImportance(this.points, this.reason);
  final int points;
  final String? reason;

  static const _high = [
    'hospital', 'clinic', 'school', 'college', 'anganwadi', 'nursery',
    'bus stand', 'bus station', 'railway', 'metro', 'airport', 'fire station',
    'police station', 'old age', 'bridge', 'highway', 'nh ',
  ];
  static const _medium = [
    'market', 'junction', 'temple', 'church', 'mosque', 'office', 'bank',
    'mall', 'stadium', 'park', 'crossing', 'bus stop', 'main road', 'town',
  ];

  static LocationImportance assess(String locationText) {
    final t = ' ${locationText.toLowerCase()} ';
    for (final w in _high) {
      if (t.contains(w)) {
        return LocationImportance(2, '+2 sensitive location (mentions "${w.trim()}")');
      }
    }
    for (final w in _medium) {
      if (t.contains(w)) {
        return LocationImportance(1, '+1 busy location (mentions "${w.trim()}")');
      }
    }
    return const LocationImportance(0, null);
  }
}
