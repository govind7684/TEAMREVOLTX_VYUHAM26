import 'package:civinex_ai/data/database/app_database.dart';
import '../support/demo_seeder.dart';
import 'package:civinex_ai/data/repositories/auth_repository.dart';
import 'package:civinex_ai/services/session_store.dart';
import 'package:civinex_ai/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  setUp(() async {
    db = await AppDatabase.open(path: inMemoryDatabasePath);
    await DemoSeeder.seed(db);
  });
  tearDown(() => db.close());

  ProviderContainer container(SessionStore store) {
    return ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sessionStoreProvider.overrideWithValue(store),
    ]);
  }

  test('signing in remembers the user id; signing out forgets it', () async {
    final store = MemorySessionStore();
    final c = container(store);
    addTearDown(c.dispose);
    expect(c.read(sessionProvider), isNull);

    await c.read(sessionProvider.notifier).signIn(DemoAccounts.officer, DemoAccounts.password);
    final user = c.read(sessionProvider)!;
    expect(await store.read(), user.id);

    c.read(sessionProvider.notifier).signOut();
    expect(c.read(sessionProvider), isNull);
    expect(await store.read(), isNull);
  });

  test('a remembered user is restored on the next start, role intact', () async {
    final store = MemorySessionStore();
    final first = container(store);
    await first.read(sessionProvider.notifier).signIn(DemoAccounts.admin, DemoAccounts.password);
    final id = first.read(sessionProvider)!.id;
    first.dispose();

    // "App restarted": main() reads the id, looks it up, passes it in.
    final restored = await AuthRepository(db).getById((await store.read())!);
    final second = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sessionStoreProvider.overrideWithValue(store),
      initialUserProvider.overrideWithValue(restored),
    ]);
    addTearDown(second.dispose);
    expect(second.read(sessionProvider)!.id, id);
    expect(second.read(sessionProvider)!.role.name, 'admin');
  });

  test('refresh signs out an account that was disabled', () async {
    final store = MemorySessionStore();
    final c = container(store);
    addTearDown(c.dispose);
    await c.read(sessionProvider.notifier).signIn(DemoAccounts.citizen, DemoAccounts.password);
    final id = c.read(sessionProvider)!.id;
    await db.update('users', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);

    await c.read(sessionProvider.notifier).refresh();
    expect(c.read(sessionProvider), isNull);
    expect(await store.read(), isNull);
  });
}
