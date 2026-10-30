import 'package:civinex_ai/core/constants/enums.dart';
import 'package:civinex_ai/core/errors/app_exceptions.dart';
import 'package:civinex_ai/data/database/app_database.dart';
import '../support/demo_seeder.dart';
import 'package:civinex_ai/data/repositories/auth_repository.dart';
import 'package:civinex_ai/data/repositories/incident_repository.dart';
import 'package:civinex_ai/data/repositories/road_repository.dart';
import 'package:civinex_ai/domain/models/road.dart';
import 'package:civinex_ai/domain/models/user.dart';
import 'package:civinex_ai/services/ai/rule_based_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late AuthRepository auth;
  late IncidentRepository incidents;
  late RoadRepository roads;
  late AppUser citizen, drainage, roadsOfficer, admin;

  setUp(() async {
    db = await AppDatabase.open(path: inMemoryDatabasePath);
    await DemoSeeder.seed(db);
    auth = AuthRepository(db);
    incidents = IncidentRepository(db, ai: RuleBasedProvider());
    roads = RoadRepository(db, incidents: incidents);
    citizen = await auth.signIn(DemoAccounts.citizen, DemoAccounts.password);
    drainage = await auth.signIn(DemoAccounts.officer, DemoAccounts.password);
    roadsOfficer = await auth.signIn(DemoAccounts.roadsOfficer, DemoAccounts.password);
    admin = await auth.signIn(DemoAccounts.admin, DemoAccounts.password);
  });

  group('access', () {
    test('citizens cannot use RoadVision', () async {
      expect(() => roads.priorityList(citizen), throwsA(isA<PermissionDeniedException>()));
      expect(() => roads.getReport(citizen, 'CVX-DEMO-003'),
          throwsA(isA<PermissionDeniedException>()));
    });

    test('drainage officer sees no road reports and cannot open one', () async {
      expect(await roads.priorityList(drainage), isEmpty);
      expect(() => roads.getReport(drainage, 'CVX-DEMO-003'),
          throwsA(isA<NotFoundException>()));
    });

    test('non-road reports are rejected', () async {
      expect(() => roads.getReport(admin, 'CVX-DEMO-001'), throwsA(isA<ValidationException>()));
    });
  });

  group('priority list', () {
    test('contains open road reports, classified by rules, worst first', () async {
      final list = await roads.priorityList(roadsOfficer);
      final ids = list.map((r) => r.incident.id).toList();
      expect(ids, containsAll(['CVX-DEMO-003', 'CVX-DEMO-006', 'CVX-DEMO-007', 'CVX-DEMO-008']));
      for (var n = 1; n < list.length; n++) {
        expect(list[n - 1].incident.priorityScore,
            greaterThanOrEqualTo(list[n].incident.priorityScore));
      }
      final deep = list.firstWhere((r) => r.incident.id == 'CVX-DEMO-006');
      expect(deep.details.type, RoadDamageType.pothole);
      expect(deep.details.severity, RoadSeverity.severe);
      expect(deep.details.typeSource, RoadSource.rules);
      final crack = list.firstWhere((r) => r.incident.id == 'CVX-DEMO-007');
      expect(crack.details.severity, RoadSeverity.minor);
      final tree = list.firstWhere((r) => r.incident.id == 'CVX-DEMO-008');
      expect(tree.details.type, RoadDamageType.obstruction);
    });

    test('admin sees the same road reports', () async {
      final ids = (await roads.priorityList(admin)).map((r) => r.incident.id);
      expect(ids, contains('CVX-DEMO-006'));
    });
  });

  group('classification override', () {
    test('officer can change it with a reason; source and audit are recorded', () async {
      await roads.updateClassification(
          actor: roadsOfficer,
          incidentId: 'CVX-DEMO-007',
          type: RoadDamageType.pothole,
          severity: RoadSeverity.moderate,
          reason: 'Checked on site');
      final r = await roads.getReport(roadsOfficer, 'CVX-DEMO-007');
      expect(r.details.type, RoadDamageType.pothole);
      expect(r.details.typeSource, RoadSource.officer);
      expect(r.details.severitySource, RoadSource.officer);
      final audit = await db.query('audit_log', where: "action = 'road_classification_changed'");
      expect(audit, hasLength(1));
    });

    test('needs a reason and at least one change; other departments are blocked', () async {
      expect(
          () => roads.updateClassification(
              actor: roadsOfficer, incidentId: 'CVX-DEMO-007',
              severity: RoadSeverity.severe, reason: ''),
          throwsA(isA<ValidationException>()));
      expect(
          () => roads.updateClassification(
              actor: roadsOfficer, incidentId: 'CVX-DEMO-007', reason: 'No change given'),
          throwsA(isA<ValidationException>()));
      expect(
          () => roads.updateClassification(
              actor: drainage, incidentId: 'CVX-DEMO-007',
              severity: RoadSeverity.severe, reason: 'Trying anyway'),
          throwsA(isA<NotFoundException>()));
    });
  });

  group('assignment', () {
    test('assigning moves a new report to Assigned and notifies the assignee', () async {
      await roads.assignOfficer(
          actor: admin, incidentId: 'CVX-DEMO-006', officerId: roadsOfficer.id);
      final r = await roads.getReport(roadsOfficer, 'CVX-DEMO-006');
      expect(r.incident.status, IncidentStatus.assigned);
      expect(r.assigneeName, roadsOfficer.name);
      final n = await incidents.notifications(roadsOfficer);
      expect(n.any((x) => x.title == 'Repair assigned to you'), isTrue);
    });

    test('cannot assign an officer from another department or a non-officer', () async {
      expect(
          () => roads.assignOfficer(
              actor: admin, incidentId: 'CVX-DEMO-006', officerId: drainage.id),
          throwsA(isA<ValidationException>()));
      expect(
          () => roads.assignOfficer(
              actor: admin, incidentId: 'CVX-DEMO-006', officerId: citizen.id),
          throwsA(isA<ValidationException>()));
    });

    test('officer list for the picker is staff only', () async {
      expect((await auth.officersInDepartment(admin, Departments.roads)).map((u) => u.id),
          contains(roadsOfficer.id));
      expect(() => auth.officersInDepartment(citizen, Departments.roads),
          throwsA(isA<PermissionDeniedException>()));
    });
  });

  group('duplicates', () {
    test('nearby pothole report is suggested as a duplicate of DEMO-003', () async {
      final m = await roads.duplicateSuggestions(roadsOfficer, 'CVX-DEMO-006');
      expect(m.map((x) => x.incident.id), contains('CVX-DEMO-003'));
      expect(m.map((x) => x.incident.id), isNot(contains('CVX-DEMO-006')));
    });

    test('closing as duplicate rejects with reason, links and notifies', () async {
      await roads.markDuplicate(
          actor: roadsOfficer, incidentId: 'CVX-DEMO-006', ofId: 'CVX-DEMO-003');
      final closed = await incidents.getVisible(roadsOfficer, 'CVX-DEMO-006');
      expect(closed.status, IncidentStatus.rejected);
      expect(closed.duplicateOfId, 'CVX-DEMO-003');
      expect(closed.rejectionReason, contains('CVX-DEMO-003'));

      final list = await roads.priorityList(roadsOfficer);
      expect(list.map((r) => r.incident.id), isNot(contains('CVX-DEMO-006')));
      final primary = list.firstWhere((r) => r.incident.id == 'CVX-DEMO-003');
      expect(primary.linkedDuplicates, 1);
    });

    test('invalid duplicate links are refused', () async {
      expect(
          () => roads.markDuplicate(
              actor: roadsOfficer, incidentId: 'CVX-DEMO-006', ofId: 'CVX-DEMO-006'),
          throwsA(isA<ValidationException>()));
      expect(
          () => roads.markDuplicate(
              actor: admin, incidentId: 'CVX-DEMO-006', ofId: 'CVX-DEMO-001'),
          throwsA(isA<ValidationException>())); // target is not a road report
      expect(
          () => roads.markDuplicate(
              actor: roadsOfficer, incidentId: 'CVX-DEMO-006', ofId: 'CVX-DEMO-001'),
          throwsA(isA<NotFoundException>())); // outside the officer's department
      expect(
          () => roads.markDuplicate(
              actor: citizen, incidentId: 'CVX-DEMO-006', ofId: 'CVX-DEMO-003'),
          throwsA(isA<PermissionDeniedException>()));
    });
  });

  group('photos', () {
    test('before and after photos are validated, stored and counted', () async {
      await roads.addRepairPhoto(
          actor: roadsOfficer, incidentId: 'CVX-DEMO-003', kind: PhotoKind.before,
          path: '/private/a.jpg', sizeBytes: 1000);
      await roads.addRepairPhoto(
          actor: roadsOfficer, incidentId: 'CVX-DEMO-003', kind: PhotoKind.after,
          path: '/private/b.png', sizeBytes: 2000);
      final photos = await roads.photos(roadsOfficer, 'CVX-DEMO-003');
      expect(photos.map((p) => p.kind), [PhotoKind.before, PhotoKind.after]);
      final r = await roads.getReport(roadsOfficer, 'CVX-DEMO-003');
      expect(r.beforePhotos, 1);
      expect(r.afterPhotos, 1);
    });

    test('bad type, size or permissions are refused', () async {
      Future<void> add(AppUser who, String path, int size) => roads.addRepairPhoto(
          actor: who, incidentId: 'CVX-DEMO-003', kind: PhotoKind.after,
          path: path, sizeBytes: size);
      expect(() => add(roadsOfficer, '/x/file.exe', 100), throwsA(isA<ValidationException>()));
      expect(() => add(roadsOfficer, '/x/big.jpg', 6 * 1024 * 1024),
          throwsA(isA<ValidationException>()));
      expect(() => add(citizen, '/x/a.jpg', 100), throwsA(isA<PermissionDeniedException>()));
      expect(() => add(drainage, '/x/a.jpg', 100), throwsA(isA<NotFoundException>()));
    });
  });

  group('demo reset', () {
    test('keeps real data and demo accounts, removes demo reports, then restores them', () async {
      final real = await auth.register(
          name: 'Real User', email: 'real2@example.com', password: 'Passw0rdX');
      final r = await incidents.submit(
          reporter: real,
          description: 'Big pothole in the middle of the road near the temple',
          locationText: 'Temple road');
      // A demo officer acts on a real record. The reset must still work.
      await roads.assignOfficer(
          actor: admin, incidentId: r.incident.id, officerId: roadsOfficer.id);
      await roads.addRepairPhoto(
          actor: roadsOfficer, incidentId: r.incident.id, kind: PhotoKind.before,
          path: '/p/a.jpg', sizeBytes: 10);

      await DemoSeeder.clearDemo(db);
      expect(await incidents.listVisible(admin), hasLength(1)); // only the real one
      expect(await auth.getById('demo-citizen'), isNotNull);

      await DemoSeeder.seed(db);
      expect((await incidents.listVisible(admin)).length, greaterThan(1));
      expect((await roads.photos(admin, r.incident.id)), hasLength(1)); // real photo kept
    });

    test('reset restores a demo account whose role was changed', () async {
      await auth.setRole(actor: admin, targetId: 'demo-citizen', role: UserRole.admin);
      await DemoSeeder.clearDemo(db);
      await DemoSeeder.seed(db);
      expect((await auth.getById('demo-citizen'))!.role, UserRole.citizen);
    });
  });
}
