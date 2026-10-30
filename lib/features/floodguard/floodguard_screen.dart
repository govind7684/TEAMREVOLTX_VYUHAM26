import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exceptions.dart';
import '../../domain/models/flood.dart';
import '../../domain/models/user.dart';
import '../../services/flood_risk.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';
import '../incidents/incident_detail_screen.dart';

Color _levelColor(FloodRiskLevel l) => switch (l) {
      FloodRiskLevel.normal => const Color(0xFF2E7D32),
      FloodRiskLevel.watch => const Color(0xFF9A7B00),
      FloodRiskLevel.warning => const Color(0xFFD9730D),
      FloodRiskLevel.severe => const Color(0xFFB3261E),
    };

/// Show inside a Scaffold (it has no app bar of its own).
class FloodGuardScreen extends ConsumerWidget {
  const FloodGuardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider)!;
    final async = ref.watch(floodDataProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(floodDataProvider)),
      data: (d) => ListView(padding: const EdgeInsets.all(16), children: [
        Text('FloodGuard', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        _RiskCard(a: d.assessment),
        const SizedBox(height: 12),
        _Actions(level: d.assessment.level),
        const SizedBox(height: 12),
        _Readings(readings: d.readings),
        if (user.isStaff) ...[
          const SizedBox(height: 12),
          _StaffControls(user: user, config: d.config),
        ],
        const SizedBox(height: 12),
        const _FloodReports(),
        const SizedBox(height: 12),
        const Text(
          'Shelters and emergency contacts are not listed because this app has no '
          'verified local data for them. Use official sources.',
          style: TextStyle(fontSize: 12),
        ),
      ]),
    );
  }
}

class _RiskCard extends StatelessWidget {
  const _RiskCard({required this.a});
  final FloodRiskAssessment a;

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(a.level);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.water_drop, color: color),
            const SizedBox(width: 8),
            Text('Estimated flood risk: ${a.level.label}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color)),
          ]),
          const SizedBox(height: 4),
          const Text(
            'Unvalidated, rule-based estimate from a few numbers. It is not a forecast or an '
            'official warning, and rainfall alone cannot predict flooding.',
            style: TextStyle(fontSize: 12),
          ),
          if (a.usesSimulatedData)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(6),
              color: Colors.amber.shade200,
              child: const Text('SIMULATED DATA is included in this estimate.',
                  style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 8),
          for (final r in a.reasons)
            Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('• $r')),
        ]),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.level});
  final FloodRiskLevel level;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Suggested actions', style: Theme.of(context).textTheme.titleMedium),
            const Text('Suggestions for staff to consider. Not instructions.',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            for (final s in FloodRiskEstimator.recommendedActions(level)) Text('• $s'),
          ]),
        ),
      );
}

class _Readings extends StatelessWidget {
  const _Readings({required this.readings});
  final List<RainfallReading> readings;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Recent readings', style: Theme.of(context).textTheme.titleMedium),
            const Text(
              'Rain is millimetres in the hour ending at the time shown. '
              'The estimate assumes one reading per hour per station.',
              style: TextStyle(fontSize: 12),
            ),
            if (readings.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No readings yet.'),
              ),
            for (final r in readings.take(10))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${r.stationName}: ${r.rainfallMm.toStringAsFixed(1)} mm'
                    '${r.waterLevelCm == null ? '' : ' · ${r.waterLevelCm!.toStringAsFixed(0)} cm'}'),
                subtitle: Text(formatDate(r.recordedAt)),
                trailing: Chip(
                  label: Text(r.source == ReadingSource.simulated ? 'SIMULATED' : 'MANUAL',
                      style: const TextStyle(fontSize: 10)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ]),
        ),
      );
}

class _StaffControls extends ConsumerWidget {
  const _StaffControls({required this.user, required this.config});
  final AppUser user;
  final FloodConfig config;

