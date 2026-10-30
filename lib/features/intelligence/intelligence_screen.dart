import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/intelligence_repository.dart';
import '../../services/intel/performance.dart';
import '../../services/intel/recurrence.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';
import '../analytics/analytics_screen.dart';
import '../incidents/incident_detail_screen.dart';
import '../map/incident_map_screen.dart';

/// Staff intelligence hub. Everything here is computed from the reports in the
/// local database; nothing is live city data and nothing is made up.
class IntelligenceScreen extends ConsumerWidget {
  const IntelligenceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider)!;
    if (!user.isStaff) {
      return const EmptyState(icon: Icons.lock_outline, message: 'Staff only.');
    }
    return DefaultTabController(
      length: 6,
      child: Column(children: [
        const TabBar(isScrollable: true, tabs: [
          Tab(text: 'Today'),
          Tab(text: 'Overview'),
          Tab(text: 'Departments'),
          Tab(text: 'Hotspots'),
          Tab(text: 'Recurring'),
          Tab(text: 'Overdue & export'),
        ]),
        Expanded(
          child: TabBarView(children: [
            const _Today(),
            const AnalyticsScreen(),
            const _Departments(),
            const IncidentMapScreen(initialMode: MapMode.heat, showTitle: false),
            const _Recurring(),
            _Overdue(user.role == UserRole.admin),
          ]),
        ),
      ]),
    );
  }
}

Widget _async(WidgetRef ref, Widget Function(IntelSnapshot s) build) {
  return ref.watch(intelProvider).when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(intelProvider)),
        data: build,
      );
}

class _Today extends ConsumerWidget {
  const _Today();
  @override
  Widget build(BuildContext context, WidgetRef ref) => _async(ref, (s) {
        final maint = ref.watch(maintenanceProvider).valueOrNull;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('City situation summary', style: Theme.of(context).textTheme.headlineSmall),
          Text('Generated ${formatDate(s.now)}', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final l in s.summary)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('• $l')),
                const Divider(),
                const Text(DailySummary.method, style: TextStyle(fontSize: 12)),
              ]),
            ),
          ),
          if (maint != null && maint.changedAnything) ...[
            const SizedBox(height: 8),
            Text('Automatic housekeeping just now: ${maint.text}', style: const TextStyle(fontSize: 12)),
          ],
          const SizedBox(height: 16),
          Text('Maintenance insights', style: Theme.of(context).textTheme.titleMedium),
          const Text(
              'Only statistics over past reports. No forecasting model is trained in this app, '
              'so none of these is a prediction by AI.',
              style: TextStyle(fontSize: 12)),
          if (s.insights.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Not enough history yet for trends. This fills in as reports accumulate.'),
            ),
          for (final i in s.insights)
            Card(
              child: ListTile(
                leading: Icon(i.kind == InsightKind.statisticalTrend
                    ? Icons.show_chart
                    : Icons.event_repeat_outlined),
                title: Text(i.title),
                subtitle: Text('${i.detail}\n${i.kindLabel}'),
                isThreeLine: true,
              ),
            ),
        ]);
      });
}

class _Departments extends ConsumerWidget {
  const _Departments();
  @override
  Widget build(BuildContext context, WidgetRef ref) => _async(ref, (s) {
        if (s.departments.isEmpty) {
          return const EmptyState(icon: Icons.apartment_outlined, message: 'No reports yet.');
        }
        String hrs(double? h) => h == null
            ? 'n/a'
            : h >= 48
                ? '${(h / 24).toStringAsFixed(1)} days'
                : '${h.toStringAsFixed(1)} h';
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Department performance', style: Theme.of(context).textTheme.headlineSmall),
          const Text('Response = report to first assignment. Resolution = report to resolved. '
              'Linked duplicates count once.', style: TextStyle(fontSize: 12)),
          for (final d in s.departments)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(Departments.nameOf(d.departmentId), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('${d.total} reports · ${d.open} open · ${d.resolved} resolved · '
                      '${d.overdue} overdue · ${d.escalated} escalated'),
                  Text('Average response: ${hrs(d.avgResponseHours)} · average resolution: ${hrs(d.avgResolutionHours)}'),
                  const SizedBox(height: 6),
                  _Bar('Resolved on time', d.slaCompliance),
                  _Bar('Citizen rating', d.avgRating == null ? null : d.avgRating! / 5,
                      note: d.avgRating == null ? 'no feedback yet' : '${d.avgRating!.toStringAsFixed(1)} / 5 (${d.ratings})'),
                  _Bar('Confirmed fixed', d.fixedConfirmedShare),
                ]),
              ),
            ),
        ]);
      });
}

