import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/city_data_repository.dart';
import '../../domain/models/city_update.dart';
import '../../domain/models/user.dart';
import '../../domain/models/flood.dart';
import '../../shared/brand/brand_widgets.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';
import '../floodguard/floodguard_screen.dart';

IconData _kindIcon(UpdateKind k) => switch (k) {
      UpdateKind.reading => Icons.speed,
      UpdateKind.advisory => Icons.warning_amber_rounded,
      UpdateKind.alert => Icons.campaign,
      UpdateKind.info => Icons.info_outline,
    };

Color _kindColor(UpdateKind k) => switch (k) {
      UpdateKind.reading => const Color(0xFF3B82F6),
      UpdateKind.advisory => const Color(0xFFD9730D),
      UpdateKind.alert => AppTheme.alert,
      UpdateKind.info => const Color(0xFF8A8A92),
    };

/// Everything municipal staff have published: readings, advisories and alerts.
/// Anyone signed in can read it; staff can post. Today the numbers are typed in
/// by hand. Rows carry a source, so an automatic feed can fill the same list
/// later without changing this screen.
class CityBoardScreen extends ConsumerStatefulWidget {
  const CityBoardScreen({super.key});
  @override
  ConsumerState<CityBoardScreen> createState() => _CityBoardScreenState();
}

class _CityBoardScreenState extends ConsumerState<CityBoardScreen> {
  CityModule? _filter;

  Future<void> _post(AppUser user) async {
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PostSheet(user: user),
    );
    if (posted == true && mounted) showMessage(context, 'Update published.');
  }

  Future<void> _remove(AppUser user, CityUpdate u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove this update?'),
        content: Text(u.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(cityDataRepositoryProvider).remove(user, u.id);
      ref.read(refreshTickProvider.notifier).state++;
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider)!;
    final async = ref.watch(cityUpdatesProvider);
    final canPost = CityDataRepository.allowedModules(user).isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('City updates')),
      floatingActionButton: canPost
          ? FloatingActionButton.extended(
              onPressed: () => _post(user),
              icon: const Icon(Icons.add),
              label: const Text('Post update'),
            )
          : null,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
        const AccentBar(),
        const SizedBox(height: 10),
        Text('What the city is reporting',
            style: AppTheme.display(Theme.of(context).textTheme.headlineSmall)),
        const SizedBox(height: 6),
        const Text('Readings, advisories and alerts published by municipal staff. '
            'For now staff type these in by hand, so check the time on each one. '
            'This is not an official warning system.',
            style: TextStyle(fontSize: 13)),
        const SizedBox(height: 12),
        const _FloodStrip(),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: const Text('All'),
                selected: _filter == null,
                onSelected: (_) => setState(() => _filter = null),
              ),
            ),
            for (final m in CityModule.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(m.label),
                  selected: _filter == m,
                  onSelected: (_) => setState(() => _filter = m),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        async.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(cityUpdatesProvider)),
          data: (all) {
            final list = _filter == null ? all : all.where((u) => u.module == _filter).toList();
            if (list.isEmpty) {
              return EmptyState(
                icon: Icons.campaign_outlined,
                message: canPost
                    ? 'Nothing published yet. Tap "Post update" to add the first one.'
                    : 'Nothing published yet. Check back soon.',
              );
            }
            return Column(children: [
              for (final u in list)
                _UpdateCard(
                  u: u,
                  onRemove: user.role == UserRole.admin || (user.isStaff && u.enteredById == user.id)
                      ? () => _remove(user, u)
                      : null,
                ),
            ]);
          },
        ),
      ]),
    );
  }
}

