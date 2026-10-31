import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exceptions.dart';
import '../../services/assist_service.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';


class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final lockOn = ref.watch(appLockEnabledProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
            ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
            ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.phone_android), label: Text('Auto')),
          ],
          selected: {mode},
          onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
        ),
        const SizedBox(height: 24),
        Text('Security', style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('App lock'),
          subtitle: const Text(
              'Ask for your fingerprint, face or phone PIN when the app opens or returns after 30 seconds away.'),
          value: lockOn,
          onChanged: (v) => _toggleLock(context, ref, v),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.password),
          title: const Text('Change password'),
          onTap: () => _changePassword(context, ref),
        ),
        if (ref.watch(cloudIdentityProvider) != null) _EmailVerifyTile(),
        const SizedBox(height: 16),
        Text('AI assistant (Claude or Gemini)', style: Theme.of(context).textTheme.titleMedium),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.auto_awesome_outlined),
          title: Text(ref.watch(assistServiceProvider).isConfigured
              ? ref.watch(assistServiceProvider).baseUrl!
              : 'Not set up'),
          subtitle: const Text('Optional. Needs the laptop server from the server folder. '
              'Only the report text you ask it to check is sent.'),
          onTap: () => _assistDialog(context, ref),
        ),
        const SizedBox(height: 16),
        Text('Language', style: Theme.of(context).textTheme.titleMedium),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.translate),
          title: Text('English'),
          subtitle: Text('Malayalam and Hindi are planned and not available yet.'),
        ),
        const SizedBox(height: 16),
        Text('Your data', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          '${ref.watch(cloudIdentityProvider) != null ? 'Your sign-in and profile are kept in the cloud, so you can log in on another phone. ' : ''}'
          'Reports, photos and documents are stored on this phone only. There is no sync of reports between '
          'devices yet, so uninstalling the app or clearing its data erases them. Vault documents '
          'are encrypted and can only be opened by the account that stored them.',
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
        ),
      ]),
    );
  }

  Future<void> _assistDialog(BuildContext context, WidgetRef ref) async {
    final svc = ref.read(assistServiceProvider);
    final url = TextEditingController(text: svc.baseUrl ?? 'http://');
    final token = TextEditingController();
    final action = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('AI assistant server'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  labelText: 'Server address', hintText: 'http://192.168.1.23:8787')),
          const SizedBox(height: 8),
          TextField(
              controller: token,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Server password (if set)',
                  helperText: 'Leave empty to keep the saved one')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'clear'), child: const Text('Turn off')),
          TextButton(onPressed: () => Navigator.pop(c, 'cancel'), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Save & test')),
        ],
      ),
    );
    final u = url.text, t = token.text;
    disposeLater([url]);
    disposeLater([token]);
    if (action == null || action == 'cancel') return;
    if (action == 'clear') {
      await svc.configure(null, null);
      ref.invalidate(assistServiceProvider);
      return;
    }
    await svc.configure(u, t.isEmpty ? ref.read(prefsProvider).get(AssistService.tokenKey) : t);
    ref.invalidate(assistServiceProvider);
    try {
      final model = await ref.read(assistServiceProvider).test();
      if (context.mounted) showMessage(context, 'Connected. Server model: $model');
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _toggleLock(BuildContext context, WidgetRef ref, bool on) async {
    if (!on) {
      ref.read(appLockEnabledProvider.notifier).set(false);
      return;
    }
    final lock = ref.read(appLockProvider);
    if (!await lock.isAvailable()) {
      if (context.mounted) {
        showMessage(context,
            'Set a screen lock or fingerprint in your phone settings first, then try again.',
            error: true);
      }
      return;
    }
    // Prove it works before relying on it, so nobody locks themselves out.
    if (await lock.authenticate('Confirm to turn on app lock')) {
      ref.read(appLockEnabledProvider.notifier).set(true);
    } else if (context.mounted) {
      showMessage(context, 'App lock was not turned on.', error: true);
    }
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Change password'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password')),
          const SizedBox(height: 8),
          TextField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'New password', helperText: '8+ characters, letters and numbers')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Change')),
        ],
      ),
    );
    final cur = current.text, nw = next.text;
    disposeLater([current]);
    disposeLater([next]);
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(authRepositoryProvider).changePassword(
          userId: ref.read(sessionProvider)!.id, current: cur, next: nw);
      if (context.mounted) showMessage(context, 'Password changed.');
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }
}


/// Shows whether the account email is verified and lets the person request the
/// verification email again. Only shown when cloud sign-in is active.
class _EmailVerifyTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_EmailVerifyTile> createState() => _EmailVerifyTileState();
}

class _EmailVerifyTileState extends ConsumerState<_EmailVerifyTile> {
  bool? _verified;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final v = await ref.read(cloudIdentityProvider)!.isEmailVerified();
    if (mounted) setState(() => _verified = v);
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await ref.read(cloudIdentityProvider)!.sendVerificationEmail();
      if (mounted) showMessage(context, 'Verification email sent. Open the link, then tap Check.');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _verified;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(v == true ? Icons.verified_outlined : Icons.mark_email_unread_outlined),
      title: Text(v == null
          ? 'Checking email status…'
          : v
              ? 'Email verified'
              : 'Email not verified'),
      subtitle: v == false ? const Text('Send yourself a verification link.') : null,
      trailing: v == false
          ? Wrap(spacing: 4, children: [
              TextButton(onPressed: _busy ? null : _send, child: const Text('Send')),
              TextButton(onPressed: _check, child: const Text('Check')),
            ])
          : null,
    );
  }
}
