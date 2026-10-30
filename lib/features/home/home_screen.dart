import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/incident.dart';
import '../notifications/notifications_screen.dart';
import '../../shared/brand/brand_widgets.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';
import '../cityboard/city_board_screen.dart';
import '../incidents/incident_detail_screen.dart';
import '../incidents/incident_list_screen.dart';
import '../credits/credits_screen.dart';
import '../vault/vault_screen.dart';

/// Citizen home: greeting, search, the person's own numbers, quick actions.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  void _runSearch(String q) {
    final text = q.trim();
    if (text.isEmpty) return;
    _push(IncidentListScreen(title: 'My reports', initialQuery: text, standalone: true));
    _search.clear();
  }

  @override
  Widget build(BuildContext context) {
    final incidents = ref.watch(incidentsProvider);
    final expiring = ref.watch(vaultExpiringProvider).valueOrNull ?? const [];
    final scheme = Theme.of(context).colorScheme;

    final notifs = ref.watch(notificationsProvider).valueOrNull ?? const <AppNotification>[];
    final primary = scheme.primary;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      HeroBox(
        scrim: 0.3,
        radius: 20,
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 150,
          child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Smarter Infrastructure\nStronger Communities',
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.2)),
            const SizedBox(height: 6),
            Text('Report  ·  Track  ·  Resolve',
                style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        onSubmitted: _runSearch,
        decoration: InputDecoration(
          hintText: 'Search issues, locations or categories…',
          prefixIcon: const Icon(Icons.search),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28), borderSide: BorderSide(color: primary.withValues(alpha: 0.6))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28), borderSide: BorderSide(color: primary, width: 2)),
        ),
      ),
      const SizedBox(height: 14),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        children: [
          _Tile(Icons.warning_amber_rounded, const Color(0xFF3B82F6), 'Report Issue', 'Log a new issue',
              () => ref.read(navIndexProvider.notifier).state = 1),
          _Tile(Icons.location_on, primary, 'Track Status', 'Check progress',
              () => _push(const IncidentListScreen(title: 'My reports', standalone: true))),
          _Tile(Icons.explore, primary, 'View Map', 'Explore by location',
              () => ref.read(navIndexProvider.notifier).state = 2),
          _Tile(Icons.bar_chart_rounded, primary, 'City Updates', 'Alerts & readings',
              () => _push(const CityBoardScreen())),
        ],
      ),
      if (expiring.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(
          color: scheme.tertiary.withValues(alpha: 0.14),
          child: ListTile(
            leading: Icon(Icons.event_busy_outlined, color: scheme.tertiary),
            title: Text(expiring.length == 1
                ? '1 document needs attention'
                : '${expiring.length} documents need attention'),
            subtitle: const Text('Expired or expiring within 30 days'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _push(const VaultScreen()),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(Icons.emoji_events_outlined, color: primary),
          title: Text(ref.watch(creditsProvider).maybeWhen(
              data: (c) => '${c.total} civic points · ${c.level}', orElse: () => 'Civic points')),
          subtitle: const Text('Earned by reporting problems'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _push(const CreditsScreen()),
        ),
      ),
      const SizedBox(height: 14),
      incidents.when(
        loading: () => const Padding(
            padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(incidentsProvider)),
        data: (list) {
          final pending = list
              .where((i) => i.status == IncidentStatus.submitted ||
                  i.status == IncidentStatus.underReview ||
                  i.status == IncidentStatus.assigned)
              .length;
          final progress = list.where((i) => i.status == IncidentStatus.inProgress).length;
          final resolved = list
              .where((i) => i.status == IncidentStatus.resolved || i.status == IncidentStatus.closed)
              .length;
          return Row(children: [
            Expanded(child: _Stat('Total', '${list.length}', Icons.assignment_outlined)),
            Expanded(child: _Stat('Pending', '$pending', Icons.hourglass_empty)),
            Expanded(child: _Stat('In progress', '$progress', Icons.build_outlined)),
            Expanded(child: _Stat('Resolved', '$resolved', Icons.check_circle_outline)),
          ]);
        },
      ),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: Text('Recent Updates', style: Theme.of(context).textTheme.titleMedium)),
        TextButton(
          onPressed: () => _push(Scaffold(
              appBar: AppBar(title: const Text('Notifications')), body: const NotificationsScreen())),
          child: const Text('View all'),
        ),
      ]),
      if (notifs.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
                'Nothing yet. When the status of one of your reports changes, or a city alert is '
                'published, it shows up here.',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
        )
      else
        for (final n in notifs.take(3))
          Card(
            child: ListTile(
              onTap: n.incidentId == null ? null : () => _push(IncidentDetailScreen(incidentId: n.incidentId!)),
              leading: CircleAvatar(
                backgroundColor: primary.withValues(alpha: 0.18),
                foregroundColor: primary,
                child: Icon(n.title.toLowerCase().contains('resolved') ? Icons.check : Icons.notifications_none),
              ),
              title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(n.body, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(timeAgo(n.createdAt), style: const TextStyle(fontSize: 11)),
                const Icon(Icons.chevron_right, size: 18),
              ]),
            ),
          ),
      const SizedBox(height: 12),
      Text(
        'CIVINEX AI is not an emergency service. In an emergency, call 112.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
    ]);
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.icon, this.color, this.title, this.subtitle, this.onTap);
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 36, color: color),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(subtitle,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ),
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon);
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.all(3),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            FittedBox(child: Text(label, style: const TextStyle(fontSize: 11))),
          ]),
        ),
      );
}
