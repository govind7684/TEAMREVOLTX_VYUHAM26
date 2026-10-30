import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Salted, iterated SHA-256 hashing for the LOCAL demo account store.
///
/// This is demo-grade. A real deployment must use a server-side identity
/// provider with a memory-hard hash (Argon2/bcrypt) and rate limiting.
class PasswordHasher {
  static const _iterations = 10000;

  static String generateSalt() {
    final rnd = Random.secure();
    return base64.encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
  }

  static String hash(String password, String salt) {
    final saltBytes = utf8.encode(salt);
    var digest = sha256.convert(utf8.encode('$salt:$password')).bytes;
    for (var i = 0; i < _iterations; i++) {
      digest = sha256.convert([...digest, ...saltBytes]).bytes;
    }
    return base64.encode(digest);
  }

  static bool verify(String password, String salt, String expectedHash) {
    final actual = hash(password, salt);
    if (actual.length != expectedHash.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual.codeUnitAt(i) ^ expectedHash.codeUnitAt(i);
    }
    return diff == 0;
  }
}
