import '../../core/constants/enums.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.departmentId,
    this.isDemo = false,
    this.isActive = true,
    this.servicesAllowed = false,
  });

  final String id;
  final String name;
  final String email;
  final UserRole role;

  /// Officers are limited to this department's records. Null for others.
  final String? departmentId;
  final bool isDemo;
  final bool isActive;

  /// An administrator can always manage the city services directory; an
  /// officer only when an administrator has allotted it.
  final bool servicesAllowed;

  bool get canManageServices => role == UserRole.admin || (role == UserRole.officer && servicesAllowed);

  bool get isStaff => role != UserRole.citizen;

  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(
        id: m['id'] as String,
        name: m['name'] as String,
        email: m['email'] as String,
        role: UserRole.values.byName(m['role'] as String),
        departmentId: m['department_id'] as String?,
        isDemo: (m['is_demo'] as int) == 1,
        isActive: (m['is_active'] as int) == 1,
        servicesAllowed: ((m['services_allowed'] as int?) ?? 0) == 1,
      );
}
