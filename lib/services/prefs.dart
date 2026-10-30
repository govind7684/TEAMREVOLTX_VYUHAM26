import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Small per-device settings (theme, onboarding seen, app lock on/off).
/// Nothing sensitive goes here: it is a plain JSON file.
class Prefs {
  Prefs._(this._map, this._file);

  /// Remembers nothing between runs. Used by tests.
  Prefs.memory()
      : _map = {},
        _file = null;

  final Map<String, String> _map;
  final File? _file;

  static Future<Prefs> open() async {
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'prefs.json'));
      var map = <String, String>{};
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          map = {for (final e in decoded.entries) '${e.key}': '${e.value}'};
        }
      }
      return Prefs._(map, file);
    } catch (_) {
      return Prefs.memory(); // unreadable: fall back to defaults
    }
  }

  String? get(String key) => _map[key];
  bool getBool(String key) => _map[key] == '1';

  Future<void> set(String key, String? value) async {
    if (value == null) {
      _map.remove(key);
    } else {
      _map[key] = value;
    }
    try {
      await _file?.writeAsString(jsonEncode(_map), flush: true);
    } catch (_) {
      // A setting that cannot be saved must never crash the app.
    }
  }

  Future<void> setBool(String key, bool value) => set(key, value ? '1' : null);
}
