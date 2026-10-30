import '../../core/constants/enums.dart';

/// The city service an update belongs to. Same names as the modules screen.
enum CityModule {
  flood('FloodGuard', Departments.drainage),
  roads('RoadVision', Departments.roads),
  traffic('TrafficMind', Departments.traffic),
  waste('WasteWise', Departments.sanitation),
  water('AquaSense', Departments.water),
  lighting('LumenCity', Departments.electrical),
  access('AccessCity', Departments.roads),
  environment('CoolCity', Departments.general),
  notice('City notice', Departments.general);

  const CityModule(this.label, this.departmentId);
  final String label;

  /// An officer may post to modules owned by their own department.
  final String departmentId;
}

enum UpdateKind {
  reading('Reading'),
  advisory('Advisory'),
  alert('Alert'),
  info('Notice');

  const UpdateKind(this.label);
  final String label;
}

/// Where a row came from. Everything is 'manual' today. 'feed' is reserved for
/// a future automatic importer so the screens do not have to change.
enum UpdateSource {
  manual('Entered by staff'),
  feed('Automatic feed');

  const UpdateSource(this.label);
  final String label;
}

class CityUpdate {
  const CityUpdate({
    required this.id,
    required this.module,
    required this.kind,
    required this.title,
    required this.detail,
    required this.area,
    required this.value,
    required this.unit,
    required this.source,
    required this.enteredByName,
    required this.enteredById,
    required this.createdAt,
    required this.expiresAt,
    required this.isDemo,
  });

  final String id, title, enteredByName, enteredById;
  final String? detail, area, unit;
  final double? value;
  final CityModule module;
  final UpdateKind kind;
  final UpdateSource source;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool isDemo;

  /// "12.5 mm", "3 m", or null when no value was entered.
  String? get valueText {
    final v = value;
    if (v == null) return null;
    final n = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return unit == null || unit!.isEmpty ? n : '$n $unit';
  }

  factory CityUpdate.fromMap(Map<String, Object?> m) => CityUpdate(
        id: m['id'] as String,
        module: CityModule.values.byName(m['module'] as String),
        kind: UpdateKind.values.byName(m['kind'] as String),
        title: m['title'] as String,
        detail: m['detail'] as String?,
        area: m['area'] as String?,
        value: (m['value'] as num?)?.toDouble(),
        unit: m['unit'] as String?,
        source: UpdateSource.values.byName(m['source'] as String),
        enteredByName: (m['who'] as String?) ?? 'Staff',
        enteredById: m['entered_by'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        expiresAt: m['expires_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['expires_at'] as int),
        isDemo: (m['is_demo'] as int) == 1,
      );
}
