import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exceptions.dart';
import '../../domain/models/incident.dart';
import '../../domain/models/workflow.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';
import '../incidents/incident_detail_screen.dart';

final myCasesProvider =
    FutureProvider<List<({Assignment assignment, Incident incident})>>((ref) async {
  ref.watch(refreshTickProvider);
  final u = ref.watch(sessionProvider);
  if (u == null || !u.isStaff) return [];
  return ref.watch(workflowRepositoryProvider).myAssignments(u);
});

/// Officer view of cases assigned to them: accept or reject, deadlines.
class MyCasesScreen extends ConsumerWidget {
  const MyCasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('My assigned cases')),
      body: ref.watch(myCasesProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(myCasesProvider)),
            data: (list) {
              if (list.isEmpty) {
                return const EmptyState(
                    icon: Icons.task_alt, message: 'No cases are assigned to you right now.');
              }
              return ListView(padding: const EdgeInsets.all(16), children: [
                for (final e in list)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text('${e.incident.id} · ${e.incident.category.label}',
                              style: Theme.of(context).textTheme.titleMedium)),
                          PriorityChip(e.incident.priority),
                        ]),
                        Text(e.incident.locationText),
                        Text(e.incident.slaDueAt == null
                            ? 'No deadline'
                            : 'Due ${formatDate(e.incident.slaDueAt!)}'
                                '${e.incident.isOverdue(now) ? ' · OVERDUE' : ''}'),
                        Text('Assigned by ${e.assignment.assignedByName} · ${e.assignment.state.name}',
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, children: [
                          if (e.assignment.state == AssignmentState.pending) ...[
                            FilledButton(
                              onPressed: () => _answer(context, ref, e.incident.id, true),
                              child: const Text('Accept'),
                            ),
                            OutlinedButton(
                              onPressed: () => _answer(context, ref, e.incident.id, false),
                              child: const Text('Reject…'),
                            ),
                          ],
                          TextButton(
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => IncidentDetailScreen(incidentId: e.incident.id))),
                            child: const Text('Open'),
                          ),
                        ]),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
    );
  }

  Future<void> _answer(BuildContext context, WidgetRef ref, String id, bool accept) async {
    String? reason;
    if (!accept) {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Reject assignment'),
          content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Reason (required)')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Reject')),
          ],
        ),
      );
      reason = c.text;
      c.dispose();
      if (ok != true) return;
    }
    try {
      await ref.read(workflowRepositoryProvider).respond(
          officer: ref.read(sessionProvider)!, incidentId: id, accept: accept, reason: reason);
      ref.read(refreshTickProvider.notifier).state++;
      if (context.mounted) showMessage(context, accept ? 'Accepted.' : 'Rejected and returned for reassignment.');
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }
}
