import 'package:civinex_ai/core/constants/enums.dart';
import 'package:civinex_ai/core/errors/app_exceptions.dart';
import 'package:civinex_ai/data/database/app_database.dart';
import '../support/demo_seeder.dart';
import 'package:civinex_ai/data/repositories/auth_repository.dart';
import 'package:civinex_ai/data/repositories/incident_repository.dart';
import 'package:civinex_ai/data/repositories/intelligence_repository.dart';
import 'package:civinex_ai/data/repositories/workflow_repository.dart';
import 'package:civinex_ai/domain/models/user.dart';
import 'package:civinex_ai/domain/models/workflow.dart';
import 'package:civinex_ai/services/ai/naive_bayes_provider.dart';
import 'package:civinex_ai/services/ai/priority_scorer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late AuthRepository auth;
  late IncidentRepository repo;
  late WorkflowRepository wf;
  late AppUser citizen, other, officer, roadsOfficer, admin;
  var clock = DateTime(2026, 6, 1, 9);

  setUp(() async {
    clock = DateTime(2026, 6, 1, 9);
    db = await AppDatabase.open(path: inMemoryDatabasePath);
    await DemoSeeder.seed(db);
    auth = AuthRepository(db);
    repo = IncidentRepository(db, ai: NaiveBayesProvider(), clock: () => clock);
    wf = WorkflowRepository(db, incidents: repo, clock: () => clock);
    citizen = await auth.signIn(DemoAccounts.citizen, DemoAccounts.password);
    officer = await auth.signIn(DemoAccounts.officer, DemoAccounts.password);
    roadsOfficer = await auth.signIn(DemoAccounts.roadsOfficer, DemoAccounts.password);
    admin = await auth.signIn(DemoAccounts.admin, DemoAccounts.password);
    other = await auth.register(name: 'Other', email: 'other@example.com', password: 'Passw0rdX');
  });

  Future<String> pothole(AppUser who,
      {double lat = 9.95, double lng = 76.28, String text = 'Big pothole in the middle of the road'}) async {
    final r = await repo.submit(
        reporter: who,
        description: text,
        locationText: 'Test road, Kochi',
        latitude: lat,
        longitude: lng);
    return r.incident.id;
  }

  group('duplicate linking', () {
    test('a near-identical report is linked to the parent and counted', () async {
      final a = await pothole(citizen);
      final r = await repo.submit(
          reporter: other,
          description: 'Big pothole in the middle of the road',
          locationText: 'Test road, Kochi',
          latitude: 9.9501,
          longitude: 76.2801);
      expect(r.linkedTo, a);
      expect(r.reporterCount, 2);
      expect(r.incident.dupVerified, isFalse);
      expect(await repo.reporterCount(a), 2);
    });

    test('linked children leave the staff queue and follow the parent status', () async {
      final a = await pothole(citizen);
      final b = (await repo.submit(
              reporter: other,
              description: 'Big pothole in the middle of the road',
              locationText: 'Test road, Kochi',
              latitude: 9.9501,
              longitude: 76.2801))
          .incident
          .id;
      final q = await repo.priorityQueue(admin);
      expect(q.any((i) => i.id == a), isTrue);
      expect(q.any((i) => i.id == b), isFalse);
      await repo.changeStatus(
          actor: admin, incidentId: a, to: IncidentStatus.resolved, note: 'Filled and tarred');
      expect((await repo.getVisible(other, b)).status, IncidentStatus.resolved);
    });

    test('staff can unlink a wrong match', () async {
      final a = await pothole(citizen);
      final b = (await repo.submit(
              reporter: other,
              description: 'Big pothole in the middle of the road',
              locationText: 'Test road, Kochi',
              latitude: 9.9501,
              longitude: 76.2801))
          .incident
          .id;
      await repo.verifyDuplicate(actor: admin, childId: b, confirm: false, note: 'different road');
      expect((await repo.getVisible(admin, b)).duplicateOfId, isNull);
      expect(await repo.reporterCount(a), 1);
    });

    test('a citizen never sees another citizen\'s name on a shared report', () async {
      final a = await pothole(citizen);
      await repo.submit(
          reporter: other,
          description: 'Big pothole in the middle of the road',
          locationText: 'Test road, Kochi',
          latitude: 9.9501,
          longitude: 76.2801);
      final h = await repo.history(citizen, a);
      expect(h.any((e) => e.actorName == 'Other'), isFalse);
    });

    test('more reporters raise the priority score', () async {
      final a = await pothole(citizen);
      final before = (await repo.getVisible(admin, a)).priorityScore;
      for (var n = 0; n < 3; n++) {
        final u = await auth.register(name: 'U$n', email: 'u$n@example.com', password: 'Passw0rdX');
        await wf.support(u, a);
      }
      final after = await repo.getVisible(admin, a);
      expect(after.priorityScore, greaterThan(before));
      expect(after.priorityReasons, contains('citizens'));
    });

    test('an officer override of priority is not undone by new reporters', () async {
      final a = await pothole(citizen);
      await repo.overrideSuggestion(
          actor: admin, incidentId: a, priority: Priority.low, reason: 'Checked on site, minor');
      for (var n = 0; n < 4; n++) {
        final u = await auth.register(name: 'U$n', email: 'v$n@example.com', password: 'Passw0rdX');
        await wf.support(u, a);
      }
      expect((await repo.getVisible(admin, a)).priority, Priority.low);
    });
  });

  group('supporters and nearby', () {
    test('support counts once, never for your own report, citizens only', () async {
      final a = await pothole(citizen);
      expect(await wf.support(other, a), 2);
      expect(() => wf.support(other, a), throwsA(isA<ValidationException>()));
      expect(() => wf.support(citizen, a), throwsA(isA<ValidationException>()));
      expect(() => wf.support(officer, a), throwsA(isA<PermissionDeniedException>()));
    });

    test('nearby view hides description, reporter and photo', () async {
      await pothole(citizen);
      final list = await wf.nearby(other, latitude: 9.95, longitude: 76.28);
      expect(list, isNotEmpty);
      final p = list.first;
      expect(p.areaText, isNot(contains('pothole')));
      expect(p.supportedByMe, isFalse);
      expect(p.citizens, 1);
    });
  });

  group('city-wide public view', () {
    test('lists open reports without GPS, including ones with no coordinates, still privacy-limited',
        () async {
      await pothole(citizen);
      await repo.submit(
          reporter: citizen,
          description: 'Garbage dumped beside the compound wall for days',
          locationText: 'No coordinates road, Kochi');
      final list = await wf.openCityWide(other);
      expect(list.length, greaterThanOrEqualTo(2));
      expect(list.any((p) => p.latitude == null), isTrue);
      expect(list.every((p) => p.distanceMeters == null), isTrue);
      expect(list.every((p) => !p.areaText.toLowerCase().contains('pothole')), isTrue);
    });
  });

  group('SLA, assignment, escalation', () {
    test('SLA deadline follows priority and is shown as overdue after it passes', () async {
      final id = await pothole(citizen);
      final i = await repo.getVisible(admin, id);
      expect(i.slaDueAt, Sla.due(i.createdAt, i.priority));
      expect(i.isOverdue(clock), isFalse);
      expect(i.isOverdue(clock.add(const Duration(days: 60))), isTrue);
    });

    test('assign needs acceptance; rejecting needs a reason and returns it to review', () async {
      final id = await pothole(citizen);
      await wf.assign(actor: admin, incidentId: id, officerId: roadsOfficer.id);
      var i = await repo.getVisible(admin, id);
      expect(i.assignedOfficerId, roadsOfficer.id);
      expect(i.status, IncidentStatus.assigned);
      expect((await wf.myAssignments(roadsOfficer)).length, 1);

      expect(() => wf.respond(officer: roadsOfficer, incidentId: id, accept: false, reason: 'no'),
          throwsA(isA<ValidationException>()));
      await wf.respond(
          officer: roadsOfficer, incidentId: id, accept: false, reason: 'On leave this week');
      i = await repo.getVisible(admin, id);
      expect(i.assignedOfficerId, isNull);
      expect(i.status, IncidentStatus.underReview);
      final notes = await repo.notifications(admin);
      expect(notes.any((n) => n.title == 'Assignment rejected'), isTrue);
    });

    test('only the assigned officer can respond', () async {
      final id = await pothole(citizen);
      await wf.assign(actor: admin, incidentId: id, officerId: roadsOfficer.id);
      expect(() => wf.respond(officer: officer, incidentId: id, accept: true),
          throwsA(isA<NotFoundException>()));
    });

    test('officers must belong to the incident department', () async {
      final id = await pothole(citizen);
      expect(() => wf.assign(actor: admin, incidentId: id, officerId: officer.id),
          throwsA(isA<ValidationException>()));
    });

    test('reassignment marks the old assignment and keeps history', () async {
      final id = await pothole(citizen);
      await wf.assign(actor: admin, incidentId: id, officerId: roadsOfficer.id);
      await wf.respond(officer: roadsOfficer, incidentId: id, accept: true);
      await wf.assign(actor: admin, incidentId: id, officerId: roadsOfficer.id, note: 'again');
      final list = await wf.assignmentsFor(admin, id);
      expect(list.where((a) => a.state == AssignmentState.reassigned).length, 1);
    });

    test('maintenance escalates overdue reports once per level and auto-assigns', () async {
      final id = await pothole(citizen);
      var rep = await wf.runMaintenance(admin);
      expect(rep.autoAssigned, greaterThanOrEqualTo(1));
      expect((await repo.getVisible(admin, id)).assignedOfficerId, roadsOfficer.id);

      clock = clock.add(const Duration(days: 20));
      rep = await wf.runMaintenance(admin);
      expect(rep.escalated, greaterThanOrEqualTo(1));
      expect((await repo.getVisible(admin, id)).escalated, isTrue);
      rep = await wf.runMaintenance(admin);
      expect(rep.escalated, 0, reason: 'already at this level');
    });

    test('officer escalation needs a reason and alerts admins', () async {
      final id = await pothole(citizen);
      expect(() => wf.escalate(roadsOfficer, id, 'x'), throwsA(isA<ValidationException>()));
      await wf.escalate(roadsOfficer, id, 'Needs a road roller we do not have');
      final i = await repo.getVisible(admin, id);
      expect(i.escalationLevel, 1);
      expect((await repo.notifications(admin)).any((n) => n.title == 'Case escalated'), isTrue);
    });

    test('resource requests are decided by admins only', () async {
      final id = await pothole(citizen);
      await wf.requestResources(roadsOfficer, id, 'Need 2 tonnes of asphalt');
      final reqs = await wf.resourceRequests(admin);
      expect(reqs.single.state, ResourceState.open);
      expect(() => wf.decideResources(roadsOfficer, reqs.single.id, true, 'ok'),
          throwsA(isA<PermissionDeniedException>()));
      await wf.decideResources(admin, reqs.single.id, true, 'Approved from stock');
      expect((await wf.resourceRequests(admin)).single.state, ResourceState.approved);
    });
  });

  group('feedback and closure', () {
    Future<String> resolved() async {
      final id = await pothole(citizen);
      await repo.changeStatus(
          actor: admin, incidentId: id, to: IncidentStatus.resolved, note: 'Filled and tarred');
      return id;
    }

    test('confirming the fix closes the report and stores the rating', () async {
      final id = await resolved();
      await wf.submitFeedback(citizen: citizen, incidentId: id, rating: 5, confirmedFixed: true);
      expect((await repo.getVisible(citizen, id)).status, IncidentStatus.closed);
      expect((await wf.feedbackFor(citizen, id))!.rating, 5);
      expect(() => wf.submitFeedback(citizen: citizen, incidentId: id, rating: 4, confirmedFixed: true),
          throwsA(isA<ValidationException>()));
    });

    test('"not fixed" reopens the report for review', () async {
      final id = await resolved();
      await wf.submitFeedback(
          citizen: citizen, incidentId: id, rating: 1, comment: 'still there', confirmedFixed: false);
      expect((await repo.getVisible(citizen, id)).status, IncidentStatus.underReview);
    });

    test('only the reporter, only after resolution, rating 1-5', () async {
      final id = await pothole(citizen);
      expect(() => wf.submitFeedback(citizen: citizen, incidentId: id, rating: 5, confirmedFixed: true),
          throwsA(isA<ValidationException>()));
      await repo.changeStatus(
          actor: admin, incidentId: id, to: IncidentStatus.resolved, note: 'Done properly');
      expect(() => wf.submitFeedback(citizen: other, incidentId: id, rating: 5, confirmedFixed: true),
          throwsA(isA<NotFoundException>()));
      expect(() => wf.submitFeedback(citizen: citizen, incidentId: id, rating: 9, confirmedFixed: true),
          throwsA(isA<ValidationException>()));
    });

    test('resolved reports with no answer are closed after the waiting period', () async {
      final id = await resolved();
      clock = clock.add(const Duration(days: WorkflowRepository.autoCloseDays + 1));
      final rep = await wf.runMaintenance(admin);
      expect(rep.autoClosed, greaterThanOrEqualTo(1));
      expect((await repo.getVisible(admin, id)).status, IncidentStatus.closed);
    });
  });

  group('internal notes and departments', () {
    test('internal notes are staff only', () async {
      final id = await pothole(citizen);
      await wf.addNote(roadsOfficer, id, 'Contractor called');
      expect((await wf.notes(admin, id)).single.body, 'Contractor called');
      expect(() => wf.notes(citizen, id), throwsA(isA<PermissionDeniedException>()));
      expect(() => wf.addNote(officer, id, 'hello'), throwsA(isA<NotFoundException>()));
    });

    test('only admins manage departments; re-routing clears the officer', () async {
      expect(() => wf.addDepartment(officer, 'Parks'), throwsA(isA<PermissionDeniedException>()));
      final d = await wf.addDepartment(admin, 'Parks & Gardens');
      expect((await wf.listDepartments()).any((x) => x.id == d), isTrue);
      final id = await pothole(citizen);
      await wf.assign(actor: admin, incidentId: id, officerId: roadsOfficer.id);
      await wf.reassignDepartment(
          admin: admin, incidentId: id, departmentId: d, reason: 'Belongs to parks');
      final i = await repo.getVisible(admin, id);
      expect(i.departmentId, d);
      expect(i.assignedOfficerId, isNull);
    });
  });

  group('intelligence', () {
    test('snapshot is staff only and builds a plain-language summary', () async {
      final intel = IntelligenceRepository(db, incidents: repo, workflow: wf, clock: () => clock);
      expect(() => intel.snapshot(citizen), throwsA(isA<PermissionDeniedException>()));
      await pothole(citizen);
      final s = await intel.snapshot(admin);
      expect(s.summary, isNotEmpty);
      expect(s.departments, isNotEmpty);
    });

    test('CSV export is admin-logged and neutralises formulas', () async {
      final intel = IntelligenceRepository(db, incidents: repo, workflow: wf, clock: () => clock);
      final csv = await intel.exportIncidentsCsv(admin);
      expect(csv.split('\n').first, contains('category'));
      expect(csv, isNot(contains('password')));
      final log = await repo.auditLog(admin);
      expect(log.any((e) => e.action == 'export'), isTrue);
    });
  });
}
