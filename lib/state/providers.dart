import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants/enums.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/cloud_auth_repository.dart';
import '../services/cloud_identity.dart';
import '../services/cloud_store.dart';
import '../services/sync_service.dart';
import '../data/repositories/city_data_repository.dart';
import '../domain/models/city_update.dart';
import '../data/repositories/flood_repository.dart';
import '../domain/models/flood.dart';
import '../data/repositories/incident_repository.dart';
import '../data/repositories/intelligence_repository.dart';
import '../data/repositories/workflow_repository.dart';
import '../domain/models/workflow.dart';
import '../data/repositories/road_repository.dart';
import '../domain/models/road.dart';
import '../domain/models/incident.dart';
import '../domain/models/user.dart';
import '../services/ai/ai_provider.dart';
import '../services/ai/image_analyzer.dart';
import '../services/ai/naive_bayes_provider.dart';
import '../services/app_lock.dart';
import '../services/assist_service.dart';
import '../services/credits.dart';
import '../services/geocoding_service.dart';
import '../services/osm_places_service.dart';
import '../data/repositories/service_places_repository.dart';
import '../services/prefs.dart';
import '../services/session_store.dart';
import '../services/vault_crypto.dart';
import '../data/repositories/vault_repository.dart';
import '../domain/models/vault.dart';

/// Overridden in main() once the database is open.
final databaseProvider = Provider<Database>((ref) => throw UnimplementedError());

/// Text classification: a small Naive Bayes model trained on this device,
/// falling back to labelled keyword rules when it knows none of the words.
final aiProviderProvider = Provider<AiProvider>((ref) => NaiveBayesProvider());

/// Non-null when Firebase started (android/app/google-services.json present).
/// main() supplies it; null means accounts stay on this phone.
final cloudIdentityProvider = Provider<CloudIdentity?>((ref) => null);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final cloud = ref.watch(cloudIdentityProvider);
  return cloud == null ? AuthRepository(db) : CloudAuthRepository(db, cloud);
});

final incidentRepositoryProvider = Provider((ref) => IncidentRepository(
      ref.watch(databaseProvider),
      ai: ref.watch(aiProviderProvider),
    ));

/// Where the signed-in user's id is remembered. main() supplies a file-backed
/// store; tests use the in-memory default.
final sessionStoreProvider = Provider<SessionStore>((ref) => MemorySessionStore());

/// The user restored from the previous run (null when signed out). Set by main().
final initialUserProvider = Provider<AppUser?>((ref) => null);

/// The signed-in user. The person stays signed in across app restarts until
/// they sign out; only the id is stored. Every repository call still re-checks
/// the user against the database, so editing local state cannot grant extra
/// permissions.
class SessionNotifier extends StateNotifier<AppUser?> {
  SessionNotifier(this._auth, this._store, [AppUser? initial]) : super(initial);
  final AuthRepository _auth;
  final SessionStore _store;

  AppUser? _remember(AppUser? u) {
    _store.write(u?.id);
    return u;
  }

  Future<void> signIn(String email, String password, {SignInAudience? audience}) async =>
      state = _remember(await _auth.signIn(email, password, audience: audience));

  Future<void> register(String name, String email, String password) async =>
      state = _remember(await _auth.register(name: name, email: email, password: password));

  Future<void> createFirstAdmin(String name, String email, String password) async =>
      state = _remember(
          await _auth.createFirstAdmin(name: name, email: email, password: password));

  /// Explicit sign-out is the ONLY thing that forgets the session.
  void signOut() {
    _store.write(null);
    _auth.signOut();
    state = null;
  }

  /// Re-reads the user (e.g. after the role was changed by an admin).
  /// Signs out if the account no longer exists or was disabled.
  Future<void> refresh() async {
    final u = state;
    if (u == null) return;
    final fresh = await _auth.getById(u.id);
    if (fresh == null || !fresh.isActive) {
      signOut();
    } else {
      state = fresh;
    }
  }
}

final sessionProvider = StateNotifierProvider<SessionNotifier, AppUser?>((ref) =>
    SessionNotifier(ref.watch(authRepositoryProvider), ref.watch(sessionStoreProvider),
        ref.read(initialUserProvider)));

