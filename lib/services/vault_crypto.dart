import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where each user's vault key lives. On Android the real implementation keeps
/// it in the hardware-backed Keystore through flutter_secure_storage.
abstract class VaultKeyStore {
  Future<List<int>?> read(String userId);
  Future<void> write(String userId, List<int> key);
}

class SecureVaultKeyStore implements VaultKeyStore {
  const SecureVaultKeyStore();
  static const _storage = FlutterSecureStorage();
  String _name(String userId) => 'civinex_vault_key_$userId';

  @override
  Future<List<int>?> read(String userId) async {
    final v = await _storage.read(key: _name(userId));
    return v == null ? null : base64Decode(v);
  }

  @override
  Future<void> write(String userId, List<int> key) =>
      _storage.write(key: _name(userId), value: base64Encode(key));
}

/// For tests only: keeps keys in memory.
class MemoryVaultKeyStore implements VaultKeyStore {
  final _keys = <String, List<int>>{};
  @override
  Future<List<int>?> read(String userId) async => _keys[userId];
  @override
  Future<void> write(String userId, List<int> key) async => _keys[userId] = key;
}

/// AES-256-GCM with a random key per user and a fresh random nonce per file.
/// GCM also authenticates, so a tampered file fails to open instead of
/// yielding garbage.
class VaultCrypto {
  VaultCrypto(this._keys);
  final VaultKeyStore _keys;
  final _algo = AesGcm.with256bits();

  Future<SecretKey> _key(String userId) async {
    var raw = await _keys.read(userId);
    if (raw == null) {
      final rnd = Random.secure();
      raw = List<int>.generate(32, (_) => rnd.nextInt(256));
      await _keys.write(userId, raw);
    }
    return SecretKey(raw);
  }

  /// Returns nonce + ciphertext + tag as one blob.
  Future<Uint8List> encrypt(String userId, List<int> plain) async {
    final box = await _algo.encrypt(plain, secretKey: await _key(userId));
    return Uint8List.fromList(box.concatenation());
  }

  /// Throws if the data was altered or the key is wrong.
  Future<Uint8List> decrypt(String userId, List<int> blob) async {
    final box = SecretBox.fromConcatenation(blob, nonceLength: 12, macLength: 16);
    final clear = await _algo.decrypt(box, secretKey: await _key(userId));
    return Uint8List.fromList(clear);
  }
}
