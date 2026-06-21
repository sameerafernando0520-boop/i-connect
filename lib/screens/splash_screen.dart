import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../config/brand_colors.dart';
import '../config/supabase_config.dart';
import '../services/notification_service.dart';
import '../utils/app_logger.dart';
import 'package:provider/provider.dart';
import '../providers/permissions_provider.dart';
import 'auth/login_page.dart';
import 'customer/customer_shell_page.dart';
import 'admin/admin_dashboard.dart';
import 'engineer/engineer_dashboard.dart';
import 'marketing/marketing_admin_dashboard.dart';
import 'engineering_admin/engineering_admin_dashboard.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  bool _navigated = false;

  // ── Entrance choreography (one pass, 2200ms) ──
  late final AnimationController _main;
  late final Animation<double> _bgFade;
  late final Animation<double> _glowIn;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoSlide;
  late final Animation<double> _tagFade;
  late final Animation<double> _tagSpacing;
  late final Animation<double> _lineGrow;
  late final Animation<double> _footerFade;

  // ── Looping ambience ──
  late final AnimationController _glowPulse;
  late final Animation<double> _glowScale;
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();

    // ── Main entrance timeline (2200ms) ──
    _main = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();

    _bgFade = _iv(0.00, 0.18, Curves.easeOut);
    _glowIn = _iv(0.05, 0.45, Curves.easeOutCubic);
    _logoFade = _iv(0.18, 0.52, Curves.easeOut);
    _logoScale = Tween<double>(begin: 0.90, end: 1.0).animate(
      CurvedAnimation(
          parent: _main,
          curve: const Interval(0.18, 0.58, curve: Curves.easeOutCubic)),
    );
    _logoSlide = Tween<double>(begin: 18, end: 0).animate(
      CurvedAnimation(
          parent: _main,
          curve: const Interval(0.18, 0.58, curve: Curves.easeOutCubic)),
    );
    _tagFade = _iv(0.42, 0.70, Curves.easeOut);
    _tagSpacing = Tween<double>(begin: 1.0, end: 3.7).animate(
      CurvedAnimation(
          parent: _main,
          curve: const Interval(0.42, 0.85, curve: Curves.easeOutCubic)),
    );
    _lineGrow = _iv(0.60, 0.90, Curves.easeInOut);
    _footerFade = _iv(0.72, 1.00, Curves.easeOut);

    // ── Breathing glow (looping) ──
    _glowPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    _glowScale = Tween<double>(begin: 0.94, end: 1.12).animate(
      CurvedAnimation(parent: _glowPulse, curve: Curves.easeInOut),
    );

    // ── Shimmer sweep (one pass) ──
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..forward();

    // Start auth check — waits minimum 0.8s for animation polish.
    _checkAuthAndNavigate();
  }

  Animation<double> _iv(double start, double end, Curve curve) =>
      Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _main, curve: Interval(start, end, curve: curve)),
      );

  @override
  void dispose() {
    _main.dispose();
    _glowPulse.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════
  //  AUTH + NAVIGATION  (preserved from existing implementation)
  // ════════════════════════════════════════════════════════════
  Future<void> _checkAuthAndNavigate() async {
    final minAnimationTime = Future.delayed(const Duration(milliseconds: 800));

    try {
      final page = await _performAuthCheck();
      await minAnimationTime;
      if (!mounted) return;
      _navigateTo(page);
    } catch (e) {
      debugPrint('Auth check failed: $e');
      await minAnimationTime;
      if (mounted) _navigateTo(const LoginPage());
    }
  }

  Future<Widget> _performAuthCheck() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return const LoginPage();

    try {
      final userData = await SupabaseConfig.client
          .from('users')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (userData == null) return const LoginPage();

      final role = userData['role'] as String? ?? 'customer';

      final ns = NotificationService();
      unawaited(ns.onLogin().catchError((_) {}));
      unawaited(ns.subscribeToRoleTopics(role).catchError((_) {}));

      switch (role) {
        case 'admin':
          return const AdminDashboard();
        case 'engineer':
          return const EngineerDashboard();
        case 'marketing_admin':
          if (mounted) {
            try {
              await context.read<PermissionsProvider>().load();
            } catch (_) {}
          }
          return const MarketingAdminDashboard();
        case 'engineering_admin':
          return const EngineeringAdminDashboard();
        default:
          AppLogger.warn('SplashScreen',
              'Unknown/unhandled role "$role" — falling back to CustomerShellPage');
          return const CustomerShellPage();
      }
    } catch (e) {
      debugPrint('Failed to fetch user role: $e');
      rethrow;
    }
  }

  void _navigateTo(Widget page) {
    if (_navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      _FadePageRoute(builder: (_) => page),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  PALETTE
  // ════════════════════════════════════════════════════════════
  static const _navyEdge = Color(0xFF081A40); // splash gradient deep edge
  static const _navyCore = Color(0xFF102A63); // splash gradient core
  static const _navyGlow = Color(0xFF15397A); // splash gradient inner glow
  static const _lime = Brand.lime;
  static const _tagColor = Color(0xFFE8EDF7); // splash tagline chip bg
  static const _footerCap = Color(0xFFB8C2D6); // splash footer cap text
  static const _footerSub = Color(0xFF8C9ABB); // splash footer sub text

  static const _ifrontiersUrl =
      'https://res.cloudinary.com/dez4dicac/image/upload/q_auto/f_auto/v1769810412/IF_logo-01_kcln3e.png';

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _navyEdge,
      ),
      child: Scaffold(
        body: AnimatedBuilder(
          animation: Listenable.merge([_main, _glowPulse, _shimmer]),
          builder: (context, _) {
            return Opacity(
              opacity: _bgFade.value,
              child: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.06),
                    radius: 1.05,
                    colors: [_navyGlow, _navyCore, _navyEdge],
                    stops: [0.0, 0.45, 1.0],
                  ),
                ),
                child: Stack(
                  children: [
                    // ── Dot grid pattern ──
                    Opacity(
                      opacity: _bgFade.value * 0.6,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _DotGridPainter(),
                      ),
                    ),

                    // ── Breathing ambient glow ──
                    _buildAmbientGlow(),

                    SafeArea(
                      child: Column(
                        children: [
                          const Spacer(flex: 5),

                          // ── Logo with shimmer ──
                          Transform.translate(
                            offset: Offset(0, _logoSlide.value),
                            child: Opacity(
                              opacity: _logoFade.value,
                              child: Transform.scale(
                                scale: _logoScale.value,
                                child: _buildWordmark(),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // ── Tagline ──
                          Opacity(
                            opacity: _tagFade.value,
                            child: Text(
                              'STAY CONNECTED. STAY AHEAD.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _tagColor,
                                fontSize: 8,
                                fontWeight: FontWeight.w500,
                                letterSpacing: _tagSpacing.value,
                              ),
                            ),
                          ),

                          const Spacer(flex: 2),

                          // ── Lime accent line ──
                          _buildLine(),

                          const Spacer(flex: 2),

                          // ── Footer ──
                          Opacity(
                            opacity: _footerFade.value,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 28),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'POWERED BY:',
                                    style: TextStyle(
                                      color: _footerCap,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 2.5,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  CachedNetworkImage(
                                    imageUrl: _ifrontiersUrl,
                                    height: 36,
                                    fit: BoxFit.contain,
                                    errorWidget: (_, __, ___) =>
                                        _ifrontiersFallback(),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Pioneering the Future',
                                    style: TextStyle(
                                      color: _footerSub,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Wordmark with shimmer sweep ──
  Widget _buildWordmark() {
    final logo = Image.asset(
      'assets/branding/splash_wordmark.png',
      width: 230,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => const Text(
        'iCONNECT',
        style: TextStyle(
          color: Colors.white,
          fontSize: 36,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
        ),
      ),
    );

    final t = _shimmer.value;
    final sweep = (t * 1.6) - 0.3;

    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [
            Colors.transparent,
            Colors.white,
            Colors.transparent,
          ],
          stops: [
            (sweep - 0.15).clamp(0.0, 1.0),
            sweep.clamp(0.0, 1.0),
            (sweep + 0.15).clamp(0.0, 1.0),
          ],
        ).createShader(bounds);
      },
      child: logo,
    );
  }

  Widget _buildAmbientGlow() {
    return Align(
      alignment: const Alignment(0, -0.18),
      child: IgnorePointer(
        child: Opacity(
          opacity: _glowIn.value * 0.6,
          child: Transform.scale(
            scale: _glowScale.value,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _navyGlow.withAlpha(150),
                    _navyGlow.withAlpha(0),
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLine() {
    return SizedBox(
      width: 140,
      height: 2,
      child: Align(
        alignment: Alignment.center,
        child: FractionallySizedBox(
          widthFactor: _lineGrow.value,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Brand.r(2)),
              gradient: LinearGradient(
                colors: [
                  _lime.withAlpha(0),
                  _lime.withAlpha(180),
                  _lime.withAlpha(0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ifrontiersFallback() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: _lime,
            borderRadius: BorderRadius.circular(Brand.r(5)),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'iFRONTIERS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

// ── Dot grid background painter ──
class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(8)
      ..style = PaintingStyle.fill;
    const spacing = 24.0;
    const radius = 0.8;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FadePageRoute<T> extends MaterialPageRoute<T> {
  _FadePageRoute({required super.builder});

  @override
  Duration get transitionDuration => const Duration(milliseconds: 600);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      FadeTransition(opacity: animation, child: child);
}
