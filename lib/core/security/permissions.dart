import '../../domain/models/incident.dart';
import '../../domain/models/user.dart';
import '../constants/enums.dart';

/// Single place for authorization rules. Repositories call these on every
/// operation, so UI hiding alone is never the only protection.
class Permissions {
  static bool canView(AppUser u, Incident i) {
    switch (u.role) {
      case UserRole.admin:
        return true;
      case UserRole.officer:
        return i.departmentId == u.departmentId;
      case UserRole.citizen:
        return i.reporterId == u.id;
    }
  }

  static bool canManage(AppUser u, Incident i) {
    if (u.role == UserRole.admin) return true;
    return u.role == UserRole.officer && i.departmentId == u.departmentId;
  }

  /// Citizens may edit or withdraw only their own report, only before
  /// staff have picked it up.
  static bool canCitizenModify(AppUser u, Incident i) =>
      u.role == UserRole.citizen &&
      i.reporterId == u.id &&
      i.status == IncidentStatus.submitted;

  static bool canManageUsers(AppUser u) => u.role == UserRole.admin;

  static bool canViewAudit(AppUser u) => u.role == UserRole.admin;

  /// Staff may move a report forward or reject; terminal states are final.
  static bool isValidTransition(IncidentStatus from, IncidentStatus to) {
    if (!from.isOpen) return false;
    const staffTargets = {
      IncidentStatus.underReview,
      IncidentStatus.assigned,
      IncidentStatus.inProgress,
      IncidentStatus.resolved,
      IncidentStatus.rejected,
    };
    return staffTargets.contains(to) && from != to;
  }
}
