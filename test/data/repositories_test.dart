import 'package:civinex_ai/core/constants/enums.dart';
import 'package:civinex_ai/core/errors/app_exceptions.dart';
import 'package:civinex_ai/data/database/app_database.dart';
import '../support/demo_seeder.dart';
import 'package:civinex_ai/data/repositories/auth_repository.dart';
import 'package:civinex_ai/data/repositories/incident_repository.dart';
import 'package:civinex_ai/domain/models/user.dart';
import 'package:civinex_ai/services/ai/rule_based_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late AuthRepository auth;
  late IncidentRepository repo;
  late AppUser citizen, officer, admin;

  setUp(() async {
    db = await AppDatabase.open(path: inMemoryDatabasePath);
    await DemoSeeder.seed(db);
    auth = AuthRepository(db);
    repo = IncidentRepository(db, ai: RuleBasedProvider());
    citizen = await auth.signIn(DemoAccounts.citizen, DemoAccounts.password);
    officer = await auth.signIn(DemoAccounts.officer, DemoAccounts.password);
    admin = await auth.signIn(DemoAccounts.admin, DemoAccounts.password);
  });

  Future<String> submitFlood() async {
    final r = await repo.submit(
      reporter: citizen,
      description: 'Severe waterlogging, knee-deep water at the junction',
      locationText: 'Test junction',
      peopleAffected: 50,
      safetyRisk: true,
    );
    return r.incident.id;
  }

  group('auth', () {
    test('wrong password is rejected with a generic message', () async {
      expect(() => auth.signIn(DemoAccounts.citizen, 'nope'),
          throwsA(isA<ValidationException>()));
    });
    test('registration always creates a citizen', () async {
      final u = await auth.register(
          name: 'Asha', email: 'asha@example.com', password: 'Passw0rdX');
      expect(u.role, UserRole.citizen);
    });
    test('weak password and duplicate email rejected', () async {
      expect(() => auth.register(name: 'A B', email: 'x@y.com', password: 'short'),
          throwsA(isA<ValidationException>()));
      expect(
          () => auth.register(
              name: 'Dup', email: DemoAccounts.citizen, password: 'Passw0rdX'),
          throwsA(isA<ValidationException>()));
    });
    test('only admin can change roles, never their own', () async {
      expect(
          () => auth.setRole(actor: citizen, targetId: citizen.id, role: UserRole.admin),
          throwsA(isA<PermissionDeniedException>()));
      expect(
          () => auth.setRole(actor: admin, targetId: admin.id, role: UserRole.citizen),
          throwsA(isA<PermissionDeniedException>()));
      await auth.setRole(
          actor: admin, targetId: citizen.id, role: UserRole.officer,
          departmentId: Departments.roads);
      expect((await auth.getById(citizen.id))!.role, UserRole.officer);
    });
  });

  group('production accounts', () {
    late AuthRepository clean;
    setUp(() async {
      final fresh = await AppDatabase.open(path: inMemoryDatabasePath);
      await DemoSeeder.ensureDepartments(fresh); // no demo users at all
      clean = AuthRepository(fresh);
    });

    test('first admin can be created once, then setup is closed', () async {
      expect(await clean.hasAdmin(), isFalse);
      final a = await clean.createFirstAdmin(
          name: 'Chief Admin', email: 'chief@city.example', password: 'Passw0rdX');
      expect(a.role, UserRole.admin);
      expect(a.isDemo, isFalse);
      expect(await clean.hasAdmin(), isTrue);
      expect(
          () => clean.createFirstAdmin(
              name: 'Intruder', email: 'intruder@x.example', password: 'Passw0rdX'),
          throwsA(isA<PermissionDeniedException>()));
    });

    test('first admin validates input', () async {
      expect(() => clean.createFirstAdmin(name: 'A', email: 'bad', password: 'x'),
          throwsA(isA<ValidationException>()));
    });

    test('admin creates staff; others cannot; officers need a department', () async {
      final a = await clean.createFirstAdmin(
          name: 'Chief Admin', email: 'chief@city.example', password: 'Passw0rdX');
      final o = await clean.createStaff(
          actor: a, name: 'Road Officer', email: 'road@city.example',
          password: 'Passw0rdX', role: UserRole.officer, departmentId: Departments.roads);
      expect(o.role, UserRole.officer);
      expect(o.departmentId, Departments.roads);
      expect(
          () => clean.createStaff(
              actor: a, name: 'No Dept', email: 'nd@city.example',
              password: 'Passw0rdX', role: UserRole.officer),
          throwsA(isA<ValidationException>()));
      expect(
          () => clean.createStaff(
              actor: o, name: 'Sneaky', email: 'sneaky@city.example',
              password: 'Passw0rdX', role: UserRole.admin),
          throwsA(isA<PermissionDeniedException>()));
      expect(
          () => clean.createStaff(
              actor: a, name: 'Dupe', email: 'ROAD@city.example',
              password: 'Passw0rdX', role: UserRole.admin),
          throwsA(isA<ValidationException>()));
    });

    test('change password checks the current one and the new one', () async {
      final a = await clean.createFirstAdmin(
          name: 'Chief Admin', email: 'chief@city.example', password: 'Passw0rdX');
      expect(() => clean.changePassword(userId: a.id, current: 'wrong', next: 'NewPassw0rd1'),
          throwsA(isA<ValidationException>()));
      expect(() => clean.changePassword(userId: a.id, current: 'Passw0rdX', next: 'short'),
          throwsA(isA<ValidationException>()));
      expect(() => clean.changePassword(userId: a.id, current: 'Passw0rdX', next: 'Passw0rdX'),
          throwsA(isA<ValidationException>()));
      await clean.changePassword(userId: a.id, current: 'Passw0rdX', next: 'NewPassw0rd1');
      expect(() => clean.signIn('chief@city.example', 'Passw0rdX'),
          throwsA(isA<ValidationException>()));
      expect((await clean.signIn('chief@city.example', 'NewPassw0rd1')).id, a.id);
    });

    test('disabled accounts cannot sign in; admins cannot disable themselves', () async {
      final a = await clean.createFirstAdmin(
          name: 'Chief Admin', email: 'chief@city.example', password: 'Passw0rdX');
      final u = await clean.register(
          name: 'Some Citizen', email: 'c@city.example', password: 'Passw0rdX');
      await clean.setActive(actor: a, targetId: u.id, active: false);
      expect(() => clean.signIn('c@city.example', 'Passw0rdX'),
          throwsA(isA<PermissionDeniedException>()));
      await clean.setActive(actor: a, targetId: u.id, active: true);
      expect((await clean.signIn('c@city.example', 'Passw0rdX')).id, u.id);
      expect(() => clean.setActive(actor: a, targetId: a.id, active: false),
          throwsA(isA<PermissionDeniedException>()));
      expect(() => clean.setActive(actor: u, targetId: a.id, active: false),
          throwsA(isA<PermissionDeniedException>()));
    });
  });

  group('incidents', () {
    test('invalid input is rejected', () async {
      expect(
          () => repo.submit(reporter: citizen, description: 'short', locationText: ''),
          throwsA(isA<ValidationException>()));
    });

    test('submit stores AI info, priority, history and notifications', () async {
      final id = await submitFlood();
      final i = await repo.getVisible(citizen, id);
      expect(i.category, IncidentCategory.flooding);
      expect(i.aiProvider, 'rule-based-local');
      expect(i.priority.index, greaterThanOrEqualTo(Priority.high.index));
      expect(i.departmentId, Departments.drainage);
      // submitted, AI analysis note, duplicate-check note
      expect((await repo.history(citizen, id)).length, 3);
      expect((await repo.notifications(citizen)), isNotEmpty);
      // Drainage officer was alerted about the high-priority report.
      expect((await repo.notifications(officer)).any((n) => n.incidentId == id), isTrue);
    });

    test('citizens only see their own reports; ids cannot be probed', () async {
      final id = await submitFlood();
      final other = await auth.register(
          name: 'Other Person', email: 'other@example.com', password: 'Passw0rdX');
      expect(await repo.listVisible(other), isEmpty);
      expect(() => repo.getVisible(other, id), throwsA(isA<NotFoundException>()));
    });

    test('officer sees only their department', () async {
      final id = await submitFlood();
      final list = await repo.listVisible(officer);
      expect(list.every((i) => i.departmentId == Departments.drainage), isTrue);
      expect(list.any((i) => i.id == id), isTrue);
      // Road damage demo report belongs to roads, not drainage.
      expect(list.any((i) => i.id == 'CVX-DEMO-003'), isFalse);
      expect(() => repo.getVisible(officer, 'CVX-DEMO-003'),
          throwsA(isA<NotFoundException>()));
    });

    test('citizen cannot change status; officer can, with rules', () async {
      final id = await submitFlood();
      expect(
          () => repo.changeStatus(
              actor: citizen, incidentId: id, to: IncidentStatus.resolved, note: 'done done'),
          throwsA(isA<PermissionDeniedException>()));
      await repo.changeStatus(actor: officer, incidentId: id, to: IncidentStatus.assigned);
      expect(
          () => repo.changeStatus(actor: officer, incidentId: id, to: IncidentStatus.resolved),
          throwsA(isA<ValidationException>())); // needs a note
      await repo.changeStatus(
          actor: officer, incidentId: id, to: IncidentStatus.resolved, note: 'Drain cleared');
      final i = await repo.getVisible(citizen, id);
      expect(i.status, IncidentStatus.resolved);
      // Terminal states are final.
      expect(
          () => repo.changeStatus(actor: officer, incidentId: id, to: IncidentStatus.inProgress),
          throwsA(isA<ValidationException>()));
      expect((await repo.auditLog(admin)).any((a) => a.action == 'status_change'), isTrue);
    });

    test('rejection needs a reason; critical rejection needs admin', () async {
      final id = await submitFlood();
      final i = await repo.getVisible(citizen, id);
      if (i.priority == Priority.critical) {
        expect(
            () => repo.changeStatus(
                actor: officer, incidentId: id, to: IncidentStatus.rejected,
                rejectionReason: 'Not our job'),
            throwsA(isA<PermissionDeniedException>()));
      }
      expect(
          () => repo.changeStatus(
              actor: admin, incidentId: id, to: IncidentStatus.rejected, rejectionReason: ''),
          throwsA(isA<ValidationException>()));
    });

    test('citizen can withdraw only before staff act', () async {
      final id = await submitFlood();
      await repo.withdraw(citizen, id);
      expect((await repo.getVisible(citizen, id)).status, IncidentStatus.withdrawn);

      final id2 = await submitFlood();
      await repo.changeStatus(actor: officer, incidentId: id2, to: IncidentStatus.assigned);
      expect(() => repo.withdraw(citizen, id2), throwsA(isA<PermissionDeniedException>()));
    });

    test('override requires a reason and is audited', () async {
      final id = await submitFlood();
      expect(
          () => repo.overrideSuggestion(
              actor: officer, incidentId: id, priority: Priority.low, reason: ''),
          throwsA(isA<ValidationException>()));
      await repo.overrideSuggestion(
          actor: officer, incidentId: id, priority: Priority.medium,
          reason: 'Water already receding');
      expect((await repo.getVisible(officer, id)).priority, Priority.medium);
      expect((await repo.auditLog(admin)).any((a) => a.action == 'ai_override'), isTrue);
    });

    test('audit log is admin only', () async {
      expect(() => repo.auditLog(officer), throwsA(isA<PermissionDeniedException>()));
      expect(() => repo.auditLog(citizen), throwsA(isA<PermissionDeniedException>()));
    });

    test('priority queue is staff only and sorted by score', () async {
      expect(() => repo.priorityQueue(citizen), throwsA(isA<PermissionDeniedException>()));
      final q = await repo.priorityQueue(admin);
      for (var n = 1; n < q.length; n++) {
        expect(q[n - 1].priorityScore, greaterThanOrEqualTo(q[n].priorityScore));
      }
    });

    test('duplicate suggestions are returned for a nearby repeat report', () async {
      await repo.submit(
          reporter: citizen,
          description: 'Big pothole in the middle of the road',
          locationText: 'Test road',
          latitude: 9.95, longitude: 76.28);
      final r = await repo.submit(
          reporter: citizen,
          description: 'Pothole in the middle of road',
          locationText: 'Test road',
          latitude: 9.9501, longitude: 76.2801);
      expect(r.duplicates, isNotEmpty);
    });
  });

  group('demo reset', () {
    test('clearDemo removes demo reports but keeps real data and demo accounts', () async {
      final real = await auth.register(
          name: 'Real User', email: 'real@example.com', password: 'Passw0rdX');
      final realReport = await repo.submit(
          reporter: real,
          description: 'Garbage dumped beside the wall for days',
          locationText: 'Real lane');
      await DemoSeeder.clearDemo(db);
      expect(await auth.getById(real.id), isNotNull);
      expect(await repo.getVisible(real, realReport.incident.id), isNotNull);
      expect(await auth.getById('demo-citizen'), isNotNull);
      expect(await repo.listVisible(admin), hasLength(1));
      await DemoSeeder.seed(db);
      expect((await repo.listVisible(admin)).length, greaterThan(1));
    });
  });
}
