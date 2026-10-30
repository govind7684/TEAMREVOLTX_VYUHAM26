import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exceptions.dart';
import '../../domain/models/incident.dart';
import '../../domain/models/user.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';

final _usersProvider = FutureProvider<List<AppUser>>((ref) async {
  ref.watch(refreshTickProvider);
  return ref.watch(authRepositoryProvider).listUsers(ref.watch(sessionProvider)!);
});

final _auditProvider = FutureProvider<List<AuditEntry>>((ref) async {
  ref.watch(refreshTickProvider);
  return ref.watch(incidentRepositoryProvider).auditLog(ref.watch(sessionProvider)!);
});

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(sessionProvider)!;
    if (me.role != UserRole.admin) {
      return const EmptyState(icon: Icons.lock_outline, message: 'Administrators only.');
    }
    return DefaultTabController(
      length: 4,
      child: Column(children: [
        const TabBar(tabs: [
          Tab(text: 'Users'),
          Tab(text: 'Departments'),
          Tab(text: 'Audit log'),
          Tab(text: 'Data')
        ]),
        Expanded(
          child: TabBarView(children: [
            _Users(me: me),
            const _DepartmentsTab(),
            const _Audit(),
            const _Data(),
          ]),
        ),
      ]),
    );
  }
}

class _Users extends ConsumerWidget {
  const _Users({required this.me});
  final AppUser me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(_usersProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(_usersProvider)),
          data: (users) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => _addStaff(context, ref),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Add staff account'),
                ),
              ),
            ),
            for (final u in users)
              ListTile(
                title: Text(u.name),
                subtitle: Text(
                    '${u.email}\n${u.role.label}${u.departmentId == null ? '' : ' · ${Departments.nameOf(u.departmentId!)}'}${u.role == UserRole.officer && u.servicesAllowed ? ' · Services access' : ''}${u.isActive ? '' : ' · DISABLED'}'),
                isThreeLine: true,
                trailing: u.id == me.id
                    ? const Text('You')
                    : PopupMenuButton<String>(
                        onSelected: (v) => _change(context, ref, u, v),
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'citizen', child: Text('Make citizen')),
                          for (final d in Departments.names.entries)
                            PopupMenuItem(
                                value: 'officer:${d.key}',
                                child: Text('Make officer: ${d.value}')),
                          const PopupMenuItem(value: 'admin', child: Text('Make administrator')),
                          if (u.role == UserRole.officer)
                            PopupMenuItem(
                                value: u.servicesAllowed ? 'services:off' : 'services:on',
                                child: Text(u.servicesAllowed
                                    ? 'Remove services access'
                                    : 'Allot services access')),
                          const PopupMenuItem(value: 'reset', child: Text('Reset password')),
                          PopupMenuItem(
                              value: u.isActive ? 'deactivate' : 'activate',
                              child: Text(u.isActive ? 'Disable account' : 'Enable account')),
                        ],
                      ),
              ),
          ]),
        );
  }

  Future<void> _addStaff(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    var role = UserRole.officer;
    String? dept = Departments.roads;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Add staff account'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
              const SizedBox(height: 8),
              TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 8),
              TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Temporary password', helperText: '8+ characters, letters and numbers')),
              const SizedBox(height: 8),
              DropdownButtonFormField<UserRole>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: UserRole.officer, child: Text('Municipal officer')),
                  DropdownMenuItem(value: UserRole.admin, child: Text('Administrator')),
                ],
                onChanged: (v) => set(() => role = v ?? UserRole.officer),
              ),
              if (role == UserRole.officer) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: dept,
                  decoration: const InputDecoration(labelText: 'Department'),
                  items: [
                    for (final d in Departments.names.entries)
                      DropdownMenuItem(value: d.key, child: Text(d.value)),
                  ],
                  onChanged: (v) => set(() => dept = v),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    final n = name.text, e = email.text, p = password.text;
    name.dispose();
    email.dispose();
    password.dispose();
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(authRepositoryProvider).createStaff(
            actor: me,
            name: n,
            email: e,
            password: p,
            role: role,
            departmentId: dept,
          );
      ref.read(refreshTickProvider.notifier).state++;
      if (context.mounted) {
        showMessage(context, 'Account created. Share the temporary password securely and '
            'ask them to change it from Profile.');
      }
    } catch (err) {
      if (context.mounted) showMessage(context, friendlyError(err), error: true);
    }
  }

  Future<void> _resetPassword(BuildContext context, WidgetRef ref, AppUser u) async {
    if (ref.read(authRepositoryProvider).usesEmailReset) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (x) => AlertDialog(
          title: Text('Email a reset link to ${u.name}?'),
          content: Text('A password reset link will be sent to ${u.email}.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('Send')),
          ],
        ),
      );
      if (yes != true) return;
      try {
        await ref
            .read(authRepositoryProvider)
            .resetPassword(actor: me, targetId: u.id, newPassword: '');
        if (context.mounted) showMessage(context, 'Reset link sent to ${u.email}.');
      } catch (e) {
        if (context.mounted) showMessage(context, friendlyError(e), error: true);
      }
      return;
    }
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: Text('Reset password for ${u.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Choose a temporary password and tell the person. They should change it '
              'after signing in (More > Settings > Change password).'),
          const SizedBox(height: 12),
          TextField(
              controller: c,
              decoration: const InputDecoration(
                  labelText: 'New password', helperText: '8+ characters, letters and numbers')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('Reset')),
        ],
      ),
    );
    final pw = c.text;
    c.dispose();
    if (ok != true) return;
    try {
      await ref
          .read(authRepositoryProvider)
          .resetPassword(actor: me, targetId: u.id, newPassword: pw);
      if (context.mounted) showMessage(context, 'Password reset and logged.');
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _change(BuildContext context, WidgetRef ref, AppUser u, String v) async {
    if (v == 'reset') return _resetPassword(context, ref, u);
    if (v.startsWith('services:')) {
      try {
        await ref.read(authRepositoryProvider).setServicesAllowed(
            actor: me, targetId: u.id, allowed: v == 'services:on');
        ref.invalidate(_usersProvider);
        ref.read(refreshTickProvider.notifier).state++;
        if (context.mounted) {
          showMessage(context, v == 'services:on'
              ? '${u.name} can now manage the city services directory.'
              : 'Services access removed.');
        }
      } catch (e) {
        if (context.mounted) showMessage(context, friendlyError(e), error: true);
      }
      return;
    }
    if (v == 'deactivate' || v == 'activate') {
      try {
        await ref.read(authRepositoryProvider).setActive(
            actor: me, targetId: u.id, active: v == 'activate');
        ref.read(refreshTickProvider.notifier).state++;
        if (context.mounted) {
          showMessage(context, v == 'activate' ? 'Account enabled.' : 'Account disabled.');
        }
      } catch (e) {
        if (context.mounted) showMessage(context, friendlyError(e), error: true);
      }
      return;
    }
    final parts = v.split(':');
    final role = UserRole.values.byName(parts.first);
    try {
      await ref.read(authRepositoryProvider).setRole(
            actor: me,
            targetId: u.id,
            role: role,
            departmentId: parts.length > 1 ? parts[1] : null,
          );
      ref.read(refreshTickProvider.notifier).state++;
      if (context.mounted) showMessage(context, 'Role updated and logged.');
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }
}

class _Audit extends ConsumerWidget {
  const _Audit();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(_auditProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(_auditProvider)),
          data: (log) => log.isEmpty
              ? const EmptyState(
                  icon: Icons.history, message: 'No staff actions recorded yet.')
              : ListView(children: [
                  for (final a in log)
                    ListTile(
                      dense: true,
                      title: Text('${a.action} · ${a.actorName}'),
                      subtitle: Text('${a.detail}\n${formatDate(a.at)}'),
                      isThreeLine: true,
                    ),
                ]),
        );
  }
}

