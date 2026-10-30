import 'dart:io';

import 'package:civinex_ai/core/errors/app_exceptions.dart';
import 'package:civinex_ai/data/database/app_database.dart';
import 'package:civinex_ai/data/repositories/auth_repository.dart';
import 'package:civinex_ai/data/repositories/vault_repository.dart';
import 'package:civinex_ai/domain/models/user.dart';
import 'package:civinex_ai/domain/models/vault.dart';
import 'package:civinex_ai/services/vault_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/demo_seeder.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late Directory dir;
  late VaultRepository vault;
  late AuthRepository auth;
  late AppUser asha, ravi;

  final bytes = List<int>.generate(2000, (i) => i % 251);

  setUp(() async {
    db = await AppDatabase.open(path: inMemoryDatabasePath);
    await DemoSeeder.ensureDepartments(db);
    auth = AuthRepository(db);
    dir = await Directory.systemTemp.createTemp('vault_test');
    vault = VaultRepository(db,
        crypto: VaultCrypto(MemoryVaultKeyStore()), baseDir: dir.path, auth: auth);
    asha = await auth.register(name: 'Asha', email: 'asha@example.com', password: 'Passw0rdX');
    ravi = await auth.register(name: 'Ravi', email: 'ravi@example.com', password: 'Passw0rdX');
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<VaultDocument> addDoc(AppUser u, {String name = 'aadhaar.pdf', DateTime? expires}) =>
      vault.add(u,
          category: VaultCategory.aadhaar,
          title: 'My Aadhaar',
          fileName: name,
          bytes: bytes,
          expiresAt: expires);

  test('stored file is encrypted on disk and decrypts back to the original', () async {
    final d = await addDoc(asha);
    final onDisk = await File('${dir.path}/${asha.id}/${d.id}.enc').readAsBytes();
    expect(onDisk, isNot(equals(bytes)));
    expect(onDisk.length, bytes.length + 12 + 16); // nonce + tag
    final opened = await vault.open(asha, d.id);
    expect(opened.bytes, bytes);
    expect(opened.document.mime, 'application/pdf');
  });

  test('a tampered file refuses to open instead of returning garbage', () async {
    final d = await addDoc(asha);
    final f = File('${dir.path}/${asha.id}/${d.id}.enc');
    final raw = await f.readAsBytes();
    raw[40] ^= 0xFF;
    await f.writeAsBytes(raw);
    await expectLater(vault.open(asha, d.id), throwsA(isA<ValidationException>()));
  });

  test('only the owner can list, open, rename, delete (administrators included)', () async {
    final d = await addDoc(asha);
    expect(await vault.list(ravi), isEmpty);
    await expectLater(vault.open(ravi, d.id), throwsA(isA<NotFoundException>()));
    await expectLater(vault.rename(ravi, d.id, 'x'), throwsA(isA<NotFoundException>()));
    await expectLater(vault.delete(ravi, d.id), throwsA(isA<NotFoundException>()));
    expect(await vault.list(asha), hasLength(1));
  });

  test('rejects bad types, empty files, oversize files and blank names', () async {
    await expectLater(addDoc(asha, name: 'virus.exe'), throwsA(isA<ValidationException>()));
    await expectLater(
        vault.add(asha, category: VaultCategory.other, title: 'x', fileName: 'a.pdf', bytes: []),
        throwsA(isA<ValidationException>()));
    await expectLater(
        vault.add(asha,
            category: VaultCategory.other,
            title: 'big',
            fileName: 'a.pdf',
            bytes: List.filled(VaultRepository.maxBytes + 1, 1)),
        throwsA(isA<ValidationException>()));
    await expectLater(
        vault.add(asha, category: VaultCategory.other, title: '  ', fileName: 'a.pdf', bytes: bytes),
        throwsA(isA<ValidationException>()));
    expect(await vault.list(asha), isEmpty);
  });

  test('rename, search, filter and delete', () async {
    final a = await addDoc(asha);
    await vault.add(asha,
        category: VaultCategory.bill, title: 'KSEB bill', fileName: 'bill.jpg', bytes: bytes);
    await vault.rename(asha, a.id, 'Aadhaar front');
    expect((await vault.list(asha, query: 'front')).single.id, a.id);
    expect((await vault.list(asha, category: VaultCategory.bill)).single.title, 'KSEB bill');
    await vault.delete(asha, a.id);
    expect(File('${dir.path}/${asha.id}/${a.id}.enc').existsSync(), isFalse);
    expect(await vault.list(asha), hasLength(1));
  });

  test('expiry reminders are sent once per stage', () async {
    final today = DateTime(2026, 10, 30);
    final d = await addDoc(asha, expires: DateTime(2026, 11, 20)); // 21 days
    expect(await vault.sendExpiryReminders(asha, now: today), 1);
    expect(await vault.sendExpiryReminders(asha, now: today), 0); // not repeated
    // Closer to expiry: a second, stronger reminder.
    expect(await vault.sendExpiryReminders(asha, now: DateTime(2026, 11, 15)), 1);
    // After expiry: a third.
    expect(await vault.sendExpiryReminders(asha, now: DateTime(2026, 11, 25)), 1);
    final rows = await db.query('notifications', where: 'user_id = ?', whereArgs: [asha.id]);
    expect(rows, hasLength(3));
    expect(rows.every((r) => !(r['title'] as String).contains('Aadhaar number')), isTrue);
    // Changing the expiry date resets the reminders.
    await vault.setExpiry(asha, d.id, DateTime(2027, 6, 1));
    expect(await vault.sendExpiryReminders(asha, now: DateTime(2026, 11, 25)), 0);
    // Nothing is created for other users.
    expect(await db.query('notifications', where: 'user_id = ?', whereArgs: [ravi.id]), isEmpty);
  });

  test('daysToExpiry counts whole days', () async {
    final d = await addDoc(asha, expires: DateTime(2026, 11, 5, 18));
    expect(d.daysToExpiry(DateTime(2026, 10, 30, 9)), 6);
    expect(d.daysToExpiry(DateTime(2026, 11, 7)), -2);
  });

  group('PIN', () {
    test('set, verify, and reject malformed PINs', () async {
      expect(await vault.hasPin(asha), isFalse);
      await expectLater(vault.setPin(asha, '12'), throwsA(isA<ValidationException>()));
      await expectLater(vault.setPin(asha, 'abcd'), throwsA(isA<ValidationException>()));
      await vault.setPin(asha, '4821');
      expect(await vault.hasPin(asha), isTrue);
      expect(await vault.verifyPin(asha, '4821'), isTrue);
      expect(await vault.verifyPin(asha, '0000'), isFalse);
      final row = (await db.query('vault_settings', where: 'user_id = ?', whereArgs: [asha.id])).single;
      expect(row['pin_hash'], isNot(contains('4821'))); // never stored in clear
    });

    test('five wrong PINs lock entry for five minutes, then it works again', () async {
      await vault.setPin(asha, '4821');
      final t = DateTime(2026, 10, 30, 10);
      for (var i = 0; i < VaultRepository.maxPinAttempts; i++) {
        expect(await vault.verifyPin(asha, '1111', now: t), isFalse);
      }
      await expectLater(vault.verifyPin(asha, '4821', now: t.add(const Duration(minutes: 1))),
          throwsA(isA<ValidationException>()));
      expect(await vault.verifyPin(asha, '4821', now: t.add(const Duration(minutes: 6))), isTrue);
    });

    test('resetting the PIN needs the account password and keeps documents', () async {
      await vault.setPin(asha, '4821');
      final d = await addDoc(asha);
      await expectLater(vault.resetPin(asha, 'wrong-password', '9999'),
          throwsA(isA<ValidationException>()));
      expect(await vault.verifyPin(asha, '4821'), isTrue);
      await vault.resetPin(asha, 'Passw0rdX', '9999');
      expect(await vault.verifyPin(asha, '9999'), isTrue);
      expect((await vault.open(asha, d.id)).bytes, bytes);
    });

    test('PINs and settings are per user', () async {
      await vault.setPin(asha, '4821');
      expect(await vault.hasPin(ravi), isFalse);
      await vault.setBiometric(asha, true);
      expect(await vault.biometricEnabled(asha), isTrue);
      expect(await vault.biometricEnabled(ravi), isFalse);
    });
  });

  test('wipe removes a user\'s files and records only', () async {
    await addDoc(asha);
    await addDoc(ravi);
    await vault.wipe(asha.id);
    expect(await vault.list(asha), isEmpty);
    expect(await vault.list(ravi), hasLength(1));
    expect(Directory('${dir.path}/${asha.id}').existsSync(), isFalse);
  });
}
