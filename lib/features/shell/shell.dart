import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../shared/brand/brand_widgets.dart';
import '../../state/providers.dart';
import '../admin/admin_dashboard.dart';
import '../admin/admin_screen.dart';
import '../home/home_screen.dart';
import '../incidents/incident_list_screen.dart';
import '../intelligence/intelligence_screen.dart';
import '../map/incident_map_screen.dart';
import '../more/more_screen.dart';
import '../notifications/notifications_screen.dart';
import '../reporting/report_screen.dart';
import '../staff/queue_screen.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.builder);
  final String label;
  final IconData icon;
  final Widget Function() builder;
}

/// Role-based navigation. The destinations come from the verified session
/// user, and every repository call re-checks authorization.
///
/// Citizen: Home, Report, Map, More.   Officer: Queue, Map, Insights, All, More.
/// Administrator: Dashboard, Complaints, Map, Insights, Manage.
class Shell extends ConsumerWidget {
  const Shell({super.key});

  static const citizenMoreIndex = 3;

  List<_Dest> _destinations(UserRole role) {
    switch (role) {
      case UserRole.citizen:
        return [
          _Dest('Home', Icons.home_outlined, () => const HomeScreen()),
          _Dest('Report', Icons.add_circle_outline, () => const ReportScreen()),
          _Dest('Map', Icons.location_on_outlined, () => const IncidentMapScreen()),
          _Dest('More', Icons.grid_view_rounded, () => const MoreScreen()),
        ];
      case UserRole.officer:
        return [
          _Dest('Queue', Icons.priority_high, () => const QueueScreen()),
          _Dest('Map', Icons.map_outlined, () => const IncidentMapScreen()),
          _Dest('Insights', Icons.insights_outlined, () => const IntelligenceScreen()),
          _Dest('All', Icons.list_alt, () => const IncidentListScreen(title: 'Department incidents')),
          _Dest('More', Icons.grid_view_rounded, () => const MoreScreen()),
        ];
      case UserRole.admin:
        return [
          _Dest('Dashboard', Icons.dashboard_outlined, () => const AdminDashboard()),
          _Dest('Complaints', Icons.list_alt, () => const IncidentListScreen(title: 'All complaints')),
          _Dest('Map', Icons.map_outlined, () => const IncidentMapScreen()),
          _Dest('Insights', Icons.insights_outlined, () => const IntelligenceScreen()),
          _Dest('Manage', Icons.admin_panel_settings_outlined, () => const AdminScreen()),
        ];
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider)!;
    // Housekeeping for staff (deadlines, auto-assign, escalation), the
    // department name registry for everyone, and expiry reminders for citizens.
    ref.watch(departmentsProvider);
    ref.watch(syncProvider); // shares reports with other phones (cloud mode)
    ref.watch(routingProvider); // automatic officer routing (administrator phone)
    if (user.isStaff) ref.watch(maintenanceProvider);
    if (!user.isStaff) ref.watch(vaultRemindersProvider);
    final dests = _destinations(user.role);
    final index = ref.watch(navIndexProvider).clamp(0, dests.length - 1);
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final unread = ref.watch(notificationsProvider).valueOrNull?.where((n) => !n.isRead).length ?? 0;

    void push(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    void openMore() {
      if (user.role == UserRole.citizen) {
        ref.read(navIndexProvider.notifier).state = citizenMoreIndex;
      } else {
        push(const MoreScreen(standalone: true));
      }
    }

    final body = Column(children: [
      AppTopBar(
        onMenu: openMore,
        trailing: [
          IconButton(
            tooltip: 'Notifications',
            icon: Badge(
              isLabelVisible: unread > 0,
              smallSize: 9,
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: () => push(Scaffold(
                appBar: AppBar(title: const Text('Notifications')),
                body: const NotificationsScreen())),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8, left: 2),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: openMore,
              child: Semantics(
                label: 'Account: ${user.name}',
                child: CircleAvatar(
                  radius: 17,
                  child: Text(user.name.trim().isEmpty ? '?' : user.name.trim()[0].toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
        ],
      ),
      Expanded(child: dests[index].builder()),
    ]);

    return Scaffold(
      body: SafeArea(
        child: wide
            ? Row(children: [
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: (i) => ref.read(navIndexProvider.notifier).state = i,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in dests)
                      NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ])
            : body,
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => ref.read(navIndexProvider.notifier).state = i,
              destinations: [
                for (final d in dests) NavigationDestination(icon: Icon(d.icon), label: d.label),
              ],
            ),
    );
  }
}
