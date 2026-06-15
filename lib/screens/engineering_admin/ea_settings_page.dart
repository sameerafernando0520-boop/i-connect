// lib/screens/engineering_admin/ea_settings_page.dart
// Engineering Admin Portal — App Settings

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../providers/theme_provider.dart';
import '../../providers/locale_provider.dart';
import '../../widgets/common/language_selector_sheet.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../widgets/common/theme_style_sheet.dart';

const Color _eaAccent = Color(0xFF16A34A);

class EaSettingsPage extends StatelessWidget {
  const EaSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeProvider = context.watch<ThemeProvider>();
    final localeProvider = context.watch<LocaleProvider>();

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: DsPageHeader(
        title: 'Settings',
        accent: HeroAccent.emerald,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(
              height: 0.5,
              color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 80),
        children: [
          // ── APPEARANCE ──────────────────────────────────────────────────
          _SectionLabel(label: 'APPEARANCE', isDark: isDark),
          const SizedBox(height: 10),
          _SettingsCard(
            isDark: isDark,
            children: [
              _ToggleRow(
                icon: isDark
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
                iconColor: _eaAccent,
                title: 'Dark Mode',
                subtitle: themeProvider.isDarkMode ? 'Dark theme is on' : 'Light theme is on',
                isDark: isDark,
                value: themeProvider.isDarkMode,
                onChanged: (_) => themeProvider.toggleTheme(),
              ),
              Divider(
                  height: 1,
                  indent: 52,
                  color: isDark ? Brand.darkBorder : Brand.borderLight),
              ListTile(
                dense: true,
                leading:
                    const Icon(Icons.style_rounded, color: _eaAccent, size: 20),
                title: Text('Dark style',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : const Color(0xFF0F172A))),
                subtitle: Text(
                    ThemeProvider.styleName(themeProvider.darkStyle),
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.textSecondaryLight)),
                trailing: Icon(Icons.chevron_right_rounded,
                    size: 18,
                    color: isDark
                        ? Brand.darkTextTertiary
                        : Brand.subtleLight),
                onTap: () => ThemeStyleSheet.show(context),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── LANGUAGE ────────────────────────────────────────────────────
          _SectionLabel(label: 'LANGUAGE', isDark: isDark),
          const SizedBox(height: 10),
          _SettingsCard(
            isDark: isDark,
            children: [
              _ActionRow(
                icon: Icons.language_rounded,
                iconColor: const Color(0xFF0EA5E9),
                title: 'App Language',
                subtitle: localeProvider.currentLanguageName,
                isDark: isDark,
                onTap: () => showLanguageSelector(context),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── NOTIFICATIONS ───────────────────────────────────────────────
          _SectionLabel(label: 'NOTIFICATIONS', isDark: isDark),
          const SizedBox(height: 10),
          _SettingsCard(
            isDark: isDark,
            children: [
              _InfoRow(
                icon: Icons.notifications_outlined,
                iconColor: const Color(0xFFF59E0B),
                title: 'Push Notifications',
                subtitle: 'Manage notification preferences in your device settings',
                isDark: isDark,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── ABOUT ────────────────────────────────────────────────────────
          _SectionLabel(label: 'ABOUT', isDark: isDark),
          const SizedBox(height: 10),
          _SettingsCard(
            isDark: isDark,
            children: [
              _InfoRow(
                icon: Icons.apps_rounded,
                iconColor: Brand.royalBlue,
                title: 'App Name',
                subtitle: 'iFrontiers Connect',
                isDark: isDark,
              ),
              _Divider(isDark: isDark),
              _InfoRow(
                icon: Icons.business_rounded,
                iconColor: Brand.royalBlue,
                title: 'Company',
                subtitle: 'iFrontiers (Pvt) Ltd',
                isDark: isDark,
              ),
              _Divider(isDark: isDark),
              _InfoRow(
                icon: Icons.badge_rounded,
                iconColor: _eaAccent,
                title: 'Portal',
                subtitle: 'Engineering Admin',
                isDark: isDark,
              ),
              _Divider(isDark: isDark),
              _InfoRow(
                icon: Icons.info_outline_rounded,
                iconColor: AdminColors.textHint(context),
                title: 'Version',
                subtitle: '1.0.0',
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.isDark});
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AdminColors.textHint(context),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children, required this.isDark});
  final List<Widget> children;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 56),
      color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0),
    );
  }
}

// Row with a toggle switch
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isDark;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(26),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B),
                    )),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: AdminColors.textHint(context),
                    )),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: _eaAccent,
          ),
        ],
      ),
    );
  }
}

// Row with a chevron (tappable action)
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.onTap,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withAlpha(26),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : const Color(0xFF1E293B),
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: AdminColors.textHint(context),
                      )),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AdminColors.textHint(context),
            ),
          ],
        ),
      ),
    );
  }
}

// Row with no action (informational only)
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.isDark,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(26),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : const Color(0xFF1E293B),
                    )),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: AdminColors.textHint(context),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
