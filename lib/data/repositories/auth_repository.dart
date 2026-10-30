import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/security/password_hasher.dart';
import '../../core/utils/validators.dart';
import '../../domain/models/user.dart';

/// Which sign-in screen a person used. A citizen account cannot sign in on the
/// administrator screen and the other way round.
enum SignInAudience { citizen, staff }

/// Accounts stored in the local database on this device. Passwords are salted
/// and iterated, but this is not a replacement for a server-side identity
/// provider with rate limiting, recovery and multi-device sessions.
class AuthRepository {
  AuthRepository(this._db);
  final Database _db;
  static const _uuid = Uuid();

  /// The local database, for the cloud subclass to keep its mirror of users.
  Database get database => _db;

  int get _ts => DateTime.now().millisecondsSinceEpoch;

  /// True when forgotten passwords are fixed by an emailed reset link (cloud
  /// accounts) rather than by an administrator typing a new one (local accounts).
  bool get usesEmailReset => false;

  /// Emails a password reset link. Cloud accounts only.
  Future<void> sendPasswordReset(String email) async {
    throw const ValidationException(
        ['Email reset is not available on this build. Ask an administrator to reset the password.']);
  }

  /// Called when the person logs out.
  Future<void> signOut() async {}


  List<String> _accountErrors(String name, String email, String password) => [
        Validators.name(name),
        Validators.email(email),
        Validators.password(password),
      ].whereType<String>().toList();

  Future<String> _insertUser(
    DatabaseExecutor db, {
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String? departmentId,
  }) async {
    final normalized = email.trim().toLowerCase();
    final exists = await db.query('users',
        where: 'email = ?', whereArgs: [normalized], limit: 1);
    if (exists.isNotEmpty) {
      throw const ValidationException(['An account with this email already exists.']);
    }
    final salt = PasswordHasher.generateSalt();
    final id = _uuid.v4();
    await db.insert('users', {
      'id': id,
      'name': name.trim(),
      'email': normalized,
      'password_hash': PasswordHasher.hash(password, salt),
      'salt': salt,
      'role': role.name,
      'department_id': departmentId,
      'is_demo': 0,
      'is_active': 1,
      'created_at': _ts,
    });
    return id;
  }

  // ------------------------------------------------------------ registration

