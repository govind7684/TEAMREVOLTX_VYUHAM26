import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/brand/brand_widgets.dart';
import '../../state/providers.dart';

/// Wraps the signed-in app. When the optional app lock is on, the app asks for
/// the fingerprint / face / phone PIN when it starts with a remembered
/// sign-in and when it returns from the background after more than 30 seconds.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child, this.grace = const Duration(seconds: 30)});
  final Widget child;
  final Duration grace;
  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  DateTime? _leftAt;
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_prompting) return; // the system dialog itself pauses the app
    if (state == AppLifecycleState.paused) {
      _leftAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (left != null &&
          ref.read(appLockEnabledProvider) &&
          DateTime.now().difference(left) > widget.grace) {
        ref.read(appLockedProvider.notifier).state = true;
      }
    }
  }

  Future<bool> _unlock() async {
    _prompting = true;
    try {
      final lock = ref.read(appLockProvider);
      if (!await lock.isAvailable()) {
        // The phone no longer has a screen lock, so there is nothing to check.
        ref.read(appLockEnabledProvider.notifier).set(false);
        ref.read(appLockedProvider.notifier).state = false;
        return true;
      }
      final ok = await lock.authenticate('Unlock CIVINEX AI');
      if (ok) ref.read(appLockedProvider.notifier).state = false;
      return ok;
    } finally {
      _prompting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(appLockedProvider) && ref.watch(appLockEnabledProvider);
    if (!locked) return widget.child;
    return LockScreen(onUnlock: _unlock);
  }
}

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.onUnlock});
  final Future<bool> Function() onUnlock;
  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _try());
  }

  Future<void> _try() async {
    final ok = await widget.onUnlock();
    if (!ok && mounted) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const BrandMark(size: 64),
              const SizedBox(height: 20),
              Text('CIVINEX AI is locked', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                _failed
                    ? 'Could not verify it is you.'
                    : 'Use your fingerprint, face or phone PIN.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _try,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Unlock'),
              ),
              TextButton(
                onPressed: () {
                  ref.read(appLockedProvider.notifier).state = false;
                  ref.read(sessionProvider.notifier).signOut();
                },
                child: const Text('Sign out instead'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
