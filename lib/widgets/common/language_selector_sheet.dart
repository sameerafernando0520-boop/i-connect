// ═══════════════════════════════════════════════════════════════
// FILE: lib/widgets/common/language_selector_sheet.dart
// NEW v18 — Reusable language picker bottom sheet.
//   Call showLanguageSelector(context) from any screen.
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:i_connect/l10n/s.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../providers/locale_provider.dart';

/// Shows a modal bottom sheet with language options.
/// Returns the selected [Locale] or null if dismissed.
Future<Locale?> showLanguageSelector(BuildContext context) {
  return showModalBottomSheet<Locale>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetCtx) => const _LanguageSelectorSheet(),
  );
}

class _LanguageSelectorSheet extends StatelessWidget {
  const _LanguageSelectorSheet();

  static const _languages = [
    _LangOption(
        code: 'en', native: 'English', subtitle: 'English', flag: '🇬🇧'),
    _LangOption(code: 'si', native: 'සිංහල', subtitle: 'Sinhala', flag: '🇱🇰'),
    _LangOption(code: 'ta', native: 'தமிழ்', subtitle: 'Tamil', flag: '🇱🇰'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = S.of(context)!;
    final localeProvider = Provider.of<LocaleProvider>(context);
    final currentCode = localeProvider.locale.languageCode;

    return Container(
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),

            // ── Drag handle ──
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withAlpha(26)
                    : Colors.black.withAlpha(26),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            const SizedBox(height: 20),

            // ── Title ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Brand.royalBlue.withAlpha(26),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.translate_rounded,
                      color: Brand.royalBlue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.settingsSelectLanguage,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Brand.darkTextPrimary
                                : Brand.darkCard,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'English · සිංහල · தமிழ்',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Language options ──
            ...List.generate(_languages.length, (i) {
              final lang = _languages[i];
              final isSelected = lang.code == currentCode;

              return _buildLanguageTile(
                context: context,
                lang: lang,
                isSelected: isSelected,
                isDark: isDark,
                isLast: i == _languages.length - 1,
                onTap: () {
                  if (!isSelected) {
                    localeProvider.setLocale(Locale(lang.code));
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${lang.native} — ${t.settingsLanguageChanged}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        backgroundColor: Brand.lightGreen,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        margin: const EdgeInsets.all(16),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                  Navigator.pop(context, Locale(lang.code));
                },
              );
            }),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageTile({
    required BuildContext context,
    required _LangOption lang,
    required bool isSelected,
    required bool isDark,
    required bool isLast,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Material(
            color: isSelected
                ? (isDark
                    ? Brand.royalBlue.withAlpha(26)
                    : Brand.royalBlueSurface)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    // ── Flag ──
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withAlpha(13)
                            : AdminColors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        lang.flag,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),

                    const SizedBox(width: 14),

                    // ── Native name + English subtitle ──
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lang.native,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: isSelected
                                  ? Brand.royalBlue
                                  : (isDark
                                      ? Brand.darkTextPrimary
                                      : Brand.darkCard),
                            ),
                          ),
                          if (lang.subtitle != lang.native) ...[
                            const SizedBox(height: 2),
                            Text(
                              lang.subtitle,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // ── Selection indicator ──
                    if (isSelected)
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Brand.royalBlue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      )
                    else
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark
                                ? Brand.darkBorderLight
                                : AdminColors.borderLight,
                            width: 2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (!isLast)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(
                height: 1,
                color: isDark ? Brand.darkBorder : AdminColors.background,
              ),
            ),
        ],
      ),
    );
  }
}

class _LangOption {
  final String code;
  final String native;
  final String subtitle;
  final String flag;

  const _LangOption({
    required this.code,
    required this.native,
    required this.subtitle,
    required this.flag,
  });
}
