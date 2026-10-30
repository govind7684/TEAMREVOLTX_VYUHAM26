import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Opens the local SQLite database and applies migrations.
///
/// Bump [schemaVersion] and add a case to [_migrate] for every schema change.
class AppDatabase {
  static const schemaVersion = 8;

  static Future<Database> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), 'civinex.db');
    return openDatabase(
      dbPath,
      version: schemaVersion,
      // Each in-memory database (used by tests) must be independent.
      singleInstance: dbPath != inMemoryDatabasePath,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, v) => _migrate(db, 0, v),
      onUpgrade: _migrate,
    );
  }

  static Future<void> _migrate(Database db, int from, int to) async {
    for (var v = from + 1; v <= to; v++) {
      switch (v) {
        case 1:
          await _createV1(db);
        case 2:
          await _createV2(db);
        case 3:
          await _createV3(db);
        case 4:
          await _createV4(db);
        case 5:
          await _createV5(db);
        case 6:
          await _createV6(db);
        case 7:
          await _createV7(db);
        case 8:
          await _createV8(db);
      }
    }
  }

  static Future<void> _createV1(Database db) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE departments (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        role TEXT NOT NULL CHECK (role IN ('citizen','officer','admin')),
        department_id TEXT REFERENCES departments(id),
        is_demo INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE incidents (
        id TEXT PRIMARY KEY,
        reporter_id TEXT NOT NULL REFERENCES users(id),
        category TEXT NOT NULL,
        description TEXT NOT NULL,
        location_text TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        photo_path TEXT,
        people_affected INTEGER NOT NULL DEFAULT 1,
        safety_risk INTEGER NOT NULL DEFAULT 0,
        priority TEXT NOT NULL,
        priority_score INTEGER NOT NULL,
        priority_reasons TEXT NOT NULL,
        ai_provider TEXT NOT NULL,
        ai_explanation TEXT NOT NULL,
        needs_human_review INTEGER NOT NULL DEFAULT 0,
        department_id TEXT NOT NULL REFERENCES departments(id),
        assigned_officer_id TEXT REFERENCES users(id),
        status TEXT NOT NULL,
        resolution_note TEXT,
        rejection_reason TEXT,
        duplicate_of_id TEXT REFERENCES incidents(id),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_demo INTEGER NOT NULL DEFAULT 0,
        data_source TEXT NOT NULL
      )''');
    batch.execute('CREATE INDEX idx_inc_reporter ON incidents(reporter_id)');
    batch.execute('CREATE INDEX idx_inc_dept_status ON incidents(department_id, status)');
    batch.execute('CREATE INDEX idx_inc_created ON incidents(created_at)');
    batch.execute('''
      CREATE TABLE status_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        incident_id TEXT NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
        status TEXT NOT NULL,
        actor_id TEXT NOT NULL REFERENCES users(id),
        note TEXT,
        created_at INTEGER NOT NULL
      )''');
    batch.execute('CREATE INDEX idx_hist_incident ON status_history(incident_id)');
    batch.execute('''
      CREATE TABLE notifications (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        incident_id TEXT REFERENCES incidents(id) ON DELETE CASCADE,
        is_read INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )''');
    batch.execute('CREATE INDEX idx_notif_user ON notifications(user_id, is_read)');
    batch.execute('''
      CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        actor_id TEXT NOT NULL REFERENCES users(id),
        action TEXT NOT NULL,
        detail TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    await batch.commit(noResult: true);
  }

  /// v2: FloodGuard readings and a small key/value settings table.
  static Future<void> _createV2(Database db) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE rainfall_readings (
        id TEXT PRIMARY KEY,
        station_name TEXT NOT NULL,
        rainfall_mm REAL NOT NULL CHECK (rainfall_mm >= 0),
        water_level_cm REAL,
        recorded_at INTEGER NOT NULL,
        source TEXT NOT NULL CHECK (source IN ('manual','simulated')),
        entered_by TEXT NOT NULL REFERENCES users(id),
        is_demo INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )''');
    batch.execute('CREATE INDEX idx_rain_time ON rainfall_readings(recorded_at)');
    batch.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
    await batch.commit(noResult: true);
  }

  /// v3: RoadVision classification details and before/after repair photos.
  static Future<void> _createV3(Database db) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE road_details (
        incident_id TEXT PRIMARY KEY REFERENCES incidents(id) ON DELETE CASCADE,
        damage_type TEXT NOT NULL,
        damage_source TEXT NOT NULL,
        severity TEXT NOT NULL,
        severity_source TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE repair_photos (
        id TEXT PRIMARY KEY,
        incident_id TEXT NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
        kind TEXT NOT NULL CHECK (kind IN ('before','after')),
        path TEXT NOT NULL,
        added_by TEXT NOT NULL REFERENCES users(id),
        created_at INTEGER NOT NULL
      )''');
    batch.execute('CREATE INDEX idx_repair_photos_inc ON repair_photos(incident_id)');
    await batch.commit(noResult: true);
  }

  /// v4 (AF-21): confidence, image findings, SLA/escalation, assignments,
  /// supporters, feedback, internal notes and resource requests.
  static Future<void> _createV4(Database db) async {
    final batch = db.batch();
    for (final col in [
      'ai_confidence REAL',
      'ai_alternatives TEXT',
      'image_label TEXT',
      'image_confidence REAL',
      'image_source TEXT',
      'image_verified INTEGER NOT NULL DEFAULT 0',
      'sla_due_at INTEGER',
      'escalated INTEGER NOT NULL DEFAULT 0',
      'escalation_level INTEGER NOT NULL DEFAULT 0',
      'priority_overridden INTEGER NOT NULL DEFAULT 0',
      'dup_verified INTEGER NOT NULL DEFAULT 1',
      'dup_score REAL',
    ]) {
      batch.execute('ALTER TABLE incidents ADD COLUMN $col');
    }
    batch.execute('CREATE INDEX idx_inc_parent ON incidents(duplicate_of_id)');
    batch.execute('''
      CREATE TABLE incident_supporters (
        incident_id TEXT NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (incident_id, user_id)
      )''');
    batch.execute('''
      CREATE TABLE assignments (
        id TEXT PRIMARY KEY,
        incident_id TEXT NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
        officer_id TEXT NOT NULL REFERENCES users(id),
        assigned_by TEXT NOT NULL REFERENCES users(id),
        state TEXT NOT NULL CHECK (state IN ('pending','accepted','rejected','reassigned')),
        reason TEXT,
        created_at INTEGER NOT NULL,
        responded_at INTEGER
      )''');
    batch.execute('CREATE INDEX idx_assign_inc ON assignments(incident_id)');
    batch.execute('CREATE INDEX idx_assign_officer ON assignments(officer_id, state)');
    batch.execute('''
      CREATE TABLE resource_requests (
        id TEXT PRIMARY KEY,
        incident_id TEXT NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
        requested_by TEXT NOT NULL REFERENCES users(id),
        description TEXT NOT NULL,
        state TEXT NOT NULL CHECK (state IN ('open','approved','declined')),
        decision_note TEXT,
        created_at INTEGER NOT NULL,
        decided_at INTEGER
      )''');
    batch.execute('''
      CREATE TABLE feedback (
        id TEXT PRIMARY KEY,
        incident_id TEXT NOT NULL UNIQUE REFERENCES incidents(id) ON DELETE CASCADE,
        user_id TEXT NOT NULL REFERENCES users(id),
        rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
        comment TEXT,
        confirmed_fixed INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE internal_notes (
        id TEXT PRIMARY KEY,
        incident_id TEXT NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
        author_id TEXT NOT NULL REFERENCES users(id),
        body TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    await batch.commit(noResult: true);
  }

  /// v5: city updates board. Staff type updates in by hand today; `source`
  /// already allows 'feed' so an automatic importer can write the same rows later.
  static Future<void> _createV5(Database db) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE city_updates (
        id TEXT PRIMARY KEY,
        module TEXT NOT NULL,
        kind TEXT NOT NULL CHECK (kind IN ('reading','advisory','alert','info')),
        title TEXT NOT NULL,
        detail TEXT,
        area TEXT,
        value REAL,
        unit TEXT,
        source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual','feed')),
        entered_by TEXT NOT NULL REFERENCES users(id),
        is_demo INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        expires_at INTEGER
      )''');
    batch.execute('CREATE INDEX idx_city_updates_time ON city_updates(created_at)');
    await batch.commit(noResult: true);
  }

  /// v8: where a report's photo came from and what the checks found.
  static Future<void> _createV8(Database db) async {
    final batch = db.batch();
    batch.execute('ALTER TABLE incidents ADD COLUMN photo_origin TEXT');
    batch.execute('ALTER TABLE incidents ADD COLUMN photo_check TEXT');
    await batch.commit(noResult: true);
  }

  /// v7: sync bookkeeping, city services directory, and the per-officer
  /// "may manage services" allotment given by an administrator.
  static Future<void> _createV7(Database db) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE sync_state (
        key TEXT PRIMARY KEY,
        hash TEXT NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE service_places (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        city TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        hours TEXT,
        latitude REAL,
        longitude REAL,
        removed INTEGER NOT NULL DEFAULT 0,
        added_by TEXT NOT NULL REFERENCES users(id),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )''');
    batch.execute('CREATE INDEX idx_service_city ON service_places(city, kind)');
    batch.execute('ALTER TABLE users ADD COLUMN services_allowed INTEGER NOT NULL DEFAULT 0');
    await batch.commit(noResult: true);
  }

  /// v6: personal document vault. Only metadata lives here; the files are
  /// stored encrypted on disk and the key is held by the Android Keystore.
  static Future<void> _createV6(Database db) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE vault_documents (
        id TEXT PRIMARY KEY,
        owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        category TEXT NOT NULL,
        title TEXT NOT NULL,
        original_name TEXT NOT NULL,
        mime TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        file_name TEXT NOT NULL,
        expires_at INTEGER,
        reminded_level INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )''');
    batch.execute('CREATE INDEX idx_vault_owner ON vault_documents(owner_id, category)');
    batch.execute('''
      CREATE TABLE vault_settings (
        user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
        pin_hash TEXT,
        pin_salt TEXT,
        use_biometric INTEGER NOT NULL DEFAULT 0,
        failed_attempts INTEGER NOT NULL DEFAULT 0,
        locked_until INTEGER,
        created_at INTEGER NOT NULL
      )''');
    await batch.commit(noResult: true);
  }
}
