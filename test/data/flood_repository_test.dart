import 'package:civinex_ai/core/errors/app_exceptions.dart';
import 'package:civinex_ai/data/database/app_database.dart';
import '../support/demo_seeder.dart';
import 'package:civinex_ai/data/repositories/auth_repository.dart';
import 'package:civinex_ai/data/repositories/flood_repository.dart';
import 'package:civinex_ai/data/repositories/incident_repository.dart';
import 'package:civinex_ai/domain/models/flood.dart';
import 'package:civinex_ai/domain/models/user.dart';
import 'package:civinex_ai/services/ai/rule_based_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late FloodRepository repo;
  late IncidentRepository incidents;
  late AppUser citizen, officer, admin;

  setUp(() async {
    db = await AppDatabase.open(path: inMemoryDatabasePath);
    // Seed users only; use a fixed time so the sample readings are predictable.
    await DemoSeeder.seed(db);
    // Remove the sample readings so each test starts from a clean slate.
    await db.delete('rainfall_readings');
    final auth = AuthRepository(db);
    repo = FloodRepository(db);
    incidents = IncidentRepository(db, ai: RuleBasedProvider());
    citizen = await auth.signIn(DemoAccounts.citizen, DemoAccounts.password);
    officer = await auth.signIn(DemoAccounts.officer, DemoAccounts.password);
    admin = await auth.signIn(DemoAccounts.admin, DemoAccounts.password);
  });

  test('citizen cannot write readings, clear or change thresholds', () async {
    expect(() => repo.addReading(actor: citizen, stationName: 'X1', rainfallMm: 5),
        throwsA(isA<PermissionDeniedException>()));
    expect(() => repo.clearSimulated(officer), throwsA(isA<PermissionDeniedException>()));
    expect(() => repo.saveConfig(officer, const FloodConfig()),
        throwsA(isA<PermissionDeniedException>()));
  });

  test('addReading validates input', () async {
    for (final bad in [
      () => repo.addReading(actor: officer, stationName: '', rainfallMm: 5),
      () => repo.addReading(actor: officer, stationName: 'Stn', rainfallMm: -1),
      () => repo.addReading(actor: officer, stationName: 'Stn', rainfallMm: 301),
      () => repo.addReading(actor: officer, stationName: 'Stn', rainfallMm: 5, waterLevelCm: -5),
      () => repo.addReading(
          actor: officer,
          stationName: 'Stn',
          rainfallMm: 5,
          recordedAt: DateTime.now().add(const Duration(hours: 2))),
      () => repo.addReading(
          actor: officer,
          stationName: 'Stn',
          rainfallMm: 5,
          recordedAt: DateTime.now().subtract(const Duration(days: 8))),
    ]) {
      await expectLater(bad(), throwsA(isA<ValidationException>()));
    }
    expect(await repo.listReadings(), isEmpty);
  });

  test('manual reading is stored, estimated and audited', () async {
    final a = await repo.addReading(
        actor: officer, stationName: 'Test Gauge', rainfallMm: 65, waterLevelCm: 20);
    expect(a.level, FloodRiskLevel.warning);
    final list = await repo.listReadings();
    expect(list.single.source, ReadingSource.manual);
    expect(list.single.stationName, 'Test Gauge');
    final audit = await db.query('audit_log', where: "action = 'flood_reading_added'");
    expect(audit, hasLength(1));
  });

  test('crossing into Warning notifies drainage officer and admin once', () async {
    await repo.addReading(actor: officer, stationName: 'Gauge', rainfallMm: 65);
    Future<int> count(String userId) async => (await db.query('notifications',
            where: "user_id = ? AND title LIKE 'Flood risk estimate%'", whereArgs: [userId]))
        .length;
    expect(await count(officer.id), 1);
    expect(await count(admin.id), 1);
    expect(await count(citizen.id), 0);

    // Still Warning, not a rise: no new notification.
    await repo.addReading(actor: officer, stationName: 'Gauge', rainfallMm: 1);
    expect(await count(officer.id), 1);
  });

  test('config defaults, save, validation and persistence', () async {
    expect((await repo.getConfig()).rainWatch, const FloodConfig().rainWatch);
    await repo.saveConfig(admin, const FloodConfig(rainWatch: 10, rainWarning: 20, rainSevere: 40));
    expect((await repo.getConfig()).rainWarning, 20);
    await expectLater(
        repo.saveConfig(admin, const FloodConfig(rainWatch: 50, rainWarning: 20)),
        throwsA(isA<ValidationException>()));
    expect((await repo.getConfig()).rainWarning, 20); // unchanged
  });

  test('open flood reports in the last 24 h feed the estimate', () async {
    for (var n = 0; n < 3; n++) {
      await incidents.submit(
        reporter: citizen,
        description: 'Waterlogging near the market, knee-deep water number $n',
        locationText: 'Market road $n',
      );
    }
    expect(await repo.countRecentFloodReports(), greaterThanOrEqualTo(3));
    final a = await repo.assess();
    expect(a.level.index, greaterThanOrEqualTo(FloodRiskLevel.watch.index));
  });

  test('demo reset removes demo readings only', () async {
    await DemoSeeder.clearDemo(db);
    await DemoSeeder.seed(db);
    final list = await repo.listReadings(limit: 100);
    expect(list.where((r) => r.isDemo).length, 6); // re-seeded sample readings
  });
}
