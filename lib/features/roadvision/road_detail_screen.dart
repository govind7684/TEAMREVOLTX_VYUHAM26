import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/security/permissions.dart';
import '../../domain/models/road.dart';
import '../../domain/models/user.dart';
import '../../services/ai/ai_provider.dart';
import '../../services/photo_store.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';
import '../incidents/incident_detail_screen.dart';
import 'road_vision_screen.dart' show severityColor;

class _RoadDetailData {
  const _RoadDetailData(this.report, this.photos, this.duplicates, this.officers);
  final RoadReport report;
  final List<RepairPhoto> photos;
  final List<DuplicateMatch> duplicates;
  final List<AppUser> officers;
}

final _roadDetailProvider =
    FutureProvider.family<_RoadDetailData, String>((ref, id) async {
  ref.watch(refreshTickProvider);
  final user = ref.watch(sessionProvider)!;
  final repo = ref.watch(roadRepositoryProvider);
  final report = await repo.getReport(user, id);
  final photos = await repo.photos(user, id);
  final dupes = report.isOpen && report.incident.duplicateOfId == null
      ? await repo.duplicateSuggestions(user, id)
      : <DuplicateMatch>[];
  final officers = await ref
      .watch(authRepositoryProvider)
      .officersInDepartment(user, report.incident.departmentId);
  return _RoadDetailData(report, photos, dupes, officers);
});

class RoadDetailScreen extends ConsumerWidget {
  const RoadDetailScreen({super.key, required this.incidentId});
  final String incidentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider)!;
    final async = ref.watch(_roadDetailProvider(incidentId));
    return Scaffold(
      appBar: AppBar(title: Text(incidentId)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
            error: e, onRetry: () => ref.invalidate(_roadDetailProvider(incidentId))),
        data: (d) {
          final r = d.report;
          final i = r.incident;
          final canManage = Permissions.canManage(user, i) && i.status.isOpen;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(
                  child: Text(i.locationText, style: Theme.of(context).textTheme.titleLarge)),
              PriorityChip(i.priority),
            ]),
            Text('${i.status.label} · reported ${formatDate(i.createdAt)}'),
            if (i.duplicateOfId != null)
              Text('Closed as a duplicate of ${i.duplicateOfId}.',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(i.description),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => IncidentDetailScreen(incidentId: i.id))),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Status, notes and timeline'),
            ),
            const SizedBox(height: 8),
            _Classification(report: r, canManage: canManage),
            _Assignment(report: r, officers: d.officers, canManage: canManage),
            if (d.duplicates.isNotEmpty || r.linkedDuplicates > 0)
              _Duplicates(report: r, matches: d.duplicates, canManage: canManage),
            _Photos(report: r, photos: d.photos, canManage: canManage),
          ]);
        },
      ),
    );
  }
}

Future<void> _guard(BuildContext context, WidgetRef ref, Future<void> Function() fn,
    String ok) async {
  try {
    await fn();
    ref.read(refreshTickProvider.notifier).state++;
    if (context.mounted) showMessage(context, ok);
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e), error: true);
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            ...children,
          ]),
        ),
      );
}

class _Classification extends ConsumerWidget {
  const _Classification({required this.report, required this.canManage});
  final RoadReport report;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = report.details;
    return _Card(title: 'Classification', children: [
      Text('Damage type: ${d.type.label}'),
      Text('Source: ${RoadSource.label(d.typeSource)}', style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 4),
      Row(children: [
        const Text('Severity: '),
        Text(d.severity.label,
            style: TextStyle(color: severityColor(d.severity), fontWeight: FontWeight.w700)),
      ]),
      Text('Source: ${RoadSource.label(d.severitySource)}',
          style: const TextStyle(fontSize: 12)),
      if (d.type == RoadDamageType.uncertain)
        const Text('Uncertain: please check on site or from the photo.',
            style: TextStyle(fontWeight: FontWeight.w600)),
      if (canManage)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => _edit(context, ref),
            child: const Text('Change type or severity'),
          ),
        ),
    ]);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    RoadDamageType? type;
    RoadSeverity? sev;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Change classification'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<RoadDamageType?>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Damage type'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Keep current')),
                  for (final t in RoadDamageType.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (v) => set(() => type = v),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<RoadSeverity?>(
                initialValue: sev,
                decoration: const InputDecoration(labelText: 'Severity'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Keep current')),
                  for (final s in RoadSeverity.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) => set(() => sev = v),
              ),
              const SizedBox(height: 8),
              TextField(
                  controller: reason,
                  decoration: const InputDecoration(labelText: 'Reason (logged)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    final reasonText = reason.text;
    disposeLater([reason]);
    if (ok != true || !context.mounted) return;
    await _guard(
      context,
      ref,
      () => ref.read(roadRepositoryProvider).updateClassification(
            actor: ref.read(sessionProvider)!,
            incidentId: report.incident.id,
            type: type,
            severity: sev,
            reason: reasonText,
          ),
      'Classification updated and logged.',
    );
  }
}

class _Assignment extends ConsumerStatefulWidget {
  const _Assignment({required this.report, required this.officers, required this.canManage});
  final RoadReport report;
  final List<AppUser> officers;
  final bool canManage;
  @override
  ConsumerState<_Assignment> createState() => _AssignmentState();
}

class _AssignmentState extends ConsumerState<_Assignment> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    return _Card(title: 'Repair assignment', children: [
      Text(r.assigneeName == null ? 'Not assigned yet.' : 'Assigned to ${r.assigneeName}.'),
      Text('Progress: ${r.incident.status.label}', style: const TextStyle(fontSize: 12)),
      if (widget.canManage) ...[
        const SizedBox(height: 8),
        if (widget.officers.isEmpty)
          const Text('No active officers in this department to assign.')
        else
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _selected,
                decoration: const InputDecoration(labelText: 'Assign to officer'),
                items: [
                  for (final o in widget.officers)
                    DropdownMenuItem(value: o.id, child: Text(o.name)),
                ],
                onChanged: (v) => setState(() => _selected = v),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _selected == null
                  ? null
                  : () => _guard(
                        context,
                        ref,
                        () => ref.read(roadRepositoryProvider).assignOfficer(
                              actor: ref.read(sessionProvider)!,
                              incidentId: r.incident.id,
                              officerId: _selected!,
                            ),
                        'Assigned.',
                      ),
              child: const Text('Assign'),
            ),
          ]),
      ],
    ]);
  }
}

