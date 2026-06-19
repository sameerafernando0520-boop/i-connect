// ============================================================
// lib/services/notification_service.dart
// COMPLETE — FCM tokens + settings page methods
// ============================================================

import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../config/supabase_config.dart'; // ① replaced supabase_flutter import
import '../main.dart' show navigatorKey;
import '../screens/customer/notification_list_page.dart';
import '../screens/engineering_admin/ea_notifications_page.dart';
import '../utils/app_logger.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _fcm = FirebaseMessaging.instance;
  // ② removed: final _supabase = Supabase.instance.client;

  String? _currentToken;
  bool _initialized = false;
  bool _permissionDenied = false;
  bool _listenersAttached = false;

  // ── Cache for settings ──────────────────────────────────
  static Map<String, dynamic>? _settingsCache;
  // M8: In-flight dedupe — two parallel callers to `getSettings()` must share
  // a single network round-trip, otherwise they both see the null cache, both
  // hit the DB, and (in the "no row yet" path) race on the default-insert.
  static Future<Map<String, dynamic>?>? _settingsInFlight;

  // ══════════════════════════════════════════════════════════
  // FCM INITIALIZATION
  // ══════════════════════════════════════════════════════════

  /// Maximum retry attempts for transient failures (timeouts).
  static const int _maxRetries = 3;

  /// Backoff durations between retries.
  static const List<Duration> _retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];

  /// Public entry point — retries transient failures, rethrows on final
  /// failure so callers can distinguish success from error.
  Future<void> initialize() async {
    if (_initialized) return;

    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        await _initializeCore();
        return; // Success — exit immediately.
      } catch (e) {
        // User explicitly denied permission — not transient, do not retry.
        if (_permissionDenied) return;

        final isLastAttempt = attempt == _maxRetries;
        if (isLastAttempt) {
          AppLogger.error('FCM',
              'Initialization failed after $_maxRetries attempts', error: e);
          rethrow; // Caller sees the failure.
        }

        final delay = _retryDelays[attempt - 1];
        AppLogger.warn('FCM',
            'Initialization attempt $attempt/$_maxRetries failed, '
            'retrying in ${delay.inSeconds}s',
            error: e);
        await Future.delayed(delay);
      }
    }
  }

  /// Runs the actual FCM init sequence. Throws on failure — the retry
  /// loop in [initialize] decides whether to retry or propagate.
  Future<void> _initializeCore() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    ).timeout(const Duration(seconds: 15));

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      _permissionDenied = true;
      AppLogger.warn('FCM', 'User denied notification permission');
      return;
    }

    _currentToken = await _fcm.getToken()
        .timeout(const Duration(seconds: 10));
    if (_currentToken != null) {
      await _registerToken(_currentToken!);
    }

    // Guard against duplicate listener registration on retry.
    if (!_listenersAttached) {
      _fcm.onTokenRefresh.listen((newToken) {
        _handleTokenRefresh(newToken);
      });

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
      _listenersAttached = true;
    }

    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageTap(initialMessage);
    }

    _initialized = true;
    AppLogger.info('FCM',
        'Initialized with token: ${_currentToken?.substring(0, 20)}...');
  }

  // ══════════════════════════════════════════════════════════
  // TOKEN MANAGEMENT
  // ══════════════════════════════════════════════════════════

  Future<void> _registerToken(String token) async {
    final userId = SupabaseConfig.client.auth.currentUser?.id; // ③
    if (userId == null) {
      // M9: Guard. `_registerToken` is reachable during cold-start before
      // any user has signed in (FCM returns a token regardless of auth), and
      // during token-refresh callbacks after logout. Log so this doesn't
      // look like silent data loss, then bail.
      AppLogger.warn('FCM',
          'Skipping token register — no authenticated user. '
          'Token will be registered on next onLogin().');
      return;
    }

    final platform = Platform.isIOS ? 'ios' : 'android';

    try {
      await SupabaseConfig.client.from('fcm_tokens').upsert(
        // ③
        {
          'user_id': userId,
          'token': token,
          'device_platform': platform,
          'device_info':
              '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
          'is_active': true,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,token',
      );
      AppLogger.info('FCM', 'Token registered for user $userId');
    } catch (e) {
      AppLogger.error('FCM', 'Token registration error', error: e);
    }
  }

  Future<void> _handleTokenRefresh(String newToken) async {
    final oldToken = _currentToken;
    _currentToken = newToken;

    if (oldToken != null && oldToken != newToken) {
      try {
        await SupabaseConfig.client // ③
            .from('fcm_tokens')
            .update({'is_active': false}).eq('token', oldToken);
      } catch (_) {}
    }

    await _registerToken(newToken);
  }

  Future<void> onLogin() async {
    // If initialization previously failed (e.g. cold-boot timeout), retry
    // the full sequence — user just authenticated against Supabase, so
    // network is clearly reachable.
    if (!_initialized && !_permissionDenied) {
      try {
        await initialize();
      } catch (e) {
        AppLogger.warn('FCM', 'Re-initialization on login failed (non-fatal)',
            error: e);
        // Fall through — still attempt token registration below if we
        // somehow have a token from a partial earlier init.
      }
    }

    if (_currentToken != null) {
      await _registerToken(_currentToken!);
    } else {
      try {
        _currentToken = await _fcm.getToken()
            .timeout(const Duration(seconds: 10));
        if (_currentToken != null) {
          await _registerToken(_currentToken!);
        }
      } catch (e) {
        AppLogger.warn('FCM', 'Token fetch on login failed', error: e);
      }
    }
  }

  Future<void> onLogout() async {
    if (_currentToken == null) return;

    final userId = SupabaseConfig.client.auth.currentUser?.id; // ③
    if (userId == null) return;

    try {
      await SupabaseConfig.client
          .from('fcm_tokens')
          .update({
            // ③
            'is_active': false,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('user_id', userId)
          .eq('token', _currentToken!);
      AppLogger.info('FCM', 'Token deactivated on logout');
    } catch (e) {
      AppLogger.error('FCM', 'Logout token cleanup error', error: e);
    }

    _settingsCache = null;
  }

  // ══════════════════════════════════════════════════════════
  // MESSAGE HANDLERS
  // ══════════════════════════════════════════════════════════

  void _handleForegroundMessage(RemoteMessage message) {
    AppLogger.info('FCM', 'Foreground message: ${message.notification?.title}');
    _storeNotification(message);
  }

  void _handleMessageTap(RemoteMessage message) {
    AppLogger.info('FCM', 'Message tapped: ${message.data}');
    _openNotifications();
  }

  /// Route a tapped push into the role-appropriate notifications screen.
  /// Admin/engineer/marketing dashboards surface alerts inline, so only
  /// customer and engineering-admin get a dedicated list pushed.
  Future<void> _openNotifications() async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      final nav = navigatorKey.currentState;
      if (userId == null || nav == null) return;

      final row = await SupabaseConfig.client
          .from('users')
          .select('role')
          .eq('id', userId)
          .maybeSingle();
      final role = row?['role'] as String? ?? 'customer';

      Widget? page;
      if (role == 'customer') {
        page = const NotificationListPage();
      } else if (role == 'engineering_admin') {
        page = const EaNotificationsPage();
      }
      if (page != null) {
        final target = page;
        nav.push(MaterialPageRoute(builder: (_) => target));
      }
    } catch (e) {
      AppLogger.warn('FCM', 'Notification tap routing failed', error: e);
    }
  }

  Future<void> _storeNotification(RemoteMessage message) async {
    final userId = SupabaseConfig.client.auth.currentUser?.id; // ③
    if (userId == null) return;

    try {
      final type = message.data['type'] ?? 'system';
      final relatedId = message.data['related_id'];

      await SupabaseConfig.client.from('notifications').insert({
        // ③
        'user_id': userId,
        'title': message.notification?.title ?? 'Notification',
        'body': message.notification?.body ?? '',
        'type': type,
        'related_id': relatedId,
        'is_read': false,
        // Push was already delivered via FCM — prevent dispatch-push re-sending.
        'push_sent_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      // Distinguish between duplicate-key errors (expected, silent) and real errors
      final errorMsg = e.toString().toLowerCase();
      if (errorMsg.contains('unique') || errorMsg.contains('duplicate') || errorMsg.contains('constraint')) {
        AppLogger.debug('FCM', 'Notification duplicate (expected): ${message.data['type']}');
      } else {
        AppLogger.error('FCM', 'Failed to store notification', error: e);
      }
    }
  }

  // ══════════════════════════════════════════════════════════
  // TOPIC SUBSCRIPTIONS
  // ══════════════════════════════════════════════════════════

  Future<void> subscribeToTopic(String topic) async {
    try {
      await _fcm.subscribeToTopic(topic)
          .timeout(const Duration(seconds: 10));
      AppLogger.info('FCM', 'Subscribed to topic: $topic');
    } catch (e) {
      AppLogger.error('FCM', 'Topic subscribe error', error: e);
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _fcm.unsubscribeFromTopic(topic)
          .timeout(const Duration(seconds: 10));
      AppLogger.info('FCM', 'Unsubscribed from topic: $topic');
    } catch (e) {
      AppLogger.error('FCM', 'Topic unsubscribe error', error: e);
    }
  }

  Future<void> subscribeToRoleTopics(String role) async {
    await subscribeToTopic('all_users');
    switch (role) {
      case 'customer':
        await subscribeToTopic('customers');
        break;
      case 'engineer':
        await subscribeToTopic('engineers');
        break;
      case 'admin':
        await subscribeToTopic('admins');
        break;
    }
  }

  Future<void> unsubscribeFromAllTopics() async {
    await unsubscribeFromTopic('all_users');
    await unsubscribeFromTopic('customers');
    await unsubscribeFromTopic('engineers');
    await unsubscribeFromTopic('admins');
  }

  // ══════════════════════════════════════════════════════════
  // SETTINGS PAGE METHODS (used by notification_settings_page)
  // ══════════════════════════════════════════════════════════

  /// Clear cached settings — forces reload next time
  static void clearCache() {
    _settingsCache = null;
  }

  /// Get notification settings for current user
  static Future<Map<String, dynamic>?> getSettings() async {
    if (_settingsCache != null) return _settingsCache;

    // M8: If another caller is already fetching, join that in-flight future
    // instead of issuing a parallel request (and racing on the default
    // insert).
    final inFlight = _settingsInFlight;
    if (inFlight != null) return inFlight;

    final future = _fetchSettings();
    _settingsInFlight = future;
    try {
      return await future;
    } finally {
      _settingsInFlight = null;
    }
  }

  static Future<Map<String, dynamic>?> _fetchSettings() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      final data = await SupabaseConfig.client
          .from('notification_settings')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (data != null) {
        _settingsCache = Map<String, dynamic>.from(data);
        return _settingsCache;
      }

      // Create default settings if none exist
      final defaults = {
        'user_id': userId,
        'push_enabled': true,
        'email_enabled': true,
        'ticket_updates': true,
        'new_messages': true,
        'promotions': false,
      };

      await SupabaseConfig.client
          .from('notification_settings')
          .insert(defaults);
      _settingsCache = defaults;
      return _settingsCache;
    } catch (e) {
      AppLogger.error('NotificationService', 'Error loading settings', error: e);
      return null;
    }
  }

  /// Update a single notification setting field
  static Future<bool> updateSetting(String field, dynamic value) async {
    // ③ removed local supabase variable — using SupabaseConfig.client directly
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      await SupabaseConfig.client // ③
          .from('notification_settings')
          .update({field: value}).eq('user_id', userId);

      // Update cache
      if (_settingsCache != null) {
        _settingsCache![field] = value;
      }

      return true;
    } catch (e) {
      AppLogger.error('NotificationService', 'Error updating setting', error: e);
      return false;
    }
  }

  /// Subscribe/unsubscribe from FCM topic based on setting
  static Future<void> updateTopicSubscription(
      String field, bool enabled) async {
    final service = NotificationService();
    String? topic;

    switch (field) {
      case 'ticket_updates':
        topic = 'ticket_updates';
        break;
      case 'new_messages':
        topic = 'new_messages';
        break;
      case 'promotions':
        topic = 'promotions';
        break;
      case 'push_enabled':
        // Master toggle — handle all topics
        if (enabled) {
          final settings = await getSettings();
          if (settings?['ticket_updates'] == true) {
            await service.subscribeToTopic('ticket_updates');
          }
          if (settings?['new_messages'] == true) {
            await service.subscribeToTopic('new_messages');
          }
          if (settings?['promotions'] == true) {
            await service.subscribeToTopic('promotions');
          }
        } else {
          await service.unsubscribeFromTopic('ticket_updates');
          await service.unsubscribeFromTopic('new_messages');
          await service.unsubscribeFromTopic('promotions');
        }
        return;
    }

    if (topic != null) {
      if (enabled) {
        await service.subscribeToTopic(topic);
      } else {
        await service.unsubscribeFromTopic(topic);
      }
    }
  }

  /// Mark all notifications as read for current user
  static Future<bool> markAllAsRead() async {
    // ③ removed local supabase variable — using SupabaseConfig.client directly
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      await SupabaseConfig.client // ③
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
      return true;
    } catch (e) {
      AppLogger.error('NotificationService', 'Error marking as read', error: e);
      return false;
    }
  }

  /// Delete all notifications for current user
  static Future<bool> clearAllNotifications() async {
    // ③ removed local supabase variable — using SupabaseConfig.client directly
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      await SupabaseConfig.client // ③
          .from('notifications')
          .delete()
          .eq('user_id', userId);
      return true;
    } catch (e) {
      AppLogger.error('NotificationService', 'Error clearing notifications', error: e);
      return false;
    }
  }

  /// Send a test notification to current user (creates in DB)
  static Future<bool> sendTestNotification() async {
    // ③ removed local supabase variable — using SupabaseConfig.client directly
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      await SupabaseConfig.client.from('notifications').insert({
        // ③
        'user_id': userId,
        'title': 'Test Notification',
        'body':
            'This is a test notification from iFrontiers Connect. If you see this, notifications are working correctly!',
        'type': 'system',
        'is_read': false,
      });
      return true;
    } catch (e) {
      AppLogger.error('NotificationService', 'Error sending test notification', error: e);
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════
  // GETTERS
  // ══════════════════════════════════════════════════════════

  String? get currentToken => _currentToken;
  bool get isInitialized => _initialized;
  bool get isPermissionDenied => _permissionDenied;
}
