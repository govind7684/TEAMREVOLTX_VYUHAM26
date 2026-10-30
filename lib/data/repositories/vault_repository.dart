import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/security/password_hasher.dart';
import '../../domain/models/user.dart';
import '../../domain/models/vault.dart';
import '../../services/vault_crypto.dart';
import 'auth_repository.dart';

/// Personal document vault. Every call is scoped to the signed-in owner: there
/// is no way to list or open another person's documents, and administrators
/// get no special access. Files are encrypted before they touch the disk.
class VaultRepository {
  VaultRepository(this._db,
      {required VaultCrypto crypto, required String baseDir, required AuthRepository auth})
      : _crypto = crypto,
        _baseDir = baseDir,
        _auth = auth;

  final Database _db;
  final VaultCrypto _crypto;
  final String _baseDir;
  final AuthRepository _auth;
  static const _uuid = Uuid();

  static const maxBytes = 10 * 1024 * 1024;
  static const _mimeByExt = {
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  };
  static const maxPinAttempts = 5;
  static const lockMinutes = 5;

  static String? mimeFor(String fileName) =>
      _mimeByExt[p.extension(fileName).replaceFirst('.', '').toLowerCase()];

  String _path(String ownerId, String fileName) => p.join(_baseDir, ownerId, fileName);

  // ------------------------------------------------------------ documents

  Future<List<VaultDocument>> list(AppUser owner, {VaultCategory? category, String query = ''}) async {
    final where = StringBuffer('owner_id = ?');
    final args = <Object?>[owner.id];
    if (category != null) {
      where.write(' AND category = ?');
      args.add(category.name);
    }
    final q = query.trim();
    if (q.isNotEmpty) {
      where.write(' AND (title LIKE ? OR original_name LIKE ?)');
      args..add('%$q%')..add('%$q%');
    }
    final rows = await _db.query('vault_documents',
        where: where.toString(), whereArgs: args, orderBy: 'created_at DESC');
    return rows.map(VaultDocument.fromMap).toList();
  }

