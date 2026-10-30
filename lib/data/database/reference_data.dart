import 'package:sqflite/sqflite.dart';

import '../../core/constants/enums.dart';

/// Reference rows every installation needs (not sample data).
class ReferenceData {
  /// Departments are reference data and always present.
  static Future<void> ensureDepartments(Database db) async {
    final batch = db.batch();
    Departments.names.forEach((id, name) {
      batch.insert('departments', {'id': id, 'name': name},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    });
    await batch.commit(noResult: true);
  }
}