/// One-line flood summary from the same rule-based estimate FloodGuard shows.
class _FloodStrip extends ConsumerWidget {
  const _FloodStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(floodDataProvider);
    return async.maybeWhen(
      data: (d) {
        final level = d.assessment.level;
        final color = switch (level) {
          FloodRiskLevel.normal => const Color(0xFF2E7D32),
          FloodRiskLevel.watch => const Color(0xFF9A7B00),
          FloodRiskLevel.warning => const Color(0xFFD9730D),
          FloodRiskLevel.severe => AppTheme.accent,
        };
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color, width: 1.5),
          ),
          child: ListTile(
            leading: Icon(Icons.water_drop, color: color),
            title: Text('Flood risk estimate: ${level.label}',
                style: TextStyle(color: color, fontWeight: FontWeight.w800)),
            subtitle: Text(d.readings.isEmpty
                ? 'No rainfall readings entered yet.'
                : 'Latest reading: ${d.readings.first.stationName}, '
                    '${d.readings.first.rainfallMm.toStringAsFixed(1)} mm'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('FloodGuard')),
                    body: const FloodGuardScreen()))),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({required this.u, this.onRemove});
  final CityUpdate u;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final color = _kindColor(u.kind);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 5, color: color),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(_kindIcon(u.kind), size: 18, color: color),
                  const SizedBox(width: 6),
                  Text('${u.kind.label.toUpperCase()} · ${u.module.label}',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: color)),
                  const Spacer(),
                  if (onRemove != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: onRemove,
                    ),
                ]),
                const SizedBox(height: 4),
                Text(u.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                if (u.valueText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(u.valueText!,
                        style: AppTheme.display(Theme.of(context).textTheme.titleLarge,
                            size: 22, color: color)),
                  ),
                if (u.area != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(children: [
                      Icon(Icons.place_outlined, size: 14, color: muted),
                      const SizedBox(width: 4),
                      Expanded(child: Text(u.area!, style: TextStyle(fontSize: 13, color: muted))),
                    ]),
                  ),
                if (u.detail != null)
                  Padding(padding: const EdgeInsets.only(top: 6), child: Text(u.detail!)),
                const SizedBox(height: 8),
                Text(
                  '${formatDate(u.createdAt)} · ${u.enteredByName} · ${u.source.label}'
                  '${u.expiresAt == null ? '' : '\nShown until ${formatDate(u.expiresAt!)}'}',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PostSheet extends ConsumerStatefulWidget {
  const _PostSheet({required this.user});
  final AppUser user;
  @override
  ConsumerState<_PostSheet> createState() => _PostSheetState();
}

class _PostSheetState extends ConsumerState<_PostSheet> {
  final _title = TextEditingController();
  final _detail = TextEditingController();
  final _area = TextEditingController();
  final _value = TextEditingController();
  final _unit = TextEditingController();
  late CityModule _module = CityDataRepository.allowedModules(widget.user).first;
  UpdateKind _kind = UpdateKind.reading;
  int? _hours = 24;
  String? _error;
  bool _busy = false;

  static const _validity = <(String, int?)>[
    ('6 hours', 6),
    ('24 hours', 24),
    ('3 days', 72),
    ('7 days', 168),
    ('30 days', 720),
    ('Until I remove it', null),
  ];

  @override
  void dispose() {
    _title.dispose();
    _detail.dispose();
    _area.dispose();
    _value.dispose();
    _unit.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final valueText = _value.text.trim();
    final value = valueText.isEmpty ? null : double.tryParse(valueText);
    if (valueText.isNotEmpty && value == null) {
      setState(() => _error = 'The value must be a number, for example 12.5');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(cityDataRepositoryProvider).add(
            actor: widget.user,
            module: _module,
            kind: _kind,
            title: _title.text,
            detail: _detail.text,
            area: _area.text,
            value: value,
            unit: _unit.text,
            validForHours: _hours,
          );
      ref.read(refreshTickProvider.notifier).state++;
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final modules = CityDataRepository.allowedModules(widget.user);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Post a city update',
              style: AppTheme.display(Theme.of(context).textTheme.titleLarge)),
          const SizedBox(height: 4),
          const Text('Visible to every signed-in user. Alerts also send an in-app notification.',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          DropdownButtonFormField<CityModule>(
            initialValue: _module,
            decoration: const InputDecoration(labelText: 'Service'),
            items: [for (final m in modules) DropdownMenuItem(value: m, child: Text(m.label))],
            onChanged: (v) => setState(() => _module = v ?? _module),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<UpdateKind>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [for (final k in UpdateKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
            onChanged: (v) => setState(() => _kind = v ?? _kind),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _title,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Headline', counterText: ''),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _area,
            decoration: const InputDecoration(labelText: 'Area or place (optional)'),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _value,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Value (optional)'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _unit,
                decoration: const InputDecoration(labelText: 'Unit', hintText: 'mm, cm, %'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _detail,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Details (optional)'),
          ),
          DropdownButtonFormField<int?>(
            initialValue: _hours,
            decoration: const InputDecoration(labelText: 'Show for'),
            items: [for (final v in _validity) DropdownMenuItem(value: v.$2, child: Text(v.$1))],
            onChanged: (v) => setState(() => _hours = v),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: const Icon(Icons.campaign_outlined),
              label: Text(_busy ? 'Publishing…' : 'Publish'),
            ),
          ),
        ]),
      ),
    );
  }
}
