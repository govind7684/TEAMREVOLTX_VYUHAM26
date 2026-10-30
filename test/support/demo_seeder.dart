import 'package:sqflite/sqflite.dart';

import 'package:civinex_ai/core/constants/enums.dart';
import 'package:civinex_ai/core/security/password_hasher.dart';
import 'package:civinex_ai/data/database/reference_data.dart';

/// TEST FIXTURES ONLY. The app itself has no demo mode and ships no sample data.
/// Accounts and records used by the automated tests.
class DemoAccounts {
  static const password = 'Demo1234';
  static const citizen = 'citizen@demo.civinex';
  static const officer = 'officer@demo.civinex';
  static const admin = 'admin@demo.civinex';
  static const roadsOfficer = 'roads@demo.civinex';
}

class DemoSeeder {
  static Future<void> ensureDepartments(Database db) => ReferenceData.ensureDepartments(db);

  /// True while the sample reports exist. After [clearDemo] this is false, so
  /// [seed] recreates everything.
  static Future<bool> hasDemoData(Database db) async {
    final r = await db
        .rawQuery("SELECT COUNT(*) c FROM incidents WHERE data_source = 'demo-sample'");
    return (r.first['c'] as int) > 0;
  }

  /// Removes demo-flagged reports, readings and demo users' notifications.
  /// Real users' data is untouched.
  ///
  /// Demo ACCOUNTS are kept (and restored by [seed]) because demo staff may
  /// have acted on real records, and those history and audit rows must keep a
  /// valid user. Audit rows are never deleted by a demo reset.
  static Future<void> clearDemo(Database db) async {
    await db.transaction((txn) async {
      await txn.delete('rainfall_readings', where: 'is_demo = 1');
      await txn.delete('city_updates', where: 'is_demo = 1');
      await txn.delete('notifications',
          where: 'user_id IN (SELECT id FROM users WHERE is_demo = 1)');
      await txn.update('incidents', {'duplicate_of_id': null},
          where: 'duplicate_of_id IN (SELECT id FROM incidents WHERE is_demo = 1)');
      // status_history, road_details, repair_photos and notifications for these
      // incidents are removed by ON DELETE CASCADE.
      await txn.delete('incidents', where: 'is_demo = 1');
    });
  }

