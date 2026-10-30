import 'package:flutter/material.dart';

import '../../core/constants/brand.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/brand/brand_widgets.dart';

/// Shared layout for every signed-out page, following the mockup: dark teal
/// gradient, logo, wordmark, tagline and the event pill, then the form. The
/// auth pages are always dark, whatever theme the person chose inside the app.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child, this.onBack, this.photo = false, this.compact = false});
  final Widget child;
  final VoidCallback? onBack;

  /// Shows the campus photo fading in from the bottom (welcome page).
  final bool photo;

  /// Smaller header, for long forms.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.dark(),
      child: Builder(builder: (context) {
        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF041019), Color(0xFF0B2545), Color(0xFF0A4F5C)],
              ),
            ),
            child: Stack(fit: StackFit.expand, children: [
              if (photo)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: MediaQuery.sizeOf(context).height * 0.4,
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (r) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black],
                      stops: [0.0, 0.6],
                    ).createShader(r),
                    child: const CampusBackdrop(scrim: 0.05),
                  ),
                ),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (onBack != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: onBack,
                              icon: const Icon(Icons.arrow_back, size: 18),
                              label: const Text('Back'),
                            ),
                          ),
                        _Header(compact: compact),
                        SizedBox(height: compact ? 18 : 28),
                        child,
                        const SizedBox(height: 20),
                        Text(
                          Brand.eventLine,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.compact});
  final bool compact;
  @override
  Widget build(BuildContext context) => Column(children: [
        BrandMark(size: compact ? 56 : 84),
        SizedBox(height: compact ? 8 : 12),
        Text(Brand.appName,
            style: AppTheme.display(null, size: compact ? 30 : 40, color: Colors.white, spacing: 1)),
        const SizedBox(height: 6),
        const Text(Brand.tagline,
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 14),
        const EventBadge(onDark: true),
      ]);
}