/// Bumped after any write so list screens reload.
final refreshTickProvider = StateProvider<int>((ref) => 0);

final incidentsProvider = FutureProvider<List<Incident>>((ref) async {
  ref.watch(refreshTickProvider);
  final user = ref.watch(sessionProvider);
  if (user == null) return [];
  return ref.watch(incidentRepositoryProvider).listVisible(user);
});

/// The signed-in citizen's civic credit points, counted from their own reports.
final creditsProvider = FutureProvider<CreditSummary>((ref) async {
  ref.watch(refreshTickProvider);
  final user = ref.watch(sessionProvider);
  if (user == null) return const CreditSummary(0, []);
  final mine = (await ref.watch(incidentRepositoryProvider).listVisible(user))
      .where((i) => i.reporterId == user.id)
      .toList();
  final fb = await ref.watch(workflowRepositoryProvider).feedbackIncidentIds(user);
  return Credits.compute(mine, feedbackFor: fb);
});

final queueProvider = FutureProvider<List<Incident>>((ref) async {
  ref.watch(refreshTickProvider);
  final user = ref.watch(sessionProvider);
  if (user == null || !user.isStaff) return [];
  return ref.watch(incidentRepositoryProvider).priorityQueue(user);
});

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) async {
  ref.watch(refreshTickProvider);
  final user = ref.watch(sessionProvider);
  if (user == null) return [];
  return ref.watch(incidentRepositoryProvider).notifications(user);
});

final floodRepositoryProvider =
    Provider((ref) => FloodRepository(ref.watch(databaseProvider)));

class FloodData {
  const FloodData(this.assessment, this.readings, this.config);
  final FloodRiskAssessment assessment;
  final List<RainfallReading> readings;
  final FloodConfig config;
}

final floodDataProvider = FutureProvider<FloodData>((ref) async {
  ref.watch(refreshTickProvider);
  ref.watch(sessionProvider); // reload on sign-in change
  final repo = ref.watch(floodRepositoryProvider);
  return FloodData(await repo.assess(), await repo.listReadings(), await repo.getConfig());
});

final roadRepositoryProvider = Provider((ref) => RoadRepository(
      ref.watch(databaseProvider),
      incidents: ref.watch(incidentRepositoryProvider),
    ));

final roadListProvider = FutureProvider<List<RoadReport>>((ref) async {
  ref.watch(refreshTickProvider);
  final user = ref.watch(sessionProvider);
  if (user == null || !user.isStaff) return [];
  return ref.watch(roadRepositoryProvider).priorityList(user);
});

/// True until the first administrator has been created. Auto-disposed so it is
/// re-checked every time the signed-out screen appears.
final needsSetupProvider = FutureProvider.autoDispose<bool>(
    (ref) async => !(await ref.watch(authRepositoryProvider).hasAdmin()));

/// Selected bottom/side navigation tab. Auto-disposed so each sign-in starts at the first tab.
final navIndexProvider = StateProvider.autoDispose<int>((ref) => 0);

// ---------------------------------------------------------------- AF-21 layer

final workflowRepositoryProvider = Provider((ref) => WorkflowRepository(
      ref.watch(databaseProvider),
      incidents: ref.watch(incidentRepositoryProvider),
    ));

final intelligenceRepositoryProvider = Provider((ref) => IntelligenceRepository(
      ref.watch(databaseProvider),
      incidents: ref.watch(incidentRepositoryProvider),
      workflow: ref.watch(workflowRepositoryProvider),
    ));

/// Staff analytics snapshot (performance, recurrence, hotspots, summary).
final intelProvider = FutureProvider<IntelSnapshot>((ref) async {
  ref.watch(refreshTickProvider);
  final user = ref.watch(sessionProvider);
  if (user == null || !user.isStaff) throw StateError('Staff only');
  return ref.watch(intelligenceRepositoryProvider).snapshot(user);
});

