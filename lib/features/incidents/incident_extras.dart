import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/security/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/incident.dart';
import '../../domain/models/road.dart';
import '../../domain/models/user.dart';
import '../../domain/models/workflow.dart';
import '../../services/ai/image_analyzer.dart';
import '../../services/ai/priority_scorer.dart';
import '../../services/photo_store.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';

class _Extras {
  const _Extras({
    required this.photos,
    required this.reporters,
    this.feedback,
    this.linked = const [],
    this.assignments = const [],
    this.notes = const [],
    this.requests = const [],
    this.officers = const [],
  });
  final List<RepairPhoto> photos;
  final int reporters;
  final FeedbackEntry? feedback;
  final List<Incident> linked;
  final List<Assignment> assignments;
  final List<InternalNote> notes;
  final List<ResourceRequest> requests;
  final List<AppUser> officers;
}

final _extrasProvider =
    FutureProvider.autoDispose.family<_Extras, String>((ref, id) async {
  ref.watch(refreshTickProvider);
  final user = ref.watch(sessionProvider)!;
  final inc = ref.watch(incidentRepositoryProvider);
  final wf = ref.watch(workflowRepositoryProvider);
  final i = await inc.getVisible(user, id);
  final photos = await wf.evidence(user, id);
  final reporters = await inc.reporterCount(i.duplicateOfId ?? i.id);
  final fb = await wf.feedbackFor(user, id);
  if (!user.isStaff || !Permissions.canManage(user, i)) {
    return _Extras(photos: photos, reporters: reporters, feedback: fb);
  }
  return _Extras(
    photos: photos,
    reporters: reporters,
    feedback: fb,
    linked: await inc.linkedReports(user, id),
    assignments: await wf.assignmentsFor(user, id),
    notes: await wf.notes(user, id),
    requests: await wf.resourceRequests(user, incidentId: id),
    officers: await ref.watch(authRepositoryProvider).officersInDepartment(user, i.departmentId),
  );
});

/// Everything added for the AF-21 workflow on the incident screen: lifecycle,
/// deadline, AI findings, duplicates, evidence, feedback and staff tools.
class IncidentExtras extends ConsumerWidget {
  const IncidentExtras({super.key, required this.incident, required this.history});
  final Incident incident;
  final List<StatusEvent> history;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider)!;
    final async = ref.watch(_extrasProvider(incident.id));
    return async.when(
      loading: () => const Padding(
          padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(_extrasProvider(incident.id))),
      data: (x) {
        final i = incident;
        final staff = user.isStaff && Permissions.canManage(user, i);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Divider(height: 32),
          _Deadline(i),
          const SizedBox(height: 12),
          _Reporters(i, x.reporters),
          const SizedBox(height: 12),
          _AiCard(i, staff: staff),
          const Divider(height: 32),
          _Lifecycle(i, history, x),
          const Divider(height: 32),
          _Evidence(i, x.photos, staff: staff && (i.status.isOpen || i.status == IncidentStatus.resolved)),
          if (user.id == i.reporterId) _FeedbackCard(i, x.feedback),
          if (staff && i.duplicateOfId != null && !i.dupVerified) _DupVerify(i),
          if (staff) ...[
            const Divider(height: 32),
            _StaffPanel(i, x, user),
          ],
        ]);
      },
    );
  }
}

String _fmt(DateTime d) => formatDate(d);

// ---------------------------------------------------------------- deadline

class _Deadline extends StatelessWidget {
  const _Deadline(this.i);
  final Incident i;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final over = i.isOverdue(now);
    return Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      const Icon(Icons.timer_outlined, size: 18),
      Text(i.slaDueAt == null
          ? 'No deadline set'
          : 'Target: ${_fmt(i.slaDueAt!)} (${Sla.label(i.priority)} for ${i.priority.label})'),
      if (over)
        Chip(
            label: const Text('Overdue'),
            visualDensity: VisualDensity.compact,
            backgroundColor: Colors.red.withValues(alpha: 0.12)),
      if (i.escalated)
        Chip(
            label: Text('Escalated L${i.escalationLevel}'),
            visualDensity: VisualDensity.compact,
            backgroundColor: Colors.orange.withValues(alpha: 0.15)),
    ]);
  }
}