class _Data extends ConsumerWidget {
  const _Data();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Active triage engine'),
      Text(ref.watch(aiProviderProvider).description,
          style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
      const Text(
          'Data is stored in a database on this device. There is no automatic backup or sync yet.',
          style: TextStyle(fontSize: 12)),
    ]);
  }
}


/// Department and officer management (administrators only; the repository
/// checks the role again on every call).
class _DepartmentsTab extends ConsumerWidget {
  const _DepartmentsTab();

  Future<String?> _ask(BuildContext context, String title, String label, [String initial = '']) async {
    final c = TextEditingController(text: initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, decoration: InputDecoration(labelText: label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
        ],
      ),
    );
    final t = c.text;
    c.dispose();
    return ok == true ? t : null;
  }

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() job) async {
    try {
      await job();
      ref.read(refreshTickProvider.notifier).state++;
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(sessionProvider)!;
    final wf = ref.read(workflowRepositoryProvider);
    final depts = ref.watch(departmentsProvider).valueOrNull ?? const [];
    final users = ref.watch(_usersProvider).valueOrNull ?? const <AppUser>[];
    final officers = users.where((u) => u.role == UserRole.officer).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text('Departments', style: Theme.of(context).textTheme.titleLarge)),
        FilledButton.icon(
          onPressed: () async {
            final n = await _ask(context, 'New department', 'Name');
            if (n == null) return;
            if (context.mounted) await _run(context, ref, () => wf.addDepartment(me, n));
          },
          icon: const Icon(Icons.add_business_outlined),
          label: const Text('Add'),
        ),
      ]),
      for (final d in depts)
        ListTile(
          title: Text(d.name),
          subtitle: Text('${officers.where((o) => o.departmentId == d.id).length} officer(s)'),
          trailing: IconButton(
            tooltip: 'Rename',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final n = await _ask(context, 'Rename department', 'Name', d.name);
              if (n == null) return;
              if (context.mounted) await _run(context, ref, () => wf.renameDepartment(me, d.id, n));
            },
          ),
        ),
      const Divider(height: 32),
      Text('Officers', style: Theme.of(context).textTheme.titleLarge),
      const Text('Moving an officer releases their open cases for reassignment.',
          style: TextStyle(fontSize: 12)),
      for (final o in officers)
        ListTile(
          title: Text(o.name),
          subtitle: Text(Departments.nameOf(o.departmentId ?? '')),
          trailing: PopupMenuButton<String>(
            tooltip: 'Move to department',
            icon: const Icon(Icons.swap_horiz),
            onSelected: (id) => _run(context, ref, () => wf.moveOfficer(me, o.id, id)),
            itemBuilder: (_) => [for (final d in depts) PopupMenuItem(value: d.id, child: Text(d.name))],
          ),
        ),
    ]);
  }
}