/// Runs housekeeping (deadlines, auto-assign, escalation, auto-close) once per
/// staff sign-in and reports what it did.
final maintenanceProvider = FutureProvider<MaintenanceReport?>((ref) async {
  final user = ref.watch(sessionProvider);
  if (user == null || !user.isStaff) return null;
  final r = await ref.watch(workflowRepositoryProvider).runMaintenance(user);
  if (r.changedAnything) Future.microtask(() => ref.read(refreshTickProvider.notifier).state++);
  return r;
});

/// Photo analysis. No image model ships with this build, so this is the
/// "unavailable" analyzer; a YOLO/TFLite implementation can replace it (see
/// docs/IMAGE_MODEL.md). Findings are then always confirmed by a person.
final imageAnalyzerProvider = Provider<ImageAnalyzer>((ref) => const UnavailableImageAnalyzer());

/// Department names (including ones added by an administrator).
final departmentsProvider = FutureProvider<List<({String id, String name})>>((ref) async {
  ref.watch(refreshTickProvider);
  ref.watch(sessionProvider);
  return ref.watch(workflowRepositoryProvider).listDepartments();
});

// ------------------------------------------------------------ city updates

final cityDataRepositoryProvider =
    Provider((ref) => CityDataRepository(ref.watch(databaseProvider)));

/// Current city updates, readable by every signed-in user.
final cityUpdatesProvider = FutureProvider<List<CityUpdate>>((ref) async {
  ref.watch(refreshTickProvider);
  if (ref.watch(sessionProvider) == null) return [];
  return ref.watch(cityDataRepositoryProvider).list();
});

// ------------------------------------------------------------ device settings

/// Overridden in main() with the file-backed settings; tests use memory.
final prefsProvider = Provider<Prefs>((ref) => Prefs.memory());

/// Claude assistant via the laptop server in server/. Not configured by default.
final assistServiceProvider = Provider<AssistService>((ref) => AssistService(ref.watch(prefsProvider)));

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._prefs)
      : super(switch (_prefs.get('theme')) {
          'light' => ThemeMode.light,
          'system' => ThemeMode.system,
          _ => ThemeMode.dark,
        });
  final Prefs _prefs;

  void set(ThemeMode m) {
    state = m;
    _prefs.set('theme', m.name);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
    (ref) => ThemeModeNotifier(ref.watch(prefsProvider)));

/// Fingerprint / face / device-PIN check. Tests override with FakeAppLock.
final appLockProvider = Provider<AppLock>((ref) => DeviceAppLock());

/// Whether the person asked for the app lock (a per-device choice).
class AppLockEnabledNotifier extends StateNotifier<bool> {
  AppLockEnabledNotifier(this._prefs) : super(_prefs.getBool('app_lock'));
  final Prefs _prefs;
  void set(bool v) {
    state = v;
    _prefs.setBool('app_lock', v);
  }
}

final appLockEnabledProvider = StateNotifierProvider<AppLockEnabledNotifier, bool>(
    (ref) => AppLockEnabledNotifier(ref.watch(prefsProvider)));

/// True while the lock screen must be shown. Starts locked when the lock is on
/// and a user was restored from the previous run.
final appLockedProvider = StateProvider<bool>(
    (ref) => ref.read(appLockEnabledProvider) && ref.read(initialUserProvider) != null);

final onboardedProvider = StateProvider<bool>((ref) => ref.read(prefsProvider).getBool('onboarded'));

final geocodingProvider = Provider<GeocodingService>((ref) => GeocodingService());

// ------------------------------------------------------------------- vault

/// Overridden in main() with the Keystore-backed store; tests use memory.
final vaultKeyStoreProvider = Provider<VaultKeyStore>((ref) => MemoryVaultKeyStore());

/// Where encrypted files are kept. main() supplies the app documents folder.
final vaultDirProvider = Provider<String>((ref) => throw UnimplementedError());

final vaultRepositoryProvider = Provider((ref) => VaultRepository(
      ref.watch(databaseProvider),
      crypto: VaultCrypto(ref.watch(vaultKeyStoreProvider)),
      baseDir: ref.watch(vaultDirProvider),
      auth: ref.watch(authRepositoryProvider),
    ));

