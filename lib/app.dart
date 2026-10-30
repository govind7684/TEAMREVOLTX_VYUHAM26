import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/auth_flow.dart';
import 'features/lock/app_lock_gate.dart';
import 'features/shell/shell.dart';
import 'shared/brand/brand_widgets.dart';
import 'state/providers.dart';

class CivinexApp extends ConsumerStatefulWidget {
  const CivinexApp({super.key});
  @override
  ConsumerState<CivinexApp> createState() => _CivinexAppState();
}

class _CivinexAppState extends ConsumerState<CivinexApp> {
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _splashDone = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    return MaterialApp(
      title: 'CIVINEX AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      home: !_splashDone
          ? const SplashScreen()
          : user != null
              ? const AppLockGate(child: Shell())
              : const AuthFlow(),
    );
  }
}
