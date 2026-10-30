import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/incident.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';
import '../floodguard/floodguard_screen.dart';
import '../incidents/incident_detail_screen.dart';
import '../modules/modules_screen.dart';
import '../officer/my_cases_screen.dart';
import '../roadvision/road_vision_screen.dart';
import '../staff/queue_screen.dart';

/// Administrator overview. Every number is counted from the stored reports; with
/// no reports everything reads 0 and an empty-state message is shown.
class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(incidentsProvider);
    final depts = {for (final d in ref.watch(departmentsProvider).valueOrNull ?? const []) d.id: d.name};
    final user = ref.watch(sessionProvider)!;
    void push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    Widget scaffolded(String t, Widget b) => Scaffold(appBar: AppBar(title: Text(t)), body: b);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(incidentsProvider)),
      data: (all) {
        final now = DateTime.now();
        final open = all.where((i) => i.status.isOpen).toList();
        final pending = all
            .where((i) => i.status == IncidentStatus.submitted || i.status == IncidentStatus.underReview)
            .length;
        final critical = open.where((i) => i.priority == Priority.critical).toList();
        final resolved = all
            .where((i) => i.status == IncidentStatus.resolved || i.status == IncidentStatus.closed)
            .length;
        final overdue = open.where((i) => i.slaDueAt != null && i.slaDueAt!.isBefore(now)).toList();
        final byDept = <String, int>{};
        for (final i in all) {
          byDept[i.departmentId] = (byDept[i.departmentId] ?? 0) + 1;
        }
        final maxDept = byDept.values.fold<int>(1, (a, b) => b > a ? b : a);
        final deptRows = byDept.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Dashboard', style: Theme.of(context).textTheme.headlineSmall),
          Text('Signed in as ${user.name}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.9,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              _Kpi('Total complaints', '${all.length}', Icons.assignment_outlined),
              _Kpi('Pending', '$pending', Icons.hourglass_empty),
              _Kpi('Critical (open)', '${critical.length}', Icons.warning_amber_rounded,
                  color: critical.isEmpty ? null : AppTheme.alert),
              _Kpi('Resolved', '$resolved', Icons.check_circle_outline),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(Icons.timer_off_outlined,
                  color: overdue.isEmpty ? null : AppTheme.ember),
              title: Text('${overdue.length} overdue'),
              subtitle: const Text('Open complaints past their deadline'),
            ),
          ),
          const SizedBox(height: 8),
          const _RoutingCard(),
          if (ref.watch(assistServiceProvider).isConfigured)
            _BriefingCard(stats: {
              'total': all.length,
              'pending': pending,
              'critical': critical.length,
              'overdue': overdue.length,
              'resolved': resolved,
              'byDepartment': {
                for (final e in deptRows) (depts[e.key] ?? Departments.nameOf(e.key)): e.value
              },
              'byCategory': {
                for (final c in IncidentCategory.values)
                  if (all.any((i) => i.category == c))
                    c.label: all.where((i) => i.category == c).length
              },
            }),
          const SizedBox(height: 8),
          Text('Complaints by department', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (all.isEmpty)
            const EmptyState(
                icon: Icons.inbox_outlined,
                message: 'No complaints have been received yet. Statistics appear here as citizens report issues.')
          else
            for (final e in deptRows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(depts[e.key] ?? Departments.nameOf(e.key))),
                    Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: e.value / maxDept, minHeight: 8),
                  ),
                ]),
              ),
          if (critical.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Critical incidents', style: Theme.of(context).textTheme.titleMedium),
            for (final Incident i in critical.take(5))
              IncidentCard(
                  incident: i, onTap: () => push(IncidentDetailScreen(incidentId: i.id))),
          ],
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ActionChip(
                avatar: const Icon(Icons.priority_high, size: 18),
                label: const Text('Priority queue'),
                onPressed: () => push(scaffolded('Priority queue', const QueueScreen()))),
            ActionChip(
                avatar: const Icon(Icons.assignment_ind_outlined, size: 18),
                label: const Text('My cases'),
                onPressed: () => push(const MyCasesScreen())),
            ActionChip(
                avatar: const Icon(Icons.add_road, size: 18),
                label: const Text('RoadVision'),
                onPressed: () => push(scaffolded('RoadVision', const RoadVisionScreen()))),
            ActionChip(
                avatar: const Icon(Icons.water_drop_outlined, size: 18),
                label: const Text('FloodGuard'),
                onPressed: () => push(scaffolded('FloodGuard', const FloodGuardScreen()))),
            ActionChip(
                avatar: const Icon(Icons.apps_outlined, size: 18),
                label: const Text('City services'),
                onPressed: () => push(const ModulesScreen())),
          ]),
        ]);
      },
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.icon, {this.color});
  final String label, value;
  final IconData icon;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(icon, color: c, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: color)),
              Text(label, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}


/// Asks Claude (through the laptop server) for a short briefing. Only counts and
/// category/department names leave the phone, never names or locations.
class _BriefingCard extends ConsumerStatefulWidget {
  const _BriefingCard({required this.stats});
  final Map<String, Object?> stats;
  @override
  ConsumerState<_BriefingCard> createState() => _BriefingCardState();
}

class _BriefingCardState extends ConsumerState<_BriefingCard> {
  String? _text;
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      final t = await ref.read(assistServiceProvider).briefing(widget.stats);
      if (mounted) setState(() => _text = t);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome_outlined, size: 18),
            const SizedBox(width: 8),
            const Expanded(
                child: Text('AI briefing (Claude)', style: TextStyle(fontWeight: FontWeight.w700))),
            TextButton(onPressed: _busy ? null : _run, child: Text(_text == null ? 'Generate' : 'Refresh')),
          ]),
          if (_busy) const LinearProgressIndicator(),
          if (_text != null) ...[
            Text(_text!),
            const SizedBox(height: 4),
            const Text('Written by an AI model from the counts above; check against the data.',
                style: TextStyle(fontSize: 11)),
          ],
        ]),
      ),
    );
  }
}


/// Switch for automatic routing: new reports go to the officer of the right
/// department who has the fewest open cases. Works while an administrator's
/// phone is open.
final _routingOnProvider = FutureProvider.autoDispose<bool>(
    (ref) => ref.watch(workflowRepositoryProvider).routingEnabled());

class _RoutingCard extends ConsumerWidget {
  const _RoutingCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(_routingOnProvider).valueOrNull ?? true;
    return Card(
      child: SwitchListTile(
        secondary: const Icon(Icons.alt_route),
        title: const Text('Automatic routing'),
        subtitle: Text(on
            ? 'New reports go to the officer of the right department with the fewest open cases. '
                'Works while an administrator phone is open. You can still reassign.'
            : 'Off. Assign reports yourself from the queue.'),
        value: on,
        onChanged: (v) async {
          try {
            await ref
                .read(workflowRepositoryProvider)
                .setRoutingEnabled(ref.read(sessionProvider)!, v);
            ref.invalidate(_routingOnProvider);
            ref.read(refreshTickProvider.notifier).state++;
          } catch (e) {
            if (context.mounted) showMessage(context, friendlyError(e), error: true);
          }
        },
      ),
    );
  }
}
