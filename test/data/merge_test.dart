import 'package:civinex_ai/core/constants/enums.dart';
import 'package:civinex_ai/core/errors/app_exceptions.dart';
import 'package:civinex_ai/data/database/app_database.dart';
import 'package:civinex_ai/data/repositories/incident_repository.dart';
import 'package:civinex_ai/data/repositories/workflow_repository.dart';
import 'package:civinex_ai/domain/models/user.dart';
import 'package:civinex_ai/services/ai/naive_bayes_provider.dart';
import 'package:civinex_ai/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../services/sync_service_test.dart' show FakeStore, settle;
import '../support/demo_seeder.dart';

Future<void> addUser(Database db, AppUser u) => db.insert('users', {
      'id': u.id,
      'name': u.name,
      'email': u.email,
      'password_hash': 'x',
      'salt': '',
      'role': u.role.name,
      'department_id': u.departmentId,
      'is_demo': 0,
      'is_active': 1,
      'services_allowed': 0,
      'created_at': 0,
    });

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const admin = AppUser(id: 'uA', name: 'Chief', email: 'c@x.example', role: UserRole.admin);
  const roadsOfficer = AppUser(
      id: 'uO', name: 'Ravi', email: 'o@x.example', role: UserRole.officer, departmentId: Departments.roads);
  const asha = AppUser(id: 'uC', name: 'Asha', email: 'a@x.example', role: UserRole.citizen);
  const ben = AppUser(id: 'uB', name: 'Ben', email: 'b@x.example', role: UserRole.citizen);

  group('manual merge', () {
    late Database db;
    late IncidentRepository inc;
    late WorkflowRepository wf;

    setUp(() async {
      db = await AppDatabase.open(path: inMemoryDatabasePath);
      await DemoSeeder.ensureDepartments(db);
      for (final u in [admin, roadsOfficer, asha, ben]) {
        await addUser(db, u);
      }
      inc = IncidentRepository(db, ai: NaiveBayesProvider());
      wf = WorkflowRepository(db, incidents: inc);
    });
    tearDown(() => db.close());

    Future<String> report(AppUser who, String text, double lat) async => (await inc.submit(
            reporter: who, description: text, locationText: 'Somewhere, Kochi', latitude: lat, longitude: 76.28))
        .incident
        .id;

    test('admin merges one report into another, then unlinks it', () async {
      final a = await report(asha, 'Big pothole in the middle of the road near the junction', 9.95);
      final b = await report(ben, 'Water pipe is leaking and the street is flooded with clean water', 9.99);
      await wf.mergeReports(actor: admin, childId: b, parentId: a, note: 'same area');
      final child = (await db.query('incidents', where: 'id = ?', whereArgs: [b])).single;
      expect(child['duplicate_of_id'], a);
      expect(child['dup_verified'], 1);
      expect(child['department_id'], (await db.query('incidents', where: 'id = ?', whereArgs: [a])).single['department_id']);
      expect(await inc.reporterCount(a), 2);

      await wf.unlinkDuplicate(actor: admin, childId: b);
      expect((await db.query('incidents', where: 'id = ?', whereArgs: [b])).single['duplicate_of_id'], isNull);
      expect(await inc.reporterCount(a), 1);
    });

    test('rules: no self-merge, no merging into a linked report, officers stay in their department', () async {
      final a = await report(asha, 'Big pothole in the middle of the road near the junction', 9.95);
      final b = await report(ben, 'Water pipe is leaking and the street is flooded with clean water', 9.99);
      await expectLater(wf.mergeReports(actor: admin, childId: a, parentId: a),
          throwsA(isA<ValidationException>()));
      await wf.mergeReports(actor: admin, childId: b, parentId: a);
      final c = await report(asha, 'Streetlight on the lane has not worked for days now', 9.97);
      await expectLater(wf.mergeReports(actor: admin, childId: c, parentId: b),
          throwsA(isA<ValidationException>()));
      await expectLater(wf.mergeReports(actor: asha, childId: c, parentId: a),
          throwsA(isA<PermissionDeniedException>()));
    });

    test('staff phone links matching reports that were filed on different phones', () async {
      final a = await report(asha, 'Big pothole in the middle of the road near the bus stand', 9.95);
      final b = await report(ben, 'Big pothole in the middle of the road near the bus stand', 9.9501);
      // Pretend they arrived from two phones, so nothing linked them yet.
      await db.update('incidents', {'duplicate_of_id': null, 'dup_verified': 1, 'dup_score': null},
          where: 'id = ?', whereArgs: [b]);
      expect(await inc.linkDuplicates(admin), 1);
      final child = (await db.query('incidents', where: 'id = ?', whereArgs: [b])).single;
      expect(child['duplicate_of_id'], a);
      expect(child['dup_verified'], 0, reason: 'awaiting staff confirmation');
      expect(await inc.linkDuplicates(admin), 0, reason: 'nothing left to link');
    });
  });

  test('two phones that changed the same report offline are merged, not overwritten', () async {
    final store = FakeStore();
    final adb = await AppDatabase.open(path: inMemoryDatabasePath);
    final odb = await AppDatabase.open(path: inMemoryDatabasePath);
    final cdb = await AppDatabase.open(path: inMemoryDatabasePath);
    addTearDown(() async {
      for (final d in [adb, odb, cdb]) {
        await d.close();
      }
    });
    for (final d in [adb, odb, cdb]) {
      await DemoSeeder.ensureDepartments(d);
    }
    await addUser(cdb, asha);
    await addUser(odb, roadsOfficer);
    await addUser(adb, admin);
    await addUser(adb, roadsOfficer);
    final aSync = SyncService(adb, store, admin)..start();
    final oSync = SyncService(odb, store, roadsOfficer)..start();
    final cSync = SyncService(cdb, store, asha)..start();
    addTearDown(() {
      aSync.stop();
      oSync.stop();
      cSync.stop();
    });

    final id = (await IncidentRepository(cdb, ai: NaiveBayesProvider()).submit(
            reporter: asha,
            description: 'Big pothole in the middle of the road near the bus stand',
            locationText: 'Main road, Kochi',
            latitude: 9.95,
            longitude: 76.28))
        .incident
        .id;
    await cSync.push();
    await settle();
    expect(await odb.query('incidents', where: 'id = ?', whereArgs: [id]), hasLength(1));
    expect(await adb.query('incidents', where: 'id = ?', whereArgs: [id]), hasLength(1));

    Future<void> addLine(Database d, String who, String note, int at) => d.insert('status_history', {
          'incident_id': id,
          'status': 'submitted',
          'actor_id': who,
          'note': note,
          'created_at': at,
        });
    // Each side writes a different line while "offline".
    await addLine(adb, 'uA', 'line from the administrator', 4000000000000);
    await addLine(odb, 'uO', 'line from the officer', 4000000000001);

    await aSync.push();
    await settle();
    await oSync.push();
    await settle();
    await aSync.push();
    await settle();

    for (final d in [adb, odb]) {
      final notes = (await d.query('status_history', where: 'incident_id = ?', whereArgs: [id]))
          .map((r) => r['note'])
          .toList();
      expect(notes, containsAll(['line from the administrator', 'line from the officer']));
    }
  });
}
