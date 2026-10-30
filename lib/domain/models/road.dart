import '../../core/constants/enums.dart';
import 'incident.dart';

enum RoadDamageType {
  pothole('Pothole'),
  damagedSurface('Damaged surface'),
  obstruction('Obstruction'),
  uncertain('Uncertain');

  const RoadDamageType(this.label);
  final String label;
}

enum RoadSeverity {
  minor('Minor', 1),
  moderate('Moderate', 2),
  severe('Severe', 3);

  const RoadSeverity(this.label, this.rank);
  final String label;
  final int rank;
}

/// Who or what set a value. Shown in the UI so nobody mistakes a keyword rule
/// for a trained model or a human check.
class RoadSource {
  static const rules = 'rule-based-local';
  static const officer = 'officer';

  static String label(String s) => switch (s) {
        rules => 'keyword rules (text only, photo not analysed)',
        officer => 'set by an officer',
        _ => s,
      };
}

class RoadDetails {
  const RoadDetails({
    required this.incidentId,
    required this.type,
    required this.typeSource,
    required this.severity,
    required this.severitySource,
  });

  final String incidentId;
  final RoadDamageType type;
  final String typeSource;
  final RoadSeverity severity;
  final String severitySource;

  factory RoadDetails.fromMap(Map<String, Object?> m) => RoadDetails(
        incidentId: m['incident_id'] as String,
        type: RoadDamageType.values.byName(m['damage_type'] as String),
        typeSource: m['damage_source'] as String,
        severity: RoadSeverity.values.byName(m['severity'] as String),
        severitySource: m['severity_source'] as String,
      );
}

enum PhotoKind { before, after }

class RepairPhoto {
  const RepairPhoto({
    required this.id,
    required this.kind,
    required this.path,
    required this.addedByName,
    required this.createdAt,
  });
  final String id;
  final PhotoKind kind;
  final String path;
  final String addedByName;
  final DateTime createdAt;
}

/// An incident together with its RoadVision data. Same underlying record as
/// everywhere else in the app; nothing is duplicated.
class RoadReport {
  const RoadReport({
    required this.incident,
    required this.details,
    this.assigneeName,
    required this.linkedDuplicates,
    required this.beforePhotos,
    required this.afterPhotos,
  });

  final Incident incident;
  final RoadDetails details;
  final String? assigneeName;

  /// How many other reports were closed as duplicates of this one.
  final int linkedDuplicates;

  /// Includes the reporter's own photo for "before".
  final int beforePhotos, afterPhotos;

  bool get isOpen => incident.status.isOpen;
  Priority get priority => incident.priority;
}
