/// Reference departments. These are generic functional units, not real
/// Kerala government bodies; rename them in the database for real use.
class Departments {
  static const roads = 'dept_roads';
  static const drainage = 'dept_drainage';
  static const sanitation = 'dept_sanitation';
  static const water = 'dept_water';
  static const electrical = 'dept_electrical';
  static const traffic = 'dept_traffic';
  static const general = 'dept_general';

  /// Mutable so departments added by an administrator show their names.
  static final names = <String, String>{
    roads: 'Roads & Infrastructure',
    drainage: 'Drainage & Flood Response',
    sanitation: 'Sanitation & Waste',
    water: 'Water Supply',
    electrical: 'Electrical & Streetlights',
    traffic: 'Traffic Management',
    general: 'General Administration',
  };

  static String nameOf(String id) => names[id] ?? id;
  static void register(String id, String name) => names[id] = name;
}

enum UserRole {
  citizen('Citizen'),
  officer('Municipal Officer'),
  admin('Administrator');

  const UserRole(this.label);
  final String label;
}

/// [baseSeverity] is 1 (minor) to 3 (potentially serious), used by the
/// priority scorer.
enum IncidentCategory {
  roadDamage('Road damage', Departments.roads, 2),
  waste('Waste & illegal dumping', Departments.sanitation, 1),
  flooding('Flooding & waterlogging', Departments.drainage, 3),
  blockedDrain('Blocked drains', Departments.drainage, 2),
  waterLeak('Water leaks & supply', Departments.water, 2),
  streetlight('Broken streetlights', Departments.electrical, 1),
  traffic('Traffic congestion', Departments.traffic, 2),
  accessibility('Accessibility barriers', Departments.roads, 2),
  environment('Environment & heat', Departments.general, 1),
  other('Other civic issues', Departments.general, 1);

  const IncidentCategory(this.label, this.departmentId, this.baseSeverity);
  final String label;
  final String departmentId;
  final int baseSeverity;
}

enum IncidentStatus {
  submitted('Submitted', true),
  underReview('Under review', true),
  assigned('Assigned', true),
  inProgress('In progress', true),
  resolved('Resolved', false),
  closed('Closed', false),
  rejected('Rejected', false),
  withdrawn('Withdrawn', false);

  const IncidentStatus(this.label, this.isOpen);
  final String label;
  final bool isOpen;
}

enum Priority {
  low('Low'),
  medium('Medium'),
  high('High'),
  critical('Critical');

  const Priority(this.label);
  final String label;
}
