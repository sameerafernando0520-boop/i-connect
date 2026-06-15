// ============================================================
// FILE: lib/screens/auth/login_page.dart
// ============================================================

import 'package:i_connect/l10n/s.dart';
import '../admin/admin_dashboard.dart';
import '../engineer/engineer_dashboard.dart';
import '../marketing/marketing_admin_dashboard.dart';
import '../engineering_admin/engineering_admin_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, AuthResponse;
import '../../config/brand_colors.dart';
import '../../providers/permissions_provider.dart';
import '../../services/notification_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'signup_page.dart';
import '../customer/home_page.dart';
import '../../widgets/common/app_logo.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscurePassword = true;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this);
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ─── LOGIN LOGIC ───────────────────────────────────────────

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      // ── Username detection ─────────────────────────────────────────────────
      // If the input has no '@', it's a staff username.
      // Try synthetic domains in order:
      //   1. @marketing.iconnect.lk    (marketer)
      //   2. @engineering.iconnect.lk  (engineering_admin)
      //   3. @engineer.iconnect.lk     (engineer)
      // The synthetic domains are never shown to the user.
      final rawInput = _emailController.text.trim();
      final isUsername = !rawInput.contains('@');

      String emailForAuth = isUsername
          ? '${rawInput.toLowerCase()}@marketing.iconnect.lk'
          : rawInput;

      AuthResponse response;
      try {
        response = await SupabaseConfig.client.auth.signInWithPassword(
          email: emailForAuth,
          password: _passwordController.text,
        );
      } on AuthException catch (_) {
        if (!isUsername) rethrow;
        // Marketing domain failed → try engineering_admin domain
        try {
          emailForAuth =
              '${rawInput.toLowerCase()}@engineering.iconnect.lk';
          response = await SupabaseConfig.client.auth.signInWithPassword(
            email: emailForAuth,
            password: _passwordController.text,
          );
        } on AuthException catch (_) {
          // Engineering admin domain failed → try engineer domain
          emailForAuth =
              '${rawInput.toLowerCase()}@engineer.iconnect.lk';
          response = await SupabaseConfig.client.auth.signInWithPassword(
            email: emailForAuth,
            password: _passwordController.text,
          );
        }
      }

      if (response.user == null) {
        throw Exception('Login failed. Please try again.');
      }

      final userData = await SupabaseConfig.client
          .from('users')
          .select('role')
          .eq('id', response.user!.id)
          .maybeSingle();

      if (!mounted) return;

      if (userData == null) {
        await SupabaseConfig.client.auth.signOut();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.warning_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                    child: Text(
                        'Account not found. Please sign up or contact support.')),
              ],
            ),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
            margin: const EdgeInsets.all(16),
          ),
        );
        return;
      }

      final role = userData['role'] as String? ?? 'customer';

      final notificationService = NotificationService();
      await notificationService.onLogin();
      await notificationService.subscribeToRoleTopics(role);

      if (!mounted) return;

      switch (role) {
        case 'admin':
          Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (_) => const AdminDashboard()));
          break;
        case 'engineer':
          Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (_) => const EngineerDashboard()));
          break;
        case 'marketing_admin':
          // Load permissions before navigating so the dashboard can render instantly
          if (!mounted) return;
          await context.read<PermissionsProvider>().load();
          if (!mounted) return;
          Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (_) => const MarketingAdminDashboard()));
          break;
        case 'engineering_admin':
          Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (_) => const EngineeringAdminDashboard()));
          break;
        default:
          Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const HomePage()));
          break;
      }
    } catch (e) {
      if (!mounted) return;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(_friendlyError(e))),
            ],
          ),
          backgroundColor: isDark ? const Color(0xFFCF6679) : Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('invalid login credentials')) {
      return 'Invalid email or password. Please try again.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Please confirm your email address first.';
    }
    if (msg.contains('network') || msg.contains('socket')) {
      return 'Network error. Check your connection.';
    }
    if (msg.contains('too many')) {
      return 'Too many attempts. Please wait and try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  // ─── FORGOT PASSWORD ──────────────────────────────────────

  void _showForgotPasswordDialog() {
    final t = S.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resetEmailController = TextEditingController();
    final resetFormKey = GlobalKey<FormState>();
    bool isResetting = false;
    bool resetSent = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return Dialog(
              backgroundColor: Brand.surface(isDark),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Brand.r(24)),
                side: isDark
                    ? BorderSide(color: Brand.darkBorder, width: 1)
                    : BorderSide.none,
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: resetSent
                    ? _buildResetSuccessContent(
                        resetEmailController.text.trim(),
                        () => Navigator.pop(dialogCtx),
                        isDark,
                      )
                    : _buildResetFormContent(
                        t: t,
                        resetEmailController: resetEmailController,
                        resetFormKey: resetFormKey,
                        isResetting: isResetting,
                        isDark: isDark,
                        onCancel: () => Navigator.pop(dialogCtx),
                        onReset: () async {
                          if (!resetFormKey.currentState!.validate()) return;
                          setDialogState(() => isResetting = true);
                          try {
                            await SupabaseConfig.client.auth
                                .resetPasswordForEmail(
                              resetEmailController.text.trim(),
                              redirectTo: 'iconnect://password-reset',
                            );
                            setDialogState(() {
                              isResetting = false;
                              resetSent = true;
                            });
                          } catch (e) {
                            setDialogState(() => isResetting = false);
                            if (dialogCtx.mounted) {
                              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.error_outline_rounded,
                                          color: Colors.white, size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _friendlyError(e),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: isDark
                                      ? const Color(0xFFCF6679)
                                      : Colors.red,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(Brand.r(12))),
                                  margin: const EdgeInsets.all(16),
                                ),
                              );
                            }
                          }
                        },
                      ),
              ),
            );
          },
        );
      },
    ).then((_) => resetEmailController.dispose());
  }

  Widget _buildResetFormContent({
    required S t,
    required TextEditingController resetEmailController,
    required GlobalKey<FormState> resetFormKey,
    required bool isResetting,
    required bool isDark,
    required VoidCallback onCancel,
    required VoidCallback onReset,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            color: isDark
                ? Brand.lightGreen.withAlpha(((0.12) * 255).toInt())
                : Brand.lightGreenSurface,
            borderRadius: BorderRadius.circular(Brand.r(20)),
            border: isDark
                ? Border.all(color: Brand.lightGreen.withAlpha(((0.15) * 255).toInt()))
                : null,
          ),
          child: Icon(Icons.lock_reset_rounded,
              color: isDark ? Brand.lightGreenBright : Brand.lightGreen,
              size: 34),
        ),
        const SizedBox(height: 20),
        Text('Reset Password',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            )),
        const SizedBox(height: 10),
        Text(
          'Enter your email address and we\'ll send you a link to reset your password.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        Form(
          key: resetFormKey,
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
              borderRadius: BorderRadius.circular(Brand.r(14)),
              border: Border.all(
                color: isDark ? Brand.darkBorderLight : Brand.borderLight,
              ),
            ),
            child: TextFormField(
              controller: resetEmailController,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please enter your email';
                }
                // H9: reject "a@b." / "a@b" / "a@.b" / whitespace — these
                // all satisfied the old contains() check but are not valid
                // addresses and only fail later against Supabase Auth.
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
                  return 'Please enter a valid email';
                }
                return null;
              },
              decoration: InputDecoration(
                hintText: 'Enter your email address',
                hintStyle: TextStyle(
                  color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                  fontSize: 14,
                ),
                prefixIcon: Icon(Icons.email_rounded,
                    color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                    size: 20),
                enabledBorder: InputBorder.none,
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Brand.r(14)),
                  borderSide: BorderSide(
                    color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                    width: 1.5,
                  ),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: isResetting ? null : onCancel,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(Brand.r(14)),
                  ),
                  child: Center(
                    child: Text(t.commonCancel,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight,
                          fontSize: 15,
                        )),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: isResetting ? null : onReset,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [Brand.darkIconActive, Brand.royalBlueGlow]
                          : [Brand.royalBlue, Brand.royalBlueLight],
                    ),
                    borderRadius: BorderRadius.circular(Brand.r(14)),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Brand.darkIconActive.withAlpha(((0.3) * 255).toInt())
                            : Brand.royalBlue.withAlpha(((0.35) * 255).toInt()),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: isResetting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Text('Send Link',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 15,
                            )),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResetSuccessContent(
      String email, VoidCallback onClose, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            color: isDark
                ? Brand.lightGreen.withAlpha(((0.12) * 255).toInt())
                : Brand.lightGreenSurface,
            borderRadius: BorderRadius.circular(Brand.r(20)),
            border: isDark
                ? Border.all(color: Brand.lightGreen.withAlpha(((0.15) * 255).toInt()))
                : null,
          ),
          child: Icon(Icons.mark_email_read_rounded,
              color: isDark ? Brand.lightGreenBright : Brand.lightGreen,
              size: 34),
        ),
        const SizedBox(height: 20),
        Text('Check Your Email',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            )),
        const SizedBox(height: 10),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              height: 1.5,
            ),
            children: [
              const TextSpan(text: 'We\'ve sent a password reset link to\n'),
              TextSpan(
                text: email,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
            borderRadius: BorderRadius.circular(Brand.r(14)),
            border: Border.all(
              color: isDark ? Brand.darkBorderLight : Brand.borderLight,
            ),
          ),
          child: Column(
            children: [
              _buildInstructionRow(
                  '1', 'Open the email from iFrontiers', isDark),
              const SizedBox(height: 10),
              _buildInstructionRow(
                  '2', 'Click the reset password link', isDark),
              const SizedBox(height: 10),
              _buildInstructionRow('3', 'Create your new password', isDark),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? Brand.lightGreen.withAlpha(((0.08) * 255).toInt())
                : Brand.lightGreenSurface,
            borderRadius: BorderRadius.circular(Brand.r(12)),
            border: Border.all(
              color: Brand.lightGreen.withAlpha(((isDark ? 0.15 : 0.2) * 255).toInt()),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: isDark ? Brand.lightGreenBright : Brand.lightGreen,
                  size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Didn\'t receive the email? Check your spam folder or try again.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: onClose,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [Brand.darkIconActive, Brand.royalBlueGlow]
                      : [Brand.royalBlue, Brand.royalBlueLight],
                ),
                borderRadius: BorderRadius.circular(Brand.r(14)),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Brand.darkIconActive.withAlpha(((0.3) * 255).toInt())
                        : Brand.royalBlue.withAlpha(((0.35) * 255).toInt()),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Center(
                child: Text('Back to Login',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 15,
                    )),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInstructionRow(String number, String text, bool isDark) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isDark ? Brand.darkIconActive : Brand.royalBlue,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                )),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                fontWeight: FontWeight.w500,
              )),
        ),
      ],
    );
  }

  // ─── BUILD ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = S.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Brand.canvas(isDark),
      ),
      child: Scaffold(
        backgroundColor: Brand.canvas(isDark),
        body: Stack(
          children: [
            // Top header — NavyGlow: deep radial gradient + glow orbs
            //              Workshop: flat ink panel with hairline border
            Container(
              height: MediaQuery.of(context).size.height * 0.38,
              decoration: BoxDecoration(
                color: Brand.isWorkshop ? Brand.workshopInk : null,
                gradient: Brand.isWorkshop
                    ? null
                    : LinearGradient(
                        colors: [Brand.splashNavyGlow, Brand.splashNavyEdge],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                borderRadius: Brand.isWorkshop
                    ? BorderRadius.zero
                    : const BorderRadius.only(
                        bottomLeft: Radius.circular(40),
                        bottomRight: Radius.circular(40),
                      ),
                border: Brand.isWorkshop
                    ? const Border(
                        bottom: BorderSide(
                            color: Brand.workshopHairline, width: 1.5))
                    : null,
              ),
              child: Stack(
                children: [
                  if (!Brand.isWorkshop) ...[
                    Positioned(
                      top: -60,
                      right: -40,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withAlpha(10),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -20,
                      left: -30,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withAlpha(6),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Content
            SafeArea(
              child: SingleChildScrollView(
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          const SizedBox(height: 30),

                          // Logo — white iConnect lockup on the dark login bg
                          const AppLogo.full(height: 92, dark: true),

                          const SizedBox(height: 20),

                          Text(t.authWelcomeBack,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.5,
                                color: isDark
                                    ? Brand.darkTextPrimary
                                    : Colors.white,
                              )),
                          const SizedBox(height: 6),
                          Text(t.authLoginSubtitle,
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Colors.white.withAlpha(((0.55) * 255).toInt()),
                              )),

                          const SizedBox(height: 40),

                          // Login Card
                          Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: Brand.surface(isDark),
                              borderRadius: Brand.isWorkshop
                                  ? BorderRadius.circular(8)
                                  : BorderRadius.circular(Brand.r(24)),
                              border: Brand.isWorkshop
                                  ? Border.all(
                                      color: Brand.cardBorder(isDark),
                                      width: Brand.cardBorderWidth)
                                  : isDark
                                      ? Border.all(color: Brand.darkBorder)
                                      : null,
                              boxShadow: Brand.isWorkshop || isDark
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: Brand.royalBlue.withAlpha(18),
                                        blurRadius: 28,
                                        offset: const Offset(0, 10),
                                      ),
                                      BoxShadow(
                                        color: Colors.black.withAlpha(10),
                                        blurRadius: 10,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Email
                                  Text(t.labelEmail,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Brand.darkTextPrimary
                                            : Brand.royalBlueDark,
                                      )),
                                  const SizedBox(height: 8),
                                  _buildInputField(
                                    controller: _emailController,
                                    hint: t.authEmailHint,
                                    icon: Icons.email_rounded,
                                    keyboardType: TextInputType.emailAddress,
                                    isDark: isDark,
                                    validator: (v) {
                                      if (v == null || v.isEmpty) {
                                        return 'Please enter your email';
                                      }
                                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                          .hasMatch(v.trim())) {
                                        return 'Please enter a valid email';
                                      }
                                      return null;
                                    },
                                  ),

                                  const SizedBox(height: 20),

                                  // Password
                                  Text(t.labelPassword,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Brand.darkTextPrimary
                                            : Brand.royalBlueDark,
                                      )),
                                  const SizedBox(height: 8),
                                  _buildInputField(
                                    controller: _passwordController,
                                    hint: t.authPasswordHint,
                                    icon: Icons.lock_rounded,
                                    isPassword: true,
                                    isDark: isDark,
                                    validator: (v) {
                                      if (v == null || v.isEmpty) {
                                        return 'Please enter your password';
                                      }
                                      if (v.length < 6) {
                                        return 'Password must be at least 6 characters';
                                      }
                                      return null;
                                    },
                                  ),

                                  const SizedBox(height: 4),

                                  // Forgot password
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: _showForgotPasswordDialog,
                                      child: Text(t.authForgotPassword,
                                          style: TextStyle(
                                            color: isDark
                                                ? Brand.lightGreenBright
                                                : Brand.lightGreen,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          )),
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  // Login Button
                                  SizedBox(
                                    width: double.infinity,
                                    child: GestureDetector(
                                      onTap: _isLoading ? null : _login,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 16),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: isDark
                                                ? [
                                                    Brand.darkIconActive,
                                                    Brand.royalBlueGlow
                                                  ]
                                                : [
                                                    Brand.royalBlueDark,
                                                    Brand.royalBlueLight
                                                  ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(Brand.r(14)),
                                          boxShadow: isDark
                                              ? null
                                              : [
                                                  BoxShadow(
                                                    color: Brand.royalBlue
                                                        .withAlpha(89),
                                                    blurRadius: 12,
                                                    offset:
                                                        const Offset(0, 4),
                                                  ),
                                                ],
                                        ),
                                        child: Center(
                                          child: _isLoading
                                              ? const SizedBox(
                                                  width: 22,
                                                  height: 22,
                                                  child:
                                                      CircularProgressIndicator(
                                                          color: Colors.white,
                                                          strokeWidth: 2.5),
                                                )
                                              : Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const Icon(Icons.login_rounded,
                                                        color: Colors.white,
                                                        size: 20),
                                                    const SizedBox(width: 10),
                                                    Text(t.authSignIn,
                                                        style: const TextStyle(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            letterSpacing: 0.2,
                                                            color:
                                                                Colors.white)),
                                                  ],
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 28),

                          // Sign up link
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('${t.authNoAccount} ',
                                  style: TextStyle(
                                    color: isDark
                                        ? Brand.darkTextSecondary
                                        : Brand.subtleLight,
                                    fontSize: 14,
                                  )),
                              GestureDetector(
                                onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const SignupPage())),
                                child: Text(t.authSignUp,
                                    style: TextStyle(
                                      color: isDark
                                          ? Brand.lightGreenBright
                                          : Brand.lightGreen,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    )),
                              ),
                            ],
                          ),

                          const SizedBox(height: 40),

                          // Footer
                          CachedNetworkImage(
                            imageUrl: 'https://res.cloudinary.com/dez4dicac/image/upload/v1769885091/Logo_1-01_gsz76s.png',
                            height: 30,
                            color: isDark ? Brand.darkTextTertiary : null,
                            errorWidget: (_, __, ___) => Text('iFrontiers',
                                style: TextStyle(
                                  color: isDark
                                      ? Brand.darkTextTertiary
                                      : Brand.subtleLight,
                                  fontSize: 12,
                                )),
                          ),

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool isDark,
    TextInputType keyboardType = TextInputType.text,
    bool isPassword = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: isPassword ? _obscurePassword : false,
      style: TextStyle(
        fontSize: 15,
        color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
      ),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
          fontSize: 14,
        ),
        prefixIcon: Icon(icon,
            color: isDark ? Brand.darkIconActive : Brand.royalBlue, size: 20),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
        filled: true,
        fillColor: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.r(16)),
          borderSide: BorderSide(
            color: isDark ? Brand.darkBorderLight : Brand.borderLight,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.r(16)),
          borderSide: BorderSide(
            color: isDark ? Brand.darkIconActive : Brand.royalBlue,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.r(16)),
          borderSide: BorderSide(color: Colors.red.shade400),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.r(16)),
          borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
        ),
      ),
    );
  }
}
