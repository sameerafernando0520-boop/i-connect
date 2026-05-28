// lib/widgets/admin/logout_dialog.dart

import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../../screens/auth/login_page.dart';

class LogoutBottomSheet extends StatefulWidget {
  const LogoutBottomSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const LogoutBottomSheet(),
    );
  }

  @override
  State<LogoutBottomSheet> createState() => _LogoutBottomSheetState();
}

class _LogoutBottomSheetState extends State<LogoutBottomSheet> {
  bool _loading = false;

  Future<void> _signOut() async {
    setState(() => _loading = true);
    try {
      await SupabaseConfig.client.auth.signOut();
      if (!mounted) return;
      // Capture the navigator before pop so navigation still works after
      // the sheet's context begins deactivating.
      final nav = Navigator.of(context);
      nav.pop(); // close sheet
      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [
            Icon(Icons.error_outline, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Sign out failed. Try again.'),
          ]),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AdminColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AdminColors.error.withAlpha(isDark ? 35 : 25),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.logout_rounded,
              color: AdminColors.error,
              size: 30,
            ),
          ),
          const SizedBox(height: 16),

          Text(
            'Sign Out?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Brand.darkTextPrimary : AdminColors.text(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You will need to sign in again\nto access the admin panel.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AdminColors.textSub(context),
            ),
          ),
          const SizedBox(height: 28),

          // Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _loading ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AdminColors.textSub(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _loading ? null : _signOut,
                  style: FilledButton.styleFrom(
                    backgroundColor: AdminColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Sign Out',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
