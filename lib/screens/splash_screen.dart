import 'dart:math' as math;
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
    with TickerProviderStateMixin {
  bool _navigated = false;

  late AnimationController _main;
  late Animation<double> _bgFade;
  late Animation<double> _wordFade;
  late Animation<double> _wordSlideY;
  late Animation<double> _tagFade;
  late Animation<double> _barFade;
  late Animation<double> _footerFade;

  late AnimationController _orbs;
  late Animation<double> _orbAngle;

  @override
  void initState() {
    super.initState();

    _main = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _bgFade     = _iv(0.00, 0.18);
    _wordFade   = _iv(0.16, 0.52);
    _wordSlideY = Tween<double>(begin: 18, end: 0).animate(CurvedAnimation(
        parent: _main, curve: const Interval(0.16, 0.56, curve: Curves.easeOutCubic)));
    _tagFade    = _iv(0.40, 0.70);
    _barFade    = _iv(0.60, 1.00);
    _footerFade = _iv(0.72, 1.00);

    _main.forward();

    _orbs = AnimationController(vsync: this, duration: const Duration(seconds: 20))
      ..repeat();
    _orbAngle = Tween<double>(begin: 0, end: 2 * math.pi)
        .animate(CurvedAnimation(parent: _orbs, curve: Curves.linear));

    Timer(const Duration(milliseconds: 3000), () {
      if (mounted) _checkAuthAndNavigate();
    });
  }

  Animation<double> _iv(double start, double end) =>
      Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: _main, curve: Interval(start, end)));

  Future<void> _checkAuthAndNavigate() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        final userData = await SupabaseConfig.client
            .from('users')
            .select('role')
            .eq('id', user.id)
            .maybeSingle();

        if (!mounted) return;
        if (userData == null) {
          _navigateTo(const LoginPage());
          return;
        }

        final role = userData['role'] as String? ?? 'customer';
        final ns = NotificationService();
        ns.onLogin().catchError((_) {});
        ns.subscribeToRoleTopics(role).catchError((_) {});
        if (!mounted) return;

        switch (role) {
          case 'admin':
            _navigateTo(const AdminDashboard());
            break;
          case 'engineer':
            _navigateTo(const EngineerDashboard());
            break;
          case 'marketing_admin':
            if (mounted) {
              try {
                await context.read<PermissionsProvider>().load();
              } catch (_) {}
            }
            if (mounted) _navigateTo(const MarketingAdminDashboard());
            break;
          case 'engineering_admin':
            _navigateTo(const EngineeringAdminDashboard());
            break;
          default:
            _navigateTo(const CustomerShellPage());
        }
      } else {
        if (mounted) _navigateTo(const LoginPage());
      }
    } catch (e) {
      debugPrint('Auth check failed: $e');
      if (mounted) _navigateTo(const LoginPage());
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
    _main.dispose();
    _orbs.dispose();
    super.dispose();
  }

  // ── Premium corporate palette (splash is always dark) ──
  static const _bgTop    = Color(0xFF0F2557);
  static const _bgMid    = Color(0xFF0B1A3B);
  static const _bgBottom = Color(0xFF071228);
  static const _blueGlow = Color(0xFF1A56DB);
  static const _green    = Color(0xFFA3C638);
  static const _muted    = Color(0xFF64748B);
  static const _faint    = Color(0xFF475569);

  @override
  Widget build(BuildContext context) {
    final t = S.of(context)!;
    final size = MediaQuery.of(context).size;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _bgBottom,
      ),
      child: Scaffold(
        body: AnimatedBuilder(
          animation: Listenable.merge([_main, _orbs]),
          builder: (context, _) {
            return Opacity(
              opacity: _bgFade.value,
              child: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_bgTop, _bgMid, _bgBottom],
                    stops: [0.0, 0.5, 1.0],
                  ),
                ),
                child: Stack(
                  children: [
                    _buildAmbientGlow(size),
                    Positioned.fill(child: _buildGrid()),
                    SafeArea(
                      child: Column(
                        children: [
                          const Spacer(flex: 3),
                          // White "iConnect" wordmark — the splash hero
                          Transform.translate(
                            offset: Offset(0, _wordSlideY.value),
                            child: Opacity(
                              opacity: _wordFade.value,
                              child: Image.asset(
                                'assets/branding/splash_wordmark.png',
                                width: 230,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                                errorBuilder: (_, __, ___) => const Text(
                                  'iConnect',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Opacity(
                            opacity: _tagFade.value,
                            child: const Text(
                              'STAY CONNECTED. STAY AHEAD.',
                              style: TextStyle(
                                color: _muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 3.2,
                              ),
                            ),
                          ),
                          const Spacer(flex: 2),
                          Opacity(
                            opacity: _barFade.value,
                            child: _buildProgress(t),
                          ),
                          const Spacer(flex: 1),
                          Opacity(
                            opacity: _footerFade.value,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 28),
                              child: Column(children: [
                                const Text('Powered by',
                                    style: TextStyle(color: _faint, fontSize: 11)),
                                const SizedBox(height: 4),
                                Text(
                                  t.companyName,
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ]),
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

  Widget _buildProgress(S t) {
    return Column(children: [
      SizedBox(
        width: 140,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: const LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: Color(0xFF1E293B),
            valueColor: AlwaysStoppedAnimation<Color>(_green),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Text(
        t.commonLoading,
        style: const TextStyle(color: _muted, fontSize: 11, letterSpacing: 1),
      ),
    ]);
  }

  Widget _buildAmbientGlow(Size size) {
    final tt = (_orbAngle.value / (2 * math.pi));
    final wobble = math.sin(tt * 2 * math.pi) * 8;
    return Positioned(
      left: (size.width / 2) - 140 + wobble,
      top: (size.height / 2) - 220,
      child: IgnorePointer(
        child: Container(
          width: 280,
          height: 280,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [_blueGlow.withAlpha(50), _blueGlow.withAlpha(0)],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGrid() => CustomPaint(
        painter: _DotGridPainter(color: Colors.white.withAlpha(8)),
      );
}

class _DotGridPainter extends CustomPainter {
  final Color color;
  const _DotGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 32.0;
    final paint = Paint()..color = color;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 0.8, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => old.color != color;
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
