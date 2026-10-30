import '../../core/constants/enums.dart';

enum AssignmentState { pending, accepted, rejected, reassigned }

class Assignment {
  const Assignment({
    required this.id,
    required this.incidentId,
    required this.officerId,
    required this.officerName,
    required this.assignedByName,
    required this.state,
    this.reason,
    required this.createdAt,
    this.respondedAt,
  });
  final String id, incidentId, officerId, officerName, assignedByName;
  final AssignmentState state;
  final String? reason;
  final DateTime createdAt;
  final DateTime? respondedAt;
}

enum ResourceState { open, approved, declined }

class ResourceRequest {
  const ResourceRequest({
    required this.id,
    required this.incidentId,
    required this.requestedByName,
    required this.description,
    required this.state,
    this.decisionNote,
    required this.createdAt,
  });
  final String id, incidentId, requestedByName, description;
  final ResourceState state;
  final String? decisionNote;
  final DateTime createdAt;
}

class FeedbackEntry {
  const FeedbackEntry({
    required this.incidentId,
    required this.rating,
    this.comment,
    required this.confirmedFixed,
    required this.createdAt,
    this.departmentId,
  });
  final String incidentId;
  final int rating;
  final String? comment;
  final bool confirmedFixed;
  final DateTime createdAt;
  final String? departmentId;
}

class InternalNote {
  const InternalNote(this.authorName, this.body, this.createdAt);
  final String authorName, body;
  final DateTime createdAt;
}

/// What a citizen may see about someone else's report. No description text,
/// no reporter, no photo, only what is needed to decide "that's my problem
/// too" and press support.
class PublicIncident {
  const PublicIncident({
    required this.id,
    required this.category,
    required this.status,
    required this.areaText,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    required this.citizens,
    required this.supportedByMe,
    required this.createdAt,
  });
  final String id;
  final IncidentCategory category;
  final IncidentStatus status;
  final String areaText;

  /// Rounded to about 100 m. Null when the reporter gave no GPS position.
  final double? latitude, longitude;

  /// Null in the city-wide list, where no position was used.
  final double? distanceMeters;
  final int citizens;
  final bool supportedByMe;
  final DateTime createdAt;
}

class MaintenanceReport {
  const MaintenanceReport({
    this.slaBackfilled = 0,
    this.autoAssigned = 0,
    this.escalated = 0,
    this.autoClosed = 0,
  });
  final int slaBackfilled, autoAssigned, escalated, autoClosed;
  bool get changedAnything => slaBackfilled + autoAssigned + escalated + autoClosed > 0;
  String get text => 'Auto-assigned $autoAssigned, escalated $escalated overdue, '
      'auto-closed $autoClosed, SLA set on $slaBackfilled.';
}
