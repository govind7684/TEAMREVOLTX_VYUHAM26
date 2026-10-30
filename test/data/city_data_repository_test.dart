import 'package:civinex_ai/core/errors/app_exceptions.dart';
import 'package:civinex_ai/data/database/app_database.dart';
import '../support/demo_seeder.dart';
import 'package:civinex_ai/data/repositories/auth_repository.dart';
import 'package:civinex_ai/data/repositories/city_data_repository.dart';
import 'package:civinex_ai/domain/models/city_update.dart';
import 'package:civinex_ai/domain/models/user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late AuthRepository auth;
  late CityDataRepository repo;
  late AppUser citizen, drainage, roads, admin;
  var clock = DateTime(2026, 6, 1, 9);

  setUp(() async {
    clock = DateTime(2026, 6, 1, 9);
    db = await AppDatabase.open(path: inMemoryDatabasePath);
    await DemoSeeder.seed(db, now: clock);
    auth = AuthRepository(db);
    repo = CityDataRepository(db, clock: () => clock);
    citizen = await auth.signIn(DemoAccounts.citizen, DemoAccounts.password);
    drainage = await auth.signIn(DemoAccounts.officer, DemoAccounts.password);
    roads = await auth.signIn(DemoAccounts.roadsOfficer, DemoAccounts.password);
    admin = await auth.signIn(DemoAccounts.admin, DemoAccounts.password);
  });

  tearDown(() => db.close());

  test('staff can post a reading; everyone can read it, with who and when', () async {
    final u = await repo.add(
        actor: drainage,
        module: CityModule.flood,
        kind: UpdateKind.reading,
        title: 'Canal level',
        area: 'Kochi',
        value: 142.5,
        unit: 'cm');
    expect(u.valueText, '142.5 cm');
    expect(u.source, UpdateSource.manual);
    final seen = await repo.list(module: CityModule.flood);
    expect(seen.map((x) => x.id), contains(u.id));
  });

  test('citizens cannot post', () async {
    expect(
        () => repo.add(
            actor: citizen, module: CityModule.notice, kind: UpdateKind.info, title: 'Hello there'),
        throwsA(isA<PermissionDeniedException>()));
    expect(CityDataRepository.allowedModules(citizen), isEmpty);
  });

  test('an officer can only post for their own department; admin for all', () async {
    expect(
        () => repo.add(
            actor: roads, module: CityModule.flood, kind: UpdateKind.info, title: 'Not mine'),
        throwsA(isA<PermissionDeniedException>()));
    await repo.add(actor: roads, module: CityModule.roads, kind: UpdateKind.info, title: 'Resurfacing');
    await repo.add(actor: admin, module: CityModule.flood, kind: UpdateKind.info, title: 'Admin note');
    expect(CityDataRepository.allowedModules(admin), CityModule.values);
  });

  test('validation: title length, value needs a unit and vice versa', () async {
    Future<void> bad({String title = 'Fine title', double? value, String? unit}) => repo.add(
        actor: admin,
        module: CityModule.flood,
        kind: UpdateKind.reading,
        title: title,
        value: value,
        unit: unit);
    expect(() => bad(title: 'ab'), throwsA(isA<ValidationException>()));
    expect(() => bad(value: 5), throwsA(isA<ValidationException>()));
    expect(() => bad(unit: 'mm'), throwsA(isA<ValidationException>()));
    expect(() => bad(value: double.nan, unit: 'mm'), throwsA(isA<ValidationException>()));
  });

  test('updates expire; "until removed" never does', () async {
    await repo.add(
        actor: admin,
        module: CityModule.notice,
        kind: UpdateKind.info,
        title: 'Short lived',
        validForHours: 6);
    await repo.add(
        actor: admin, module: CityModule.notice, kind: UpdateKind.info, title: 'Stays up');
    expect((await repo.list(module: CityModule.notice)).length, 2);
    clock = clock.add(const Duration(hours: 7));
    final later = (await repo.list(module: CityModule.notice)).map((u) => u.title);
    expect(later, ['Stays up']);
  });

  test('an alert notifies everyone else; other kinds do not', () async {
    Future<int> unread(String id) async => (await db.rawQuery(
            "SELECT COUNT(*) c FROM notifications WHERE user_id = ? AND title LIKE 'City alert:%'",
            [id]))
        .first['c'] as int;
    await repo.add(
        actor: drainage, module: CityModule.flood, kind: UpdateKind.advisory, title: 'Advisory only');
    expect(await unread(citizen.id), 0);
    await repo.add(
        actor: drainage, module: CityModule.flood, kind: UpdateKind.alert, title: 'Water rising');
    expect(await unread(citizen.id), 1);
    expect(await unread(drainage.id), 0, reason: 'the author is not notified');
  });

  test('only the author or an admin can remove; removal is audited', () async {
    final u = await repo.add(
        actor: drainage, module: CityModule.flood, kind: UpdateKind.info, title: 'To remove');
    expect(() => repo.remove(citizen, u.id), throwsA(isA<PermissionDeniedException>()));
    expect(() => repo.remove(roads, u.id), throwsA(isA<PermissionDeniedException>()));
    await repo.remove(admin, u.id);
    expect((await repo.list()).where((x) => x.id == u.id), isEmpty);
    final log = await db.query('audit_log', where: "action = 'city_update_removed'");
    expect(log, hasLength(1));
    expect(() => repo.remove(admin, u.id), throwsA(isA<NotFoundException>()));
  });

  test('demo mode seeds clearly labelled sample updates', () async {
    final all = await repo.list();
    expect(all.where((u) => u.isDemo), isNotEmpty);
    expect(all.where((u) => u.isDemo).every((u) => u.title.startsWith('Sample')), isTrue);
  });
}
