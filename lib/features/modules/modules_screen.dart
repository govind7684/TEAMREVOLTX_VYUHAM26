import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../domain/models/incident.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';
import '../floodguard/floodguard_screen.dart';
import '../incidents/incident_detail_screen.dart';
import '../roadvision/road_vision_screen.dart';

/// One city service. Every module reads the SAME incident table through the
/// SAME repository, filtered by category, so nothing is duplicated.
class ModuleSpec {
  const ModuleSpec(this.name, this.icon, this.summary, this.limits, this.categories,
      {this.custom, this.filter});
  final String name, summary, limits;
  final IconData icon;
  final List<IncidentCategory> categories;
  final bool Function(Incident)? filter;
  final Widget Function(WidgetRef ref)? custom;

  bool matches(Incident i) => filter != null ? filter!(i) : categories.contains(i.category);
}

final modules = <ModuleSpec>[
  ModuleSpec('FloodGuard', Icons.water_drop_outlined, 'Flooding and drainage monitoring.',
      'Risk level is a threshold estimate from typed-in readings, not a forecast.',
      [IncidentCategory.flooding, IncidentCategory.blockedDrain],
      custom: (_) => const FloodGuardScreen()),
  ModuleSpec('RoadVision', Icons.add_road, 'Road damage and pothole management.',
      'Reads report text only; photos are not analysed automatically.',
      [IncidentCategory.roadDamage],
      custom: (_) => const RoadVisionScreen()),
  ModuleSpec('TrafficMind', Icons.traffic_outlined, 'Traffic infrastructure reports.',
      'No live traffic feed is connected. This lists citizen reports about signals, junctions and congestion.',
      [IncidentCategory.traffic]),
  ModuleSpec('WasteWise', Icons.delete_outline, 'Waste management and illegal dumping.',
      'No bin sensors are connected. Based on citizen reports only.', [IncidentCategory.waste]),
  ModuleSpec('AquaSense', Icons.water_outlined, 'Water supply and leakage.',
      'No flow or pressure sensors are connected. Based on citizen reports only.',
      [IncidentCategory.waterLeak]),
  ModuleSpec('LumenCity', Icons.lightbulb_outline, 'Streetlight management.',
      'No lamp telemetry is connected. Based on citizen reports only.',
      [IncidentCategory.streetlight]),
  ModuleSpec('Emeroute', Icons.emergency_outlined,
      'Reports that carry a safety risk, are critical, or have been escalated.',
      'This is NOT an emergency dispatch system and holds no emergency phone numbers. '
      'In an emergency call your official emergency services.',
      [],
      filter: _urgent),
  ModuleSpec('AccessCity', Icons.accessible_forward, 'Accessibility barriers in public spaces.',
      'Based on citizen reports only; no audit data about buildings or footpaths is loaded.',
      [IncidentCategory.accessibility]),
  ModuleSpec('CoolCity', Icons.thermostat, 'Environmental issues and urban heat.',
      'No heat or air-quality sensors are connected. Based on citizen reports only.',
      [IncidentCategory.environment]),
];

bool _urgent(Incident i) =>
    i.safetyRisk || i.priority == Priority.critical || (i.escalated && i.status.isOpen);

class ModulesScreen extends ConsumerWidget {
  const ModulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(incidentsProvider);
    final all = async.valueOrNull ?? const <Incident>[];
    return Scaffold(
      appBar: AppBar(title: const Text('City modules')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Nine services, one shared incident database. Each module is a filtered view '
            'of the same reports, so a report is never entered twice.'),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 700 ? 3 : 2;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.35,
            children: [
              for (final m in modules)
                _Tile(
                  m,
                  all.where((i) => i.status.isOpen && i.duplicateOfId == null && m.matches(i)).length,
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => ModuleScreen(spec: m))),
                ),
            ],
          );
        }),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.m, this.open, {required this.onTap});
  final ModuleSpec m;
  final int open;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(m.icon, size: 28, color: Theme.of(context).colorScheme.secondary),
              const Spacer(),
              Text(m.name, style: Theme.of(context).textTheme.titleMedium),
              Text('$open open', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      );
}

class ModuleScreen extends ConsumerWidget {
  const ModuleScreen({super.key, required this.spec});
  final ModuleSpec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider)!;
    // Staff-only specialist screens; citizens get the generic list.
    final custom = spec.custom;
    final canUseCustom = custom != null &&
        (spec.name == 'FloodGuard' ||
            (user.isStaff &&
                (user.role == UserRole.admin || user.departmentId == Departments.roads)));
    final async = ref.watch(incidentsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(spec.name)),
      body: canUseCustom
          ? custom(ref)
          : async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(incidentsProvider)),
              data: (all) {
                final list = all.where(spec.matches).toList();
                final open = list.where((i) => i.status.isOpen).length;
                return ListView(padding: const EdgeInsets.all(16), children: [
                  Text(spec.summary, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(spec.limits, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  Text('${list.length} report${list.length == 1 ? '' : 's'} · $open open',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  if (list.isEmpty)
                    const EmptyState(icon: Icons.inbox_outlined, message: 'No reports in this module yet.')
                  else
                    for (final i in list)
                      IncidentCard(
                        incident: i,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => IncidentDetailScreen(incidentId: i.id))),
                      ),
                  if (!user.isStaff) ...[
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                        ref.read(navIndexProvider.notifier).state = 1;
                      },
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: const Text('Report an issue'),
                    ),
                  ],
                ]);
              },
            ),
    );
  }
}
