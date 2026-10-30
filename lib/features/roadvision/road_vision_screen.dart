import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/road.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';
import 'road_detail_screen.dart';

Color severityColor(RoadSeverity s) => switch (s) {
      RoadSeverity.severe => const Color(0xFFB3261E),
      RoadSeverity.moderate => const Color(0xFF9A7B00),
      RoadSeverity.minor => const Color(0xFF2E7D32),
    };

/// Repair priority list for road damage. Show inside a Scaffold.
class RoadVisionScreen extends ConsumerWidget {
  const RoadVisionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider)!;
    if (!user.isStaff) {
      return const EmptyState(icon: Icons.lock_outline, message: 'Staff only.');
    }
    final async = ref.watch(roadListProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(roadListProvider)),
      data: (list) {
        final severe = list.where((r) => r.details.severity == RoadSeverity.severe).length;
        final unassigned = list.where((r) => r.incident.assignedOfficerId == null).length;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('RoadVision', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          const Text(
            'Damage type and severity come from keyword rules on the report text. '
            'Photos are stored but not analysed. Officers can change any value and '
            'changes are logged.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            Chip(label: Text('${list.length} open')),
            Chip(label: Text('$severe severe')),
            Chip(label: Text('$unassigned unassigned')),
          ]),
          const Text('Ranked by priority score, then severity, then age.',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          if (list.isEmpty)
            const EmptyState(
                icon: Icons.add_road, message: 'No open road damage reports in your scope.')
          else
            for (var n = 0; n < list.length; n++) _RoadCard(rank: n + 1, report: list[n]),
        ]);
      },
    );
  }
}

class _RoadCard extends StatelessWidget {
  const _RoadCard({required this.rank, required this.report});
  final int rank;
  final RoadReport report;

  @override
  Widget build(BuildContext context) {
    final i = report.incident;
    final d = report.details;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => RoadDetailScreen(incidentId: i.id))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 14, child: Text('$rank', style: const TextStyle(fontSize: 12))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(i.locationText, style: Theme.of(context).textTheme.titleSmall),
                Text('${i.id} · ${i.status.label}', style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 0, children: [
                  Chip(
                    label: Text(d.type.label),
                    visualDensity: VisualDensity.compact,
                  ),
                  Chip(
                    label: Text(d.severity.label,
                        style: TextStyle(color: severityColor(d.severity))),
                    side: BorderSide(color: severityColor(d.severity)),
                    visualDensity: VisualDensity.compact,
                  ),
                ]),
                Text(
                  report.assigneeName == null
                      ? 'Unassigned'
                      : 'Assigned to ${report.assigneeName}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'Photos: ${report.beforePhotos} before, ${report.afterPhotos} after'
                  '${report.linkedDuplicates > 0 ? ' · ${report.linkedDuplicates} duplicate(s) linked' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
              ]),
            ),
            Column(children: [
              PriorityChip(i.priority),
            ]),
          ]),
        ),
      ),
    );
  }
}
