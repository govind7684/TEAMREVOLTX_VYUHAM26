import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/utils/validators.dart';
import '../../domain/models/user.dart';
import '../../services/cloud_identity.dart';
import 'auth_repository.dart';

/// Accounts held by Firebase Authentication (who you are) and one Firestore
/// document per person (`users/{uid}`: name, role, department, active flag).
///
/// The phone keeps a mirror row in its own `users` table, keyed by the
/// Firebase uid, because the rest of the app (reports, audit log, vault) still
/// stores its data on the phone and refers to people by id. No password is
/// stored locally for cloud accounts.
class CloudAuthRepository extends AuthRepository {
  CloudAuthRepository(Database db, this._cloud) : super(db);
  final CloudIdentity _cloud;

  static const _mirrorHash = 'cloud-account';

  @override
  bool get usesEmailReset => true;

  CloudIdentity get cloud => _cloud;

  int get _now => DateTime.now().millisecondsSinceEpoch;

  // ------------------------------------------------------------- mirroring

  /// Plain-language note about how far the last sign-in got, shown under the form.
  static String lastSignInStage = '';

  AppUser _fromProfile(String uid, Map<String, Object?> p) {
    final roleName = p['role'] as String?;
    final role = UserRole.values.where((r) => r.name == roleName).firstOrNull ?? UserRole.citizen;
    return AppUser(
      id: uid,
      name: (p['name'] as String?)?.trim().isNotEmpty == true ? p['name'] as String : 'User',
      email: ((p['email'] as String?) ?? '').toLowerCase(),
      role: role,
      departmentId: role == UserRole.officer ? p['departmentId'] as String? : null,
      isActive: p['active'] != false,
      servicesAllowed: p['servicesAllowed'] == true,
    );
  }

  Future<void> _mirror(AppUser u) async {
    await database.transaction((txn) async {
      // A leftover local account with the same email but a different id would
      // violate the unique email column.
      await txn.delete('users', where: 'email = ? AND id <> ?', whereArgs: [u.email, u.id]);
      final values = {
        'name': u.name,
        'email': u.email,
        'role': u.role.name,
        'department_id': u.departmentId,
        'is_active': u.isActive ? 1 : 0,
        'services_allowed': u.servicesAllowed ? 1 : 0,
      };
      final n = await txn.update('users', values, where: 'id = ?', whereArgs: [u.id]);
      if (n == 0) {
        await txn.insert('users', {
          'id': u.id,
          ...values,
          'password_hash': _mirrorHash,
          'salt': '',
          'is_demo': 0,
          'created_at': _now,
        });
      }
    });
  }

  List<String> _errors(String name, String email, String password) => [
        Validators.name(name),
        Validators.email(email),
        Validators.password(password),
      ].whereType<String>().toList();

  // --------------------------------------------------------------- startup

  /// The user Firebase still has signed in, for restoring a session. Uses the
  /// server when reachable (so a disabled account is signed out) and the
  /// phone's mirror when offline.
  Future<AppUser?> restore() async {
    final uid = _cloud.currentUid;
    if (uid == null) return null;
    try {
      final profile = await _cloud.getProfile(uid);
      if (profile == null) return await getById(uid);
      final u = _fromProfile(uid, profile);
      if (!u.isActive) {
        await _cloud.signOut();
        return null;
      }
      await _mirror(u);
      return u;
    } catch (_) {
      final local = await getById(uid);
      return (local != null && local.isActive) ? local : null;
    }
  }

  // --------------------------------------------------------------- sign up

