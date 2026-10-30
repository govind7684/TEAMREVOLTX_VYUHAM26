import 'package:civinex_ai/core/constants/enums.dart';
import 'package:civinex_ai/core/errors/app_exceptions.dart';
import 'package:civinex_ai/data/database/app_database.dart';
import 'package:civinex_ai/data/repositories/auth_repository.dart';
import 'package:civinex_ai/data/repositories/cloud_auth_repository.dart';
import 'package:civinex_ai/services/cloud_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/demo_seeder.dart';

/// In-memory stand-in for Firebase, so the account rules can be tested offline.
class FakeCloud implements CloudIdentity {
  final accounts = <String, ({String uid, String password})>{}; // by email
  final profiles = <String, Map<String, Object?>>{};
  String? uid;
  final resets = <String>[];
  var verificationsSent = 0;
  var _n = 0;

  String _create(String email, String password) {
    final e = email.trim().toLowerCase();
    if (accounts.containsKey(e)) {
      throw const ValidationException(['An account with this email already exists.']);
    }
    final id = 'uid${++_n}';
    accounts[e] = (uid: id, password: password);
    return id;
  }

  @override
  String? get currentUid => uid;
  @override
  Future<String> createAccount(String email, String password) async => uid = _create(email, password);
  @override
  Future<String> createAccountForSomeoneElse(String email, String password) async =>
      _create(email, password);
  @override
  Future<String> signIn(String email, String password) async {
    final a = accounts[email.trim().toLowerCase()];
    if (a == null || a.password != password) {
      throw const ValidationException(['Incorrect email or password.']);
    }
    return uid = a.uid;
  }

  @override
  Future<void> signOut() async => uid = null;
  @override
  Future<void> sendPasswordReset(String email) async => resets.add(email);
  @override
  Future<void> sendVerificationEmail() async => verificationsSent++;
  @override
  Future<bool> isEmailVerified() async => false;
  @override
  Future<bool> verifyPassword(String password) async =>
      accounts.values.any((a) => a.uid == uid && a.password == password);
  @override
  Future<void> updatePassword(String newPassword) async {
    final k = accounts.entries.firstWhere((e) => e.value.uid == uid).key;
    accounts[k] = (uid: uid!, password: newPassword);
  }

  @override
  Future<Map<String, Object?>?> getProfile(String id) async => profiles[id];
  @override
  Future<void> setProfile(String id, Map<String, Object?> data, {bool merge = false}) async =>
      profiles[id] = merge ? {...?profiles[id], ...data} : {...data};
  @override
  Future<List<Map<String, Object?>>> listProfiles() async =>
      [for (final e in profiles.entries) {...e.value, 'id': e.key}];
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late FakeCloud cloud;
  late CloudAuthRepository auth;

  setUp(() async {
    db = await AppDatabase.open(path: inMemoryDatabasePath);
    await DemoSeeder.ensureDepartments(db);
    cloud = FakeCloud();
    // The first administrator is created in the Firebase console.
    cloud.accounts['chief@city.example'] = (uid: 'uidAdmin', password: 'Passw0rdX');
    cloud.profiles['uidAdmin'] = {
      'name': 'Chief', 'email': 'chief@city.example', 'role': 'admin', 'active': true
    };
    auth = CloudAuthRepository(db, cloud);
  });
  tearDown(() => db.close());

  test('registration creates a citizen profile and sends a verification email', () async {
    final u = await auth.register(name: 'Asha', email: 'Asha@Example.com', password: 'Passw0rdX');
    expect(u.role, UserRole.citizen);
    expect(cloud.profiles[u.id]!['role'], 'citizen');
    expect(cloud.verificationsSent, 1);
    expect(await auth.getById(u.id), isNotNull);
  });

  test('setup is never offered and cannot be used', () async {
    expect(await auth.hasAdmin(), isTrue);
    await expectLater(
        auth.createFirstAdmin(name: 'X Y', email: 'x@y.example', password: 'Passw0rdX'),
        throwsA(isA<PermissionDeniedException>()));
  });

