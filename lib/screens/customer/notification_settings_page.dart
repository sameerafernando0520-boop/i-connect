// ============================================================
// FILE: lib/screens/customer/notification_settings_page.dart
// ============================================================


import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../services/notification_service.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;

  // Master toggle
  bool _notificationsEnabled = true;

  // Push notification toggles
  bool _pushServiceReminders = true;
  bool _pushProductUpdates = true;
  bool _pushTicketUpdates = true;
  bool _pushNewMessages = true;
  bool _pushPromotions = true;
  bool _pushSystem = true;

  // Email toggles
  bool _emailTicketUpdates = false;
  bool _emailServiceReminders = false;

  // Quiet hours
  bool _quietHoursEnabled = false;
  String _quietHoursStart = '22:00';
  String _quietHoursEnd = '07:00';

  // Preferences
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;

  // Stats
  int _unreadCount = 0;
  int _totalNotifications = 0;

  // Action states
  String? _savingAction; // 'mark_read' | 'clear'

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _loadSettings();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ── Load Settings ────────────────────────────────────────
  Future<void> _loadSettings() async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;

      final settingsFuture = SupabaseConfig.client
          .from('notification_settings')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      final notifFuture = SupabaseConfig.client
          .from('notifications')
          .select('id, is_read')
          .eq('user_id', userId);

      final results = await Future.wait<dynamic>([
        settingsFuture,
        notifFuture,
      ]);
      if (!mounted) return;

      final settings = results[0] as Map<String, dynamic>?;
      final notifications = results[1] as List;

      setState(() {
        if (settings != null) {
          _notificationsEnabled = settings['push_enabled'] ?? true;
          _pushServiceReminders = settings['service_reminders'] ?? true;
          _pushProductUpdates = settings['product_updates'] ?? true;
          _pushTicketUpdates = settings['ticket_updates'] ?? true;
          _pushNewMessages = settings['new_messages'] ?? true;
          _pushPromotions = settings['promotions'] ?? true;
          _pushSystem = settings['system_alerts'] ?? true;
          _emailTicketUpdates = settings['email_enabled'] ?? false;
          _emailServiceReminders = settings['email_service_reminders'] ?? false;
          _quietHoursEnabled = settings['quiet_hours_enabled'] ?? false;
          _quietHoursStart = settings['quiet_hours_start'] ?? '22:00';
          _quietHoursEnd = settings['quiet_hours_end'] ?? '07:00';
          _soundEnabled = settings['sound_enabled'] ?? true;
          _vibrationEnabled = settings['vibration_enabled'] ?? true;
        }

        _totalNotifications = notifications.length;
        _unreadCount = notifications.where((n) => n['is_read'] == false).length;
        _isLoading = false;
      });

      _animController.forward();
    } catch (e) {
      debugPrint('NotificationSettings load error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      _animController.forward();
    }
  }

  // ── Update Setting ───────────────────────────────────────
  Future<void> _updateSetting(String field, dynamic value) async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;

      await SupabaseConfig.client.from('notification_settings').upsert(
        {'user_id': userId, field: value},
        onConflict: 'user_id',
      );

      // Update FCM topic subscriptions for push toggles
      if (field.startsWith('push_') ||
          field == 'service_reminders' ||
          field == 'product_updates' ||
          field == 'ticket_updates' ||
          field == 'new_messages' ||
          field == 'promotions' ||
          field == 'system_alerts') {
        try {
          await NotificationService.updateTopicSubscription(
              field, value as bool);
        } catch (_) {}
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to save setting', isError: true);
    }
  }

  // ── Mark All Read ────────────────────────────────────────
  Future<void> _markAllAsRead() async {
    setState(() => _savingAction = 'mark_read');

    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      await SupabaseConfig.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);

      if (!mounted) return;
      setState(() {
        _unreadCount = 0;
        _savingAction = null;
      });
      _showSnackBar('All notifications marked as read');
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingAction = null);
      _showSnackBar('Failed to mark as read', isError: true);
    }
  }

  // ── Clear All ────────────────────────────────────────────
  Future<void> _clearAllNotifications() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: isDark ? Brand.darkCard : Brand.cardLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(((isDark ? 0.15 : 0.08) * 255).toInt()),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.delete_sweep_rounded,
                    color: Colors.red.shade400, size: 34),
              ),
              const SizedBox(height: 20),
              Text(
                'Clear All Notifications?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'This will permanently delete all\nyour notifications.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(dialogCtx, false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color:
                                isDark ? Brand.darkBorder : Brand.borderLight,
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(dialogCtx, true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: Text(
                            'Clear All',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _savingAction = 'clear');

    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      await SupabaseConfig.client
          .from('notifications')
          .delete()
          .eq('user_id', userId);

      if (!mounted) return;
      setState(() {
        _unreadCount = 0;
        _totalNotifications = 0;
        _savingAction = null;
      });
      _showSnackBar('All notifications cleared');
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingAction = null);
      _showSnackBar('Failed to clear notifications', isError: true);
    }
  }

  // ── Time Picker ──────────────────────────────────────────
  void _showQuietTimePicker(bool isStart) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentTime = isStart ? _quietHoursStart : _quietHoursEnd;
    final parts = currentTime.split(':');
    int hour = int.tryParse(parts[0]) ?? (isStart ? 22 : 7);
    int minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? const ColorScheme.dark(
                    primary: Brand.darkIconActive,
                    onPrimary: Color(0xFF1A1F36),
                    surface: Brand.darkCard,
                    onSurface: Brand.darkTextPrimary,
                  )
                : const ColorScheme.light(
                    primary: Brand.royalBlueDark,
                    onPrimary: Colors.white,
                    onSurface: Brand.royalBlueDark,
                  ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: isDark ? Brand.darkCard : Brand.cardLight,
              hourMinuteShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              dayPeriodShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final formatted =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';

      setState(() {
        if (isStart) {
          _quietHoursStart = formatted;
        } else {
          _quietHoursEnd = formatted;
        }
      });

      _updateSetting(
        isStart ? 'quiet_hours_start' : 'quiet_hours_end',
        formatted,
      );
    }
  }

  // ── Helpers ──────────────────────────────────────────────
  String _formatTime(String time24) {
    final parts = time24.split(':');
    int hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts.length > 1 ? parts[1] : '00';
    final period = hour >= 12 ? 'PM' : 'AM';
    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;
    return '$hour:$minute $period';
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red : Brand.lightGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? Brand.darkBg : Brand.scaffoldLight,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color:
                      isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                      strokeWidth: 3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading settings...',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? Brand.darkBg : Brand.scaffoldLight,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: RefreshIndicator(
          color: isDark ? Brand.darkIconActive : Brand.royalBlue,
          backgroundColor: isDark ? Brand.darkCard : Brand.cardLight,
          onRefresh: _loadSettings,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(child: _buildTopBar(isDark)),
              SliverToBoxAdapter(child: _buildNotificationStats(isDark)),
              SliverToBoxAdapter(child: _buildMasterToggle(isDark)),
              if (_notificationsEnabled) ...[
                SliverToBoxAdapter(child: _buildPushNotifications(isDark)),
                SliverToBoxAdapter(child: _buildEmailNotifications(isDark)),
                SliverToBoxAdapter(child: _buildQuietHours(isDark)),
                SliverToBoxAdapter(child: _buildPreferences(isDark)),
              ],
              SliverToBoxAdapter(child: _buildActions(isDark)),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top Bar ──────────────────────────────────────────────
  Widget _buildTopBar(bool isDark) {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 8, 16, 0),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 46,
                height: 46,
                margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  color: isDark ? Brand.darkCard : Brand.cardLight,
                  borderRadius: BorderRadius.circular(12),
                  border: isDark ? Border.all(color: Brand.darkBorder) : null,
                  boxShadow: isDark ? null : [
                    BoxShadow(
                      color: Brand.royalBlue.withAlpha(15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(Icons.arrow_back_ios_new_rounded,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    size: 22),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Notification Settings',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
            ),
            if (_unreadCount > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(((0.1) * 255).toInt()),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.red.withAlpha(((0.2) * 255).toInt())),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.circle, color: Colors.red, size: 8),
                    const SizedBox(width: 5),
                    Text(
                      '$_unreadCount',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Notification Stats ───────────────────────────────────
  Widget _buildNotificationStats(bool isDark) {
    final accent = isDark ? Brand.darkIconActive : Brand.royalBlue;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  accent.withAlpha(((0.15) * 255).toInt()),
                  accent.withAlpha(((0.05) * 255).toInt()),
                ]
              : [Brand.royalBlueDark, Brand.royalBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? accent.withAlpha(((0.08) * 255).toInt())
                : Brand.royalBlueDark.withAlpha(((0.4) * 255).toInt()),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: isDark
                  ? accent.withAlpha(((0.15) * 255).toInt())
                  : Colors.white.withAlpha(((0.15) * 255).toInt()),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.notifications_rounded,
              color: isDark ? accent : Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notification Overview',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Brand.darkTextPrimary : Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$_totalNotifications total • $_unreadCount unread',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Brand.darkTextSecondary : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _notificationsEnabled
                  ? Brand.lightGreen.withAlpha(((isDark ? 0.2 : 1) * 255).toInt())
                  : Colors.red.withAlpha(((isDark ? 0.2 : 0.8) * 255).toInt()),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _notificationsEnabled ? 'ON' : 'OFF',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? (_notificationsEnabled
                        ? Brand.lightGreenBright
                        : Colors.red)
                    : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Master Toggle ────────────────────────────────────────
  Widget _buildMasterToggle(bool isDark) {
    final accent = isDark ? Brand.darkIconActive : Brand.royalBlue;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _notificationsEnabled
              ? accent.withAlpha(((0.3) * 255).toInt())
              : (isDark ? Brand.darkBorder : Brand.borderLight),
          width: _notificationsEnabled ? 1.5 : 1,
        ),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: _notificationsEnabled
                ? accent.withAlpha(20)
                : Brand.royalBlue.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _notificationsEnabled
                  ? accent.withAlpha(((0.1) * 255).toInt())
                  : (isDark ? Brand.darkCardElevated : const Color(0xFFF1F5F9)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _notificationsEnabled
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_rounded,
              color: _notificationsEnabled
                  ? accent
                  : (isDark ? Brand.darkTextSecondary : Brand.subtleLight),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'All Notifications',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _notificationsEnabled
                      ? 'You will receive notifications'
                      : 'All notifications are disabled',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.85,
            child: CupertinoSwitch(
              value: _notificationsEnabled,
              activeTrackColor: accent,
              onChanged: (val) {
                setState(() => _notificationsEnabled = val);
                _updateSetting('push_enabled', val);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Push Notifications ───────────────────────────────────
  Widget _buildPushNotifications(bool isDark) {
    final accent = isDark ? Brand.darkIconActive : Brand.royalBlue;
    final enabledCount = [
      _pushServiceReminders,
      _pushProductUpdates,
      _pushTicketUpdates,
      _pushNewMessages,
      _pushPromotions,
      _pushSystem,
    ].where((e) => e).length;

    return _buildSection(
      isDark: isDark,
      icon: Icons.phone_android_rounded,
      title: 'Push Notifications',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: accent.withAlpha(((0.1) * 255).toInt()),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$enabledCount/6',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: accent,
          ),
        ),
      ),
      children: [
        _buildToggleItem(
          icon: Icons.build_circle_rounded,
          label: 'Service Reminders',
          subtitle: 'Warranty & maintenance alerts',
          color: const Color(0xFFFF9800),
          value: _pushServiceReminders,
          isDark: isDark,
          onChanged: (val) {
            setState(() => _pushServiceReminders = val);
            _updateSetting('service_reminders', val);
          },
        ),
        _buildToggleDivider(isDark),
        _buildToggleItem(
          icon: Icons.new_releases_rounded,
          label: 'Product Updates',
          subtitle: 'New machines & catalog changes',
          color: const Color(0xFF4CAF50),
          value: _pushProductUpdates,
          isDark: isDark,
          onChanged: (val) {
            setState(() => _pushProductUpdates = val);
            _updateSetting('product_updates', val);
          },
        ),
        _buildToggleDivider(isDark),
        _buildToggleItem(
          icon: Icons.confirmation_num_rounded,
          label: 'Ticket Updates',
          subtitle: 'Status changes & assignments',
          color: const Color(0xFF2196F3),
          value: _pushTicketUpdates,
          isDark: isDark,
          onChanged: (val) {
            setState(() => _pushTicketUpdates = val);
            _updateSetting('ticket_updates', val);
          },
        ),
        _buildToggleDivider(isDark),
        _buildToggleItem(
          icon: Icons.chat_rounded,
          label: 'New Messages',
          subtitle: 'Chat & support messages',
          color: const Color(0xFF00BCD4),
          value: _pushNewMessages,
          isDark: isDark,
          onChanged: (val) {
            setState(() => _pushNewMessages = val);
            _updateSetting('new_messages', val);
          },
        ),
        _buildToggleDivider(isDark),
        _buildToggleItem(
          icon: Icons.local_offer_rounded,
          label: 'Promotions & Offers',
          subtitle: 'Special deals & discounts',
          color: const Color(0xFFE91E63),
          value: _pushPromotions,
          isDark: isDark,
          onChanged: (val) {
            setState(() => _pushPromotions = val);
            _updateSetting('promotions', val);
          },
        ),
        _buildToggleDivider(isDark),
        _buildToggleItem(
          icon: Icons.security_rounded,
          label: 'System Alerts',
          subtitle: 'Important system announcements',
          color: Brand.royalBlueDark,
          value: _pushSystem,
          isDark: isDark,
          onChanged: (val) {
            setState(() => _pushSystem = val);
            _updateSetting('system_alerts', val);
          },
        ),
      ],
    );
  }

  // ── Email Notifications ──────────────────────────────────
  Widget _buildEmailNotifications(bool isDark) {
    return _buildSection(
      isDark: isDark,
      icon: Icons.email_rounded,
      title: 'Email Notifications',
      children: [
        _buildToggleItem(
          icon: Icons.confirmation_num_outlined,
          label: 'Ticket Updates via Email',
          subtitle: 'Get ticket status changes in email',
          color: const Color(0xFF2196F3),
          value: _emailTicketUpdates,
          isDark: isDark,
          onChanged: (val) {
            setState(() => _emailTicketUpdates = val);
            _updateSetting('email_enabled', val);
          },
        ),
        _buildToggleDivider(isDark),
        _buildToggleItem(
          icon: Icons.build_outlined,
          label: 'Service Reminders via Email',
          subtitle: 'Maintenance alerts in your inbox',
          color: const Color(0xFFFF9800),
          value: _emailServiceReminders,
          isDark: isDark,
          onChanged: (val) {
            setState(() => _emailServiceReminders = val);
            _updateSetting('email_service_reminders', val);
          },
        ),
      ],
    );
  }

  // ── Quiet Hours ──────────────────────────────────────────
  Widget _buildQuietHours(bool isDark) {
    const quietColor = Color(0xFF5C6BC0);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _quietHoursEnabled
              ? quietColor.withAlpha(((0.3) * 255).toInt())
              : (isDark ? Brand.darkBorder : Brand.borderLight),
        ),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: quietColor.withAlpha(((0.1) * 255).toInt()),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.nightlight_round,
                    color: quietColor, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quiet Hours',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pause notifications during set hours',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                      ),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.85,
                child: CupertinoSwitch(
                  value: _quietHoursEnabled,
                  activeTrackColor: quietColor,
                  onChanged: (val) {
                    setState(() => _quietHoursEnabled = val);
                    _updateSetting('quiet_hours_enabled', val);
                  },
                ),
              ),
            ],
          ),
          if (_quietHoursEnabled) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildTimeCard(
                    label: 'Start',
                    time: _formatTime(_quietHoursStart),
                    icon: Icons.bedtime_rounded,
                    onTap: () => _showQuietTimePicker(true),
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Brand.darkCardElevated
                        : const Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_forward_rounded,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTimeCard(
                    label: 'End',
                    time: _formatTime(_quietHoursEnd),
                    icon: Icons.wb_sunny_rounded,
                    onTap: () => _showQuietTimePicker(false),
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: quietColor.withAlpha(((0.06) * 255).toInt()),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: quietColor.withAlpha(((0.15) * 255).toInt())),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: quietColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Notifications will be silenced from ${_formatTime(_quietHoursStart)} to ${_formatTime(_quietHoursEnd)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeCard({
    required String label,
    required String time,
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCardElevated : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
           border: isDark
           ? Border.all(color: Brand.darkBorder) : null,
        ),
        child: Column(
          children: [
            const Icon(Icons.access_time_rounded,
                color: Color(0xFF5C6BC0), size: 22),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              time,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Preferences ──────────────────────────────────────────
  Widget _buildPreferences(bool isDark) {
    return _buildSection(
      isDark: isDark,
      icon: Icons.tune_rounded,
      title: 'Preferences',
      children: [
        _buildToggleItem(
          icon: Icons.volume_up_rounded,
          label: 'Notification Sound',
          subtitle: 'Play sound for notifications',
          color: const Color(0xFF00BCD4),
          value: _soundEnabled,
          isDark: isDark,
          onChanged: (val) {
            setState(() => _soundEnabled = val);
            _updateSetting('sound_enabled', val);
          },
        ),
        _buildToggleDivider(isDark),
        _buildToggleItem(
          icon: Icons.vibration_rounded,
          label: 'Vibration',
          subtitle: 'Vibrate for notifications',
          color: const Color(0xFF795548),
          value: _vibrationEnabled,
          isDark: isDark,
          onChanged: (val) {
            setState(() => _vibrationEnabled = val);
            _updateSetting('vibration_enabled', val);
          },
        ),
      ],
    );
  }

  // ── Actions ──────────────────────────────────────────────
  Widget _buildActions(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(20),
         border: isDark
         ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildActionItem(
            icon: Icons.done_all_rounded,
            label: 'Mark All as Read',
            subtitle: '$_unreadCount unread notifications',
            color: const Color(0xFF4CAF50),
            onTap: _unreadCount > 0 ? _markAllAsRead : null,
            enabled: _unreadCount > 0,
            isSaving: _savingAction == 'mark_read',
            isDark: isDark,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 72),
            child: Divider(
                color: isDark ? Brand.darkBorder : Brand.borderLight,
                height: 1),
          ),
          _buildActionItem(
            icon: Icons.delete_sweep_rounded,
            label: 'Clear All Notifications',
            subtitle: '$_totalNotifications notifications',
            color: Colors.red,
            onTap: _totalNotifications > 0 ? _clearAllNotifications : null,
            enabled: _totalNotifications > 0,
            isSaving: _savingAction == 'clear',
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  // ── Shared Widgets ───────────────────────────────────────
  Widget _buildSection({
    required bool isDark,
    required IconData icon,
    required String title,
    Widget? trailing,
    required List<Widget> children,
  }) {
    final accent = isDark ? Brand.darkIconActive : Brand.royalBlue;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(20),
         border: isDark
         ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color:
                      isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback? onTap,
    required bool enabled,
    required bool isSaving,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: enabled && !isSaving ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withAlpha(((0.1) * 255).toInt()),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: isSaving
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    : Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: (isDark ? Brand.darkTextSecondary : Brand.subtleLight)
                    .withAlpha(((0.5) * 255).toInt()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleItem({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required bool value,
    required bool isDark,
    required ValueChanged<bool> onChanged,
  }) {
    final accent = isDark ? Brand.darkIconActive : Brand.royalBlue;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withAlpha(((0.1) * 255).toInt()),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.75,
            child: CupertinoSwitch(
              value: value,
              activeTrackColor: accent,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleDivider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 50),
      child: Divider(
          color: isDark ? Brand.darkBorder : Brand.borderLight, height: 12),
    );
  }
}
