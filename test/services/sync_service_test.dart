import 'dart:async';

import 'package:civinex_ai/core/constants/enums.dart';
import 'package:civinex_ai/data/database/app_database.dart';
import 'package:civinex_ai/data/repositories/incident_repository.dart';
import 'package:civinex_ai/data/repositories/workflow_repository.dart';
import 'package:civinex_ai/domain/models/user.dart';
import 'package:civinex_ai/services/ai/naive_bayes_provider.dart';
import 'package:civinex_ai/services/cloud_store.dart';
import 'package:civinex_ai/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/demo_seeder.dart';

/// In-memory stand-in for Firestore shared by two "phones".
class FakeStore implements CloudStore {
  final docs = <String, Map<String, Map<String, Object?>>>{};
  final _watchers = <({String col, String? field, Object? eq, StreamController<List<RemoteDoc>> c})>[];

  bool _match(Map<String, Object?> d, String? f, Object? eq) => f == null || d[f] == eq;

  @override
  Future<void> put(String collection, String id, Map<String, Object?> data) async {
    // Same round trip as the real thing: only plain values survive.
    final copy = Map<String, Object?>.from(_clone(data) as Map);
    (docs[collection] ??= {})[id] = copy;
    for (final w in _watchers.where((w) => w.col == collection)) {
      if (_match(copy, w.field, w.eq)) w.c.add([RemoteDoc(id, Map.of(copy))]);
    }
  }

  Object? _clone(Object? v) => v is Map
      ? {for (final e in v.entries) '${e.key}': _clone(e.value)}
      : v is List
          ? v.map(_clone).toList()
          : v;

  @override
  Stream<List<RemoteDoc>> watch(String collection, {String? field, Object? equals}) {
    late StreamController<List<RemoteDoc>> c;
    c = StreamController<List<RemoteDoc>>(onListen: () {
      final now = [
        for (final e in (docs[collection] ?? {}).entries)
          if (_match(e.value, field, equals)) RemoteDoc(e.key, Map.of(e.value))
      ];
      if (now.isNotEmpty) c.add(now);
    });
    _watchers.add((col: collection, field: field, eq: equals, c: c));
    return c.stream;
  }
}

/// Database calls run in another isolate, so give the listeners real time.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 700));

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database cdb, odb, adb;
  late FakeStore store;
  late AppUser citizen, officer, admin;

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

  setUp(() async {
    store = FakeStore();
    citizen = const AppUser(id: 'uC', name: 'Asha', email: 'a@x.example', role: UserRole.citizen);
    officer = const AppUser(
        id: 'uO', name: 'Ravi', email: 'o@x.example', role: UserRole.officer, departmentId: Departments.roads);
    admin = const AppUser(id: 'uA', name: 'Chief', email: 'c@x.example', role: UserRole.admin);
    cdb = await AppDatabase.open(path: inMemoryDatabasePath);
    odb = await AppDatabase.open(path: inMemoryDatabasePath);
    adb = await AppDatabase.open(path: inMemoryDatabasePath);
    for (final d in [cdb, odb, adb]) {
      await DemoSeeder.ensureDepartments(d);
    }
    await addUser(cdb, citizen);
    await addUser(odb, officer);
    await addUser(adb, admin);
    await addUser(adb, officer); // the administrator phone knows the officers
  });
  tearDown(() async {
    for (final d in [cdb, odb, adb]) {
      await d.close();
    }
  });

  test('a report goes citizen -> admin, is auto-routed, and reaches officer and citizen', () async {
    final cSync = SyncService(cdb, store, citizen)..start();
    final aSync = SyncService(adb, store, admin)..start();
    final oSync = SyncService(odb, store, officer)..start();
    addTearDown(() {
      cSync.stop();
      aSync.stop();
      oSync.stop();
    });

    // Citizen files a report on their own phone.
    final crepo = IncidentRepository(cdb, ai: NaiveBayesProvider());
    final r = await crepo.submit(
        reporter: citizen,
        description: 'Big pothole in the middle of the road near the bus stand',
        locationText: 'Main road, Kochi',
        latitude: 9.95,
        longitude: 76.28);
    final id = r.incident.id;
    await cSync.push();
    await settle();

    // Administrator phone received it with the reporter's name.
    final onAdmin = await adb.query('incidents', where: 'id = ?', whereArgs: [id]);
    expect(onAdmin, hasLength(1));
    expect(onAdmin.first['reporter_id'], 'uC');
    expect(await adb.query('status_history', where: 'incident_id = ?', whereArgs: [id]), isNotEmpty);

    // Automatic routing on the administrator phone picks the roads officer.
    final wf = WorkflowRepository(adb, incidents: IncidentRepository(adb, ai: NaiveBayesProvider()));
    expect(await wf.autoRoute(admin), 1);
    await aSync.push();
    await settle();

    final onOfficer = await odb.query('incidents', where: 'id = ?', whereArgs: [id]);
    expect(onOfficer, hasLength(1));
    expect(onOfficer.first['assigned_officer_id'], 'uO');
    expect(await odb.query('assignments', where: 'incident_id = ?', whereArgs: [id]), hasLength(1));

    // The citizen phone sees the new status and the assignment note in the history.
    final onCitizen = await cdb.query('incidents', where: 'id = ?', whereArgs: [id]);
    expect(onCitizen.first['assigned_officer_id'], 'uO');
    expect(onCitizen.first['status'], 'assigned');

    // Nothing is left to route.
    expect(await wf.autoRoute(admin), 0);
  });

  test('the citizen phone does not receive other citizens\' reports', () async {
    final cSync = SyncService(cdb, store, citizen)..start();
    final aSync = SyncService(adb, store, admin)..start();
    addTearDown(() {
      cSync.stop();
      aSync.stop();
    });
    const other = AppUser(id: 'uX', name: 'Other', email: 'x@x.example', role: UserRole.citizen);
    await addUser(adb, other);
    final r = await IncidentRepository(adb, ai: NaiveBayesProvider()).submit(
        reporter: other,
        description: 'Streetlight is not working on the lane',
        locationText: 'Lane 4, Kochi',
        latitude: 9.96,
        longitude: 76.29);
    await aSync.push();
    await settle();
    expect(await cdb.query('incidents', where: 'id = ?', whereArgs: [r.incident.id]), isEmpty);
  });
}