  test('audiences are separated', () async {
    await auth.register(name: 'Asha', email: 'asha@example.com', password: 'Passw0rdX');
    await auth.signOut();
    await expectLater(
        auth.signIn('asha@example.com', 'Passw0rdX', audience: SignInAudience.staff),
        throwsA(isA<ValidationException>()));
    await expectLater(
        auth.signIn('chief@city.example', 'Passw0rdX', audience: SignInAudience.citizen),
        throwsA(isA<ValidationException>()));
    expect(cloud.currentUid, isNull, reason: 'a refused sign-in must not leave a session');
    final admin = await auth.signIn('chief@city.example', 'Passw0rdX', audience: SignInAudience.staff);
    expect(admin.role, UserRole.admin);
  });

  test('admin creates an officer without being signed out', () async {
    final admin = await auth.signIn('chief@city.example', 'Passw0rdX');
    final officer = await auth.createStaff(
        actor: admin,
        name: 'Officer',
        email: 'officer@city.example',
        password: 'Passw0rdX',
        role: UserRole.officer,
        departmentId: 'dept_roads');
    expect(cloud.currentUid, 'uidAdmin');
    expect(cloud.profiles[officer.id]!['role'], 'officer');
    final list = await auth.officersInDepartment(admin, 'dept_roads');
    expect(list.map((u) => u.id), [officer.id]);
  });

  test('only administrators can create staff, and citizens cannot', () async {
    final c = await auth.register(name: 'Asha', email: 'asha@example.com', password: 'Passw0rdX');
    await expectLater(
        auth.createStaff(
            actor: c, name: 'Bad Guy', email: 'bad@x.example', password: 'Passw0rdX', role: UserRole.admin),
        throwsA(isA<PermissionDeniedException>()));
  });

  test('a disabled account cannot sign in or be restored', () async {
    final admin = await auth.signIn('chief@city.example', 'Passw0rdX');
    final c = await auth.register(name: 'Asha', email: 'asha@example.com', password: 'Passw0rdX');
    await auth.signIn('chief@city.example', 'Passw0rdX');
    await auth.setActive(actor: admin, targetId: c.id, active: false);
    await expectLater(auth.signIn('asha@example.com', 'Passw0rdX'),
        throwsA(isA<PermissionDeniedException>()));
    cloud.uid = c.id;
    expect(await auth.restore(), isNull);
  });

  test('password reset sends an email; admin reset emails the person', () async {
    await auth.sendPasswordReset('asha@example.com');
    expect(cloud.resets, ['asha@example.com']);
    await expectLater(auth.sendPasswordReset('not-an-email'), throwsA(isA<ValidationException>()));
    final c = await auth.register(name: 'Asha', email: 'asha@example.com', password: 'Passw0rdX');
    final admin = await auth.signIn('chief@city.example', 'Passw0rdX');
    await auth.resetPassword(actor: admin, targetId: c.id, newPassword: '');
    expect(cloud.resets.last, 'asha@example.com');
  });

  test('change password checks the current one', () async {
    final c = await auth.register(name: 'Asha', email: 'asha@example.com', password: 'Passw0rdX');
    await expectLater(auth.changePassword(userId: c.id, current: 'wrong', next: 'NewPassw0rd1'),
        throwsA(isA<ValidationException>()));
    await auth.changePassword(userId: c.id, current: 'Passw0rdX', next: 'NewPassw0rd1');
    expect(await auth.verifyPassword(c.id, 'NewPassw0rd1'), isTrue);
  });

  test('restore works offline from the phone mirror', () async {
    final c = await auth.register(name: 'Asha', email: 'asha@example.com', password: 'Passw0rdX');
    cloud.profiles.remove(c.id); // simulate no profile reachable
    expect((await auth.restore())!.id, c.id);
  });

  test('local mode is unchanged', () async {
    final local = AuthRepository(db);
    expect(local.usesEmailReset, isFalse);
    await expectLater(local.sendPasswordReset('a@b.example'), throwsA(isA<ValidationException>()));
  });
}
