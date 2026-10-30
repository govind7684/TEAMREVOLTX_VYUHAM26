import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'data/database/app_database.dart';
import 'data/database/reference_data.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/cloud_auth_repository.dart';
import 'services/cloud_identity.dart';
import 'services/cloud_store.dart';
import 'domain/models/user.dart';
import 'services/prefs.dart';
import 'services/session_store.dart';
import 'services/vault_crypto.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  final db = await AppDatabase.open();
  await ReferenceData.ensureDepartments(db);
  final prefs = await Prefs.open();
  final docs = await getApplicationDocumentsDirectory();

  // Stay signed in until the person signs out. Only the id is remembered, and
  // it is checked against the database here, so a deleted or disabled account
  // goes back to the sign-in screen.
  final store = FileSessionStore();
  final cloud = await FirebaseIdentity.tryStart(); // null => accounts stay on this phone
  AppUser? restored;
  if (cloud != null) {
    // Firebase remembers who is signed in; the profile confirms the account
    // is still active.
    restored = await CloudAuthRepository(db, cloud).restore();
    await store.write(restored?.id);
  } else {
    final savedId = await store.read();
    if (savedId != null) {
      restored = await AuthRepository(db).getById(savedId);
      if (restored == null || !restored.isActive) {
        restored = null;
        await store.write(null);
      }
    }
  }

  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      cloudIdentityProvider.overrideWithValue(cloud),
      cloudStoreProvider.overrideWithValue(cloud == null ? null : FirestoreStore()),
      sessionStoreProvider.overrideWithValue(store),
      initialUserProvider.overrideWithValue(restored),
      prefsProvider.overrideWithValue(prefs),
      vaultKeyStoreProvider.overrideWithValue(const SecureVaultKeyStore()),
      vaultDirProvider.overrideWithValue(p.join(docs.path, 'vault')),
    ],
    child: const CivinexApp(),
  ));
}