  Future<VaultDocument> add(
    AppUser owner, {
    required VaultCategory category,
    required String title,
    required String fileName,
    required List<int> bytes,
    DateTime? expiresAt,
  }) async {
    final mime = mimeFor(fileName);
    if (mime == null) {
      throw const ValidationException(['Only PDF, JPG, PNG or WebP files can be stored.']);
    }
    if (bytes.isEmpty) throw const ValidationException(['That file is empty.']);
    if (bytes.length > maxBytes) {
      throw const ValidationException(['Files must be 10 MB or smaller.']);
    }
    final name = title.trim();
    if (name.isEmpty || name.length > 80) {
      throw const ValidationException(['Give the document a name (up to 80 characters).']);
    }
    final id = _uuid.v4();
    final stored = '$id.enc';
    final blob = await _crypto.encrypt(owner.id, bytes);
    final file = File(_path(owner.id, stored));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(blob, flush: true);
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await _db.insert('vault_documents', {
        'id': id,
        'owner_id': owner.id,
        'category': category.name,
        'title': name,
        'original_name': p.basename(fileName),
        'mime': mime,
        'size_bytes': bytes.length,
        'file_name': stored,
        'expires_at': expiresAt?.millisecondsSinceEpoch,
        'reminded_level': 0,
        'created_at': now,
        'updated_at': now,
      });
    } catch (_) {
      if (await file.exists()) await file.delete(); // no orphaned encrypted file
      rethrow;
    }
    return VaultDocument.fromMap((await _db.query('vault_documents', where: 'id = ?', whereArgs: [id])).first);
  }

  Future<Map<String, Object?>> _owned(AppUser owner, String id) async {
    final rows = await _db.query('vault_documents',
        where: 'id = ? AND owner_id = ?', whereArgs: [id, owner.id], limit: 1);
    if (rows.isEmpty) throw const NotFoundException('That document was not found.');
    return rows.first;
  }

  /// Decrypts a document for viewing, exporting or opening.
  Future<VaultFile> open(AppUser owner, String id) async {
    final row = await _owned(owner, id);
    final file = File(_path(owner.id, row['file_name'] as String));
    if (!await file.exists()) {
      throw const NotFoundException('The stored file is missing from this phone.');
    }
    try {
      final bytes = await _crypto.decrypt(owner.id, await file.readAsBytes());
      return VaultFile(VaultDocument.fromMap(row), bytes);
    } catch (_) {
      throw const ValidationException(
          ['This document could not be decrypted. It may be damaged, or the phone\'s secure key was reset.']);
    }
  }

  Future<void> rename(AppUser owner, String id, String title) async {
    await _owned(owner, id);
    final name = title.trim();
    if (name.isEmpty || name.length > 80) {
      throw const ValidationException(['Give the document a name (up to 80 characters).']);
    }
    await _db.update(
        'vault_documents', {'title': name, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setExpiry(AppUser owner, String id, DateTime? expiresAt) async {
    await _owned(owner, id);
    await _db.update(
        'vault_documents',
        {
          'expires_at': expiresAt?.millisecondsSinceEpoch,
          'reminded_level': 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id]);
  }

  Future<void> delete(AppUser owner, String id) async {
    final row = await _owned(owner, id);
    final file = File(_path(owner.id, row['file_name'] as String));
    if (await file.exists()) await file.delete();
    await _db.delete('vault_documents', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------ reminders

  /// Creates an in-app notification when a document is within 30 days of its
  /// expiry, again within 7 days, and once it has expired. Each stage is
  /// sent only once per expiry date. Returns how many were created.
  Future<int> sendExpiryReminders(AppUser owner, {DateTime? now}) async {
    final today = now ?? DateTime.now();
    final docs = await list(owner);
    var created = 0;
    for (final d in docs) {
      final days = d.daysToExpiry(today);
      if (days == null) continue;
      final level = days < 0 ? 3 : days <= 7 ? 2 : days <= 30 ? 1 : 0;
      final row = await _owned(owner, d.id);
      if (level == 0 || level <= (row['reminded_level'] as int)) continue;
      final when = days < 0
          ? 'expired ${-days} day${-days == 1 ? '' : 's'} ago'
          : days == 0
              ? 'expires today'
              : 'expires in $days day${days == 1 ? '' : 's'}';
      await _db.insert('notifications', {
        'id': _uuid.v4(),
        'user_id': owner.id,
        'title': 'Document ${days < 0 ? 'expired' : 'expiring'}: ${d.title}',
        'body': 'Your ${d.category.label} $when. Open Document Vault to update it.',
        'incident_id': null,
        'is_read': 0,
        'created_at': today.millisecondsSinceEpoch,
      });
      await _db.update('vault_documents', {'reminded_level': level},
          where: 'id = ?', whereArgs: [d.id]);
      created++;
    }
    return created;
  }

  // ------------------------------------------------------------ PIN / lock

  Future<Map<String, Object?>?> _settings(String userId) async {
    final r = await _db.query('vault_settings', where: 'user_id = ?', whereArgs: [userId], limit: 1);
    return r.isEmpty ? null : r.first;
  }

  Future<bool> hasPin(AppUser owner) async => (await _settings(owner.id))?['pin_hash'] != null;

  Future<bool> biometricEnabled(AppUser owner) async =>
      ((await _settings(owner.id))?['use_biometric'] as int? ?? 0) == 1;

  Future<void> _upsert(String userId, Map<String, Object?> values) async {
    final existing = await _settings(userId);
    if (existing == null) {
      await _db.insert('vault_settings', {
        'user_id': userId,
        'use_biometric': 0,
        'failed_attempts': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        ...values,
      });
    } else {
      await _db.update('vault_settings', values, where: 'user_id = ?', whereArgs: [userId]);
    }
  }

  static String? validatePin(String pin) =>
      RegExp(r'^\d{4,8}$').hasMatch(pin) ? null : 'The PIN must be 4 to 8 digits.';

  Future<void> setPin(AppUser owner, String pin) async {
    final err = validatePin(pin);
    if (err != null) throw ValidationException([err]);
    final salt = PasswordHasher.generateSalt();
    await _upsert(owner.id, {
      'pin_hash': PasswordHasher.hash(pin, salt),
      'pin_salt': salt,
      'failed_attempts': 0,
      'locked_until': null,
    });
  }

  /// True when the PIN is right. Five wrong tries lock PIN entry for five
  /// minutes (biometric unlock is unaffected).
  Future<bool> verifyPin(AppUser owner, String pin, {DateTime? now}) async {
    final t = now ?? DateTime.now();
    final s = await _settings(owner.id);
    if (s == null || s['pin_hash'] == null) {
      throw const ValidationException(['Set a vault PIN first.']);
    }
    final until = s['locked_until'] as int?;
    if (until != null && until > t.millisecondsSinceEpoch) {
      final mins = ((until - t.millisecondsSinceEpoch) / 60000).ceil();
      throw ValidationException(['Too many wrong PINs. Try again in $mins minute${mins == 1 ? '' : 's'}.']);
    }
    final ok = PasswordHasher.verify(pin, s['pin_salt'] as String, s['pin_hash'] as String);
    if (ok) {
      await _upsert(owner.id, {'failed_attempts': 0, 'locked_until': null});
      return true;
    }
    final fails = (s['failed_attempts'] as int) + 1;
    await _upsert(owner.id, {
      'failed_attempts': fails >= maxPinAttempts ? 0 : fails,
      'locked_until':
          fails >= maxPinAttempts ? t.add(const Duration(minutes: lockMinutes)).millisecondsSinceEpoch : null,
    });
    return false;
  }

  /// Sets a new PIN after the person proves who they are with the account
  /// password. Documents stay readable: the PIN guards the screen, while the
  /// files are protected by the Keystore-held key.
  Future<void> resetPin(AppUser owner, String accountPassword, String newPin) async {
    if (!await _auth.verifyPassword(owner.id, accountPassword)) {
      throw const ValidationException(['That account password is not correct.']);
    }
    await setPin(owner, newPin);
  }

  Future<void> setBiometric(AppUser owner, bool on) => _upsert(owner.id, {'use_biometric': on ? 1 : 0});

  /// Removes every vault file of this user (used if the account is deleted).
  Future<void> wipe(String userId) async {
    final dir = Directory(p.join(_baseDir, userId));
    if (await dir.exists()) await dir.delete(recursive: true);
    await _db.delete('vault_documents', where: 'owner_id = ?', whereArgs: [userId]);
    await _db.delete('vault_settings', where: 'user_id = ?', whereArgs: [userId]);
  }
}