class _Bar extends StatelessWidget {
  const _Bar(this.label, this.value, {this.note});
  final String label;
  final double? value;
  final String? note;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontSize: 12))),
          Expanded(
              child: LinearProgressIndicator(value: value, minHeight: 8, color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(4))),
          SizedBox(
              width: 80,
              child: Text(note ?? (value == null ? 'n/a' : '${(value! * 100).round()}%'),
                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
        ]),
      );
}

class _Recurring extends ConsumerWidget {
  const _Recurring();
  @override
  Widget build(BuildContext context, WidgetRef ref) => _async(ref, (s) {
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Recurring faults', style: Theme.of(context).textTheme.headlineSmall),
          const Text('Places with three or more reports of the same kind in 180 days, or a repeat '
              'after a fix. A fault that keeps returning usually needs a lasting repair.',
              style: TextStyle(fontSize: 12)),
          if (s.recurring.isEmpty)
            const EmptyState(icon: Icons.verified_outlined, message: 'No recurring faults detected.'),
          for (final r in s.recurring)
            Card(
              child: ListTile(
                leading: const Icon(Icons.repeat),
                title: Text('${r.category.label} · ${r.locationText}'),
                subtitle: Text('${r.reports} reports since ${formatDate(r.firstAt)}'
                    '${r.fixedBefore > 0 ? ' · came back after ${r.fixedBefore} fix${r.fixedBefore == 1 ? '' : 'es'}' : ''}'
                    '${r.meanIntervalDays == null ? '' : ' · about one every ${r.meanIntervalDays!.toStringAsFixed(0)} days'}'),
                isThreeLine: true,
              ),
            ),
          const SizedBox(height: 12),
          Text('Busiest areas right now', style: Theme.of(context).textTheme.titleMedium),
          for (final c in s.clusters.where((c) => c.count >= 2).take(5))
            ListTile(
              leading: CircleAvatar(child: Text('${c.count}')),
              title: Text('${c.dominantCategory.label} near ${c.items.first.locationText}'),
              subtitle: const Text('open reports within 250 m'),
            ),
        ]);
      });
}

class _Overdue extends ConsumerWidget {
  const _Overdue(this.isAdmin);
  final bool isAdmin;

  Future<void> _export(BuildContext context, WidgetRef ref, bool perf) async {
    final repo = ref.read(intelligenceRepositoryProvider);
    final me = ref.read(sessionProvider)!;
    try {
      final csv = perf ? await repo.exportPerformanceCsv(me) : await repo.exportIncidentsCsv(me);
      final dir = await getApplicationDocumentsDirectory();
      final ex = Directory(p.join(dir.path, 'exports'));
      await ex.create(recursive: true);
      final name = '${perf ? 'department_performance' : 'incidents'}_'
          '${DateTime.now().toIso8601String().substring(0, 10)}.csv';
      final f = File(p.join(ex.path, name));
      await f.writeAsString(csv);
      await Clipboard.setData(ClipboardData(text: csv));
      if (context.mounted) {
        showMessage(context, 'Saved to ${f.path} and copied to the clipboard.');
      }
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => _async(ref, (s) {
        final over = s.overdue..sort((a, b) => a.slaDueAt!.compareTo(b.slaDueAt!));
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Downloadable reports', style: Theme.of(context).textTheme.headlineSmall),
          const Text('CSV files hold operational fields only: no reporter names and no free text. '
              'Each export is written to the audit log.', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: () => _export(context, ref, false),
              icon: const Icon(Icons.download),
              label: const Text('Incidents (CSV)'),
            ),
            OutlinedButton.icon(
              onPressed: () => _export(context, ref, true),
              icon: const Icon(Icons.download),
              label: const Text('Department performance (CSV)'),
            ),
          ]),
          const Divider(height: 32),
          Row(children: [
            Expanded(child: Text('Overdue cases (${over.length})', style: Theme.of(context).textTheme.titleLarge)),
            TextButton.icon(
              onPressed: () async {
                final r = await ref.read(workflowRepositoryProvider).runMaintenance(ref.read(sessionProvider)!);
                ref.read(refreshTickProvider.notifier).state++;
                if (context.mounted) showMessage(context, r.changedAnything ? r.text : 'Nothing needed changing.');
              },
              icon: const Icon(Icons.rule),
              label: const Text('Run SLA check'),
            ),
          ]),
          if (over.isEmpty)
            const EmptyState(icon: Icons.check_circle_outline, message: 'Nothing is past its deadline.'),
          for (final i in over)
            Card(
              child: ListTile(
                leading: Icon(Icons.warning_amber_rounded, color: AppTheme.priorityColor(i.priority.name)),
                title: Text('${i.id} · ${i.category.label}'),
                subtitle: Text('${Departments.nameOf(i.departmentId)} · due ${formatDate(i.slaDueAt!)}'
                    '${i.escalated ? ' · escalated L${i.escalationLevel}' : ''}'),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => IncidentDetailScreen(incidentId: i.id))),
              ),
            ),
        ]);
      });
}
