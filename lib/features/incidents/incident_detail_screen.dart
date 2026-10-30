import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/security/permissions.dart';
import '../../domain/models/incident.dart';
import '../../domain/models/user.dart';
import '../../shared/widgets/common.dart';
import '../../services/photo_check.dart';
import '../../state/providers.dart';
import 'incident_extras.dart';

final _detailProvider =
    FutureProvider.family<(Incident, List<StatusEvent>), String>((ref, id) async {
  ref.watch(refreshTickProvider);
  final user = ref.watch(sessionProvider)!;
  final repo = ref.watch(incidentRepositoryProvider);
  final incident = await repo.getVisible(user, id);
  return (incident, await repo.history(user, id));
});

class IncidentDetailScreen extends ConsumerWidget {
  const IncidentDetailScreen({super.key, required this.incidentId});
  final String incidentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_detailProvider(incidentId));
    final user = ref.watch(sessionProvider)!;
    return Scaffold(
      appBar: AppBar(title: Text(incidentId)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
            error: e, onRetry: () => ref.invalidate(_detailProvider(incidentId))),
        data: (data) {
          final (i, history) = data;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(
                  child: Text(i.category.label,
                      style: Theme.of(context).textTheme.headlineSmall)),
              PriorityChip(i.priority),
            ]),
            Text('${i.status.label} · ${Departments.nameOf(i.departmentId)}'),
            const SizedBox(height: 12),
            Text(i.description),
            const SizedBox(height: 8),
            Text('Location: ${i.locationText}'),
            if (i.hasCoordinates)
              Text('Coordinates: ${i.latitude!.toStringAsFixed(5)}, '
                  '${i.longitude!.toStringAsFixed(5)}'),
            Text('Reported: ${formatDate(i.createdAt)}'),
            if (i.photoPath != null && File(i.photoPath!).existsSync())
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(i.photoPath!), height: 180, fit: BoxFit.cover),
                ),
              ),
            if (PhotoCheck.parse(i.photoCheck) case final pc?) ...[
              const SizedBox(height: 8),
              Card(
                color: pc.verdict == PhotoVerdict.suspicious
                    ? Theme.of(context).colorScheme.errorContainer
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Photo check: ${pc.verdict.label}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    for (final l in pc.lines) Text('• $l', style: const TextStyle(fontSize: 12)),
                    const Text('A hint for staff, not proof either way.', style: TextStyle(fontSize: 11)),
                  ]),
                ),
              ),
            ],
            if (i.rejectionReason != null) ...[
              const SizedBox(height: 8),
              Text('Rejected: ${i.rejectionReason}'),
            ],
            if (i.resolutionNote != null) ...[
              const SizedBox(height: 8),
              Text('Resolution: ${i.resolutionNote}'),
            ],
            const Divider(height: 32),
            Text('Why this priority', style: Theme.of(context).textTheme.titleMedium),
            Text('Score ${i.priorityScore}: ${i.priorityReasons}'),
            const SizedBox(height: 8),
            Text('Triage suggestion', style: Theme.of(context).textTheme.titleMedium),
            Text(i.aiExplanation),
            Text('Source: ${i.aiProvider}', style: const TextStyle(fontSize: 12)),
            if (i.needsHumanReview)
              const Text('Flagged for human review.',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            IncidentExtras(incident: i, history: history),
            const Divider(height: 32),
            Text('Timeline', style: Theme.of(context).textTheme.titleMedium),
            for (final e in history)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.circle, size: 10),
                title: Text(e.status.label),
                subtitle: Text(
                    '${formatDate(e.at)} · ${e.actorName}${e.note == null ? '' : '\n${e.note}'}'),
              ),
            if (Permissions.canCitizenModify(user, i)) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _withdraw(context, ref, user, i),
                child: const Text('Withdraw this report'),
              ),
            ],
            if (user.isStaff && Permissions.canManage(user, i) && i.status.isOpen)
              _StaffActions(incident: i),
          ]);
        },
      ),
    );
  }

  Future<void> _withdraw(BuildContext context, WidgetRef ref, AppUser user, Incident i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Withdraw report?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Withdraw')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(incidentRepositoryProvider).withdraw(user, i.id);
      ref.read(refreshTickProvider.notifier).state++;
      if (context.mounted) showMessage(context, 'Report withdrawn.');
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }
}

class _StaffActions extends ConsumerStatefulWidget {
  const _StaffActions({required this.incident});
  final Incident incident;
  @override
  ConsumerState<_StaffActions> createState() => _StaffActionsState();
}

class _StaffActionsState extends ConsumerState<_StaffActions> {
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _go(IncidentStatus to) async {
    setState(() => _busy = true);
    try {
      await ref.read(incidentRepositoryProvider).changeStatus(
            actor: ref.read(sessionProvider)!,
            incidentId: widget.incident.id,
            to: to,
            note: _note.text,
            rejectionReason: _note.text,
          );
      ref.read(refreshTickProvider.notifier).state++;
      _note.clear();
      if (mounted) showMessage(context, 'Status changed to ${to.label}.');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.incident.status;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Divider(height: 32),
      Text('Staff actions', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      TextField(
        controller: _note,
        decoration: const InputDecoration(
            labelText: 'Note (required for Resolve or Reject)'),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final to in [
          IncidentStatus.underReview,
          IncidentStatus.assigned,
          IncidentStatus.inProgress,
          IncidentStatus.resolved,
          IncidentStatus.rejected,
        ])
          if (Permissions.isValidTransition(status, to))
            FilledButton.tonal(
              onPressed: _busy ? null : () => _go(to),
              child: Text(to.label),
            ),
      ]),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: _busy ? null : () => _override(context),
        child: const Text('Override category or priority'),
      ),
    ]);
  }

  Future<void> _override(BuildContext context) async {
    IncidentCategory? cat;
    Priority? prio;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Override suggestion'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<IncidentCategory?>(
              initialValue: cat,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Keep current')),
                for (final k in IncidentCategory.values)
                  DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              onChanged: (v) => set(() => cat = v),
            ),
            DropdownButtonFormField<Priority?>(
              initialValue: prio,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Keep current')),
                for (final k in Priority.values)
                  DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              onChanged: (v) => set(() => prio = v),
            ),
            TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Reason (logged)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) {
      reason.dispose();
      return;
    }
    try {
      await ref.read(incidentRepositoryProvider).overrideSuggestion(
            actor: ref.read(sessionProvider)!,
            incidentId: widget.incident.id,
            category: cat,
            priority: prio,
            reason: reason.text,
          );
      ref.read(refreshTickProvider.notifier).state++;
      if (mounted) showMessage(this.context, 'Override saved and logged.');
    } catch (e) {
      if (mounted) showMessage(this.context, friendlyError(e), error: true);
    } finally {
      reason.dispose();
    }
  }
}
