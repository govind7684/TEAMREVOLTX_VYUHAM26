import 'package:civinex_ai/core/constants/enums.dart';
import 'package:civinex_ai/core/errors/app_exceptions.dart';
import 'package:civinex_ai/data/database/app_database.dart';
import 'package:civinex_ai/data/repositories/auth_repository.dart';
import 'package:civinex_ai/domain/models/user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/demo_seeder.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late AuthRepository auth;
  late AppUser admin, officer, citizen;

  setUp(() async {
    db = await AppDatabase.open(path: inMemoryDatabasePath);
    await DemoSeeder.ensureDepartments(db);
    auth = AuthRepository(db);
    admin = await auth.createFirstAdmin(
        name: 'Chief', email: 'chief@city.example', password: 'Passw0rdX');
    officer = await auth.createStaff(
        actor: admin,
        name: 'Officer',
        email: 'officer@city.example',
        password: 'Passw0rdX',
        role: UserRole.officer,
        departmentId: 'dept_roads');
    citizen = await auth.register(name: 'Asha', email: 'asha@example.com', password: 'Passw0rdX');
  });
  tearDown(() => db.close());

  test('a fresh install has no reports, no sample accounts', () async {
    final fresh = await AppDatabase.open(path: inMemoryDatabasePath);
    expect(await AuthRepository(fresh).hasAdmin(), isFalse);
    final c = await fresh.rawQuery('SELECT (SELECT COUNT(*) FROM users) u, (SELECT COUNT(*) FROM incidents) i, '
        '(SELECT COUNT(*) FROM rainfall_readings) r, (SELECT COUNT(*) FROM city_updates) c');
    expect(c.single.values.every((v) => v == 0), isTrue);
    await fresh.close();
  });

  test('citizen login only accepts citizen accounts', () async {
    expect((await auth.signIn('asha@example.com', 'Passw0rdX', audience: SignInAudience.citizen)).id,
        citizen.id);
    await expectLater(
        auth.signIn('chief@city.example', 'Passw0rdX', audience: SignInAudience.citizen),
        throwsA(isA<ValidationException>()));
    await expectLater(
        auth.signIn('officer@city.example', 'Passw0rdX', audience: SignInAudience.citizen),
        throwsA(isA<ValidationException>()));
  });

  test('administrator login only accepts staff accounts', () async {
    expect((await auth.signIn('chief@city.example', 'Passw0rdX', audience: SignInAudience.staff)).role,
        UserRole.admin);
    expect((await auth.signIn('officer@city.example', 'Passw0rdX', audience: SignInAudience.staff)).id,
        officer.id);
    await expectLater(
        auth.signIn('asha@example.com', 'Passw0rdX', audience: SignInAudience.staff),
        throwsA(isA<ValidationException>()));
  });

  test('wrong password gives the same message for citizen and staff screens', () async {
    Future<String> msg(String email, SignInAudience a) async {
      try {
        await auth.signIn(email, 'nope', audience: a);
      } on ValidationException catch (e) {
        return e.message;
      }
      return 'no error';
    }

    expect(await msg('asha@example.com', SignInAudience.citizen), 'Incorrect email or password.');
    expect(await msg('chief@city.example', SignInAudience.staff), 'Incorrect email or password.');
    expect(await msg('nobody@example.com', SignInAudience.staff), 'Incorrect email or password.');
  });

  test('register always creates a citizen', () async {
    expect(citizen.role, UserRole.citizen);
    await expectLater(auth.register(name: 'X Y', email: 'asha@example.com', password: 'Passw0rdX'),
        throwsA(isA<ValidationException>()));
  });

  test('administrator can reset a password; others cannot; it is audited', () async {
    await auth.resetPassword(actor: admin, targetId: citizen.id, newPassword: 'NewPassw0rd1');
    await expectLater(auth.signIn('asha@example.com', 'Passw0rdX'), throwsA(isA<ValidationException>()));
    expect((await auth.signIn('asha@example.com', 'NewPassw0rd1')).id, citizen.id);

    await expectLater(auth.resetPassword(actor: officer, targetId: citizen.id, newPassword: 'NewPassw0rd2'),
        throwsA(isA<PermissionDeniedException>()));
    await expectLater(auth.resetPassword(actor: citizen, targetId: admin.id, newPassword: 'NewPassw0rd2'),
        throwsA(isA<PermissionDeniedException>()));
    await expectLater(auth.resetPassword(actor: admin, targetId: admin.id, newPassword: 'NewPassw0rd2'),
        throwsA(isA<PermissionDeniedException>()));
    await expectLater(auth.resetPassword(actor: admin, targetId: citizen.id, newPassword: 'short'),
        throwsA(isA<ValidationException>()));

    final log = await db.query('audit_log', where: "action = 'password_reset_by_admin'");
    expect(log, hasLength(1));
    expect(log.single['detail'], isNot(contains('NewPassw0rd1')));
  });

  test('verifyPassword', () async {
    expect(await auth.verifyPassword(citizen.id, 'Passw0rdX'), isTrue);
    expect(await auth.verifyPassword(citizen.id, 'wrong'), isFalse);
    expect(await auth.verifyPassword('missing', 'Passw0rdX'), isFalse);
  });
}
