import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Remembers WHICH user is signed in, so the app opens straight to the home
/// screen after it was closed. Only the user id is kept, never a password.
///
/// On start the id is looked up in the database again and rejected if the
/// account was deleted or disabled, so a stale file cannot grant access or
/// extra permissions.
abstract class SessionStore {
  Future<String?> read();
  Future<void> write(String? userId);
}

/// Used by tests and as the default: remembers nothing between runs.
class MemorySessionStore implements SessionStore {
  String? _id;
  @override
  Future<String?> read() async => _id;
  @override
  Future<void> write(String? userId) async => _id = userId;
}

/// Stores the id in a small file in the app's private storage folder.
class FileSessionStore implements SessionStore {
  File? _file;

  Future<File> _open() async {
    final existing = _file;
    if (existing != null) return existing;
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return _file = File(p.join(dir.path, 'session.txt'));
  }

  @override
  Future<String?> read() async {
    try {
      final f = await _open();
      if (!await f.exists()) return null;
      final id = (await f.readAsString()).trim();
      return id.isEmpty ? null : id;
    } catch (_) {
      return null; // unreadable: just ask the person to sign in again
    }
  }

  @override
  Future<void> write(String? userId) async {
    try {
      final f = await _open();
      if (userId == null) {
        if (await f.exists()) await f.delete();
      } else {
        await f.writeAsString(userId, flush: true);
      }
    } catch (_) {
      // Not being able to remember the session must never block sign-in.
    }
  }
}