  /// Self-registration. Always creates a citizen.
  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final errors = _accountErrors(name, email, password);
    if (errors.isNotEmpty) throw ValidationException(errors);
    final id = await _insertUser(_db,
        name: name, email: email, password: password, role: UserRole.citizen);
    return (await getById(id))!;
  }

  /// True when at least one administrator exists.
  Future<bool> hasAdmin() async {
    final r = await _db.rawQuery("SELECT COUNT(*) c FROM users WHERE role = 'admin'");
    return (r.first['c'] as int) > 0;
  }

  /// First-run setup. Works only while NO administrator exists, so it cannot
  /// be used to take over an installation that is already set up.
  Future<AppUser> createFirstAdmin({
    required String name,
    required String email,
    required String password,
  }) async {
    final errors = _accountErrors(name, email, password);
    if (errors.isNotEmpty) throw ValidationException(errors);
    final id = await _db.transaction((txn) async {
      final r = await txn.rawQuery("SELECT COUNT(*) c FROM users WHERE role = 'admin'");
      if ((r.first['c'] as int) > 0) {
        throw const PermissionDeniedException('Setup is already complete.');
      }
      final newId = await _insertUser(txn,
          name: name, email: email, password: password, role: UserRole.admin);
      await txn.insert('audit_log', {
        'actor_id': newId,
        'action': 'first_admin_created',
        'detail': 'Initial administrator account created during setup',
        'created_at': _ts,
      });
      return newId;
    });
    return (await getById(id))!;
  }

  /// Administrator creates an officer or another administrator.
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
    final errors = _accountErrors(name, email, password);
    if (role == UserRole.officer && !Departments.names.containsKey(departmentId)) {
      errors.add('Choose a department for an officer.');
    }
    if (errors.isNotEmpty) throw ValidationException(errors);
    final id = await _db.transaction((txn) async {
      final newId = await _insertUser(txn,
          name: name,
          email: email,
          password: password,
          role: role,
          departmentId: role == UserRole.officer ? departmentId : null);
      await txn.insert('audit_log', {
        'actor_id': actor.id,
        'action': 'staff_created',
        'detail': '${email.trim().toLowerCase()} as ${role.name}'
            '${departmentId == null || role != UserRole.officer ? '' : ' in $departmentId'}',
        'created_at': _ts,
      });
      return newId;
    });
    return (await getById(id))!;
  }

  // ----------------------------------------------------------------- sign-in

  Future<AppUser> signIn(String email, String password, {SignInAudience? audience}) async {
    const generic = ValidationException(['Incorrect email or password.']);
    final rows = await _db.query('users',
        where: 'email = ?', whereArgs: [email.trim().toLowerCase()], limit: 1);
    if (rows.isEmpty) throw generic;
    final row = rows.first;
    if (!PasswordHasher.verify(
        password, row['salt'] as String, row['password_hash'] as String)) {
      throw generic;
    }
    final user = AppUser.fromMap(row);
    if (!user.isActive) {
      throw const PermissionDeniedException('This account is disabled.');
    }
    if (audience == SignInAudience.citizen && user.isStaff) {
      throw const ValidationException(
          ['This is an administrator or officer account. Use Administrator Login.']);
    }
    if (audience == SignInAudience.staff && !user.isStaff) {
      throw const ValidationException(['This is a citizen account. Use Citizen Login.']);
    }
    return user;
  }

  /// An administrator sets a new temporary password for someone who forgot
  /// theirs. Not for your own account (use change password). Audited.
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
    final problem = Validators.password(newPassword);
    if (problem != null) throw ValidationException([problem]);
    final salt = PasswordHasher.generateSalt();
    await _db.transaction((txn) async {
      final n = await txn.update(
          'users', {'salt': salt, 'password_hash': PasswordHasher.hash(newPassword, salt)},
          where: 'id = ?', whereArgs: [targetId]);
      if (n == 0) throw const NotFoundException();
      await txn.insert('audit_log', {
        'actor_id': actor.id,
        'action': 'password_reset_by_admin',
        'detail': 'Temporary password set for user $targetId',
        'created_at': _ts,
      });
    });
  }

  /// True when [password] is the account's current password. Used to confirm
  /// a sensitive action (for example resetting the vault PIN).
  Future<bool> verifyPassword(String userId, String password) async {
    final rows = await _db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
    if (rows.isEmpty) return false;
    final row = rows.first;
    return PasswordHasher.verify(password, row['salt'] as String, row['password_hash'] as String);
  }

  Future<void> changePassword({
    required String userId,
    required String current,
    required String next,
  }) async {
    final rows = await _db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
    if (rows.isEmpty) throw const NotFoundException();
    final row = rows.first;
    if (!PasswordHasher.verify(
        current, row['salt'] as String, row['password_hash'] as String)) {
      throw const ValidationException(['Current password is incorrect.']);
    }
    final problem = Validators.password(next);
    if (problem != null) throw ValidationException([problem]);
    if (next == current) {
      throw const ValidationException(['Choose a password different from the current one.']);
    }
    final salt = PasswordHasher.generateSalt();
    await _db.transaction((txn) async {
      await txn.update(
          'users', {'salt': salt, 'password_hash': PasswordHasher.hash(next, salt)},
          where: 'id = ?', whereArgs: [userId]);
      await txn.insert('audit_log', {
        'actor_id': userId,
        'action': 'password_changed',
        'detail': 'Password changed by the account owner',
        'created_at': _ts,
      });
    });
  }

  // ---------------------------------------------------------------- reading

  Future<AppUser?> getById(String id) async {
    final rows = await _db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : AppUser.fromMap(rows.first);
  }

  Future<List<AppUser>> listUsers(AppUser actor) async {
    if (actor.role != UserRole.admin) {
      throw const PermissionDeniedException('Only administrators can list users.');
    }
    final rows = await _db.query('users', orderBy: 'role, name');
    return rows.map(AppUser.fromMap).toList();
  }

  /// Active officers of one department, for assignment pickers. Staff only.
  Future<List<AppUser>> officersInDepartment(AppUser actor, String departmentId) async {
    if (!actor.isStaff) {
      throw const PermissionDeniedException('Staff access only.');
    }
    final rows = await _db.query('users',
        where: "role = 'officer' AND is_active = 1 AND department_id = ?",
        whereArgs: [departmentId],
        orderBy: 'name');
    return rows.map(AppUser.fromMap).toList();
  }

  // ------------------------------------------------------------ admin edits

  /// Only an administrator may change roles, and never their own.
  Future<void> setRole({
    required AppUser actor,
    required String targetId,
    required UserRole role,
    String? departmentId,
  }) async {
    if (actor.role != UserRole.admin) {
      throw const PermissionDeniedException('Only administrators can change roles.');
    }
    if (actor.id == targetId) {
      throw const PermissionDeniedException('You cannot change your own role.');
    }
    if (role == UserRole.officer && departmentId == null) {
      throw const ValidationException(['Choose a department for an officer.']);
    }
    await _db.transaction((txn) async {
      await txn.update(
        'users',
        {
          'role': role.name,
          'department_id': role == UserRole.officer ? departmentId : null,
        },
        where: 'id = ?',
        whereArgs: [targetId],
      );
      await txn.insert('audit_log', {
        'actor_id': actor.id,
        'action': 'role_change',
        'detail': 'User $targetId set to ${role.name}',
        'created_at': _ts,
      });
    });
  }

  /// Disable or re-enable an account. Never your own, so an administrator
  /// cannot lock themselves out.
  Future<void> setActive({
    required AppUser actor,
    required String targetId,
    required bool active,
  }) async {
    if (actor.role != UserRole.admin) {
      throw const PermissionDeniedException('Only administrators can disable accounts.');
    }
    if (actor.id == targetId) {
      throw const PermissionDeniedException('You cannot disable your own account.');
    }
    await _db.transaction((txn) async {
      final n = await txn.update('users', {'is_active': active ? 1 : 0},
          where: 'id = ?', whereArgs: [targetId]);
      if (n == 0) throw const NotFoundException();
      await txn.insert('audit_log', {
        'actor_id': actor.id,
        'action': active ? 'account_enabled' : 'account_disabled',
        'detail': 'User $targetId',
        'created_at': _ts,
      });
    });
  }

  /// An administrator allots (or removes) the right of an officer to manage the
  /// city services directory.
  Future<void> setServicesAllowed({
    required AppUser actor,
    required String targetId,
    required bool allowed,
  }) async {
    if (actor.role != UserRole.admin) {
      throw const PermissionDeniedException('Only administrators can allot services access.');
    }
    await _db.transaction((txn) async {
      final n = await txn.update('users', {'services_allowed': allowed ? 1 : 0},
          where: "id = ? AND role = 'officer'", whereArgs: [targetId]);
      if (n == 0) throw const ValidationException(['Only officers can be allotted services access.']);
      await txn.insert('audit_log', {
        'actor_id': actor.id,
        'action': allowed ? 'services_allotted' : 'services_removed',
        'detail': 'User $targetId',
        'created_at': _ts,
      });
    });
  }
}
