import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../services/analytics.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';

/// Staff analytics. Uses the same permission-filtered incident list as every
/// other screen, so officers only see numbers for their own department.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider)!;
    if (!user.isStaff) {
      return const EmptyState(icon: Icons.lock_outline, message: 'Staff only.');
    }
    final async = ref.watch(incidentsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(incidentsProvider)),
      data: (all) {
        if (all.isEmpty) {
          return const EmptyState(
              icon: Icons.insights_outlined,
              message: 'No data yet. Charts appear once reports are submitted.');
        }
        final r = Analytics.compute(all, now: DateTime.now());
        final scheme = Theme.of(context).colorScheme;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Analytics', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            user.role == UserRole.admin
                ? 'All departments'
                : Departments.nameOf(user.departmentId ?? ''),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _Tile('Open', '${r.open}')),
            Expanded(child: _Tile('Resolved', '${r.resolved}')),
            Expanded(child: _Tile('Waiting 7d+', '${r.overdueOpen}')),
          ]),
          const SizedBox(height: 16),
          _Section(
            title: 'Summary',
            note: 'Generated from fixed rules on your data. Not an AI model.',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final line in r.summary)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $line'),
                ),
            ]),
          ),
          _Section(
            title: 'Open reports by priority',
            child: Column(children: [
              for (final p in Priority.values.reversed)
                _BarRow(
                  label: p.label,
                  value: r.openByPriority[p] ?? 0,
                  max: _max(r.openByPriority.values),
                  color: AppTheme.priorityColor(p.name),
                ),
            ]),
          ),
          _Section(
            title: 'Reports per day (last ${Analytics.trendDays} days)',
            child: _Trend(counts: r.dailyCreated, color: scheme.secondary, now: DateTime.now()),
          ),
          _Section(
            title: 'By category (all reports)',
            child: Column(children: [
              for (final e in (r.byCategory.entries.toList()
                    ..sort((a, b) => b.value.compareTo(a.value))))
                _BarRow(
                  label: e.key.label,
                  value: e.value,
                  max: _max(r.byCategory.values),
                  color: scheme.primary,
                ),
            ]),
          ),
          _Section(
            title: 'Department workload',
            child: Column(children: [
              for (final e in (r.byDepartment.entries.toList()
                    ..sort((a, b) => b.value.open.compareTo(a.value.open))))
                _BarRow(
                  label: Departments.nameOf(e.key),
                  value: e.value.open,
                  max: _max(r.byDepartment.values.map((d) => d.open)),
                  color: scheme.tertiary,
                  suffix: '${e.value.open} open · ${e.value.resolved} resolved',
                ),
            ]),
          ),
        ]);
      },
    );
  }

  static int _max(Iterable<int> v) {
    final m = v.isEmpty ? 0 : v.reduce((a, b) => a > b ? a : b);
    return m == 0 ? 1 : m;
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(label, style: const TextStyle(fontSize: 12)),
          ]),
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.note});
  final String title;
  final String? note;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (note != null) Text(note!, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            child,
          ]),
        ),
      );
}

/// Horizontal bar with the number always printed next to it, so the chart
/// never depends on colour alone.
class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
    this.suffix,
  });
  final String label;
  final int value, max;
  final Color color;
  final String? suffix;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Semantics(
          label: '$label: ${suffix ?? value}',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
              Text(suffix ?? '$value', style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 2),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value / max,
                minHeight: 8,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
          ]),
        ),
      );
}

class _Trend extends StatelessWidget {
  const _Trend({required this.counts, required this.color, required this.now});
  final List<int> counts;
  final Color color;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final max = counts.reduce((a, b) => a > b ? a : b);
    const chartHeight = 100.0;
    return Semantics(
      label: 'Reports per day for the last ${counts.length} days, '
          '${counts.fold<int>(0, (a, b) => a + b)} in total',
      child: Column(children: [
        SizedBox(
          height: chartHeight + 18,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var n = 0; n < counts.length; n++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text(counts[n] == 0 ? '' : '${counts[n]}',
                        style: const TextStyle(fontSize: 10)),
                    Container(
                      height: max == 0 ? 2 : (counts[n] / max) * chartHeight + 2,
                      decoration: BoxDecoration(
                        color: counts[n] == 0 ? color.withValues(alpha: 0.25) : color,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_label(now.subtract(Duration(days: counts.length - 1))),
              style: const TextStyle(fontSize: 11)),
          const Text('today', style: TextStyle(fontSize: 11)),
        ]),
      ]),
    );
  }

  static String _label(DateTime d) => '${d.day}/${d.month}';
}
