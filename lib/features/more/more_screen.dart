import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand.dart';
import '../../core/constants/enums.dart';
import '../../state/providers.dart';
import '../about/about_screen.dart';
import '../credits/credits_screen.dart';
import '../cityboard/city_board_screen.dart';
import '../floodguard/floodguard_screen.dart';
import '../incidents/incident_list_screen.dart';
import '../modules/modules_screen.dart';
import '../nearby/nearby_screen.dart';
import '../notifications/notifications_screen.dart';
import '../officer/my_cases_screen.dart';
import '../services/services_screen.dart';
import '../settings/settings_screen.dart';
import '../vault/vault_screen.dart';

/// Profile and everything that does not have its own tab.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key, this.standalone = false});
  final bool standalone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider)!;
    final scheme = Theme.of(context).colorScheme;
    void push(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    Widget scaffolded(String title, Widget body) =>
        Scaffold(appBar: AppBar(title: Text(title)), body: body);

    Widget row(IconData icon, String title, String subtitle, VoidCallback onTap, {bool dot = false}) => Column(children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            leading: Icon(icon, size: 28, color: scheme.primary),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(subtitle),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (dot) Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFE5484D), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right),
            ]),
            onTap: onTap,
          ),
          Divider(height: 1, color: scheme.outlineVariant),
        ]);

    final unread = ref.watch(notificationsProvider).valueOrNull?.any((n) => !n.isRead) ?? false;

    final list = ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => push(const SettingsScreen()),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            CircleAvatar(
              radius: 34,
              child: Text(user.name.trim().isEmpty ? '?' : user.name.trim()[0].toUpperCase(),
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user.name, style: Theme.of(context).textTheme.titleLarge),
                Text(user.email, style: TextStyle(color: scheme.onSurfaceVariant)),
                Text(user.role.label, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12)),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      if (!user.isStaff) ...[
        Card(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.primary, width: 1.5)),
          child: ListTile(
            leading: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.assignment_outlined, color: scheme.primary),
            ),
            title: const Text('My Reports', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('View your submitted issues'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const IncidentListScreen(title: 'My reports', standalone: true)),
          ),
        ),
        row(Icons.folder_special_outlined, 'Document Vault', 'Private, encrypted on this phone', () => push(const VaultScreen())),
        row(Icons.near_me_outlined, 'Problems nearby', 'Issues reported around you', () => push(const NearbyScreen())),
      ],
      if (user.role == UserRole.officer)
        row(Icons.assignment_ind_outlined, 'My assigned cases', 'Accept, work and resolve', () => push(const MyCasesScreen())),
      row(Icons.settings_outlined, 'Settings', 'App preferences', () => push(const SettingsScreen())),
      row(Icons.notifications_none, 'Notifications', 'Alerts & updates',
          () => push(scaffolded('Notifications', const NotificationsScreen())), dot: unread),
      if (user.role == UserRole.citizen)
        row(Icons.emoji_events_outlined, 'Civic points', 'Credits for reporting', () => push(const CreditsScreen())),
      row(Icons.local_hospital_outlined, 'Nearby services', 'Hospitals, police, workshops, puncture shops',
          () => push(const ServicesScreen())),
      row(Icons.campaign_outlined, 'City Updates', 'Readings, advisories and alerts', () => push(const CityBoardScreen())),
      row(Icons.apps_outlined, 'City Services', 'Roads, water, waste, lighting and more', () => push(const ModulesScreen())),
      row(Icons.water_drop_outlined, 'FloodGuard', 'Flood risk estimate', () => push(scaffolded('FloodGuard', const FloodGuardScreen()))),
      row(Icons.help_outline, 'Help & Support', 'FAQs and contact', () => push(const AboutScreen())),
      row(Icons.info_outline, 'About CIVINEX AI', 'Version ${Brand.version}', () => push(const AboutScreen())),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        onPressed: () => _confirmSignOut(context, ref),
        icon: const Icon(Icons.logout),
        label: const Text('Log Out'),
      ),
      const SizedBox(height: 6),
      Text('You stay signed in on this phone until you log out.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
    ]);

    return standalone ? Scaffold(appBar: AppBar(title: const Text('Account')), body: list) : list;
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to use CIVINEX AI.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Log out')),
        ],
      ),
    );
    if (ok != true) return;
    // Close any pages stacked above the shell, then forget the session.
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    ref.read(sessionProvider.notifier).signOut();
  }
}
