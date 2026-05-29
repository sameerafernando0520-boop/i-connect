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
import 'package:cached_network_image/cached_network_image.dart';

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
  late Animation<double> _glowScale;
  late Animation<double> _glowOpacity;
  late Animation<double> _logoFade;
  late Animation<double> _logoScale;
  late Animation<double> _logoSlideY;
  late Animation<double> _wordFade;
  late Animation<double> _tagFade;
  late Animation<double> _barFade;
  late Animation<double> _footerFade;

  late AnimationController _pulse;
  late Animation<double> _pulseScale;

  late AnimationController _orbs;
  late Animation<double> _orbAngle;

  @override
  void initState() {
    super.initState();

    _main = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _bgFade      = _iv(0.00, 0.20);
    _glowScale   = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _main, curve: const Interval(0.10, 0.55, curve: Curves.easeOutCubic)));
    _glowOpacity = _iv(0.10, 0.55);
    _logoFade    = _iv(0.20, 0.60);
    _logoScale   = Tween<double>(begin: 0.8, end: 1.0)
        .animate(CurvedAnimation(parent: _main, curve: const Interval(0.20, 0.60, curve: Curves.easeOutBack)));
    _logoSlideY  = Tween<double>(begin: 20, end: 0)
        .animate(CurvedAnimation(parent: _main, curve: const Interval(0.20, 0.60, curve: Curves.easeOutCubic)));
    _wordFade    = _iv(0.50, 0.80);
    _tagFade     = _iv(0.60, 0.85);
    _barFade     = _iv(0.72, 1.00);
    _footerFade  = _iv(0.78, 1.00);

    _main.forward();

    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 1.0, end: 1.12)
        .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

    _orbs = AnimationController(vsync: this, duration: const Duration(seconds: 20))
      ..repeat();
    _orbAngle = Tween<double>(begin: 0, end: 2 * math.pi)
        .animate(CurvedAnimation(parent: _orbs, curve: Curves.linear));

    Timer(const Duration(seconds: 3), () {
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
    _pulse.dispose();
    _orbs.dispose();
    super.dispose();
  }

  // ── Premium corporate palette (hardcoded — splash is always dark) ──
  static const _bgTop    = Color(0xFF0F2557);
  static const _bgMid    = Color(0xFF0B1A3B);
  static const _bgBottom = Color(0xFF071228);
  static const _blue     = Color(0xFF3B82F6);
  static const _blueGlow = Color(0xFF1A56DB);
  static const _accent   = Color(0xFF60A5FA);
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
          animation: Listenable.merge([_main, _pulse, _orbs]),
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
                          _buildLogo(),
                          const SizedBox(height: 32),
                          Opacity(
                            opacity: _wordFade.value,
                            child: CachedNetworkImage(
                              imageUrl: 'https://res.cloudinary.com/dez4dicac/image/upload/q_auto/f_auto/v1769810412/IF_logo-01_kcln3e.png',
                              width: 170,
                              height: 65,
                              fit: BoxFit.contain,
                              errorWidget: (_, __, ___) => const SizedBox.shrink(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Opacity(
                            opacity: _wordFade.value,
                            child: _buildBrandLabel(),
                          ),
                          const SizedBox(height: 12),
                          Opacity(
                            opacity: _tagFade.value,
                            child: const Text(
                              'STAY CONNECTED. STAY AHEAD.',
                              style: TextStyle(
                                color: _muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 3.5,
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
                                const Text(
                                  'Powered by',
                                  style: TextStyle(color: _faint, fontSize: 11),
                                ),
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

  Widget _buildLogo() {
    return Transform.translate(
      offset: Offset(0, _logoSlideY.value),
      child: Opacity(
        opacity: _logoFade.value,
        child: Transform.scale(
          scale: _logoScale.value,
          child: SizedBox(
            width: 160,
            height: 160,
            child: Stack(alignment: Alignment.center, children: [
              // Outer breathing glow
              Opacity(
                opacity: _glowOpacity.value * 0.25,
                child: Transform.scale(
                  scale: _glowScale.value * _pulseScale.value,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        _blue.withAlpha(60),
                        _blue.withAlpha(0),
                      ]),
                    ),
                  ),
                ),
              ),
              // Inner ring
              Opacity(
                opacity: _glowOpacity.value * 0.6,
                child: Transform.scale(
                  scale: _glowScale.value,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _blue.withAlpha(40),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              // Logo
              ClipOval(
                child: Image.asset(
                  'assets/splash_logo.png',
                  width: 100,
                  height: 100,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.link,
                    size: 52,
                    color: _blue,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandLabel() {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _dash(_accent),
      const SizedBox(width: 10),
      const Text(
        'i CONNECT',
        style: TextStyle(
          color: _accent,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 6,
        ),
      ),
      const SizedBox(width: 10),
      _dash(_accent),
    ]);
  }

  Widget _dash(Color color) => Container(
        width: 24,
        height: 1.5,
        decoration: BoxDecoration(
          color: color.withAlpha(128),
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _buildProgress(S t) {
    return Column(children: [
      SizedBox(
        width: 140,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: const LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: Color(0xFF1E293B),
            valueColor: AlwaysStoppedAnimation<Color>(_blue),
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
    final t = (_orbAngle.value / (2 * math.pi));
    final wobble = math.sin(t * 2 * math.pi) * 8;
    return Positioned(
      left: (size.width / 2) - 140 + wobble,
      top: (size.height / 2) - 200,
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
