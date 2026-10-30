import 'package:flutter/material.dart';

import '../../core/constants/brand.dart';
import '../../core/theme/app_theme.dart';

const _heroGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF041019), Color(0xFF0B2545), Color(0xFF0A5C63)],
);

/// Short teal bar used as the recurring accent above headlines.
class AccentBar extends StatelessWidget {
  const AccentBar({super.key, this.width = 44, this.height = 5});
  final double width, height;
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
            color: AppTheme.accent, borderRadius: BorderRadius.circular(height / 2)),
      );
}

/// The CIVINEX "C" mark (assets/brand/mark.png, transparent background).
/// Falls back to a drawn tile if the asset is missing.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: Brand.appName,
        image: true,
        child: ExcludeSemantics(
          child: Image.asset(
            'assets/brand/mark.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.accent, AppTheme.navy],
                ),
                borderRadius: BorderRadius.circular(size * 0.28),
              ),
              child: Icon(Icons.location_city_rounded, color: Colors.white, size: size * 0.58),
            ),
          ),
        ),
      );
}

/// Full logo: mark plus the CIVINEX AI wordmark. For dark backgrounds only
/// (the wordmark is white).
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.width = 220});
  final double width;
  @override
  Widget build(BuildContext context) => Semantics(
        label: Brand.appName,
        image: true,
        child: ExcludeSemantics(
          child: Image.asset(
            'assets/brand/logo_full.png',
            width: width,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => BrandMark(size: width / 3),
          ),
        ),
      );
}

/// Small pill naming the event.
class EventBadge extends StatelessWidget {
  const EventBadge({super.key, this.onDark = false, this.compact = false});
  final bool onDark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = onDark ? Colors.white : scheme.onSurface;
    final tint = onDark ? AppTheme.accent : scheme.primary;
    return Semantics(
      label: Brand.eventLine,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 14, vertical: compact ? 3 : 7),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tint.withValues(alpha: 0.55)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bolt_rounded, size: compact ? 12 : 16, color: tint),
          const SizedBox(width: 4),
          Text(
            Brand.eventShort,
            style: TextStyle(
              color: fg,
              fontSize: compact ? 11 : 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ]),
      ),
    );
  }
}

/// Full "Built for ..." line for footers.
class EventFooter extends StatelessWidget {
  const EventFooter({super.key, this.onDark = false});
  final bool onDark;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          Brand.eventLine,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: onDark ? Colors.white70 : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
}

/// Hero card with the Digital University Kerala campus photo, darkened toward
/// the bottom so white text stays readable.
class HeroBox extends StatelessWidget {
  const HeroBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 22,
    this.scrim = 0.55,
    this.minHeight = 0,
  });
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final double scrim;
  final double minHeight;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          constraints: BoxConstraints(minHeight: minHeight),
          decoration: const BoxDecoration(gradient: _heroGradient),
          child: Stack(children: [
            Positioned.fill(child: CampusBackdrop(scrim: scrim)),
            Padding(padding: padding, child: child),
          ]),
        ),
      );
}

/// The campus photo under a navy scrim. If the asset is missing it shows
/// nothing and the gradient behind it remains.
class CampusBackdrop extends StatelessWidget {
  const CampusBackdrop({super.key, this.scrim = 0.7});

  /// 0 shows the photo fully, 1 hides it. Keep it higher where text sits on top.
  final double scrim;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Stack(fit: StackFit.expand, children: [
          Image.asset(
            'assets/brand/campus_bg.jpg',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.ink.withValues(alpha: (scrim - 0.35).clamp(0.0, 1.0)),
                  AppTheme.ink.withValues(alpha: (scrim + 0.3).clamp(0.0, 1.0)),
                ],
              ),
            ),
          ),
        ]),
      );
}

/// Small teal bar plus "DIGITAL UNIVERSITY KERALA · VYUHAM 26".
class EventEyebrow extends StatelessWidget {
  const EventEyebrow({super.key, this.color = Colors.white});
  final Color color;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        const AccentBar(width: 24, height: 4),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '${Brand.host} · ${Brand.event}'.toUpperCase(),
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.0),
          ),
        ),
      ]);
}

/// Top bar shown above every signed-in screen, as in the mockup: menu button,
/// centred wordmark, then action buttons.
class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key, this.trailing = const [], this.onMenu});
  final List<Widget> trailing;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        SizedBox(
          width: 48,
          child: onMenu == null
              ? const SizedBox.shrink()
              : IconButton(tooltip: 'Menu', icon: const Icon(Icons.menu), onPressed: onMenu),
        ),
        Expanded(
          child: Center(
            child: Text(Brand.appName,
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: scheme.onSurface)),
          ),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: trailing.isEmpty ? [const SizedBox(width: 48)] : trailing),
      ]),
    );
  }
}

/// Full-width primary button with the teal-to-cyan gradient used in the mockup.
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.onPressed, this.busy = false, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled || busy ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(colors: [Color(0xFF14E0C8), Color(0xFF12B7D4)]),
            boxShadow: [BoxShadow(color: AppTheme.accent.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 4))],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(26),
            onTap: enabled ? onPressed : null,
            child: Center(
              child: busy
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppTheme.ink))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      if (icon != null) ...[Icon(icon, color: AppTheme.ink, size: 20), const SizedBox(width: 8)],
                      Text(label, style: const TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w800, fontSize: 16)),
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Launch screen: logo and tagline over the navy gradient, campus photo fading
/// in from the bottom.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: MediaQuery.sizeOf(context).height * 0.58,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black],
                stops: [0.0, 0.55],
              ).createShader(r),
              child: const CampusBackdrop(scrim: 0.05),
            ),
          ),
          SafeArea(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(offset: Offset(0, 16 * (1 - t)), child: child),
              ),
              child: Column(children: [
                const Spacer(flex: 2),
                const BrandLogo(width: 250),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(Brand.tagline,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.35)),
                ),
                const Spacer(flex: 6),
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, 28),
                  child: Text('Smarter Infrastructure.\nBetter Tomorrows.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, height: 1.35)),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
