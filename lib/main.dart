// ═══════════════════════════════════════════════════════════════
// FILE: lib/main.dart
// UPDATED v18 — Added localization, dotenv for env vars
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
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
import 'widgets/init_error_widget.dart';

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
late ValueNotifier<bool> _isRetrying;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _isRetrying = ValueNotifier(false);

  // ── Load environment variables ──
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('✅ Environment loaded');
  } catch (e) {
    debugPrint('❌ Failed to load .env: $e');
    debugPrint('   → Copy .env.example to .env and fill in values');
  }

  await _initializeServices();

  runApp(const MyApp());
}

/// Initialize Firebase and Supabase with timeouts.
Future<void> _initializeServices() async {
  // ── Firebase initialization with timeout (10s) ──
  // If Firebase fails, notifications won't work but the app can still function.
  try {
    await Firebase.initializeApp().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw TimeoutException('Firebase init timeout after 10s', null);
      },
    );
    debugPrint('✅ Firebase initialized');

    // ── Crashlytics: global error handlers ──
    // Suppress collection in debug to keep the dashboard clean.
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);

    // Framework errors (build / layout / rendering).
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;

    // Uncaught async errors outside the Flutter framework.
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    debugPrint('✅ Crashlytics wired');
  } catch (e) {
    _firebaseInitFailed = true;
    _firebaseInitError = e.toString();
    debugPrint('❌ Firebase init failed: $e');
  }

  // ── Supabase initialization with timeout (8s) ──
  // If Supabase fails, the app shows an error UI and user can retry.
  try {
    await SupabaseConfig.initialize().timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        throw TimeoutException('Supabase init timeout after 8s', null);
      },
    );
    debugPrint('✅ Supabase initialized');
  } catch (e) {
    _supabaseInitFailed = true;
    _supabaseInitError = e.toString();
    debugPrint('❌ Supabase init failed: $e');
  }

  // ── Background services (non-blocking) ──
  // These will not block the UI. If they fail, the app continues with reduced features.
  unawaited(
    OfflineCacheService.instance.initialize().catchError((e) {
      debugPrint('⚠️ Offline cache init failed: $e');
    }),
  );
  unawaited(
    ConnectivityService.instance.initialize().catchError((e) {
      debugPrint('⚠️ Connectivity service init failed: $e');
    }),
  );

  // ── FCM: Initialize notification service (fire-and-forget) ──
  // Notifications are non-critical; they initialize in background after app shows.
  // This prevents blank screens on poor networks.
  unawaited(
    NotificationService().initialize().then((_) {
      debugPrint('✅ Notifications initialized');
    }).catchError((e) {
      debugPrint('⚠️ Notification init failed (non-fatal): $e');
    }),
  );
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

    // Only set up auth listener if Supabase succeeded
    if (!_supabaseInitFailed) {
      _setupAuthListener();
    }

    // M7: Defer the warning SnackBar until after the first frame — before that
    // point `navigatorKey.currentContext` is null and ScaffoldMessenger can't
    // locate a host.
    if (_firebaseInitFailed && !_supabaseInitFailed) {
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
    // ── If Supabase failed, show error UI with retry ──
    if (_supabaseInitFailed) {
      return ValueListenableBuilder<bool>(
        valueListenable: _isRetrying,
        builder: (context, isRetrying, _) {
          return InitErrorWidget(
            firebaseError: _firebaseInitFailed ? _firebaseInitError : null,
            supabaseError: _supabaseInitError,
            isRetrying: isRetrying,
            onRetry: () async {
              _isRetrying.value = true;
              try {
                // Reset the flags before retrying
                _firebaseInitFailed = false;
                _firebaseInitError = null;
                _supabaseInitFailed = false;
                _supabaseInitError = null;

                // Re-initialize services
                await _initializeServices();

                if (!mounted) return;

                // If still failed after retry, keep showing error
                if (_supabaseInitFailed) {
                  _isRetrying.value = false;
                  return;
                }

                // Success! Rebuild the app
                setState(() {});
                _setupAuthListener();
              } catch (e) {
                debugPrint('Retry failed: $e');
                _supabaseInitFailed = true;
                _supabaseInitError = e.toString();
                _isRetrying.value = false;
              }
            },
          );
        },
      );
    }

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