  static Future<void> seed(Database db, {DateTime? now}) async {
    final t = now ?? DateTime.now();
    await ensureDepartments(db);
    if (await hasDemoData(db)) {
      try {
        await _sampleCityUpdates(db, t); // added in a later version; safe to repeat
      } catch (_) {
        // An old demo database without the sample staff: skip the samples.
      }
      return;
    }

    Future<void> user(String id, String name, String email, UserRole role,
        {String? dept}) async {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hash(DemoAccounts.password, salt);
      await db.insert('users', {
        'id': id,
        'name': name,
        'email': email,
        'password_hash': hash,
        'salt': salt,
        'role': role.name,
        'department_id': dept,
        'is_demo': 1,
        'is_active': 1,
        'created_at': t.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      // Restore the documented role and password if an earlier session changed them.
      await db.update(
          'users',
          {
            'name': name,
            'role': role.name,
            'department_id': dept,
            'password_hash': hash,
            'salt': salt,
            'is_active': 1,
          },
          where: 'id = ?',
          whereArgs: [id]);
    }

    await user('demo-citizen', 'Demo Citizen', DemoAccounts.citizen, UserRole.citizen);
    await user('demo-officer', 'Demo Officer (Drainage)', DemoAccounts.officer,
        UserRole.officer, dept: Departments.drainage);
    await user('demo-officer-roads', 'Demo Officer (Roads)', DemoAccounts.roadsOfficer,
        UserRole.officer, dept: Departments.roads);
    await user('demo-admin', 'Demo Administrator', DemoAccounts.admin, UserRole.admin);

    // Sample reports. Coordinates are illustrative points in Kochi/Thiruvananthapuram,
    // not real incident records.
    final samples = <_Sample>[
      _Sample('CVX-DEMO-001', IncidentCategory.flooding,
          'Heavy waterlogging on the main road, knee-deep water near the bus stop.',
          'Demo: MG Road junction, Kochi', 9.9816, 76.2999, 60, true, Priority.high, 8,
          IncidentStatus.submitted, 1),
      _Sample('CVX-DEMO-002', IncidentCategory.blockedDrain,
          'Drain blocked with plastic waste, water overflowing onto the lane.',
          'Demo: Market Road, Kochi', 9.9712, 76.2845, 25, false, Priority.medium, 5,
          IncidentStatus.assigned, 4),
      _Sample('CVX-DEMO-003', IncidentCategory.roadDamage,
          'Large pothole in the middle of the road, two-wheelers swerving around it.',
          'Demo: Statue Junction, Thiruvananthapuram', 8.5000, 76.9500, 40, false,
          Priority.medium, 5, IncidentStatus.inProgress, 6),
      _Sample('CVX-DEMO-004', IncidentCategory.streetlight,
          'Streetlight not working for a week, the lane is very dark at night.',
          'Demo: Park Lane, Thiruvananthapuram', 8.4900, 76.9400, 10, false,
          Priority.low, 2, IncidentStatus.resolved, 9),
      _Sample('CVX-DEMO-005', IncidentCategory.waste,
          'Garbage dumped beside the compound wall for several days.',
          'Demo: Canal Road, Kochi', 9.9600, 76.2700, 8, false, Priority.low, 2,
          IncidentStatus.submitted, 2),
      _Sample('CVX-DEMO-006', IncidentCategory.roadDamage,
          'Another very deep pothole at Statue Junction, a bike skidded here yesterday.',
          'Demo: Statue Junction, Thiruvananthapuram', 8.50015, 76.95005, 30, true,
          Priority.high, 8, IncidentStatus.submitted, 1),
      _Sample('CVX-DEMO-007', IncidentCategory.roadDamage,
          'Small hairline cracks on the surface near the school gate.',
          'Demo: School Road, Thiruvananthapuram', 8.5200, 76.9300, 5, false,
          Priority.low, 2, IncidentStatus.submitted, 3),
      _Sample('CVX-DEMO-008', IncidentCategory.roadDamage,
          'Fallen tree branch and debris blocking half of the road.',
          'Demo: Beach Road, Kochi', 9.9650, 76.2400, 40, false,
          Priority.medium, 5, IncidentStatus.submitted, 2),
    ];

    // Sample FloodGuard readings: clearly SIMULATED, rising over 6 hours.
    for (var h = 5; h >= 0; h--) {
      final at = t.subtract(Duration(hours: h));
      await db.insert('rainfall_readings', {
        'id': 'demo-rain-$h',
        'station_name': 'Sim Station A',
        'rainfall_mm': 6.0 + (5 - h) * 3,
        'water_level_cm': 20.0 + (5 - h) * 8,
        'recorded_at': at.millisecondsSinceEpoch,
        'source': 'simulated',
        'entered_by': 'demo-officer',
        'is_demo': 1,
        'created_at': at.millisecondsSinceEpoch,
      });
    }

    for (final s in samples) {
      final created = t.subtract(Duration(days: s.daysAgo));
      await db.insert('incidents', {
        'id': s.id,
        'reporter_id': 'demo-citizen',
        'category': s.category.name,
        'description': s.description,
        'location_text': s.location,
        'latitude': s.lat,
        'longitude': s.lng,
        'people_affected': s.people,
        'safety_risk': s.safety ? 1 : 0,
        'priority': s.priority.name,
        'priority_score': s.score,
        'priority_reasons': 'Sample data: score set by the demo seeder.',
        'ai_provider': 'demo-seed',
        'ai_explanation': 'Sample record created by the demo seeder. No AI ran.',
        'needs_human_review': 0,
        'department_id': s.category.departmentId,
        'status': s.status.name,
        'resolution_note':
            s.status == IncidentStatus.resolved ? 'Sample resolution: bulb replaced.' : null,
        'created_at': created.millisecondsSinceEpoch,
        'updated_at': created.millisecondsSinceEpoch,
        'is_demo': 1,
        'data_source': 'demo-sample',
      });
      await db.insert('status_history', {
        'incident_id': s.id,
        'status': IncidentStatus.submitted.name,
        'actor_id': 'demo-citizen',
        'note': 'Report submitted (sample)',
        'created_at': created.millisecondsSinceEpoch,
      });
    }
    await _sampleCityUpdates(db, t);
  }

  /// Labelled sample notices so the City updates board is not empty in a demo.
  /// Fixed ids plus "ignore" make this safe to run on every start.
  static Future<void> _sampleCityUpdates(Database db, DateTime t) async {
    Future<void> row(String id, String module, String kind, String title, String? detail,
        String area, double? value, String? unit, String by, int hoursAgo) {
      final at = t.subtract(Duration(hours: hoursAgo)).millisecondsSinceEpoch;
      return db.insert(
        'city_updates',
        {
          'id': id,
          'module': module,
          'kind': kind,
          'title': title,
          'detail': detail,
          'area': area,
          'value': value,
          'unit': unit,
          'source': 'manual',
          'entered_by': by,
          'is_demo': 1,
          'created_at': at,
          'expires_at': null,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await row('demo-cu-1', 'flood', 'reading', 'Sample: river gauge reading',
        'Sample figure entered by the demo officer.', 'Demo: Kochi canal', 142, 'cm',
        'demo-officer', 2);
    await row('demo-cu-2', 'flood', 'advisory', 'Sample: avoid low-lying roads tonight',
        'Sample advisory. Not a real warning.', 'Demo: Kochi', null, null, 'demo-officer', 5);
    await row('demo-cu-3', 'roads', 'info', 'Sample: resurfacing planned',
        'Sample notice about a planned road repair.', 'Demo: Statue Junction',
        null, null, 'demo-officer-roads', 20);
  }
}

class _Sample {
  _Sample(this.id, this.category, this.description, this.location, this.lat,
      this.lng, this.people, this.safety, this.priority, this.score, this.status,
      this.daysAgo);
  final String id;
  final IncidentCategory category;
  final String description, location;
  final double lat, lng;
  final int people;
  final bool safety;
  final Priority priority;
  final int score;
  final IncidentStatus status;
  final int daysAgo;
}