final vaultDocsProvider = FutureProvider.autoDispose<List<VaultDocument>>((ref) async {
  ref.watch(refreshTickProvider);
  final user = ref.watch(sessionProvider);
  if (user == null) return [];
  return ref.watch(vaultRepositoryProvider).list(user);
});

/// Documents expiring within 30 days or already expired (for the Home banner).
final vaultExpiringProvider = FutureProvider.autoDispose<List<VaultDocument>>((ref) async {
  final docs = await ref.watch(vaultDocsProvider.future);
  final now = DateTime.now();
  return docs.where((d) => (d.daysToExpiry(now) ?? 999) <= 30).toList();
});

/// Creates in-app reminders for documents nearing expiry. Runs once per
/// citizen sign-in and whenever the vault changes.
final vaultRemindersProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watch(refreshTickProvider);
  final user = ref.watch(sessionProvider);
  if (user == null) return 0;
  final n = await ref.watch(vaultRepositoryProvider).sendExpiryReminders(user);
  if (n > 0) Future.microtask(() => ref.invalidate(notificationsProvider));
  return n;
});

/// The cloud database, when Firebase started. Overridden by main().
final cloudStoreProvider = Provider<CloudStore?>((ref) => null);

/// Keeps this phone's reports in step with the cloud while someone is signed
/// in. Watched by the Shell so it lives as long as the session. Null in local
/// mode.
final syncProvider = Provider<SyncService?>((ref) {
  final store = ref.watch(cloudStoreProvider);
  final user = ref.watch(sessionProvider.select((u) => u?.id));
  final current = ref.read(sessionProvider);
  if (store == null || user == null || current == null) return null;
  var disposed = false;
  late final SyncService svc;
  DateTime? lastMirror;
  Future<void> refreshPeople() async {
    final auth = ref.read(authRepositoryProvider);
    final now = DateTime.now();
    if (auth is! CloudAuthRepository || !current.isStaff) return;
    if (lastMirror != null && now.difference(lastMirror!) < const Duration(seconds: 60)) return;
    lastMirror = now;
    await auth.refreshMirror();
  }

  svc = SyncService(ref.read(databaseProvider), store, current, onChange: () async {
    if (disposed) return;
    if (current.role == UserRole.admin) {
      await refreshPeople();
      await ref.read(incidentRepositoryProvider).linkDuplicates(current);
      await ref.read(workflowRepositoryProvider).autoRoute(current);
    }
    if (disposed) return;
    ref.read(refreshTickProvider.notifier).state++;
    svc.pushSoon();
  });
  svc.start();
  Future(() async {
    await refreshPeople();
    if (disposed) return;
    if (current.role == UserRole.admin) {
      await ref.read(incidentRepositoryProvider).linkDuplicates(current);
      await ref.read(workflowRepositoryProvider).autoRoute(current);
    }
    svc.pushSoon();
  });
  ref.listen<int>(refreshTickProvider, (_, __) => svc.pushSoon());
  ref.onDispose(() {
    disposed = true;
    svc.stop();
  });
  return svc;
});

/// Automatic routing on an administrator's phone: whenever data changes, give
/// unassigned reports to the least-loaded officer of the right department.
final routingProvider = Provider<void>((ref) {
  final user = ref.watch(sessionProvider.select((u) => u?.id));
  final current = ref.read(sessionProvider);
  if (user == null || current == null || current.role != UserRole.admin) return;
  var busy = false;
  var disposed = false;
  Future<void> run() async {
    if (busy || disposed) return;
    busy = true;
    try {
      final l = await ref.read(incidentRepositoryProvider).linkDuplicates(current);
      final n = await ref.read(workflowRepositoryProvider).autoRoute(current);
      if ((n > 0 || l > 0) && !disposed) ref.read(refreshTickProvider.notifier).state++;
    } catch (_) {
    } finally {
      busy = false;
    }
  }

  ref.listen<int>(refreshTickProvider, (_, __) => run());
  Future.microtask(run);
  ref.onDispose(() => disposed = true);
});

final servicePlacesRepositoryProvider =
    Provider((ref) => ServicePlacesRepository(ref.watch(databaseProvider)));

final osmPlacesProvider = Provider<OsmPlacesService>((ref) => OsmPlacesService());