  @override
  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final errors = _errors(name, email, password);
    if (errors.isNotEmpty) throw ValidationException(errors);
    final uid = await _cloud.createAccount(email, password);
    final u = AppUser(
        id: uid, name: name.trim(), email: email.trim().toLowerCase(), role: UserRole.citizen);
    try {
      await _cloud.setProfile(uid, {
        'name': u.name,
        'email': u.email,
        'role': 'citizen',
        'active': true,
        'createdAt': _now,
      });
    } catch (e) {
      await _cloud.signOut();
      rethrow;
    }
    await _mirror(u);
    try {
      await _cloud.sendVerificationEmail();
    } catch (_) {/* verification can be requested again from Settings */}
    return u;
  }

  /// With cloud accounts the first administrator is created in the Firebase
  /// console, so setup never appears in the app.
  @override
  Future<bool> hasAdmin() async => true;

  @override
  Future<AppUser> createFirstAdmin({
    required String name,
    required String email,
    required String password,
  }) async =>
      throw const PermissionDeniedException(
          'The first administrator is created in the Firebase console.');

  @override
  Future<AppUser> createStaff({
    required AppUser actor,
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String? departmentId,
  }) async {
    if (actor.role != UserRole.admin) {
      throw const PermissionDeniedException('Only administrators can create staff accounts.');
    }
    if (role == UserRole.citizen) {
      throw const ValidationException(['Citizens register themselves.']);
    }
    final errors = _errors(name, email, password);
    if (role == UserRole.officer && !Departments.names.containsKey(departmentId)) {
      errors.add('Choose a department for an officer.');
    }
    if (errors.isNotEmpty) throw ValidationException(errors);
    final uid = await _cloud.createAccountForSomeoneElse(email, password);
    final u = AppUser(
      id: uid,
      name: name.trim(),
      email: email.trim().toLowerCase(),
      role: role,
      departmentId: role == UserRole.officer ? departmentId : null,
    );
    await _cloud.setProfile(uid, {
      'name': u.name,
      'email': u.email,
      'role': role.name,
      if (u.departmentId != null) 'departmentId': u.departmentId,
      'active': true,
      'createdAt': _now,
    });
    await _mirror(u);
    await database.insert('audit_log', {
      'actor_id': actor.id,
      'action': 'staff_created',
      'detail': '${u.email} as ${role.name}${u.departmentId == null ? '' : ' in ${u.departmentId}'}',
      'created_at': _now,
    });
    return u;
  }

  // --------------------------------------------------------------- sign in

  @override
  Future<AppUser> signIn(String email, String password, {SignInAudience? audience}) async {
    lastSignInStage = 'Firebase did not accept this email and password.';
    final uid = await _cloud.signIn(email, password);
    lastSignInStage = 'Firebase accepted the password. Reading the profile for this account...';
    debugPrint('CIVINEX signIn: Firebase accepted the password, uid=$uid');
    try {
      var profile = await _cloud.getProfile(uid);
      lastSignInStage = profile == null
          ? 'Firebase accepted the password, but there is NO profile document for uid $uid in Firestore users.'
          : 'Firebase accepted the password. Profile found: role=${profile['role']}, active=${profile['active']}.';
      debugPrint('CIVINEX signIn: profile ${profile == null ? 'NOT FOUND for this uid' : 'found: role=${profile['role']} (${profile['role'].runtimeType}), active=${profile['active']} (${profile['active'].runtimeType})'}');
      if (profile == null) {
        if (audience == SignInAudience.staff) {
          throw const PermissionDeniedException(
              'This account has no administrator or officer profile.');
        }
        // A citizen whose sign-up was interrupted before the profile was saved.
        profile = {
          'name': email.split('@').first,
          'email': email.trim().toLowerCase(),
          'role': 'citizen',
          'active': true,
          'createdAt': _now,
        };
        await _cloud.setProfile(uid, profile);
      }
      final u = _fromProfile(uid, profile);
      if (!u.isActive) {
        throw const PermissionDeniedException('This account is disabled.');
      }
      if (audience == SignInAudience.citizen && u.isStaff) {
        throw const ValidationException(
            ['This is an administrator or officer account. Use Administrator Login.']);
      }
      if (audience == SignInAudience.staff && !u.isStaff) {
        throw const ValidationException(['This is a citizen account. Use Citizen Login.']);
      }
      await _mirror(u);
      return u;
    } catch (_) {
      await _cloud.signOut();
      rethrow;
    }
  }

  @override
  Future<void> signOut() => _cloud.signOut();

  // ------------------------------------------------------------- passwords

  @override
  Future<void> sendPasswordReset(String email) async {
    final problem = Validators.email(email);
    if (problem != null) throw ValidationException([problem]);
    await _cloud.sendPasswordReset(email);
  }

  /// Administrators cannot set another person's password in Firebase without a
  /// server, so they email the person a reset link instead.
  @override
  Future<void> resetPassword({
    required AppUser actor,
    required String targetId,
    required String newPassword,
  }) async {
    if (actor.role != UserRole.admin) {
      throw const PermissionDeniedException('Only administrators can reset passwords.');
    }
    if (actor.id == targetId) {
      throw const PermissionDeniedException('Use Change password for your own account.');
    }
    final target = await getById(targetId);
    if (target == null) throw const NotFoundException();
    await _cloud.sendPasswordReset(target.email);
    await database.insert('audit_log', {
      'actor_id': actor.id,
      'action': 'password_reset_email_sent',
      'detail': 'Reset link emailed to user $targetId',
      'created_at': _now,
    });
  }

  @override
  Future<bool> verifyPassword(String userId, String password) async {
    if (_cloud.currentUid != userId) return false;
    return _cloud.verifyPassword(password);
  }

  @override
  Future<void> changePassword({
    required String userId,
    required String current,
    required String next,
  }) async {
    if (_cloud.currentUid != userId) {
      throw const PermissionDeniedException('Please sign in again.');
    }
    if (!await _cloud.verifyPassword(current)) {
      throw const ValidationException(['Current password is incorrect.']);
    }
    final problem = Validators.password(next);
    if (problem != null) throw ValidationException([problem]);
    if (next == current) {
      throw const ValidationException(['Choose a password different from the current one.']);
    }
    await _cloud.updatePassword(next);
    await database.insert('audit_log', {
      'actor_id': userId,
      'action': 'password_changed',
      'detail': 'Password changed by the account owner',
      'created_at': _now,
    });
  }

  // --------------------------------------------------------------- reading

  /// Copies every account's profile (staff may read all) into this phone's user
  /// table so officers can be picked, routed to and named. Best effort.
  Future<void> refreshMirror() async {
    try {
      for (final p in await _cloud.listProfiles()) {
        await _mirror(_fromProfile(p['id'] as String, p));
      }
    } catch (_) {/* offline: use what the phone already knows */}
  }

  @override
  Future<List<AppUser>> listUsers(AppUser actor) async {
    if (actor.role != UserRole.admin) {
      throw const PermissionDeniedException('Only administrators can list users.');
    }
    await refreshMirror();
    return super.listUsers(actor);
  }

  @override
  Future<List<AppUser>> officersInDepartment(AppUser actor, String departmentId) async {
    if (!actor.isStaff) throw const PermissionDeniedException('Staff access only.');
    await refreshMirror();
    return super.officersInDepartment(actor, departmentId);
  }

  // ------------------------------------------------------------ admin edits

  Future<void> _requireOnlineAdmin(AppUser actor, String targetId, String own) async {
    if (actor.role != UserRole.admin) {
      throw PermissionDeniedException(own);
    }
  }

  @override
  Future<void> setRole({
    required AppUser actor,
    required String targetId,
    required UserRole role,
    String? departmentId,
  }) async {
    await _requireOnlineAdmin(actor, targetId, 'Only administrators can change roles.');
    if (actor.id == targetId) {
      throw const PermissionDeniedException('You cannot change your own role.');
    }
    if (role == UserRole.officer && departmentId == null) {
      throw const ValidationException(['Choose a department for an officer.']);
    }
    await _cloud.setProfile(
        targetId,
        {
          'role': role.name,
          'departmentId': role == UserRole.officer ? departmentId : null,
        },
        merge: true);
    await super.setRole(
        actor: actor, targetId: targetId, role: role, departmentId: departmentId);
  }

  @override
  Future<void> setActive({
    required AppUser actor,
    required String targetId,
    required bool active,
  }) async {
    await _requireOnlineAdmin(actor, targetId, 'Only administrators can disable accounts.');
    if (actor.id == targetId) {
      throw const PermissionDeniedException('You cannot disable your own account.');
    }
    await _cloud.setProfile(targetId, {'active': active}, merge: true);
    await super.setActive(actor: actor, targetId: targetId, active: active);
  }

  @override
  Future<void> setServicesAllowed({
    required AppUser actor,
    required String targetId,
    required bool allowed,
  }) async {
    if (actor.role != UserRole.admin) {
      throw const PermissionDeniedException('Only administrators can allot services access.');
    }
    await _cloud.setProfile(targetId, {'servicesAllowed': allowed}, merge: true);
    await super.setServicesAllowed(actor: actor, targetId: targetId, allowed: allowed);
  }
}
