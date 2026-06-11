// Bottom sheet for picking the app appearance:
// Light, or one of three dark looks — Navy Glow, Workshop, Fusion.
// Open with ThemeStyleSheet.show(context) from any settings page.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/brand_colors.dart';
import '../../providers/theme_provider.dart';

class ThemeStyleSheet {
  ThemeStyleSheet._();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ThemeStyleBody(),
    );
  }
}

class _ThemeStyleBody extends StatelessWidget {
  const _ThemeStyleBody();

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Appearance',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color:
                    isDark ? Brand.darkTextPrimary : Brand.textPrimaryLight,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick a light or dark look. Dark has three styles.',
              style: TextStyle(
                fontSize: 12.5,
                color: isDark
                    ? Brand.darkTextSecondary
                    : Brand.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 16),
            _LightTile(
              selected: !tp.isDarkMode,
              onTap: () => tp.setDarkMode(false),
            ),
            const SizedBox(height: 10),
            ...DarkStyle.values.map((s) {
              final p = Brand.paletteFor(s);
              final selected = tp.isDarkMode && tp.darkStyle == s;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _StyleTile(
                  name: ThemeProvider.styleName(s),
                  caption: switch (s) {
                    DarkStyle.navy =>
                        'Deep splash navy with a soft blue glow',
                    DarkStyle.workshop =>
                        'Warm ink canvas with the lime spark',
                    DarkStyle.fusion =>
                        'Navy depth with outlined Workshop cards',
                  },
                  palette: p,
                  selected: selected,
                  onTap: () => tp.setDarkStyle(s),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _LightTile extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  const _LightTile({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _TileShell(
      selected: selected,
      accent: Brand.royalBlue,
      onTap: onTap,
      preview: Container(
        decoration: BoxDecoration(
          color: Brand.scaffoldLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Brand.borderLight),
        ),
        padding: const EdgeInsets.all(7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 6,
              decoration: BoxDecoration(
                color: Brand.royalBlue,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 5),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Brand.cardLight,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Brand.borderLight),
                ),
              ),
            ),
          ],
        ),
      ),
      name: 'Light',
      caption: 'Bright, clean, daytime default',
    );
  }
}

class _StyleTile extends StatelessWidget {
  final String name;
  final String caption;
  final DarkPalette palette;
  final bool selected;
  final VoidCallback onTap;

  const _StyleTile({
    required this.name,
    required this.caption,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _TileShell(
      selected: selected,
      accent: palette.primary,
      onTap: onTap,
      preview: Container(
        decoration: BoxDecoration(
          color: palette.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.border),
        ),
        padding: const EdgeInsets.all(7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 6,
              decoration: BoxDecoration(
                color: palette.primary,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 5),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: palette.card,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: palette.border),
                ),
              ),
            ),
          ],
        ),
      ),
      name: name,
      caption: caption,
    );
  }
}

class _TileShell extends StatelessWidget {
  final bool selected;
  final Color accent;
  final Widget preview;
  final String name;
  final String caption;
  final VoidCallback onTap;

  const _TileShell({
    required this.selected,
    required this.accent,
    required this.preview,
    required this.name,
    required this.caption,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = selected
        ? accent
        : (isDark ? Brand.darkBorder : Brand.borderLight);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Brand.cardLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: selected ? 1.6 : 1),
        ),
        child: Row(
          children: [
            SizedBox(width: 64, height: 48, child: preview),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : Brand.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark
                          ? Brand.darkTextSecondary
                          : Brand.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              size: 22,
              color: selected
                  ? accent
                  : (isDark ? Brand.darkBorderLight : Brand.borderLight),
            ),
          ],
        ),
      ),
    );
  }
}