  Future<void> _run<T>(BuildContext context, WidgetRef ref, Future<T> Function() fn, String ok) async {
    try {
      await fn();
      ref.read(refreshTickProvider.notifier).state++;
      if (context.mounted) showMessage(context, ok);
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Staff tools', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => _addReading(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Enter a reading'),
          ),
          if (user.role == UserRole.admin) ...[
            const Divider(height: 24),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton(
                onPressed: () => _editThresholds(context, ref),
                child: const Text('Edit thresholds'),
              ),
            ]),
            const Text(
              'Default thresholds are illustrative placeholders, not calibrated for any location.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ]),
      ),
    );
  }

  Future<void> _addReading(BuildContext context, WidgetRef ref) async {
    final station = TextEditingController();
    final rain = TextEditingController();
    final level = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Enter a reading'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: station,
                decoration: const InputDecoration(labelText: 'Station or place name')),
            const SizedBox(height: 8),
            TextField(
              controller: rain,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Rain in the last hour (mm)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: level,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Water level, cm (optional)'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    final stationText = station.text;
    final rainText = rain.text.trim();
    final levelText = level.text.trim();
    station.dispose();
    rain.dispose();
    level.dispose();
    if (ok != true || !context.mounted) return;

    final rainValue = double.tryParse(rainText);
    final levelValue = levelText.isEmpty ? null : double.tryParse(levelText);
    if (rainValue == null || (levelText.isNotEmpty && levelValue == null)) {
      showMessage(context, 'Rainfall and water level must be numbers.', error: true);
      return;
    }
    await _run(
      context,
      ref,
      () => ref.read(floodRepositoryProvider).addReading(
            actor: user,
            stationName: stationText,
            rainfallMm: rainValue,
            waterLevelCm: levelValue,
          ),
      'Reading saved.',
    );
  }

  Future<void> _editThresholds(BuildContext context, WidgetRef ref) async {
    final fields = <String, TextEditingController>{
      'Rain watch (mm / 3 h)': TextEditingController(text: '${config.rainWatch}'),
      'Rain warning (mm / 3 h)': TextEditingController(text: '${config.rainWarning}'),
      'Rain severe (mm / 3 h)': TextEditingController(text: '${config.rainSevere}'),
      'Level watch (cm)': TextEditingController(text: '${config.levelWatch}'),
      'Level warning (cm)': TextEditingController(text: '${config.levelWarning}'),
      'Level severe (cm)': TextEditingController(text: '${config.levelSevere}'),
      'Reports in 24 h to raise one step': TextEditingController(text: '${config.reportBump}'),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Thresholds'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in fields.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: e.value,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: e.key),
                ),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    final v = fields.values.map((c) => c.text.trim()).toList();
    for (final c in fields.values) {
      c.dispose();
    }
    if (ok != true || !context.mounted) return;

    final nums = v.map(double.tryParse).toList();
    if (nums.any((n) => n == null)) {
      showMessage(context, 'All thresholds must be numbers.', error: true);
      return;
    }
    final cfg = FloodConfig(
      rainWatch: nums[0]!,
      rainWarning: nums[1]!,
      rainSevere: nums[2]!,
      levelWatch: nums[3]!,
      levelWarning: nums[4]!,
      levelSevere: nums[5]!,
      reportBump: nums[6]!.toInt(),
    );
    await _run(context, ref, () => ref.read(floodRepositoryProvider).saveConfig(user, cfg),
        'Thresholds saved and logged.');
  }
}

/// Open flooding and blocked-drain reports the signed-in user may see.
class _FloodReports extends ConsumerWidget {
  const _FloodReports();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(incidentsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Flooding and drain reports', style: Theme.of(context).textTheme.titleMedium),
          const Text(
            'Only reports you are allowed to see. Locations come from report text; this '
            'app has no road network data to work out affected roads.',
            style: TextStyle(fontSize: 12),
          ),
          async.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
            error: (e, _) =>
                ErrorState(error: e, onRetry: () => ref.invalidate(incidentsProvider)),
            data: (all) {
              final list = all
                  .where((i) =>
                      i.status.isOpen &&
                      (i.category == IncidentCategory.flooding ||
                          i.category == IncidentCategory.blockedDrain))
                  .toList();
              if (list.isEmpty) {
                return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No open flooding or drain reports visible to you.'));
              }
              return Column(children: [
                for (final i in list)
                  IncidentCard(
                    incident: i,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => IncidentDetailScreen(incidentId: i.id))),
                  ),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}
