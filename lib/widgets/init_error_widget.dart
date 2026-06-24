import 'package:flutter/material.dart';
import '../config/admin_theme.dart';
import '../config/brand_colors.dart';

/// [InitErrorWidget] shows a user-friendly error screen when Firebase or Supabase
/// initialization fails. Offers a retry button to reinitialize.
class InitErrorWidget extends StatelessWidget {
  const InitErrorWidget({
    super.key,
    required this.firebaseError,
    required this.supabaseError,
    required this.onRetry,
    this.isRetrying = false,
  });

  final String? firebaseError;
  final String? supabaseError;
  final VoidCallback onRetry;
  final bool isRetrying;

  @override
  Widget build(BuildContext context) {
    final errorMessage = supabaseError != null
        ? 'Unable to connect to the server. Please check your internet connection and try again.'
        : 'Push notifications may not work on this device, but the app should function normally.';

    return MaterialApp(
      home: Scaffold(
        backgroundColor: Brand.scaffoldLight,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Error Icon ──
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: supabaseError != null
                          ? StatusColors.danger.withAlpha(20)
                          : AdminColors.internal,
                    ),
                    child: Center(
                      child: Icon(
                        supabaseError != null
                            ? Icons.cloud_off_rounded
                            : Icons.warning_amber_rounded,
                        size: 50,
                        color: supabaseError != null
                            ? StatusColors.danger
                            : AdminColors.internal,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Error Title ──
                  Text(
                    supabaseError != null
                        ? 'Connection Error'
                        : 'Notification Warning',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Brand.textPrimaryLight,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  // ── Error Description ──
                  Text(
                    errorMessage,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: AdminColors.textSecondary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // ── Retry Button ──
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: isRetrying ? null : onRetry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Brand.royalBlue,
                        disabledBackgroundColor: AdminColors.textSecondary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isRetrying
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Try Again',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Help Text ──
                  Text(
                    supabaseError != null
                        ? 'Make sure you have a stable internet connection'
                        : 'You can still use the app, but won\'t receive notifications',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AdminColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
