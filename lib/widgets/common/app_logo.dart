// lib/widgets/common/app_logo.dart
//
// Single source of truth for rendering the iConnect brand logo.
// Picks the correct artwork for the variant (full lockup / horizontal wordmark
// / square app-icon mark) and the correct tone (navy-ink for light surfaces,
// white-ink for dark surfaces). Tone auto-detects from the ambient theme
// brightness unless [dark] is passed explicitly.
//
// Assets live in assets/branding/ (declared as a folder in pubspec.yaml).

import 'package:flutter/material.dart';

enum AppLogoVariant {
  /// Full stacked lockup: icon + "iCONNECT" wordmark + tagline.
  full,

  /// Horizontal wordmark with the integrated icon — compact, for app bars.
  wordmark,

  /// Square app-icon tile (navy background + green/white glyph).
  mark,
}

class AppLogo extends StatelessWidget {
  final AppLogoVariant variant;
  final double? height;
  final double? width;

  /// Force the tone: true = white-ink (dark backgrounds),
  /// false = navy-ink (light backgrounds). Null = follow theme brightness.
  final bool? dark;

  final BoxFit fit;
  final String? semanticLabel;

  const AppLogo({
    super.key,
    this.variant = AppLogoVariant.wordmark,
    this.height,
    this.width,
    this.dark,
    this.fit = BoxFit.contain,
    this.semanticLabel,
  });

  const AppLogo.full({
    super.key,
    this.height,
    this.width,
    this.dark,
    this.fit = BoxFit.contain,
    this.semanticLabel,
  }) : variant = AppLogoVariant.full;

  const AppLogo.wordmark({
    super.key,
    this.height,
    this.width,
    this.dark,
    this.fit = BoxFit.contain,
    this.semanticLabel,
  }) : variant = AppLogoVariant.wordmark;

  const AppLogo.mark({
    super.key,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
    this.semanticLabel,
  })  : variant = AppLogoVariant.mark,
        dark = null;

  static const String _base = 'assets/branding';

  String _asset(bool useDark) {
    switch (variant) {
      case AppLogoVariant.full:
        return useDark ? '$_base/logo_dark.png' : '$_base/logo_light.png';
      case AppLogoVariant.wordmark:
        return useDark ? '$_base/wordmark_dark.png' : '$_base/wordmark_light.png';
      case AppLogoVariant.mark:
        return '$_base/app_icon.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    final useDark = dark ?? (Theme.of(context).brightness == Brightness.dark);
    return Image.asset(
      _asset(useDark),
      height: height,
      width: width,
      fit: fit,
      filterQuality: FilterQuality.high,
      semanticLabel: semanticLabel ?? 'iConnect',
      // Graceful textual fallback if an asset is missing.
      errorBuilder: (_, __, ___) => SizedBox(
        height: height,
        width: width,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'iConnect',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: (height ?? 22) * 0.55,
              letterSpacing: 0.5,
              color: useDark ? Colors.white : const Color(0xFF262261),
            ),
          ),
        ),
      ),
    );
  }
}
