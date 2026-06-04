import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:i_connect/l10n/s.dart';
import 'dart:async';
import '../config/supabase_config.dart';
import '../services/notification_service.dart';
import 'package:provider/provider.dart';
import '../providers/permissions_provider.dart';
import 'auth/login_page.dart';
import 'customer/customer_shell_page.dart';
import 'admin/admin_dashboard.dart';
import 'engineer/engineer_dashboard.dart';
import 'marketing/marketing_admin_dashboard.dart';
import 'engineering_admin/engineering_admin_dashboard.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _navigated = false;

  late final AnimationController _c;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoRise;
  late final Animation<double> _tagFade;
  late final Animation<double> _bottomFade;

  @override
  void initState() {
    super.initState();

    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..forward();

    // Simple, corporate reveal: logo fades + eases up and gently scales in,
    // tagline follows, then the footer/loader settle.
    _logoFade = CurvedAnimation(
        parent: _c, curve: const Interval(0.00, 0.55, curve: Curves.easeOut));
    _logoScale = Tween<double>(begin: 0.94, end: 1.0).animate(CurvedAnimation(
        parent: _c,
        curve: const Interval(0.00, 0.65, curve: Curves.easeOutCubic)));
    _logoRise = Tween<double>(begin: 12, end: 0).animate(CurvedAnimation(
        parent: _c,
        curve: const Interval(0.00, 0.60, curve: Curves.easeOutCubic)));
    _tagFade = CurvedAnimation(
        parent: _c, curve: const Interval(0.35, 0.75, curve: Curves.easeOut));
    _bottomFade = CurvedAnimation(
        parent: _c, curve: const Interval(0.55, 1.00, curve: Curves.easeOut));

    // Start auth check immediately, but wait for min animation time (0.8s for polish and readability)
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    // ── Minimum 0.8s animation for visual polish, auth check runs in parallel ──
    final minAnimationTime = Future.delayed(const Duration(milliseconds: 800));
    
    try {
      // Run auth check in parallel with animation
      final page = await _performAuthCheck();
      
      // Wait for minimum animation time to complete
      await minAnimationTime;
      
      if (!mounted) return;
      _navigateTo(page);
    } catch (e) {
      debugPrint('Auth check failed: $e');
      await minAnimationTime; // Still wait for animation polish
      if (mounted) _navigateTo(const LoginPage());
    }
  }

  /// Perform the actual authentication check and return the page to navigate to.
  Future<Widget> _performAuthCheck() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) {
      return const LoginPage();
    }

    try {
      final userData = await SupabaseConfig.client
          .from('users')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (userData == null) {
        return const LoginPage();
      }

      final role = userData['role'] as String? ?? 'customer';
      
      // Setup notifications
      final ns = NotificationService();
      unawaited(ns.onLogin().catchError((_) {}));
      unawaited(ns.subscribeToRoleTopics(role).catchError((_) {}));

      // Determine destination
      switch (role) {
        case 'admin':
          return const AdminDashboard();
        case 'engineer':
          return const EngineerDashboard();
        case 'marketing_admin':
          // Pre-load permissions for marketing admin
          if (mounted) {
            try {
              await context.read<PermissionsProvider>().load();
            } catch (_) {}
          }
          return const MarketingAdminDashboard();
        case 'engineering_admin':
          return const EngineeringAdminDashboard();
        default:
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

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // Corporate navy palette (splash is always dark).
  static const _bgTop = Color(0xFF12306B);
  static const _bgBottom = Color(0xFF081229);
  static const _green = Color(0xFFA3C638);
  static const _muted = Color(0xFF8595B4);
  static const _faint = Color(0xFF5A6B8C);

  @override
  Widget build(BuildContext context) {
    final t = S.of(context)!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _bgBottom,
      ),
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_bgTop, _bgBottom],
            ),
          ),
          child: Stack(
            children: [
              // Subtle centered glow for depth.
              Center(
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      const Color(0xFF1A56DB).withAlpha(46),
                      const Color(0xFF1A56DB).withAlpha(0),
                    ]),
                  ),
                ),
              ),

              // Centered logo + tagline (the hero).
              Center(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) {
                    return Opacity(
                      opacity: _logoFade.value,
                      child: Transform.translate(
                        offset: Offset(0, _logoRise.value),
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'assets/branding/splash_wordmark.png',
                                width: 236,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                                errorBuilder: (_, __, ___) => const Text(
                                  'iConnect',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Opacity(
                                opacity: _tagFade.value,
                                child: const Text(
                                  'STAY CONNECTED. STAY AHEAD.',
                                  style: TextStyle(
                                    color: _muted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Loader + footer pinned to the bottom.
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 44),
                  child: AnimatedBuilder(
                    animation: _bottomFade,
                    builder: (context, _) => Opacity(
                      opacity: _bottomFade.value,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 38,
                            height: 38,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor:
                                  const AlwaysStoppedAnimation<Color>(_green),
                              backgroundColor: Colors.white.withAlpha(20),
                            ),
                          ),
                          const SizedBox(height: 22),
                          const Text('Powered by',
                              style: TextStyle(color: _faint, fontSize: 11)),
                          const SizedBox(height: 4),
                          Text(
                            t.companyName,
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
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
    );
  }
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
