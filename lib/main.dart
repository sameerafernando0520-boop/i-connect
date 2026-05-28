// ═══════════════════════════════════════════════════════════════
// FILE: lib/main.dart
// UPDATED v18 — Added localization, dotenv for env vars
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:i_connect/l10n/s.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState;
import 'config/supabase_config.dart';
import 'config/brand_colors.dart';
import 'providers/theme_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/permissions_provider.dart';
import 'services/notification_service.dart';
import 'services/connectivity_service.dart';
import 'services/offline_cache_service.dart';
import 'screens/splash_screen.dart';

import 'screens/auth/signup_page.dart';

import 'screens/auth/reset_password_page.dart';
import 'screens/customer/customer_shell_page.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/engineer/engineer_dashboard.dart';
import 'screens/marketing/marketing_admin_dashboard.dart';
import 'screens/engineering_admin/engineering_admin_dashboard.dart';

// ── Global navigator key for deep link navigation ──
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// M7: Init-phase telemetry. `main()` runs before any widget exists, so the
// only way to surface a failed Firebase/Supabase init to the user is to stash
// the error here and consume it once the first Scaffold mounts.
bool _firebaseInitFailed = false;
String? _firebaseInitError;
bool _supabaseInitFailed = false;
String? _supabaseInitError;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Load environment variables ──
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('✅ Environment loaded');
  } catch (e) {
    debugPrint('❌ Failed to load .env: $e');
    debugPrint('   → Copy .env.example to .env and fill in values');
  }

  try {
    await Firebase.initializeApp();
    debugPrint('✅ Firebase initialized');
  } catch (e) {
    // M7: Firebase failure makes push notifications unusable. Track it so the
    // first screen can warn the user instead of silently dropping messages.
    _firebaseInitFailed = true;
    _firebaseInitError = e.toString();
    debugPrint('❌ Firebase init failed: $e');
  }

  try {
    await SupabaseConfig.initialize();
    debugPrint('✅ Supabase initialized');
  } catch (e) {
    // M7: Without Supabase nothing works — but crashing main() would leave the
    // user staring at a Flutter error. Set the flag and let `MyApp` show a
    // recoverable error screen.
    _supabaseInitFailed = true;
    _supabaseInitError = e.toString();
    debugPrint('❌ Supabase init failed: $e');
  }

  // ── v24: Offline cache + connectivity (non-blocking) ──
  unawaited(OfflineCacheService.instance.initialize());
  unawaited(ConnectivityService.instance.initialize());

  // ── FCM: Initialize notification service (fire-and-forget — must not block runApp) ──
  // Awaiting FCM token fetches before runApp() causes a blank screen if the
  // device has no network or FCM isn't ready. Run in background instead.
  // Retries transient timeouts up to 3× with backoff (see notification_service.dart).
  unawaited(NotificationService().initialize().then((_) {
    debugPrint('✅ Notifications initialized');
  }).catchError((e) {
    debugPrint('⚠️ Notification init failed (non-fatal): $e');
  }));

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _setupAuthListener();
    // M7: Defer the warning SnackBar until after the first frame — before that
    // point `navigatorKey.currentContext` is null and ScaffoldMessenger can't
    // locate a host.
    if (_firebaseInitFailed || _supabaseInitFailed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showInitFailureBanner();
      });
    }
  }

  void _showInitFailureBanner() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    if (messenger == null) return;

    final msg = _supabaseInitFailed
        ? 'Server connection failed. Some features may not work. '
            'Please check your internet and restart.'
        : 'Push notifications are unavailable on this device.';

    messenger.showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        backgroundColor:
            _supabaseInitFailed ? Colors.red.shade700 : Brand.royalBlue,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );

    debugPrint('⚠️ Init failures surfaced — firebase=$_firebaseInitError '
        'supabase=$_supabaseInitError');
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // AUTH STATE LISTENER
  // ═══════════════════════════════════════════════════════════

  void _setupAuthListener() {
    _authSubscription =
        SupabaseConfig.client.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      final session = data.session;

      debugPrint('🔑 Auth event: $event');

      // ── Reset locale + permissions on sign-out ──
      if (event == AuthChangeEvent.signedOut) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          try {
            await ctx.read<LocaleProvider>().clearLocale();
          } catch (e) {
            debugPrint('⚠️ clearLocale on signOut failed: $e');
          }
          try {
            ctx.read<PermissionsProvider>().clear();
          } catch (e) {
            debugPrint('⚠️ PermissionsProvider.clear on signOut failed: $e');
          }
        }
        return;
      }

      // ── Token refresh: if the refresh failed the session will be null,
      //    which means the user's grant effectively expired — force re-login
      //    so subsequent DB queries don't silently fail with 401. ──
      if (event == AuthChangeEvent.tokenRefreshed) {
        if (session == null) {
          debugPrint(
              '🔑 Token refresh returned null session — forcing sign-out');
          try {
            await SupabaseConfig.client.auth.signOut();
          } catch (e) {
            debugPrint('⚠️ signOut after expired refresh failed: $e');
          }
        }
        return;
      }

      // ── Password recovery: user tapped reset email link ──
      if (event == AuthChangeEvent.passwordRecovery) {
        final nav = navigatorKey.currentState;
        if (nav != null) {
          nav.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const ResetPasswordPage()),
            (_) => false,
          );
        }
        return;
      }

      if (event == AuthChangeEvent.signedIn && session != null) {
        final userId = session.user.id;

        // ── Load this user's saved language preference ──
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          try {
            await ctx.read<LocaleProvider>().loadForUser(userId);
          } catch (e) {
            debugPrint('⚠️ loadForUser locale failed: $e');
          }
        }

        // Register FCM token on login
        try {
          await NotificationService().onLogin();
        } catch (e) {
          debugPrint('⚠️ NotificationService.onLogin failed: $e');
        }

        // Subscribe to role-based FCM topics + navigate
        try {
          final userData = await SupabaseConfig.client
              .from('users')
              .select('role')
              .eq('id', userId)
              .maybeSingle();

          if (userData != null) {
            final role = userData['role'] as String? ?? 'customer';
            await NotificationService().subscribeToRoleTopics(role);
            _navigateByRole(role);
          }
        } catch (e) {
          debugPrint('⚠️ Auth listener role fetch error: $e');
        }
      }
    });
  }

  // ═══════════════════════════════════════════════════════════
  // DEEP LINK HANDLING
  // ═══════════════════════════════════════════════════════════

  void handleDeepLinkUri(Uri uri) {
    debugPrint('🔗 Deep link received: $uri');

    final scheme = uri.scheme;
    final host = uri.host;
    final pathSegments = uri.pathSegments;

    if (scheme == 'iconnect') {
      if (host == 'auth-callback') {
        debugPrint('🔗 Auth callback — handled by auth state listener');
        return;
      }

      if (host == 'password-reset') {
        debugPrint('🔗 Password recovery deep link — auth listener will route');
        return;
      }

      if (host == 'ref' && pathSegments.isNotEmpty) {
        final raw = pathSegments.first.trim().toUpperCase();
        if (!RegExp(r'^[A-Z0-9]{3,20}$').hasMatch(raw)) {
          debugPrint(
              '🔗 Rejected malformed referral code: ${pathSegments.first}');
          return;
        }
        debugPrint('🔗 Referral code from deep link: $raw');
        _handleReferralDeepLink(raw);
        return;
      }
    }

    debugPrint('🔗 Unhandled deep link: $uri');
  }

  void _handleReferralDeepLink(String code) {
    final currentUser = SupabaseConfig.client.auth.currentUser;

    if (currentUser != null) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        ScaffoldMessenger.of(ctx).clearSnackBars();
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Referral codes can only be used during signup.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          backgroundColor: Brand.royalBlue,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.all(16),
        ));
      }
      return;
    }

    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => SignupPage(referralCode: code),
      ),
      (route) => false,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // ROLE-BASED NAVIGATION
  // ═══════════════════════════════════════════════════════════

  void _navigateByRole(String role) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    Widget destination;
    switch (role) {
      case 'admin':
        destination = const AdminDashboard();
        break;
      case 'engineer':
        destination = const EngineerDashboard();
        break;
      case 'marketing_admin':
        destination = const MarketingAdminDashboard();
        break;
      case 'engineering_admin':
        destination = const EngineeringAdminDashboard();
        break;
      default:
        destination = const CustomerShellPage();
    }

    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destination),
      (route) => false,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => PermissionsProvider()),
        // ⚠️ AppTheme REMOVED — do not add back (see handoff §5)
      ],
      child: Consumer2<ThemeProvider, LocaleProvider>(
        builder: (context, themeProvider, localeProvider, child) {
          return MaterialApp(
            title: 'i Connect',
            navigatorKey: navigatorKey,
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode:
                themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,

            // ── Localization ──
            locale: localeProvider.locale,
            supportedLocales: LocaleProvider.supported,
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],

            home: const SplashScreen(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