class _Reporters extends StatelessWidget {
  const _Reporters(this.i, this.count);
  final Incident i;
  final int count;
  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      if (count > 1) '$count citizens report this problem.',
      if (i.duplicateOfId != null)
        'Tracked together with ${i.duplicateOfId}'
            '${i.dupVerified ? '' : ' (automatic match, waiting for staff to confirm)'}.',
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.groups_outlined, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(lines.join(' '))),
    ]);
  }
}

// ---------------------------------------------------------------- AI card

class _AiCard extends ConsumerWidget {
  const _AiCard(this.i, {required this.staff});
  final Incident i;
  final bool staff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.psychology_outlined, size: 18),
            const SizedBox(width: 8),
            Text('AI analysis', style: t.titleMedium),
          ]),
          const SizedBox(height: 8),
          if (i.aiConfidence != null) ...[
            Text('Category: ${i.category.label} · ${(i.aiConfidence! * 100).round()}% model estimate'),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: i.aiConfidence, minHeight: 6),
            if (i.aiAlternatives != null)
              Text('Also possible: ${i.aiAlternatives}', style: const TextStyle(fontSize: 12)),
          ] else
            Text('Category: ${i.category.label} · from keyword rules (no probability)'),
          const SizedBox(height: 4),
          Text(i.aiProvider == 'naive-bayes-local'
              ? 'Engine: small text model trained on this device. Its percentage is an estimate, not a measured accuracy.'
              : 'Engine: ${i.aiProvider}. Not a trained model.',
              style: const TextStyle(fontSize: 12)),
          const Divider(height: 20),
          if (i.photoPath == null)
            const Text('No photo attached.', style: TextStyle(fontSize: 12))
          else if (i.imageLabel == null)
            const Text('Photo attached; nobody has said what it shows yet.',
                style: TextStyle(fontSize: 12))
          else
            Text(
                'Photo shows: ${i.imageLabel}'
                '${i.imageConfidence == null ? '' : ' · ${(i.imageConfidence! * 100).round()}% (${i.imageSource})'}'
                ' · ${i.imageSource == ImageAnalyzer.humanSource ? 'tagged by a person' : 'model suggestion'}'
                '${i.imageVerified ? ', verified' : ', not yet verified by staff'}',
                style: const TextStyle(fontSize: 13)),
          if (staff && i.photoPath != null)
            TextButton.icon(
              onPressed: () => _verifyPhoto(context, ref),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Confirm or correct what the photo shows'),
            ),
        ]),
      ),
    );
  }

  Future<void> _verifyPhoto(BuildContext context, WidgetRef ref) async {
    final picked = await showDialog<IncidentCategory>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('The photo shows…'), children: [
        for (final e in supportedPhotoFaults.entries)
          SimpleDialogOption(onPressed: () => Navigator.pop(c, e.value), child: Text(e.key)),
      ]),
    );
    if (picked == null) return;
    try {
      await ref.read(incidentRepositoryProvider).verifyPhotoFinding(
          actor: ref.read(sessionProvider)!, incidentId: i.id, shows: picked);
      ref.read(refreshTickProvider.notifier).state++;
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }
}

// --------------------------------------------------------------- lifecycle

class _Lifecycle extends StatelessWidget {
  const _Lifecycle(this.i, this.history, this.x);
  final Incident i;
  final List<StatusEvent> history;
  final _Extras x;

