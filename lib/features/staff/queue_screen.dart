import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';
import '../floodguard/floodguard_screen.dart';
import '../incidents/incident_detail_screen.dart';
import '../modules/modules_screen.dart';
import '../notifications/notifications_screen.dart';
import '../officer/my_cases_screen.dart';
import '../roadvision/road_vision_screen.dart';

/// Priority queue and simple overview for officers and administrators.
class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider)!;
    final async = ref.watch(queueProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(queueProvider)),
      data: (queue) {
        final byPriority = {
          for (final p in Priority.values) p: queue.where((i) => i.priority == p).length,
        };
        return ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            Expanded(
              child: Text(
                user.role == UserRole.admin
                    ? 'City overview'
                    : Departments.nameOf(user.departmentId ?? ''),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (user.role == UserRole.admin || user.departmentId == Departments.roads)
              IconButton(
                tooltip: 'RoadVision',
                icon: const Icon(Icons.add_road),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('RoadVision')),
                        body: const RoadVisionScreen()))),
              ),
            IconButton(
              tooltip: 'City modules',
              icon: const Icon(Icons.apps_outlined),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const ModulesScreen())),
            ),
            IconButton(
              tooltip: 'My assigned cases',
              icon: Badge(
                isLabelVisible: (ref.watch(myCasesProvider).valueOrNull?.length ?? 0) > 0,
                label: Text('${ref.watch(myCasesProvider).valueOrNull?.length ?? 0}'),
                child: const Icon(Icons.assignment_ind_outlined),
              ),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const MyCasesScreen())),
            ),
            IconButton(
              tooltip: 'FloodGuard',
              icon: const Icon(Icons.water_drop_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('FloodGuard')),
                      body: const FloodGuardScreen()))),
            ),
            IconButton(
              tooltip: 'Notifications',
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Notifications')),
                      body: const NotificationsScreen()))),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final p in Priority.values.reversed)
              Chip(label: Text('${p.label}: ${byPriority[p]}')),
          ]),
          Text('${queue.length} open · sorted by priority score',
              style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          if (queue.isEmpty)
            const EmptyState(
                icon: Icons.task_alt, message: 'No open reports. Nothing needs attention.')
          else
            for (final i in queue)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                IncidentCard(
                  incident: i,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => IncidentDetailScreen(incidentId: i.id))),
                ),
                if (i.needsHumanReview)
                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 4),
                    child: Text('Needs human review', style: TextStyle(fontSize: 12)),
                  ),
              ]),
        ]);
      },
    );
  }
}