class _Duplicates extends ConsumerWidget {
  const _Duplicates({required this.report, required this.matches, required this.canManage});
  final RoadReport report;
  final List<DuplicateMatch> matches;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Card(title: 'Possible duplicates', children: [
      if (report.linkedDuplicates > 0)
        Text('${report.linkedDuplicates} other report(s) were closed as duplicates of this one.'),
      if (matches.isNotEmpty)
        const Text(
          'Suggested from category, distance, age and text overlap. These are suggestions; '
          'you decide.',
          style: TextStyle(fontSize: 12),
        ),
      for (final m in matches)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${m.incident.id} · ${m.incident.status.label}'),
          subtitle: Text('${m.incident.locationText}\n${m.reasons.join(', ')}'),
          isThreeLine: true,
          trailing: canManage
              ? TextButton(
                  onPressed: () => _link(context, ref, m.incident.id),
                  child: const Text('Close this as duplicate'),
                )
              : null,
        ),
    ]);
  }

  Future<void> _link(BuildContext context, WidgetRef ref, String keepId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Close as duplicate?'),
        content: Text(
            'This report (${report.incident.id}) will be closed as a duplicate of $keepId '
            'and the reporter will be told. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Close it')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _guard(
      context,
      ref,
      () => ref.read(roadRepositoryProvider).markDuplicate(
            actor: ref.read(sessionProvider)!,
            incidentId: report.incident.id,
            ofId: keepId,
          ),
      'Closed as a duplicate of $keepId.',
    );
  }
}

class _Photos extends ConsumerWidget {
  const _Photos({required this.report, required this.photos, required this.canManage});
  final RoadReport report;
  final List<RepairPhoto> photos;
  final bool canManage;

  Widget _strip(List<String> paths) {
    if (paths.isEmpty) return const Text('None yet.');
    return SizedBox(
      height: 110,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final p in paths)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: File(p).existsSync()
                  ? Image.file(File(p), height: 110, width: 140, fit: BoxFit.cover)
                  : Container(
                      height: 110,
                      width: 140,
                      color: Colors.black12,
                      alignment: Alignment.center,
                      child: const Text('File missing', style: TextStyle(fontSize: 12)),
                    ),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final before = [
      if (report.incident.photoPath != null) report.incident.photoPath!,
      ...photos.where((p) => p.kind == PhotoKind.before).map((p) => p.path),
    ];
    final after = photos.where((p) => p.kind == PhotoKind.after).map((p) => p.path).toList();
    return _Card(title: 'Before and after photos', children: [
      const Text('Photos are stored on this device only and are not analysed.',
          style: TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
      const Text('Before', style: TextStyle(fontWeight: FontWeight.w600)),
      _strip(before),
      const SizedBox(height: 8),
      const Text('After repair', style: TextStyle(fontWeight: FontWeight.w600)),
      _strip(after),
      if (report.isOpen && after.isEmpty)
        const Text('No after photo yet. Add one when the repair is done.',
            style: TextStyle(fontSize: 12)),
      if (canManage || (report.incident.status == IncidentStatus.resolved)) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
            onPressed: () => _add(context, ref, PhotoKind.before),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Add before photo'),
          ),
          OutlinedButton.icon(
            onPressed: () => _add(context, ref, PhotoKind.after),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Add after photo'),
          ),
        ]),
      ],
    ]);
  }

  Future<void> _add(BuildContext context, WidgetRef ref, PhotoKind kind) async {
    StoredPhoto? stored;
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      stored = await const PhotoStore().save(picked.path, folder: 'repair_photos');
    } catch (_) {
      if (context.mounted) {
        showMessage(context, 'Could not read that photo. Try another one.', error: true);
      }
      return;
    }
    if (!context.mounted) return;
    final saved = stored;
    try {
      await ref.read(roadRepositoryProvider).addRepairPhoto(
            actor: ref.read(sessionProvider)!,
            incidentId: report.incident.id,
            kind: kind,
            path: saved.path,
            sizeBytes: saved.sizeBytes,
          );
      ref.read(refreshTickProvider.notifier).state++;
      if (context.mounted) showMessage(context, '${kind.name} photo added.');
    } catch (e) {
      // Do not leave an unreferenced copy behind when validation fails.
      await const PhotoStore().deleteQuietly(saved.path);
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }
}