  @override
  Widget build(BuildContext context) {
    bool seen(IncidentStatus s) => history.any((e) => e.status == s);
    final steps = <(String, bool, String?)>[
      ('Report submitted', true, null),
      ('AI analysis completed', true, i.aiProvider),
      ('Duplicate verification', i.duplicateOfId == null || i.dupVerified,
          i.duplicateOfId != null && !i.dupVerified ? 'waiting for staff' : null),
      ('Priority assigned', true, i.priority.label),
      ('Department selected', true, Departments.nameOf(i.departmentId)),
      ('Officer assigned', i.assignedOfficerId != null || seen(IncidentStatus.assigned), null),
      ('Work in progress', seen(IncidentStatus.inProgress) || seen(IncidentStatus.resolved), null),
      ('Resolution evidence uploaded', x.photos.any((p) => p.kind == PhotoKind.after), null),
      ('Citizen verification or feedback', x.feedback != null, null),
      ('Incident closed', i.status == IncidentStatus.closed, null),
    ];
    final firstOpen = steps.indexWhere((s) => !s.$2);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Lifecycle', style: Theme.of(context).textTheme.titleMedium),
      if (i.status == IncidentStatus.rejected || i.status == IncidentStatus.withdrawn)
        Text('This report ended as ${i.status.label.toLowerCase()}.'),
      for (var n = 0; n < steps.length; n++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Icon(
              steps[n].$2
                  ? Icons.check_circle
                  : n == firstOpen
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
              size: 18,
              color: steps[n].$2
                  ? AppTheme.accent
                  : n == firstOpen
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).disabledColor,
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Text('${n + 1}. ${steps[n].$1}${steps[n].$3 == null ? '' : ' · ${steps[n].$3}'}',
                    style: TextStyle(
                        fontWeight: n == firstOpen ? FontWeight.w600 : FontWeight.normal))),
          ]),
        ),
    ]);
  }
}

// ---------------------------------------------------------------- evidence

class _Evidence extends ConsumerWidget {
  const _Evidence(this.i, this.photos, {required this.staff});
  final Incident i;
  final List<RepairPhoto> photos;
  final bool staff;

  Future<void> _add(BuildContext context, WidgetRef ref, PhotoKind kind) async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final stored = await const PhotoStore().save(picked.path, folder: 'repair_photos');
      try {
        await ref.read(workflowRepositoryProvider).addEvidence(
            actor: ref.read(sessionProvider)!,
            incidentId: i.id,
            kind: kind,
            path: stored.path,
            sizeBytes: stored.sizeBytes);
        ref.read(refreshTickProvider.notifier).state++;
      } catch (_) {
        await const PhotoStore().deleteQuietly(stored.path);
        rethrow;
      }
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget group(String title, PhotoKind k) {
      final list = photos.where((p) => p.kind == k).toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (list.isEmpty)
          const Text('None yet', style: TextStyle(fontSize: 12))
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in list)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: File(p.path).existsSync()
                    ? Image.file(File(p.path), width: 110, height: 110, fit: BoxFit.cover,
                        semanticLabel: '$title photo by ${p.addedByName}')
                    : const SizedBox(width: 110, height: 110, child: Icon(Icons.broken_image_outlined)),
              ),
          ]),
        if (staff)
          TextButton.icon(
            onPressed: () => _add(context, ref, k),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text('Add ${k.name} photo'),
          ),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Before and after', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      group('Before repair', PhotoKind.before),
      const SizedBox(height: 8),
      group('After repair (resolution evidence)', PhotoKind.after),
    ]);
  }
}

// ---------------------------------------------------------------- feedback

class _FeedbackCard extends ConsumerStatefulWidget {
  const _FeedbackCard(this.i, this.existing);
  final Incident i;
  final FeedbackEntry? existing;
  @override
  ConsumerState<_FeedbackCard> createState() => _FeedbackCardState();
}

