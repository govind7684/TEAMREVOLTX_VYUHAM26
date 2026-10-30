import '../../core/constants/enums.dart';

class Incident {
  const Incident({
    required this.id,
    required this.reporterId,
    required this.category,
    required this.description,
    required this.locationText,
    this.latitude,
    this.longitude,
    this.photoPath,
    required this.peopleAffected,
    required this.safetyRisk,
    required this.priority,
    required this.priorityScore,
    required this.priorityReasons,
    required this.aiProvider,
    required this.aiExplanation,
    required this.needsHumanReview,
    required this.departmentId,
    this.assignedOfficerId,
    required this.status,
    this.resolutionNote,
    this.rejectionReason,
    this.duplicateOfId,
    required this.createdAt,
    required this.updatedAt,
    required this.isDemo,
    required this.dataSource,
    this.aiConfidence,
    this.aiAlternatives,
    this.imageLabel,
    this.imageConfidence,
    this.imageSource,
    this.imageVerified = false,
    this.slaDueAt,
    this.escalated = false,
    this.escalationLevel = 0,
    this.priorityOverridden = false,
    this.dupVerified = true,
    this.dupScore,
    this.photoOrigin,
    this.photoCheck,
  });

  final String id;
  final String reporterId;
  final IncidentCategory category;
  final String description;
  final String locationText;
  final double? latitude;
  final double? longitude;
  final String? photoPath;
  final int peopleAffected;
  final bool safetyRisk;
  final Priority priority;
  final int priorityScore;
  final String priorityReasons;

  /// Which engine produced the suggestion, e.g. "rule-based-local".
  final String aiProvider;
  final String aiExplanation;
  final bool needsHumanReview;
  final String departmentId;
  final String? assignedOfficerId;
  final IncidentStatus status;
  final String? resolutionNote;
  final String? rejectionReason;
  final String? duplicateOfId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDemo;
  final String dataSource;

  /// Model probability for the chosen category (null for rule-based output).
  final double? aiConfidence;
  final String? aiAlternatives;
  final String? imageLabel;
  final double? imageConfidence;

  /// 'human' (a person tagged the photo) or a model id. Never invented.
  final String? imageSource;
  final bool imageVerified;
  final DateTime? slaDueAt;
  final bool escalated;
  final int escalationLevel;
  final bool priorityOverridden;

  /// False while an automatic duplicate link still waits for staff to confirm.
  final bool dupVerified;
  final double? dupScore;

  /// 'camera' (taken live in the app) or 'gallery'. Null when there is no photo.
  final String? photoOrigin;

  /// JSON written by the photo checks; read with PhotoCheck.parse.
  final String? photoCheck;

  /// An open report linked under a parent: staff work the parent only.
  bool get isLinkedChild => duplicateOfId != null && status.isOpen;

  bool isOverdue(DateTime now) =>
      status.isOpen && slaDueAt != null && now.isAfter(slaDueAt!);

  bool get hasCoordinates => latitude != null && longitude != null;

  factory Incident.fromMap(Map<String, Object?> m) => Incident(
        id: m['id'] as String,
        reporterId: m['reporter_id'] as String,
        category: IncidentCategory.values.byName(m['category'] as String),
        description: m['description'] as String,
        locationText: m['location_text'] as String,
        latitude: (m['latitude'] as num?)?.toDouble(),
        longitude: (m['longitude'] as num?)?.toDouble(),
        photoPath: m['photo_path'] as String?,
        peopleAffected: m['people_affected'] as int,
        safetyRisk: (m['safety_risk'] as int) == 1,
        priority: Priority.values.byName(m['priority'] as String),
        priorityScore: m['priority_score'] as int,
        priorityReasons: m['priority_reasons'] as String,
        aiProvider: m['ai_provider'] as String,
        aiExplanation: m['ai_explanation'] as String,
        needsHumanReview: (m['needs_human_review'] as int) == 1,
        departmentId: m['department_id'] as String,
        assignedOfficerId: m['assigned_officer_id'] as String?,
        status: IncidentStatus.values.byName(m['status'] as String),
        resolutionNote: m['resolution_note'] as String?,
        rejectionReason: m['rejection_reason'] as String?,
        duplicateOfId: m['duplicate_of_id'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
        isDemo: (m['is_demo'] as int) == 1,
        dataSource: m['data_source'] as String,
        aiConfidence: (m['ai_confidence'] as num?)?.toDouble(),
        aiAlternatives: m['ai_alternatives'] as String?,
        imageLabel: m['image_label'] as String?,
        imageConfidence: (m['image_confidence'] as num?)?.toDouble(),
        imageSource: m['image_source'] as String?,
        imageVerified: ((m['image_verified'] as int?) ?? 0) == 1,
        slaDueAt: m['sla_due_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['sla_due_at'] as int),
        escalated: ((m['escalated'] as int?) ?? 0) == 1,
        escalationLevel: (m['escalation_level'] as int?) ?? 0,
        priorityOverridden: ((m['priority_overridden'] as int?) ?? 0) == 1,
        dupVerified: ((m['dup_verified'] as int?) ?? 1) == 1,
        dupScore: (m['dup_score'] as num?)?.toDouble(),
        photoOrigin: m['photo_origin'] as String?,
        photoCheck: m['photo_check'] as String?,
      );
}

class StatusEvent {
  const StatusEvent({
    required this.status,
    required this.actorName,
    this.note,
    required this.at,
  });
  final IncidentStatus status;
  final String actorName;
  final String? note;
  final DateTime at;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.incidentId,
    required this.isRead,
    required this.createdAt,
  });
  final String id;
  final String title;
  final String body;
  final String? incidentId;
  final bool isRead;
  final DateTime createdAt;
}

class AuditEntry {
  const AuditEntry({
    required this.actorName,
    required this.action,
    required this.detail,
    required this.at,
  });
  final String actorName;
  final String action;
  final String detail;
  final DateTime at;
}