class _FeedbackCardState extends ConsumerState<_FeedbackCard> {
  int _rating = 0;
  final _comment = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send(bool fixed) async {
    if (_rating == 0) {
      showMessage(context, 'Choose a rating from 1 to 5 first.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(workflowRepositoryProvider).submitFeedback(
          citizen: ref.read(sessionProvider)!,
          incidentId: widget.i.id,
          rating: _rating,
          comment: _comment.text,
          confirmedFixed: fixed);
      ref.read(refreshTickProvider.notifier).state++;
      if (mounted) {
        showMessage(context, fixed ? 'Thank you. The report is closed.' : 'Thanks. We reopened it for review.');
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fb = widget.existing;
    if (fb != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text('Your feedback: ${fb.rating}/5, ${fb.confirmedFixed ? 'confirmed fixed' : 'said not fixed'}'
            '${fb.comment == null ? '' : '\n"${fb.comment}"'}'),
      );
    }
    if (widget.i.status != IncidentStatus.resolved) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Was it fixed?', style: Theme.of(context).textTheme.titleMedium),
          const Text('Your answer closes the report, or sends it back for another look.',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(spacing: 4, children: [
            for (var n = 1; n <= 5; n++)
              ChoiceChip(
                label: Text('$n ★'),
                selected: _rating == n,
                onSelected: (_) => setState(() => _rating = n),
              ),
          ]),
          TextField(
            controller: _comment,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Comment (optional)'),
          ),
          Wrap(spacing: 8, children: [
            FilledButton(onPressed: _busy ? null : () => _send(true), child: const Text('Yes, it is fixed')),
            OutlinedButton(onPressed: _busy ? null : () => _send(false), child: const Text('Not fixed')),
          ]),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------ duplicate verifying

class _DupVerify extends ConsumerWidget {
  const _DupVerify(this.i);
  final Incident i;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> go(bool confirm) async {
      try {
        await ref.read(incidentRepositoryProvider).verifyDuplicate(
            actor: ref.read(sessionProvider)!, childId: i.id, confirm: confirm);
        ref.read(refreshTickProvider.notifier).state++;
      } catch (e) {
        if (context.mounted) showMessage(context, friendlyError(e), error: true);
      }
    }

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Duplicate check', style: Theme.of(context).textTheme.titleMedium),
          Text('Matched ${i.duplicateOfId} automatically '
              '(${((i.dupScore ?? 0) * 100).round()}% similarity from category, distance and wording). '
              'This is a similarity score, not a probability.'),
          Wrap(spacing: 8, children: [
            FilledButton(onPressed: () => go(true), child: const Text('Same problem')),
            OutlinedButton(onPressed: () => go(false), child: const Text('Different problem')),
          ]),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------- staff panel

class _StaffPanel extends ConsumerStatefulWidget {
  const _StaffPanel(this.i, this.x, this.user);
  final Incident i;
  final _Extras x;
  final AppUser user;
  @override
  ConsumerState<_StaffPanel> createState() => _StaffPanelState();
}

class _StaffPanelState extends ConsumerState<_StaffPanel> {
  final _note = TextEditingController();
  String? _officer;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job, String done) async {
    try {
      await job();
      ref.read(refreshTickProvider.notifier).state++;
      if (mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<String?> _ask(String title, String label) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, maxLines: 3, decoration: InputDecoration(labelText: label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Send')),
        ],
      ),
    );
    final text = c.text;
    c.dispose();
    return ok == true ? text : null;
  }

  /// Pick the main report to merge this one into.
  Future<void> _merge(Incident i) async {
    final me = widget.user;
    final all = ref.read(incidentsProvider).valueOrNull ?? const <Incident>[];
    final candidates = all
        .where((o) =>
            o.id != i.id &&
            o.status.isOpen &&
            o.duplicateOfId == null &&
            (me.role == UserRole.admin || o.departmentId == i.departmentId))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (candidates.isEmpty) {
      showMessage(context, 'There is no other open report to merge into.', error: true);
      return;
    }
    final target = await showDialog<Incident>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Merge into which report?'),
        children: [
          SizedBox(
            width: double.maxFinite,
            height: 360,
            child: ListView(children: [
              for (final o in candidates.take(60))
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, o),
                  child: Text('${o.id}\n${o.category.label} · ${o.locationText}',
                      style: const TextStyle(fontSize: 13)),
                ),
            ]),
          ),
        ],
      ),
    );
    if (target == null || !mounted) return;
    final why = await _ask('Why merge ${i.id} into ${target.id}?', 'Note (optional)');
    if (why == null) return;
    await _run(
        () => ref
            .read(workflowRepositoryProvider)
            .mergeReports(actor: me, childId: i.id, parentId: target.id, note: why),
        'Merged. They are now tracked together.');
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.i, x = widget.x, me = widget.user;
    final wf = ref.read(workflowRepositoryProvider);
    final open = i.status.isOpen;
    final mine = i.assignedOfficerId == me.id;
    final pending = x.assignments.any((a) => a.officerId == me.id && a.state == AssignmentState.pending);
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Assignment', style: t.titleMedium),
      if (x.assignments.isEmpty) const Text('Nobody assigned yet.'),
      for (final a in x.assignments)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(switch (a.state) {
            AssignmentState.pending => Icons.hourglass_empty,
            AssignmentState.accepted => Icons.check_circle_outline,
            AssignmentState.rejected => Icons.cancel_outlined,
            AssignmentState.reassigned => Icons.swap_horiz,
          }),
          title: Text('${a.officerName} · ${a.state.name}'),
          subtitle: Text('by ${a.assignedByName}, ${_fmt(a.createdAt)}${a.reason == null ? '' : '\n${a.reason}'}'),
        ),
      if (open && pending && mine)
        Wrap(spacing: 8, children: [
          FilledButton(
            onPressed: () => _run(
                () => wf.respond(officer: me, incidentId: i.id, accept: true), 'Assignment accepted.'),
            child: const Text('Accept assignment'),
          ),
          OutlinedButton(
            onPressed: () async {
              final why = await _ask('Reject assignment', 'Reason (required)');
              if (why == null) return;
              await _run(() => wf.respond(officer: me, incidentId: i.id, accept: false, reason: why),
                  'Assignment rejected and sent back.');
            },
            child: const Text('Reject with reason'),
          ),
        ]),
      if (open && !i.isLinkedChild) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: x.officers.any((o) => o.id == _officer) ? _officer : null,
              decoration: const InputDecoration(labelText: 'Assign or reassign to'),
              items: [for (final o in x.officers) DropdownMenuItem(value: o.id, child: Text(o.name))],
              onChanged: (v) => setState(() => _officer = v),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _officer == null
                ? null
                : () => _run(() => wf.assign(actor: me, incidentId: i.id, officerId: _officer!), 'Assigned.'),
            child: const Text('Assign'),
          ),
        ]),
        TextButton.icon(
          onPressed: () => _run(() async {
            final o = await wf.autoAssign(me, i.id);
            if (context.mounted) showMessage(context, 'Assigned to ${o.name} (fewest open cases).');
          }, 'Done.'),
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Auto-assign to least-loaded officer'),
        ),
      ],
      if (me.role == UserRole.admin && open)
        TextButton.icon(
          onPressed: () async {
            final depts = await wf.listDepartments();
            if (!context.mounted) return;
            final d = await showDialog<String>(
              context: context,
              builder: (c) => SimpleDialog(title: const Text('Send to department'), children: [
                for (final e in depts)
                  SimpleDialogOption(onPressed: () => Navigator.pop(c, e.id), child: Text(e.name)),
              ]),
            );
            if (d == null || d == i.departmentId) return;
            final why = await _ask('Why re-route?', 'Reason (required)');
            if (why == null) return;
            await _run(
                () => wf.reassignDepartment(admin: me, incidentId: i.id, departmentId: d, reason: why),
                'Re-routed.');
          },
          icon: const Icon(Icons.alt_route),
          label: const Text('Re-route to another department'),
        ),
      if (i.isLinkedChild)
        Card(
          child: ListTile(
            leading: const Icon(Icons.link),
            title: Text('Linked to ${i.duplicateOfId}'),
            subtitle: Text(i.dupVerified
                ? 'Tracked together with the main report.'
                : 'Awaiting staff confirmation that it is the same problem.'),
            trailing: PopupMenuButton<String>(
              onSelected: (v) => _run(
                  () => v == 'confirm'
                      ? wf.confirmDuplicate(actor: me, childId: i.id)
                      : wf.unlinkDuplicate(actor: me, childId: i.id),
                  v == 'confirm' ? 'Duplicate confirmed.' : 'Unlinked.'),
              itemBuilder: (_) => [
                if (!i.dupVerified) const PopupMenuItem(value: 'confirm', child: Text('Confirm duplicate')),
                const PopupMenuItem(value: 'unlink', child: Text('Unlink')),
              ],
            ),
          ),
        ),
      if (open && !i.isLinkedChild)
        TextButton.icon(
          onPressed: () => _merge(i),
          icon: const Icon(Icons.merge_type),
          label: const Text('Merge into another report'),
        ),
      if (x.linked.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Linked duplicate reports (${x.linked.length})', style: t.titleMedium),
        for (final c in x.linked)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.link),
            title: Text(c.id),
            subtitle: Text('${c.status.label} · ${c.dupVerified ? 'confirmed' : 'awaiting confirmation'}'),
            trailing: PopupMenuButton<String>(
              onSelected: (v) => _run(
                  () => v == 'confirm'
                      ? wf.confirmDuplicate(actor: me, childId: c.id)
                      : wf.unlinkDuplicate(actor: me, childId: c.id),
                  v == 'confirm' ? 'Duplicate confirmed.' : 'Unlinked.'),
              itemBuilder: (_) => [
                if (!c.dupVerified) const PopupMenuItem(value: 'confirm', child: Text('Confirm duplicate')),
                const PopupMenuItem(value: 'unlink', child: Text('Unlink')),
              ],
            ),
          ),
      ],
      if (open) ...[
        const SizedBox(height: 12),
        Text('Support tools', style: t.titleMedium),
        Wrap(spacing: 8, runSpacing: 4, children: [
          OutlinedButton.icon(
            onPressed: () async {
              final txt = await _ask('Request resources', 'What is needed? (crew, material, budget)');
              if (txt == null) return;
              await _run(() => wf.requestResources(me, i.id, txt), 'Request sent to administrators.');
            },
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Request resources'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final txt = await _ask('Escalate case', 'Why is this unresolved?');
              if (txt == null) return;
              await _run(() => wf.escalate(me, i.id, txt), 'Escalated.');
            },
            icon: const Icon(Icons.trending_up),
            label: const Text('Escalate'),
          ),
        ]),
      ],
      for (final r in x.requests)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text(r.description),
          subtitle: Text('${r.requestedByName} · ${r.state.name}${r.decisionNote == null ? '' : ' · ${r.decisionNote}'}'),
          trailing: me.role == UserRole.admin && r.state == ResourceState.open
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Approve',
                    icon: const Icon(Icons.check),
                    onPressed: () => _run(() => wf.decideResources(me, r.id, true, 'Approved'), 'Approved.'),
                  ),
                  IconButton(
                    tooltip: 'Decline',
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      final why = await _ask('Decline request', 'Reason');
                      if (why == null) return;
                      await _run(() => wf.decideResources(me, r.id, false, why), 'Declined.');
                    },
                  ),
                ])
              : null,
        ),
      const SizedBox(height: 12),
      Text('Internal notes (never shown to citizens)', style: t.titleMedium),
      Row(children: [
        Expanded(child: TextField(controller: _note, decoration: const InputDecoration(labelText: 'Add a note'))),
        IconButton(
          tooltip: 'Save note',
          icon: const Icon(Icons.send),
          onPressed: () => _run(() async {
            await wf.addNote(me, i.id, _note.text);
            _note.clear();
          }, 'Note saved.'),
        ),
      ]),
      for (final n in x.notes)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(n.body),
          subtitle: Text('${n.authorName} · ${_fmt(n.createdAt)}'),
        ),
    ]);
  }
}
