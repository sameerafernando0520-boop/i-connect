// lib/screens/customer/home_page.dart
//
// ═══════════════════════════════════════════════════════════
//  CHANGES (v13 fix):
//   [FIX-1] Recent activity: 5 → 4 (fetch + display)
//   [FIX-2] Map mutation → spread copy (notification callback)
//   [FIX-3] Realtime cleanup: unsubscribe → removeChannel
//   [FIX-4] Category counts: computed from ALL machines via
//           dashboard join, not from 3-item _machines list
//   [FIX-5] Debounce timer (2s) for realtime-triggered reloads
//   [FIX-6] _fetchUpcomingPayments: safer join-based filter
//
//  CHANGES (v14 — Tier System):
//   [T-1]  State: _tierData, _dailyLoginChecked
//   [T-2]  Tier computed getters
//   [T-3]  Tier helper methods
//   [T-4]  _fetchTierInfo RPC method
//   [T-5]  _refreshIfStale caching guard
//   [T-6]  _loadAllData triggers _fetchTierInfo (non-blocking)
//   [T-7]  Realtime callbacks wrapped in try/catch (G5)
//   [T-8]  Nav .then() calls use _refreshIfStale where safe
//   [T-9]  _buildHeroCard replaced with tier-integrated version
//   [T-10] "Refer & Earn" quick action wired to ReferralPage
// ═══════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../widgets/common/app_logo.dart';
import '../../widgets/ds/ds_widgets.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../l10n/s.dart';
import '../../utils/time_utils.dart';
import '../../utils/string_utils.dart';
import '../../widgets/common/nav_badge_indicator.dart';
import '../../widgets/common/ic_icons.dart';
import '../../widgets/customer/promotional_carousel.dart';
import '../auth/login_page.dart';
import 'points_history_page.dart';

import 'catalog_page.dart';
import 'machine_detail_page.dart';
import 'profile_page.dart';
import 'my_machines_page.dart';
import 'support_tickets_page.dart';
import 'notification_list_page.dart';
import 'ticket_detail_page.dart';
import 'customer_installments_page.dart';
import 'referral_page.dart';
import '../../widgets/customer/customer_nav_bar.dart';
import '../../widgets/customer/customer_nav_controller.dart';

// ══════════════════════════════════════════════════════════════
//  CUSTOM ICONS — LASER
// ══════════════════════════════════════════════════════════════
class LaserIcon extends StatelessWidget {
  final Color color;
  final double size;
  const LaserIcon({super.key, this.color = Brand.royalBlue, this.size = 40});

  @override
  Widget build(BuildContext context) => Semantics(
      label: 'Laser cutter machine category',
      child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _LaserPainter(color: color))));
}

class _LaserPainter extends CustomPainter {
  final Color color;
  const _LaserPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final w = size.width, h = size.height;

    canvas.drawPath(
        Path()
          ..moveTo(w * 0.05, h * 0.08)
          ..lineTo(w * 0.95, h * 0.08)
          ..lineTo(w * 0.85, h * 0.22)
          ..lineTo(w * 0.15, h * 0.22)
          ..close(),
        paint);
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.30, h * 0.25)
          ..lineTo(w * 0.70, h * 0.25)
          ..lineTo(w * 0.62, h * 0.36)
          ..lineTo(w * 0.38, h * 0.36)
          ..close(),
        paint);
    canvas.drawRect(
        Rect.fromLTWH(w * 0.40, h * 0.37, w * 0.20, h * 0.13), paint);
    canvas.drawRect(
        Rect.fromLTWH(w * 0.465, h * 0.50, w * 0.07, h * 0.20), paint);

    final sp = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeWidth = w * 0.05
      ..strokeCap = StrokeCap.round;
    _spark(canvas, sp, Offset(w * 0.20, h * 0.60), Offset(w * 0.32, h * 0.57));
    _spark(canvas, sp, Offset(w * 0.17, h * 0.70), Offset(w * 0.32, h * 0.68));
    _spark(canvas, sp, Offset(w * 0.80, h * 0.60), Offset(w * 0.68, h * 0.57));
    _spark(canvas, sp, Offset(w * 0.83, h * 0.70), Offset(w * 0.68, h * 0.68));

    canvas.drawRect(
        Rect.fromLTWH(w * 0.05, h * 0.76, w * 0.38, h * 0.16), paint);
    canvas.drawRect(
        Rect.fromLTWH(w * 0.57, h * 0.76, w * 0.38, h * 0.16), paint);
  }

  void _spark(Canvas c, Paint p, Offset a, Offset b) {
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    final nx = -dy / len * p.strokeWidth / 2, ny = dx / len * p.strokeWidth / 2;
    c.drawPath(
        Path()
          ..moveTo(a.dx + nx, a.dy + ny)
          ..lineTo(b.dx + nx, b.dy + ny)
          ..lineTo(b.dx - nx, b.dy - ny)
          ..lineTo(a.dx - nx, a.dy - ny)
          ..close(),
        p..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_LaserPainter old) => old.color != color;
}

// ══════════════════════════════════════════════════════════════
//  CUSTOM ICONS — CNC
// ══════════════════════════════════════════════════════════════
class CncIcon extends StatelessWidget {
  final Color color;
  final double size;
  const CncIcon({super.key, this.color = Brand.royalBlue, this.size = 40});

  @override
  Widget build(BuildContext context) => Semantics(
      label: 'CNC router machine category',
      child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _CncPainter(color: color))));
}

class _CncPainter extends CustomPainter {
  final Color color;
  const _CncPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final w = size.width, h = size.height;

    final cx = w * 0.38,
        cy = h * 0.54,
        outerR = w * 0.30,
        innerR = w * 0.19,
        holeR = w * 0.07;
    const teeth = 8;
    final gearPath = Path();
    for (int i = 0; i < teeth; i++) {
      final a1 = (2 * math.pi / teeth) * i - math.pi / 2;
      final a2 = a1 + (2 * math.pi / teeth) * 0.4;
      final a3 = a2 + (2 * math.pi / teeth) * 0.2;
      final a4 = a1 + (2 * math.pi / teeth);
      if (i == 0) {
        gearPath.moveTo(cx + outerR * math.cos(a1), cy + outerR * math.sin(a1));
      } else {
        gearPath.lineTo(cx + outerR * math.cos(a1), cy + outerR * math.sin(a1));
      }
      gearPath
        ..lineTo(cx + outerR * math.cos(a2), cy + outerR * math.sin(a2))
        ..lineTo(cx + innerR * math.cos(a3), cy + innerR * math.sin(a3))
        ..lineTo(cx + innerR * math.cos(a4), cy + innerR * math.sin(a4));
    }
    gearPath.close();
    final holePath = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: holeR));
    canvas.drawPath(
        Path.combine(PathOperation.difference, gearPath, holePath), paint);
    canvas.drawCircle(
        Offset(cx, cy), w * 0.025, Paint()..color = color.withAlpha(89));

    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.62, h * 0.06, w * 0.32, h * 0.20),
            const Radius.circular(3)),
        paint);
    canvas.drawRect(Rect.fromLTWH(w * 0.63, h * 0.14, w * 0.30, h * 0.04),
        Paint()..color = Colors.white.withAlpha(89));
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.62, h * 0.28)
          ..lineTo(w * 0.94, h * 0.28)
          ..lineTo(w * 0.89, h * 0.46)
          ..lineTo(w * 0.67, h * 0.46)
          ..close(),
        paint);
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.69, h * 0.47)
          ..lineTo(w * 0.87, h * 0.47)
          ..lineTo(w * 0.78, h * 0.64)
          ..close(),
        paint);
  }

  @override
  bool shouldRepaint(_CncPainter old) => old.color != color;
}

// ══════════════════════════════════════════════════════════════
//  HOME PAGE
// ══════════════════════════════════════════════════════════════
class HomePage extends StatefulWidget {
  /// When embedded in CustomerShellPage, pass showNavBar: false so the
  /// shell's single CustomerNavBar is used instead of a per-page one.
  final bool showNavBar;
  const HomePage({super.key, this.showNavBar = true});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // ─── State ─────────────────────────────────────────────────
  // Note: HomePage represents the "Home" tab itself (currentIndex == 0).
  // Tabs 1/2/3/4 are full pushReplacement-routed pages (MyMachinesPage,
  // SupportTicketsPage, KnowledgeBasePage, ProfilePage), so we no longer
  // embed them inside this Scaffold — that was causing two stacked
  // navigation bars to render at once and the bar to scroll with content.
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  // ─── Data ──────────────────────────────────────────────────
  Map<String, dynamic> _dashboard = {};
  List<Map<String, dynamic>> _machines = [];
  List<Map<String, dynamic>> _recentActivity = [];
  List<Map<String, dynamic>> _upcomingPayments = [];

  // ─── Realtime ──────────────────────────────────────────────
  RealtimeChannel? _notificationChannel;
  RealtimeChannel? _ticketChannel;
  Timer? _realtimeDebounce; // ✅ FIX-5: debounce timer

  // ── Tier System ── [T-1]
  Map<String, dynamic> _tierData = {};
  bool _dailyLoginChecked = false;

  // ─── Animation ─────────────────────────────────────────────
  late AnimationController _heroAnimController;
  late Animation<double> _heroFadeIn;
  late Animation<Offset> _heroSlideIn;

  DateTime? _lastLoadTime;

  // ─── Journey / Suggestion System ───────────────────────────
  Map<String, dynamic>? _suggestion;
  bool _loadingSuggestion = false;

  // ─── Formatting ────────────────────────────────────────────
  static final _lkrFormat = NumberFormat('#,##0', 'en_US');

  // ─── Computed Getters ──────────────────────────────────────
  String get _userName => _dashboard['full_name'] as String? ?? '';
  String get _companyName => _dashboard['company_name'] as String? ?? '';
  String? get _profileImageUrl => _dashboard['profile_photo'] as String?;
  int get _totalMachines =>
      (_dashboard['total_machines'] as num?)?.toInt() ?? 0;
  int get _openTickets => (_dashboard['open_tickets'] as num?)?.toInt() ?? 0;
  int get _activePlans => (_dashboard['active_plans'] as num?)?.toInt() ?? 0;
  String? get _nextServiceDate => _dashboard['next_service_date'] as String?;
  String? get _nextServiceMachineName =>
      _dashboard['next_service_machine_name'] as String?;
  int get _expiringWarrantyCount =>
      (_dashboard['expiring_warranty_count'] as num?)?.toInt() ?? 0;

  // ── Installment computed ──
  int get _overduePaymentCount =>
      _upcomingPayments.where((p) => p['status'] == 'overdue').length;

  Map<String, dynamic>? get _nextDuePayment {
    final pending =
        _upcomingPayments.where((p) => p['status'] == 'pending').toList();
    if (pending.isEmpty) return null;
    pending
        .sort((a, b) => (a['due_date'] ?? '').compareTo(b['due_date'] ?? ''));
    return pending.first;
  }

  // ✅ FIX-4: category counts from full machine list (not limited 3)
  Map<String, dynamic> get _categoryCounts =>
      (_dashboard['category_counts'] is Map)
          ? Map<String, dynamic>.from(_dashboard['category_counts'] as Map)
          : <String, dynamic>{};

  // ── Tier Computed Getters ── [T-2]
  String get _currentTier =>
      (_tierData['tier'] as Map?)?['current'] as String? ?? 'bronze';
  int get _totalPoints =>
      ((_tierData['tier'] as Map?)?['total_points'] as num?)?.toInt() ?? 0;
  double get _tierProgressPercent =>
      ((_tierData['tier'] as Map?)?['progress_percent'] as num?)?.toDouble() ??
      0;
  int get _nextTierThreshold =>
      ((_tierData['tier'] as Map?)?['next_threshold'] as num?)?.toInt() ?? 500;
  int get _loginStreak =>
      ((_tierData['tier'] as Map?)?['login_streak'] as num?)?.toInt() ?? 0;


  // ═══════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _heroAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _heroFadeIn =
        CurvedAnimation(parent: _heroAnimController, curve: Curves.easeOut);
    _heroSlideIn = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _heroAnimController, curve: Curves.easeOutCubic));

    _loadAllData();
    _setupRealtimeSubscriptions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heroAnimController.dispose();
    _realtimeDebounce?.cancel(); // ✅ FIX-5

    // ✅ FIX-3: use removeChannel instead of unsubscribe
    if (_notificationChannel != null) {
      SupabaseConfig.client.removeChannel(_notificationChannel!);
    }
    if (_ticketChannel != null) {
      SupabaseConfig.client.removeChannel(_ticketChannel!);
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      if (_lastLoadTime == null ||
          now.difference(_lastLoadTime!).inSeconds > 30) {
        _loadAllData();
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  // DATA LOADING
  // ═══════════════════════════════════════════════════════════

  Future<void> _loadAllData() async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) {
        _navigateToLogin();
        return;
      }

      final results = await Future.wait<dynamic>([
        _fetchDashboard(userId),
        _fetchMachines(userId),
        _fetchRecentActivity(userId),
        _fetchUpcomingPayments(userId),
      ]);

      if (!mounted) return;

      setState(() {
        _dashboard = Map<String, dynamic>.from(results[0] as Map);
        _machines = List<Map<String, dynamic>>.from((results[1] as List)
            .map((m) => Map<String, dynamic>.from(m as Map)));
        _recentActivity = List<Map<String, dynamic>>.from((results[2] as List)
            .map((a) => Map<String, dynamic>.from(a as Map)));
        _upcomingPayments = List<Map<String, dynamic>>.from((results[3] as List)
            .map((p) => Map<String, dynamic>.from(p as Map)));
        _isLoading = false;
        _hasError = false;
      });

      // Propagate the open-ticket count to the shell's shared nav badge.
      CustomerNavController.setOpenTickets(_openTickets);

      if (!_heroAnimController.isCompleted) {
        _heroAnimController.forward();
      }
      _lastLoadTime = DateTime.now();

      // Fetch tier info separately (non-blocking, non-critical) [T-6]
      _fetchTierInfo(userId);
      _loadSuggestion(); // non-blocking, fire-and-forget
    } catch (e) {
      debugPrint('Home page load error: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Unable to load data. Pull down to retry.';
      });
    }
  }

  // Consolidated home load: ONE RPC round-trip (get_customer_dashboard_summary)
  // instead of ~7 separate queries. Falls back to the per-query path on any
  // failure so the home screen never breaks.
  Future<Map<String, dynamic>> _fetchDashboard(String userId) async {
    try {
      final res = await SupabaseConfig.client
          .rpc('get_customer_dashboard_summary', params: {'p_user_id': userId});
      if (res is Map) {
        final data = Map<String, dynamic>.from(res);
        final ns = data['next_service'];
        return _assembleDashboard(
          userData: data['profile'] is Map
              ? Map<String, dynamic>.from(data['profile'] as Map)
              : <String, dynamic>{},
          machineList: ((data['machines'] as List?) ?? const [])
              .map((m) => Map<String, dynamic>.from(m as Map))
              .toList(),
          ticketList: ((data['tickets'] as List?) ?? const [])
              .map((t) => Map<String, dynamic>.from(t as Map))
              .toList(),
          planList: ((data['plans'] as List?) ?? const [])
              .map((p) => Map<String, dynamic>.from(p as Map))
              .toList(),
          unreadCount: (data['unread_notifications'] as num?)?.toInt() ?? 0,
          nextServiceDate: ns is Map ? ns['next_service_due'] as String? : null,
          nextServiceMachineName: ns is Map ? ns['machine_name'] as String? : null,
          expiringWarrantyCount:
              (data['expiring_warranty_count'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (e) {
      debugPrint('⚠️ get_customer_dashboard_summary failed, using fallback: $e');
    }
    return _fetchDashboardLegacy(userId);
  }

  Future<Map<String, dynamic>> _fetchDashboardLegacy(String userId) async {
    final results = await Future.wait<dynamic>([
      SupabaseConfig.client
          .from('users')
          .select('full_name, company_name, profile_photo, created_at')
          .eq('id', userId)
          .maybeSingle(),
      // ✅ FIX-4: added machine_catalog(category) join for category counts
      SupabaseConfig.client
          .from('customer_machines')
          .select('id, status, machine_catalog(category)')
          .eq('user_id', userId),
      SupabaseConfig.client
          .from('service_tickets')
          .select('id, status, ticket_type')
          .eq('user_id', userId)
          .eq('is_deleted', false),
      SupabaseConfig.client
          .from('installment_plans')
          .select('id, payment_status')
          .eq('user_id', userId),
    ]);

    final userData = results[0] != null
        ? Map<String, dynamic>.from(results[0] as Map)
        : <String, dynamic>{};
    final machineList = (results[1] as List? ?? [])
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();
    final ticketList = (results[2] as List? ?? [])
        .map((t) => Map<String, dynamic>.from(t as Map))
        .toList();
    final planList = (results[3] as List? ?? [])
        .map((p) => Map<String, dynamic>.from(p as Map))
        .toList();

    int unreadCount = 0;
    try {
      final unreadResult = await SupabaseConfig.client
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);
      unreadCount = (unreadResult as List?)?.length ?? 0;
    } catch (_) {}

    String? nextServiceDate;
    String? nextServiceMachineName;
    int expiringWarrantyCount = 0;

    try {
      final upcomingService = await SupabaseConfig.client
          .from('customer_machines')
          .select('next_service_due, machine_catalog!inner(machine_name)')
          .eq('user_id', userId)
          .not('next_service_due', 'is', null)
          .gte('next_service_due', DateTime.now().toUtc().toIso8601String())
          .order('next_service_due', ascending: true)
          .limit(1);

      if (upcomingService.isNotEmpty) {
        nextServiceDate = upcomingService[0]['next_service_due'];
        final catalog =
            upcomingService[0]['machine_catalog'] as Map<String, dynamic>?;
        nextServiceMachineName = catalog?['machine_name'];
      }

      final thirtyDaysFromNow = DateTime.now().add(const Duration(days: 30));
      final expiringWarranties = await SupabaseConfig.client
          .from('customer_machines')
          .select('id')
          .eq('user_id', userId)
          .gte('warranty_end_date', DateTime.now().toUtc().toIso8601String())
          .lte('warranty_end_date', thirtyDaysFromNow.toIso8601String());

      expiringWarrantyCount = (expiringWarranties as List?)?.length ?? 0;
    } catch (_) {}

    return _assembleDashboard(
      userData: userData,
      machineList: machineList,
      ticketList: ticketList,
      planList: planList,
      unreadCount: unreadCount,
      nextServiceDate: nextServiceDate,
      nextServiceMachineName: nextServiceMachineName,
      expiringWarrantyCount: expiringWarrantyCount,
    );
  }

  /// Pure assembly of the home dashboard map from raw inputs — shared by the
  /// consolidated RPC fast-path and the legacy per-query fallback.
  Map<String, dynamic> _assembleDashboard({
    required Map<String, dynamic> userData,
    required List<Map<String, dynamic>> machineList,
    required List<Map<String, dynamic>> ticketList,
    required List<Map<String, dynamic>> planList,
    required int unreadCount,
    required String? nextServiceDate,
    required String? nextServiceMachineName,
    required int expiringWarrantyCount,
  }) {
    final categoryCounts = <String, int>{};
    for (final m in machineList) {
      final catalog = m['machine_catalog'] as Map<String, dynamic>?;
      final cat = catalog?['category'] as String?;
      if (cat != null && cat.isNotEmpty) {
        categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
      }
    }

    int progress = 0;
    if (userData['full_name'] != null && userData['company_name'] != null) {
      progress += 10;
    }
    if (machineList.isNotEmpty) {
      progress += 15 + ((machineList.length - 1) * 10).clamp(0, 30);
    }
    if (ticketList.any((t) => t['ticket_type'] == 'support')) {
      progress += 10;
    }
    if (ticketList.any((t) => t['ticket_type'] == 'inquiry')) {
      progress += 10;
    }
    if (ticketList.any((t) => t['ticket_type'] == 'order')) {
      progress += 15;
    }
    progress = progress.clamp(0, 100);

    return {
      'full_name': userData['full_name'] ?? '',
      'company_name': userData['company_name'] ?? '',
      'profile_photo': userData['profile_photo'],
      'member_since': userData['created_at'],
      'total_machines': machineList.length,
      'active_machines':
          machineList.where((m) => m['status'] == 'active').length,
      'machines_in_service':
          machineList.where((m) => m['status'] == 'service').length,
      // Active set (per project spec): badge counts only tickets that are
      // genuinely still open. Anything in the closed set
      // {'resolved','closed','completed','cancelled'} must NOT show in the badge.
      // Using a positive whitelist guards against new closed-style statuses
      // (e.g. 'completed') being miscounted as "open".
      'open_tickets': ticketList
          .where((t) => const {
                'new',
                'open',
                'assigned',
                'in_progress',
                'waiting_customer',
              }.contains(t['status']))
          .length,
      'total_tickets': ticketList.length,
      'pending_inquiries': ticketList
          .where((t) =>
              t['ticket_type'] == 'inquiry' &&
              const {
                'new',
                'open',
                'assigned',
                'in_progress',
                'waiting_customer',
              }.contains(t['status']))
          .length,
      'active_orders': ticketList
          .where((t) =>
              t['ticket_type'] == 'order' &&
              const {
                'new',
                'open',
                'assigned',
                'in_progress',
                'waiting_customer',
              }.contains(t['status']))
          .length,
      'progress_percentage': progress,
      'unread_notifications': unreadCount,
      'next_service_date': nextServiceDate,
      'next_service_machine_name': nextServiceMachineName,
      'expiring_warranty_count': expiringWarrantyCount,
      'active_plans':
          planList.where((p) => p['payment_status'] == 'active').length,
      // ✅ FIX-4: store category counts in dashboard
      'category_counts': Map<String, dynamic>.from(categoryCounts),
    };
  }

  Future<List<Map<String, dynamic>>> _fetchMachines(String userId) async {
    try {
      final response = await SupabaseConfig.client
          .from('customer_machines')
          .select('''
            id, serial_number, purchase_date, warranty_end_date,
            next_service_due, status, catalog_machine_id,
            machine_catalog!inner(
              machine_name, model_number, category, brand,
              product_images, image_url, images
            )
          ''')
          .eq('user_id', userId)
          .order('purchase_date', ascending: false)
          .limit(3);

      return List<Map<String, dynamic>>.from(response).map((m) {
        final catalog = m['machine_catalog'] as Map<String, dynamic>? ?? {};
        return {
          'machine_id': m['id'],
          'catalog_machine_id': m['catalog_machine_id'],
          'machine_name': catalog['machine_name'] ?? 'Unknown Machine',
          'model_number': catalog['model_number'] ?? '',
          'category': catalog['category'] ?? '',
          'brand': catalog['brand'] ?? '',
          'serial_number': m['serial_number'],
          'purchase_date': m['purchase_date'],
          'warranty_end_date': m['warranty_end_date'],
          'next_service_due': m['next_service_due'],
          'status': m['status'] ?? 'active',
          'product_image': _getMachineImage(catalog),
          'days_until_service': m['next_service_due'] != null
              ? DateTime.parse(m['next_service_due'])
                  .difference(DateTime.now())
                  .inDays
              : null,
          'warranty_active': m['warranty_end_date'] != null
              ? DateTime.parse(m['warranty_end_date']).isAfter(DateTime.now())
              : false,
        };
      }).toList();
    } catch (e) {
      debugPrint('⚠️ Fetch machines error: $e');
      return [];
    }
  }

  String? _getMachineImage(Map<String, dynamic> catalog) {
    final p = catalog['product_images'];
    if (p is List && p.isNotEmpty) return p[0] as String?;
    final u = catalog['image_url'];
    if (u is String && u.isNotEmpty) return u;
    final i = catalog['images'];
    if (i is List && i.isNotEmpty) return i[0] as String?;
    return null;
  }

  // ✅ FIX-1: limit changed from 5 → 4
  Future<List<Map<String, dynamic>>> _fetchRecentActivity(String userId) async {
    try {
      final tickets = await SupabaseConfig.client
          .from('service_tickets')
          .select(
              'id, ticket_number, ticket_type, subject, status, updated_at, created_at')
          .eq('user_id', userId)
          .eq('is_deleted', false)
          .order('updated_at', ascending: false)
          .limit(4);

      return List<Map<String, dynamic>>.from(tickets)
          .map((t) => {
                'activity_type': t['ticket_type'] ?? 'support',
                'title': t['subject'] ?? 'Ticket',
                'subtitle': 'Ticket #${t['ticket_number'] ?? ''}',
                'activity_date': t['updated_at'] ?? t['created_at'],
                'related_id': t['id'],
                'status': t['status'] ?? 'open',
              })
          .toList();
    } catch (e) {
      debugPrint('⚠️ Fetch activity error: $e');
      return [];
    }
  }

  // ✅ FIX-6: safer join-based filter (no direct user_id on payments)
  Future<List<Map<String, dynamic>>> _fetchUpcomingPayments(
      String userId) async {
    try {
      final response = await SupabaseConfig.client
          .from('installment_payments')
          .select('''
            id, installment_number, amount, due_date, status,
            installment_plans!inner(
              id, payment_status, num_installments,
              customer_machines(
                serial_number,
                machine_catalog(machine_name)
              )
            )
          ''')
          .eq('installment_plans.user_id', userId)
          .inFilter('status', ['pending', 'overdue'])
          .order('due_date', ascending: true)
          .limit(10);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('⚠️ Fetch upcoming payments error: $e');
      return [];
    }
  }

  // ── Tier Info Fetch ── [T-4]
  Future<void> _fetchTierInfo(String userId) async {
    try {
      // Daily login check — fire once per session
      if (!_dailyLoginChecked) {
        _dailyLoginChecked = true;
        SupabaseConfig.client
            .rpc('check_daily_login', params: {'p_user_id': userId})
            .then((_) {})
            .catchError((e) {
              debugPrint('⚠️ Daily login check error: $e');
            });
      }

      final result = await SupabaseConfig.client
          .rpc('get_tier_dashboard', params: {'p_user_id': userId});

      if (!mounted) return;
      setState(() {
        _tierData = result is Map
            ? Map<String, dynamic>.from(result)
            : <String, dynamic>{};
      });
    } catch (e) {
      debugPrint('⚠️ Fetch tier info error: $e');
      // Non-fatal — hero card falls back to defaults
    }
  }

  // ── G8: Response caching — skip reload if data is fresh ── [T-5]
  void _refreshIfStale({bool force = false}) {
    if (!force &&
        _lastLoadTime != null &&
        DateTime.now().difference(_lastLoadTime!).inSeconds < 2) {
      return; // data is fresh enough
    }
    _loadAllData();
  }

  // ─── REALTIME ──────────────────────────────────────────────

  void _setupRealtimeSubscriptions() {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;

    _notificationChannel = SupabaseConfig.client
        .channel('home_notifications_$userId')
        .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: userId),
            callback: (payload) {
              // ✅ FIX-2 + G5 [T-7]: spread copy + try/catch
              try {
                if (!mounted) return;
                final current =
                    (_dashboard['unread_notifications'] as num?)?.toInt() ?? 0;
                setState(() {
                  _dashboard = {
                    ..._dashboard,
                    'unread_notifications': current + 1,
                  };
                });
              } catch (e) {
                debugPrint('⚠️ Realtime notification callback error: $e');
              }
            })
        .subscribe();

    _ticketChannel = SupabaseConfig.client
        .channel('home_tickets_$userId')
        // v24 fix: listen to ALL events (insert + update + delete) so the
        // open-tickets badge stays accurate when tickets are created
        // server-side or auto-resolved by an admin/engineer action.
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'service_tickets',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: userId),
            callback: (payload) {
              // ✅ FIX-5 + G5 [T-7]: debounce + try/catch
              try {
                if (!mounted) return;
                _realtimeDebounce?.cancel();
                _realtimeDebounce = Timer(const Duration(milliseconds: 500), () {
                  final uid = SupabaseConfig.client.auth.currentUser?.id;
                  if (uid == null || !mounted) return;
                  Future.wait<dynamic>([
                    _fetchDashboard(uid),
                    _fetchRecentActivity(uid),
                  ]).then((results) {
                    if (!mounted) return;
                    setState(() {
                      _dashboard = Map<String, dynamic>.from(results[0] as Map);
                      _recentActivity = List<Map<String, dynamic>>.from(
                          (results[1] as List)
                              .map((a) => Map<String, dynamic>.from(a as Map)));
                    });
                    // v24 fix: propagate the fresh open-ticket count to the
                    // shared nav badge so the dot disappears when the ticket
                    // moves to resolved/closed/completed in realtime.
                    CustomerNavController.setOpenTickets(_openTickets);
                  }).catchError((e) {
                    debugPrint('⚠️ Realtime refresh error: $e');
                  });
                });
              } catch (e) {
                debugPrint('⚠️ Realtime ticket callback error: $e');
              }
            })
        .subscribe();
  }

  void _navigateToLogin() {
    if (!mounted) return;
    SupabaseConfig.client.auth.signOut();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  // ─── BANNER NAVIGATION HELPERS ─────────────────────────────

  void _navigateToMachineFromBanner(String machineId) async {
    try {
      final data = await SupabaseConfig.client
          .from('machine_catalog')
          .select()
          .eq('id', machineId)
          .maybeSingle();

      if (!mounted || data == null) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MachineDetailPage(machine: data),
        ),
      );
    } catch (e) {
      debugPrint('Failed to load machine for banner: $e');
    }
  }

  void _navigateToCatalogFromBanner(String category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CatalogPage(initialCategory: category),
      ),
    );
  }

  // ─── HELPERS ───────────────────────────────────────────────



  String _formatLKR(dynamic amount) {
    if (amount == null) return 'Rs. 0';
    final val = amount is num
        ? amount.toDouble()
        : double.tryParse(amount.toString()) ?? 0;
    return 'Rs. ${_lkrFormat.format(val)}';
  }

  // ── Tier Helpers ── [T-3]

  Map<String, dynamic> _getTierConfig(String tier) {
    switch (tier) {
      case 'platinum':
        return {
          'label': 'PLATINUM',
          'emoji': '💎',
          'color': const Color(0xFFE5E4E2),
          'gradient': [const Color(0xFFE5E4E2), const Color(0xFFB8B8B8)],
        };
      case 'gold':
        return {
          'label': 'GOLD',
          'emoji': '🥇',
          'color': const Color(0xFFFFD700),
          'gradient': [const Color(0xFFFFD700), const Color(0xFFFFA000)],
        };
      case 'silver':
        return {
          'label': 'SILVER',
          'emoji': '🥈',
          'color': const Color(0xFFC0C0C0),
          'gradient': [const Color(0xFFC0C0C0), const Color(0xFF9E9E9E)],
        };
      default:
        return {
          'label': 'BRONZE',
          'emoji': '🥉',
          'color': const Color(0xFFCD7F32),
          'gradient': [const Color(0xFFCD7F32), const Color(0xFFA0522D)],
        };
    }
  }

  String _getTierProgressMessage() {
    final pointsNeeded = _nextTierThreshold - _totalPoints;
    if (_currentTier == 'platinum') {
      return 'You\'ve reached the highest tier! 🎉';
    }
    final nextTier = _currentTier == 'bronze'
        ? 'Silver'
        : _currentTier == 'silver'
            ? 'Gold'
            : 'Platinum';
    return '$pointsNeeded pts to $nextTier →';
  }



  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Brand.darkCard)
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.white),
      child: Scaffold(
        backgroundColor: Brand.canvas(isDark),
        // Home tab body only — never embed sibling tab pages here, because
        // each of those pages is itself a Scaffold with its own
        // CustomerNavBar. Embedding them stacked two nav bars on top of each
        // other and made the inner one feel like it was scrolling with the
        // page content.
        body: _buildHomeContent(isDark),
        bottomNavigationBar: widget.showNavBar
            ? CustomerNavBar(
                currentIndex: 0,
                openTickets: _openTickets,
                onTabSelected: (idx) {
                  if (idx == 0) {
                    _refreshIfStale();
                  } else {
                    CustomerNavController.switchTab(idx);
                  }
                },
              )
            : null,
      ),
    );
  }

  // ─── SKELETON ──────────────────────────────────────────────

  Widget _buildSkeleton(bool isDark) {
    return SafeArea(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _skBox(52, 52, 16, isDark),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    _skBox(90, 12, 6, isDark),
                    const SizedBox(height: 8),
                    _skBox(150, 20, 8, isDark),
                  ])),
              _skBox(44, 44, 14, isDark),
              const SizedBox(width: 10),
              _skBox(44, 44, 14, isDark),
            ]),
            const SizedBox(height: 20),
            _skBox(double.infinity, 160, 20, isDark),
            const SizedBox(height: 28),
            _skBox(double.infinity, 210, 24, isDark),
            const SizedBox(height: 28),
            _skBox(130, 18, 8, isDark),
            const SizedBox(height: 16),
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(5, (_) => _skBox(56, 80, 18, isDark))),
            const SizedBox(height: 28),
            _skBox(120, 18, 8, isDark),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _skBox(double.infinity, 120, 20, isDark)),
              const SizedBox(width: 14),
              Expanded(child: _skBox(double.infinity, 120, 20, isDark)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _skBox(double.infinity, 120, 20, isDark)),
              const SizedBox(width: 14),
              Expanded(child: _skBox(double.infinity, 120, 20, isDark)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _skBox(double w, double h, double r, bool isDark) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: isDark
              ? Brand.darkBorderLight.withAlpha(77)
              : Brand.royalBlue.withAlpha(13),
          borderRadius: BorderRadius.circular(r),
        ),
      );

  // ─── BODY ──────────────────────────────────────────────────
  // Tab dispatcher removed in v22.1: HomePage now only renders its own
  // home content. Other tabs are full pushReplacement-routed pages.

  Widget _buildHomeContent(bool isDark) {
    if (_isLoading) return _buildSkeleton(isDark);
    return SafeArea(
      top: false,
      child: RefreshIndicator(
        onRefresh: _loadAllData,
        color: isDark ? Brand.darkIconActive : Brand.royalBlue,
        backgroundColor: Brand.surface(isDark),
        displacement: 60,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isDark),
              if (_hasError) _buildErrorBanner(isDark),

              // ── 1. Promotional Carousel (TOP) ─────────────
              const SizedBox(height: 20),
              PromotionalCarousel(
                onNavigateToMachine: _navigateToMachineFromBanner,
                onNavigateToCatalog: _navigateToCatalogFromBanner,
              ),
              const SizedBox(height: 20),

              // ── 2. Customer Dashboard (tier + stats) ──────
              SlideTransition(
                position: _heroSlideIn,
                child: FadeTransition(
                    opacity: _heroFadeIn, child: _buildHeroCard(isDark)),
              ),

              // ── 3. Suggest Machine / Next Journey ─────────
              _buildNextJourneyCard(isDark),

              // ── 4. Everything else (under the suggest panel) ──
              _buildAlertBanners(isDark),
              _buildPaymentBanners(isDark),
              _buildSectionTitle('Browse Categories', isDark),
              _buildCategoryRow(isDark),
              _buildSectionTitle('Quick Actions', isDark),
              _buildQuickActions(isDark),
              _buildMyMachinesSection(isDark),
              if (_recentActivity.isNotEmpty) _buildRecentActivity(isDark),
              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
    );
  }

  // ─── SECTION TITLE ─────────────────────────────────────────

  Widget _buildSectionTitle(String title, bool isDark,
      {VoidCallback? onViewAll}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [Brand.darkIconActive, Brand.royalBlueGlow]
                    : [Brand.royalBlue, Brand.royalBlueGlow],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(Brand.r(2)),
            ),
          ),
          const SizedBox(width: 10),
          Text(title,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                letterSpacing: -0.4,
              )),
          const Spacer(),
          if (onViewAll != null) _viewAllChip(isDark, onViewAll),
        ],
      ),
    );
  }

  Widget _viewAllChip(bool isDark, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Brand.r(20)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
            borderRadius: BorderRadius.circular(Brand.r(20)),
            border: Border.all(
                color: isDark
                    ? Brand.darkBorderLight
                    : Brand.royalBlue.withAlpha(31)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(S.of(context)!.commonViewAll,
                style: TextStyle(
                  color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward_rounded,
                size: 14,
                color: isDark ? Brand.darkIconActive : Brand.royalBlue),
          ]),
        ),
      ),
    );
  }

  // ─── HEADER ────────────────────────────────────────────────

  Widget _buildHeader(bool isDark) {
    return Container(
      decoration: const BoxDecoration(
        // Splash-navy radial — the brand signature shared by every role home.
        gradient: RadialGradient(
          center: Alignment(0, -1.2),
          radius: 1.6,
          colors: [
            Brand.splashNavyGlow,
            Brand.splashNavyCore,
            Brand.splashNavyEdge,
          ],
          stops: [0.0, 0.45, 1.0],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 16, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: AppLogo.wordmark(height: 24, dark: true),
          ),
          Row(
            children: [
          // L8: Wrap the icon-only profile avatar in a Semantics(button:true,
          // label:...) so screen readers announce "Open profile, button"
          // instead of the raw image URL / "Unlabeled" fallback.
          Semantics(
            button: true,
            label: 'Open profile',
            child: GestureDetector(
              onTap: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ProfilePage()));
                // Profile definitely changed — full reload
                if (mounted) _loadAllData();
              },
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Brand.r(16)),
                  gradient: LinearGradient(
                    colors: isDark
                        ? [Brand.darkIconActive, Brand.royalBlueGlow]
                        : [Brand.royalBlue, Brand.royalBlueLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: isDark
                            ? Brand.darkIconActive.withAlpha(64)
                            : Brand.royalBlue.withAlpha(89),
                        blurRadius: 14,
                        offset: const Offset(0, 5))
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Brand.r(16)),
                  child:
                      _profileImageUrl != null && _profileImageUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: _profileImageUrl!,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => _avatarFallback(isDark),
                              errorWidget: (_, __, ___) =>
                                  _avatarFallback(isDark),
                            )
                          : _avatarFallback(isDark),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(TimeUtils.getGreeting(),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.1,
                  )),
              const SizedBox(height: 2),
              Text(_userName,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 7),
              const DsLimeLine(),
            ]),
          ),
          _headerBtn(
              Icons.search_rounded,
              isDark,
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CatalogPage())),
              // L8: label the icon-only button for screen readers.
              semanticLabel: 'Search machines'),
          const SizedBox(width: 10),
          NavBadgeIndicator(
            badgeType: NavBadgeType.notifications,
            builder: (_, count) => _notifBtn(isDark, count),
          ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback(bool isDark) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
            gradient: LinearGradient(
          colors: isDark
              ? [Brand.darkIconActive, Brand.royalBlueGlow]
              : [Brand.royalBlue, Brand.royalBlueLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )),
        child: Center(
            child: Text(StringUtils.getInitials(_userName),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                ))),
      );

  Widget _headerBtn(
    IconData icon,
    bool isDark,
    VoidCallback onTap, {
    String? semanticLabel,
  }) {
    // L8: Wrap in Semantics(button:true, label:...) so icon-only header
    // buttons announce their purpose to VoiceOver / TalkBack. `excludeSemantics`
    // suppresses the duplicate "button" role that InkWell would otherwise
    // emit — one announcement, one label.
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Brand.r(14)),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Brand.surface(isDark),
              borderRadius: BorderRadius.circular(Brand.r(14)),
              border: isDark ? Border.all(color: Brand.darkBorder) : null,
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                          color: Brand.royalBlue.withAlpha(13),
                          blurRadius: 10,
                          offset: const Offset(0, 3))
                    ],
            ),
            child: Icon(icon,
                color: isDark ? Brand.darkTextSecondary : Brand.royalBlue,
                size: 22),
          ),
        ),
      ),
    );
  }

  Widget _notifBtn(bool isDark, int count) {
    // L8: Dynamic semantic label — pronounce the unread count so blind users
    // know whether a tap is worth making. `excludeSemantics:true` prevents
    // the red badge's "99+" text from being read separately from the button.
    final label = count == 0
        ? 'Notifications'
        : 'Notifications, $count unread';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const NotificationListPage()));
          // Unread count definitely changed — full reload
          if (mounted) _loadAllData();
        },
        borderRadius: BorderRadius.circular(Brand.r(14)),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius: BorderRadius.circular(Brand.r(14)),
            border: isDark ? Border.all(color: Brand.darkBorder) : null,
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                        color: Brand.royalBlue.withAlpha(13),
                        blurRadius: 10,
                        offset: const Offset(0, 3))
                  ],
          ),
          child: Stack(children: [
            Center(
                child: Icon(Icons.notifications_outlined,
                    color: isDark ? Brand.darkTextSecondary : Brand.royalBlue,
                    size: 22)),
            if (count > 0)
              Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFFFF4757), Color(0xFFFF6B81)]),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Brand.surface(isDark),
                          width: 2.5),
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 20, minHeight: 20),
                    child: Center(
                        child: Text(count > 99 ? '99+' : '$count',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700))),
                  )),
          ]),
        ),
      ),
    ),
    );
  }

  // ─── ERROR BANNER ──────────────────────────────────────────

  Widget _buildErrorBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D1215) : StatusColors.danger.withAlpha(20),
        borderRadius: BorderRadius.circular(Brand.r(18)),
        border: Border.all(color: StatusColors.danger.withAlpha(isDark ? 51 : 38)),
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: StatusColors.danger.withAlpha(isDark ? 51 : 38),
              borderRadius: BorderRadius.circular(Brand.r(12))),
          child: Icon(Icons.cloud_off_rounded,
              color: isDark ? const Color(0xFFFF6B6B) : StatusColors.danger, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(S.of(context)!.homeConnectionIssue,
              style: TextStyle(
                  color: isDark ? const Color(0xFFFF6B6B) : StatusColors.danger,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
          const SizedBox(height: 2),
          Text(_errorMessage,
              style: TextStyle(
                  color: isDark ? Brand.darkTextSecondary : StatusColors.danger.withAlpha(179),
                  fontSize: 12)),
        ])),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                _isLoading = true;
                _hasError = false;
              });
              // Intentional full reload — user pressed Retry
              _loadAllData();
            },
            borderRadius: BorderRadius.circular(Brand.r(10)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                  color: StatusColors.danger.withAlpha(isDark ? 38 : 31),
                  borderRadius: BorderRadius.circular(Brand.r(10))),
              child: Text(S.of(context)!.commonRetry,
                  style: TextStyle(
                      color: isDark
                          ? const Color(0xFFFF6B6B)
                          : StatusColors.danger.withAlpha(179),
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ),
          ),
        ),
      ]),
    );
  }

  // ─── ALERT BANNERS ─────────────────────────────────────────

  Widget _buildAlertBanners(bool isDark) {
    final alerts = <Widget>[];

    if (_nextServiceDate != null && _nextServiceMachineName != null) {
      try {
        final d =
            DateTime.parse(_nextServiceDate!).difference(DateTime.now()).inDays;
        if (d <= 14) {
          alerts.add(_alertCard(
              Icons.build_circle_rounded,
              'Service Due Soon',
              '${_nextServiceMachineName!} needs service in $d day${d == 1 ? '' : 's'}',
              d <= 3 ? StatusColors.danger : Colors.orange,
              isDark,
              () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MyMachinesPage())).then((_) {
                    if (mounted) _refreshIfStale();
                  })));
        }
      } catch (_) {}
    }

    if (_expiringWarrantyCount > 0) {
      alerts.add(_alertCard(
          Icons.shield_outlined,
          'Warranty Expiring',
          '$_expiringWarrantyCount machine${_expiringWarrantyCount == 1 ? '' : 's'} with warranty expiring within 30 days',
          Colors.amber.shade700,
          isDark,
          () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const MyMachinesPage()))
                  .then((_) {
                if (mounted) _refreshIfStale();
              })));
    }

    return alerts.isEmpty ? const SizedBox.shrink() : Column(children: alerts);
  }

  // ─── PAYMENT BANNERS ──────────────────────────────────────

  Widget _buildPaymentBanners(bool isDark) {
    final banners = <Widget>[];

    if (_overduePaymentCount > 0) {
      final overduePayments =
          _upcomingPayments.where((p) => p['status'] == 'overdue').toList();
      final totalOverdue = overduePayments.fold<double>(
          0, (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0));

      banners.add(_paymentAlertCard(
        icon: Icons.warning_amber_rounded,
        title:
            '$_overduePaymentCount Payment${_overduePaymentCount == 1 ? '' : 's'} Overdue',
        subtitle: 'Total overdue: ${_formatLKR(totalOverdue)}',
        color: StatusColors.danger,
        isDark: isDark,
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const CustomerInstallmentsPage())).then((_) {
          if (mounted) _loadAllData();
        }),
      ));
    }

    final next = _nextDuePayment;
    if (next != null) {
      final dueDate = DateTime.tryParse(next['due_date']?.toString() ?? '');
      if (dueDate != null) {
        final daysUntil = dueDate.difference(DateTime.now()).inDays;
        final amount = (next['amount'] as num?)?.toDouble() ?? 0;
        final plan = next['installment_plans'] as Map<String, dynamic>?;
        final cm = plan?['customer_machines'] as Map<String, dynamic>?;
        final catalog = cm?['machine_catalog'] as Map<String, dynamic>?;
        final machineName = catalog?['machine_name']?.toString() ?? 'Machine';
        final installmentNum = next['installment_number']?.toString() ?? '';
        final totalInstallments = plan?['num_installments']?.toString() ?? '';

        final Color bannerColor;
        final String timeText;
        if (daysUntil <= 0) {
          bannerColor = StatusColors.danger;
          timeText = 'Due today!';
        } else if (daysUntil <= 3) {
          bannerColor = Colors.orange;
          timeText = 'Due in $daysUntil day${daysUntil == 1 ? '' : 's'}';
        } else if (daysUntil <= 7) {
          bannerColor = Colors.amber.shade700;
          timeText = 'Due in $daysUntil days';
        } else {
          bannerColor = isDark ? Brand.darkIconActive : Brand.royalBlue;
          timeText = 'Due in $daysUntil days';
        }

        banners.add(_paymentAlertCard(
          icon: Icons.payments_rounded,
          title: '$timeText — ${_formatLKR(amount)}',
          subtitle:
              '$machineName • Installment $installmentNum/$totalInstallments',
          color: bannerColor,
          isDark: isDark,
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const CustomerInstallmentsPage())).then((_) {
            if (mounted) _loadAllData();
          }),
        ));
      }
    }

    return banners.isEmpty
        ? const SizedBox.shrink()
        : Column(children: banners);
  }

  Widget _paymentAlertCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final alertColor = isDark ? color.withAlpha(217) : color;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : alertColor.withAlpha(13),
          borderRadius: BorderRadius.circular(Brand.r(16)),
          border: Border.all(color: alertColor.withAlpha(isDark ? 38 : 46)),
        ),
        child: Row(children: [
          Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: alertColor.withAlpha(isDark ? 31 : 38),
                  borderRadius: BorderRadius.circular(Brand.r(12))),
              child: Icon(icon, color: alertColor, size: 22)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: alertColor)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12,
                        color:
                            isDark ? Brand.darkTextSecondary : Colors.black54)),
              ])),
          Icon(Icons.chevron_right_rounded,
              color: alertColor.withAlpha(128), size: 22),
        ]),
      ),
    );
  }

  Widget _alertCard(IconData icon, String title, String msg, Color c,
      bool isDark, VoidCallback onTap) {
    final alertColor = isDark ? c.withAlpha(217) : c;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : c.withAlpha(13),
          borderRadius: BorderRadius.circular(Brand.r(16)),
          border: Border.all(
              color: isDark ? alertColor.withAlpha(38) : c.withAlpha(46)),
        ),
        child: Row(children: [
          Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: alertColor.withAlpha(isDark ? 31 : 38),
                  borderRadius: BorderRadius.circular(Brand.r(12))),
              child: Icon(icon, color: alertColor, size: 22)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: alertColor)),
                const SizedBox(height: 2),
                Text(msg,
                    style: TextStyle(
                        fontSize: 12,
                        color:
                            isDark ? Brand.darkTextSecondary : Colors.black54)),
              ])),
          Icon(Icons.chevron_right_rounded,
              color: alertColor.withAlpha(128), size: 22),
        ]),
      ),
    );
  }

  // ─── TIER DETAILS SHEET ─────────────────────────────────────

  void _showTierDetailsSheet(bool isDark) {
    // Initial fetch from _tierData
    final allBenefits = (_tierData['benefits'] as List?)
            ?.map((b) => Map<String, dynamic>.from(b as Map))
            .toList() ??
        [];
    final recentPoints = (_tierData['recent_points'] as List?)
            ?.map((p) => Map<String, dynamic>.from(p as Map))
            .toList() ??
        [];
    final thresholds = (_tierData['thresholds'] as List?)
            ?.map((t) => Map<String, dynamic>.from(t as Map))
            .toList() ??
        [];

    String selectedTier = _currentTier.isEmpty ? 'bronze' : _currentTier;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) {
          final tierConfig = _getTierConfig(_currentTier);
          final tierColor = tierConfig['color'] as Color;
          final tierLabel = tierConfig['label'] as String;
          final tierEmoji = tierConfig['emoji'] as String;

          final selectedTierConfig = _getTierConfig(selectedTier);
          final selectedTierColor = selectedTierConfig['color'] as Color;
          final selectedTierLabel = selectedTierConfig['label'] as String;

          final displayedBenefits = allBenefits.where((b) {
            return (b['tier'] as String?)?.toLowerCase() == selectedTier.toLowerCase();
          }).toList();

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            decoration: BoxDecoration(
              color: Brand.surface(isDark),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                borderRadius: BorderRadius.circular(Brand.r(2)),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
                  children: [
                    // ── Current Tier Header ──
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isDark
                                ? [
                                    tierColor.withAlpha(30),
                                    tierColor.withAlpha(15)
                                  ]
                                : [
                                    tierColor.withAlpha(25),
                                    tierColor.withAlpha(10)
                                  ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(Brand.r(20)),
                          border:
                              Border.all(color: tierColor.withAlpha(60)),
                        ),
                        child: Column(
                          children: [
                            Text(tierEmoji,
                                style: const TextStyle(fontSize: 40)),
                            const SizedBox(height: 8),
                            Text(
                              '$tierLabel Member',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Brand.darkTextPrimary
                                    : Brand.royalBlueDark,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$_totalPoints points earned',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight,
                              ),
                            ),
                            if (_loginStreak > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                '🔥 $_loginStreak day login streak',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFF97316),
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            // Progress bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(Brand.r(6)),
                              child: LinearProgressIndicator(
                                value: (_tierData['tier'] as Map?)?[
                                            'progress_percent'] !=
                                        null
                                    ? ((_tierData['tier'] as Map)['progress_percent']
                                                as num)
                                            .toDouble() /
                                        100
                                    : 0,
                                minHeight: 8,
                                backgroundColor:
                                    tierColor.withAlpha(isDark ? 40 : 30),
                                valueColor: AlwaysStoppedAnimation(tierColor),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _getTierProgressMessage(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── All Tiers Overview ──
                    _tierSheetSectionTitle(
                        'Tier Levels', Icons.stars_rounded, isDark),
                    const SizedBox(height: 10),
                    ...thresholds.map((t) {
                      final name = (t['tier'] as String?)?.toUpperCase() ?? '';
                      final tierVal = t['tier'] as String? ?? '';
                      final minPts = (t['min_points'] as num?)?.toInt() ?? 0;
                      final cfg = _getTierConfig(tierVal);
                      final c = cfg['color'] as Color;
                      final em = cfg['emoji'] as String;
                      final isCurrent = tierVal == _currentTier;
                      final isSelected = tierVal == selectedTier;
                      final isUnlocked = _totalPoints >= minPts;

                      return GestureDetector(
                        onTap: () {
                          setSheetState(() {
                            selectedTier = tierVal;
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? c.withAlpha(isDark ? 35 : 25)
                                : (isDark
                                    ? Brand.darkCardElevated
                                    : Brand.scaffoldLight),
                            borderRadius: BorderRadius.circular(Brand.r(14)),
                            border: isSelected
                                ? Border.all(color: c.withAlpha(120), width: 1.5)
                                : Border.all(
                                    color: isDark
                                        ? Brand.darkBorder
                                        : Brand.borderLight),
                          ),
                          child: Row(
                            children: [
                              Text(em, style: const TextStyle(fontSize: 22)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          name,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? Brand.darkTextPrimary
                                                : Brand.royalBlueDark,
                                          ),
                                        ),
                                        if (isCurrent) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: c.withAlpha(40),
                                              borderRadius:
                                                  BorderRadius.circular(Brand.r(8)),
                                            ),
                                            child: Text(
                                              'Current',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: c,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$minPts+ points',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Brand.darkTextTertiary
                                            : Brand.subtleLight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isUnlocked)
                                const Icon(Icons.check_circle_rounded,
                                    color: Color(0xFF22C55E), size: 20)
                              else
                                Icon(Icons.lock_outline_rounded,
                                    color: isDark
                                        ? Brand.darkTextTertiary
                                        : Brand.subtleLight,
                                    size: 20),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 20),

                    // ── Benefits per Selected Tier ──
                    _tierSheetSectionTitle(
                        selectedTier == _currentTier
                            ? 'Your Benefits'
                            : '$selectedTierLabel Benefits',
                        Icons.card_giftcard_rounded,
                        isDark),
                    const SizedBox(height: 10),
                    if (selectedTier != _currentTier) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: selectedTierColor.withAlpha(15),
                          borderRadius: BorderRadius.circular(Brand.r(10)),
                          border: Border.all(color: selectedTierColor.withAlpha(40)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 16, color: selectedTierColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Viewing benefits for a different tier.',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: selectedTierColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (displayedBenefits.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Benefits for this tier will appear here.',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? Brand.darkTextTertiary
                                : Brand.subtleLight,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    else
                      ...displayedBenefits.map((b) {
                        final title = b['title'] as String? ?? 'Benefit';
                        final desc = b['description'] as String? ?? '';
                        final icon = b['icon'] as String? ?? 'star';

                        IconData iconData;
                        switch (icon) {
                          case 'discount':
                            iconData = Icons.discount_rounded;
                            break;
                          case 'priority':
                            iconData = Icons.bolt_rounded;
                            break;
                          case 'support':
                            iconData = Icons.support_agent_rounded;
                            break;
                          case 'gift':
                            iconData = Icons.card_giftcard_rounded;
                            break;
                          case 'shipping':
                            iconData = Icons.local_shipping_rounded;
                            break;
                          default:
                            iconData = Icons.star_rounded;
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Brand.darkCardElevated
                                : Brand.scaffoldLight,
                            borderRadius: BorderRadius.circular(Brand.r(14)),
                            border: Border.all(
                              color: isDark
                                  ? Brand.darkBorder
                                  : Brand.borderLight,
                            ),
                            // Optional: dim opacity if the tier is locked? The requirements just said to preview next tier benefits
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: selectedTierColor.withAlpha(isDark ? 30 : 20),
                                  borderRadius: BorderRadius.circular(Brand.r(10)),
                                ),
                                child: Icon(iconData,
                                    color: selectedTierColor, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Brand.darkTextPrimary
                                            : Brand.royalBlueDark,
                                      ),
                                    ),
                                    if (desc.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        desc,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? Brand.darkTextTertiary
                                              : Brand.subtleLight,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 20),

                    const SizedBox(height: 20),

                    // ── Points History ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _tierSheetSectionTitle(
                            'Recent Points', Icons.history_rounded, isDark),
                        TextButton(
                          onPressed: () {
                            final nav = Navigator.of(context);
                            nav.pop(); // Close the sheet
                            nav.push(
                              MaterialPageRoute(
                                builder: (_) => const PointsHistoryPage(),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'See More',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Brand.royalBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (recentPoints.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Your points activity will appear here.',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? Brand.darkTextTertiary
                                : Brand.subtleLight,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    else
                      ...recentPoints.map((p) {
                        final type =
                            p['activity_type'] as String? ?? '';
                        final pts =
                            (p['final_points'] as num?)?.toInt() ?? 0;
                        final desc =
                            p['description'] as String? ?? type;
                        final date =
                            p['created_at'] as String? ?? '';
                        final isPositive = pts >= 0;

                        String fmtDate = '';
                        try {
                          final dt = DateTime.parse(date);
                          final diff = DateTime.now().difference(dt);
                          if (diff.inMinutes < 60) {
                            fmtDate = '${diff.inMinutes}m ago';
                          } else if (diff.inHours < 24) {
                            fmtDate = '${diff.inHours}h ago';
                          } else if (diff.inDays < 7) {
                            fmtDate = '${diff.inDays}d ago';
                          } else {
                            fmtDate =
                                '${dt.day}/${dt.month}/${dt.year}';
                          }
                        } catch (_) {}

                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Brand.darkCardElevated
                                : Brand.scaffoldLight,
                            borderRadius: BorderRadius.circular(Brand.r(12)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: (isPositive
                                          ? StatusColors.success
                                          : StatusColors.danger)
                                      .withAlpha(isDark ? 30 : 20),
                                  borderRadius:
                                      BorderRadius.circular(Brand.r(8)),
                                ),
                                child: Icon(
                                  isPositive
                                      ? Icons.add_rounded
                                      : Icons.remove_rounded,
                                  size: 18,
                                  color: isPositive
                                      ? StatusColors.success
                                      : StatusColors.danger,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      desc,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: isDark
                                            ? Brand.darkTextPrimary
                                            : Brand.royalBlueDark,
                                      ),
                                      maxLines: 1,
                                      overflow:
                                          TextOverflow.ellipsis,
                                    ),
                                    if (fmtDate.isNotEmpty)
                                      Text(
                                        fmtDate,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? Brand.darkTextTertiary
                                              : Brand.subtleLight,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                '${isPositive ? '+' : ''}$pts',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isPositive
                                      ? StatusColors.success
                                      : StatusColors.danger,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        );
        },
      ),
    );
  }


  Widget _tierSheetSectionTitle(String title, IconData icon, bool isDark) {
    return Row(
      children: [
        Icon(icon,
            size: 18,
            color: isDark ? Brand.darkTextSecondary : Brand.royalBlue),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
          ),
        ),
      ],
    );
  }

  // ─── HERO CARD (Tier-integrated) ── [T-9] ─────────────────

  Widget _buildHeroCard(bool isDark) {
    final tierConfig = _getTierConfig(_currentTier);
    final tierColor = tierConfig['color'] as Color;
    final tierLabel = tierConfig['label'] as String;
    final tierEmoji = tierConfig['emoji'] as String;
    final pal = Brand.navyHero;
    final isW = Brand.isWorkshop;

    return GestureDetector(
      onTap: () => _showTierDetailsSheet(isDark),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Brand.r(22)),
          gradient: isW
              ? null
              : RadialGradient(
                  center: const Alignment(0.6, -1.4),
                  radius: 2.0,
                  colors: isDark
                      ? [const Color(0xFF0D1B30), const Color(0xFF0A1628), const Color(0xFF060E1A)]
                      : pal.gradient,
                  stops: const [0.0, 0.45, 1.0],
                ),
          color: isW
              ? (isDark ? Brand.darkCard : Brand.canvas(isDark))
              : null,
          border: isW
              ? Border.all(color: Brand.cardBorder(isDark), width: 1.5)
              : (isDark ? Border.all(color: pal.frostedBorder.withAlpha(60)) : null),
          boxShadow: isDark
              ? null
              : isW
                  ? null
                  : [
                      BoxShadow(
                        color: Brand.splashNavyEdge.withAlpha(40),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
        ),
        child: Column(children: [
          // ── Top accent bar ──
          Container(
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(Brand.r(22)),
                topRight: Radius.circular(Brand.r(22)),
              ),
              gradient: LinearGradient(
                colors: tierConfig['gradient'] as List<Color>,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── Tier Badge Row ──
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isW
                        ? tierColor.withAlpha(isDark ? 31 : 18)
                        : tierColor.withAlpha(50),
                    borderRadius: BorderRadius.circular(Brand.r(20)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(tierEmoji, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 5),
                    Text('$tierLabel Member',
                        style: TextStyle(
                          color: isW ? tierColor : Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        )),
                  ]),
                ),
                const Spacer(),
                if (_companyName.isNotEmpty)
                  Flexible(
                      child: Text(_companyName,
                          style: TextStyle(
                            color: isW
                                ? Brand.inkSoft(isDark)
                                : pal.label,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 22),

              // ── Stats Row ──
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(S.of(context)!.homeMyMachines,
                      style: TextStyle(
                          color: isW
                              ? Brand.inkSoft(isDark)
                              : pal.label,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text('$_totalMachines',
                      style: TextStyle(
                        color: isW
                            ? Brand.ink(isDark)
                            : Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        letterSpacing: -2,
                      )),
                ]),
                const Spacer(),
                _heroStat(
                    (c) => IcChatGearIcon(color: c, size: 22),
                    '$_openTickets', 'Open', isDark),
                const SizedBox(width: 14),
                _heroStat(
                    (c) => Icon(Icons.payments_rounded, color: c, size: 22),
                    '$_activePlans', 'Plans', isDark),
              ]),
              const SizedBox(height: 22),

              // ── Points + Streak Row ──
              Row(children: [
                // Points display
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isW
                        ? tierColor.withAlpha(isDark ? 26 : 15)
                        : tierColor.withAlpha(45),
                    borderRadius: BorderRadius.circular(Brand.r(10)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.stars_rounded,
                        color: isW ? tierColor : Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text('$_totalPoints pts',
                        style: TextStyle(
                          color: isW ? tierColor : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        )),
                  ]),
                ),
                const SizedBox(width: 8),
                // Login streak
                if (_loginStreak > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: isW
                          ? Colors.orange.withAlpha(isDark ? 22 : 15)
                          : Colors.orange.withAlpha(40),
                      borderRadius: BorderRadius.circular(Brand.r(10)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Text('🔥', style: TextStyle(fontSize: 11)),
                      const SizedBox(width: 3),
                      Text('$_loginStreak day',
                          style: TextStyle(
                            color: isW
                                ? (isDark
                                    ? Colors.orange.shade300
                                    : Colors.orange.shade700)
                                : Colors.orange.shade200,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          )),
                    ]),
                  ),
                const Spacer(),
                // Progress message
                Flexible(
                  child: Text(_getTierProgressMessage(),
                      style: TextStyle(
                        color: isW
                            ? Brand.inkSoft(isDark)
                            : pal.label,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right),
                ),
              ]),
              const SizedBox(height: 10),

              // ── Tier Progress Bar ──
              Container(
                height: 5,
                decoration: BoxDecoration(
                    color: isW
                        ? (isDark
                            ? Brand.darkBorderLight.withAlpha(77)
                            : const Color(0xFFE2E8F0))
                        : Colors.white.withAlpha(30),
                    borderRadius: BorderRadius.circular(Brand.r(10))),
                child: Stack(children: [
                  FractionallySizedBox(
                    widthFactor: (_tierProgressPercent / 100.0).clamp(0.0, 1.0),
                    child: Container(
                        decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: tierConfig['gradient'] as List<Color>),
                      borderRadius: BorderRadius.circular(Brand.r(10)),
                    )),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _heroStat(Widget Function(Color) iconWidget, String val, String label, bool isDark) {
    final isW = Brand.isWorkshop;
    return Column(children: [
      Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: isW
                ? (isDark ? Brand.lightGreen.withAlpha(22) : Brand.lightGreenSurface)
                : Brand.lightGreen.withAlpha(35),
            borderRadius: BorderRadius.circular(Brand.r(14)),
          ),
          child: Center(
              child: iconWidget(isW
                  ? (isDark ? Brand.lightGreenBright : Brand.lightGreen)
                  : Brand.lightGreenBright))),
      const SizedBox(height: 7),
      Text(val,
          style: TextStyle(
              color: isW
                  ? (isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)
                  : Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 17)),
      Text(label,
          style: TextStyle(
              color: isW
                  ? (isDark ? Brand.darkTextTertiary : Brand.subtleLight)
                  : Brand.navyHero.label,
              fontSize: 11,
              fontWeight: FontWeight.w500)),
    ]);
  }

  // ─── CATEGORY ROW ──────────────────────────────────────────

  Widget _buildCategoryRow(bool isDark) {
    final iconColor = isDark ? Brand.darkIconActive : Brand.royalBlue;
    // Responsive icon size: 5 items with equal spacing in available width
    final screenW = MediaQuery.sizeOf(context).width;
    final iconSize = ((screenW - 40) / 5 - 8).clamp(44.0, 62.0);

    final categories = <Map<String, dynamic>>[
      {
        'widget': Icon(Icons.print_rounded, color: iconColor, size: 26),
        'label': 'Printers',
        'cat': 'Digital Printers'
      },
      {
        'widget': LaserIcon(color: iconColor, size: 26),
        'label': 'Lasers',
        'cat': 'Laser Cutters'
      },
      {
        'widget': CncIcon(color: iconColor, size: 26),
        'label': 'CNC',
        'cat': 'CNC Routers'
      },
      {
        'widget': Icon(Icons.layers_rounded, color: iconColor, size: 26),
        'label': 'Finishing',
        'cat': 'Finishing Equipment'
      },
      {
        'widget': Icon(Icons.grid_view_rounded, color: iconColor, size: 26),
        'label': 'All',
        'cat': 'all'
      },
    ];

    // ✅ FIX-4: use dashboard category counts (computed from ALL machines)
    final catCounts = _categoryCounts;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: categories.map((cat) {
          final catVal = cat['cat'] as String;
          final count = catVal == 'all'
              ? _totalMachines
              : ((catCounts[catVal] as num?)?.toInt() ?? 0);

          return GestureDetector(
            onTap: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => catVal == 'all'
                        ? const CatalogPage()
                        : CatalogPage(initialCategory: catVal),
                  ));
            },
            child: Column(children: [
              Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Brand.darkCardElevated
                        : Brand.royalBlueSurface,
                    borderRadius: BorderRadius.circular(Brand.r(18)),
                    border: Border.all(
                        color: isDark
                            ? Brand.darkBorderLight
                            : Brand.royalBlue.withAlpha(26),
                        width: 1.5),
                    boxShadow: isDark
                        ? null
                        : [
                            BoxShadow(
                                color: Brand.royalBlue.withAlpha(15),
                                blurRadius: 8,
                                offset: const Offset(0, 3))
                          ],
                  ),
                  child: Center(child: cat['widget'] as Widget),
                ),
                if (count > 0)
                  Positioned(
                      top: -6,
                      right: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [
                            Brand.lightGreen,
                            Brand.lightGreenBright
                          ]),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color:
                                  Brand.canvas(isDark),
                              width: 2.5),
                          boxShadow: [
                            BoxShadow(
                                color: Brand.lightGreen.withAlpha(77),
                                blurRadius: 6)
                          ],
                        ),
                        constraints:
                            const BoxConstraints(minWidth: 22, minHeight: 22),
                        child: Center(
                            child: Text('$count',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700))),
                      )),
              ]),
              const SizedBox(height: 8),
              Text(cat['label'] as String,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  )),
            ]),
          );
        }).toList(),
      ),
    );
  }

  // ─── QUICK ACTIONS ─────────────────────────────────────────

  Widget _buildQuickActions(bool isDark) {
    final items = [
      _QA(
          'My Machines',
          '$_totalMachines registered',
          (c) => Icon(Icons.settings_suggest_rounded, color: c, size: 22),
          'my_machines',
          isDark ? Brand.darkIconActive : Brand.royalBlue,
          isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
          null),
      _QA(
          'Get Support',
          '$_openTickets open tickets',
          (c) => IcChatGearIcon(color: c, size: 22),
          'support',
          isDark ? const Color(0xFFFF8A65) : const Color(0xFFE65100),
          isDark ? Brand.darkCardElevated : const Color(0xFFFFF3E0),
          _openTickets > 0 ? '$_openTickets' : null),
      _QA(
          'Catalog',
          'Browse machines',
          (c) => Icon(Icons.storefront_rounded, color: c, size: 22),
          'catalog',
          isDark ? Brand.lightGreenBright : Brand.lightGreenDark,
          isDark ? Brand.darkCardElevated : Brand.lightGreenSurface,
          null),
      _QA(
          'Knowledge',
          'Guides & tips',
          (c) => Icon(Icons.auto_stories_rounded, color: c, size: 22),
          'knowledge',
          isDark ? const Color(0xFFCE93D8) : const Color(0xFF6A1B9A),
          isDark ? Brand.darkCardElevated : const Color(0xFFF3E5F5),
          null),
      _QA(
          'My Installments',
          _overduePaymentCount > 0
              ? '$_overduePaymentCount overdue'
              : '$_activePlans active plans',
          (c) => Icon(Icons.payments_rounded, color: c, size: 22),
          'installments',
          isDark ? const Color(0xFF4FC3F7) : Brand.royalBlue,
          isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
          _overduePaymentCount > 0 ? '$_overduePaymentCount' : null),
      // ── Refer & Earn ── [T-10]
      _QA(
          'Refer & Earn',
          'Invite friends',
          (c) => Icon(Icons.card_giftcard_rounded, color: c, size: 22),
          'referral',
          isDark ? const Color(0xFFFFD54F) : const Color(0xFFF57F17),
          isDark ? Brand.darkCardElevated : const Color(0xFFFFF8E1),
          null),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          mainAxisExtent: 130,
        ),
        children: items.map((q) => _buildQACard(q, isDark)).toList(),
      ),
    );
  }

  Widget _buildQACard(_QA q, bool isDark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleQuickAction(q.route),
        borderRadius: BorderRadius.circular(Brand.r(22)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius: BorderRadius.circular(Brand.r(22)),
            border: Border.all(
                color: isDark ? Brand.darkBorder : q.accent.withAlpha(20)),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                        color: q.accent.withAlpha(15),
                        blurRadius: 14,
                        offset: const Offset(0, 5))
                  ],
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                      color: q.bgColor,
                      borderRadius: BorderRadius.circular(Brand.r(14)),
                      border: isDark
                          ? Border.all(color: Brand.darkBorderLight, width: 1)
                          : null),
                  child: Center(child: q.iconWidget(q.accent))),
              const Spacer(),
              if (q.badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: StatusColors.danger.withAlpha(isDark ? 38 : 26),
                    borderRadius: BorderRadius.circular(Brand.r(10)),
                    border: Border.all(
                        color: StatusColors.danger.withAlpha(isDark ? 64 : 51)),
                  ),
                  child: Text(q.badge!,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color:
                              isDark ? const Color(0xFFFF6B6B) : StatusColors.danger)),
                ),
            ]),
            const Spacer(),
            Text(q.title,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color:
                        isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
            const SizedBox(height: 3),
            Text(q.subtitle,
                style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
    );
  }

  void _handleQuickAction(String route) {
    switch (route) {
      // Tab-switching routes — handled by the shell (no push needed).
      case 'my_machines':
        CustomerNavController.switchTab(1);
        return;
      case 'support':
        CustomerNavController.switchTab(2);
        return;
      case 'knowledge':
        CustomerNavController.switchTab(3);
        return;
      // Full-screen pushes (not tab pages).
      case 'catalog':
        Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CatalogPage()))
            .then((_) {
          if (mounted) _refreshIfStale(force: true);
        });
        return;
      case 'installments':
        Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => const CustomerInstallmentsPage()))
            .then((_) {
          if (mounted) _refreshIfStale(force: true);
        });
        return;
      // ── Refer & Earn ── [T-10]
      case 'referral':
        Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ReferralPage()))
            .then((_) {
          if (mounted) _refreshIfStale(force: true);
        });
        return;
      default:
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Coming soon!')));
    }
  }

  // ─── MY MACHINES ───────────────────────────────────────────

  Widget _buildMyMachinesSection(bool isDark) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
        child: Row(children: [
          Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: isDark
                        ? [Brand.darkIconActive, Brand.royalBlueGlow]
                        : [Brand.royalBlue, Brand.royalBlueGlow],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter),
                borderRadius: BorderRadius.circular(Brand.r(2)),
              )),
          const SizedBox(width: 10),
          Text(S.of(context)!.homeMyMachines,
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  letterSpacing: -0.4)),
          const Spacer(),
          if (_machines.isNotEmpty)
            _viewAllChip(
                isDark,
                () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const MyMachinesPage())).then((_) {
                      if (mounted) _refreshIfStale();
                    })),
        ]),
      ),
      const SizedBox(height: 14),
      _machines.isEmpty ? _emptyMachines(isDark) : _machineList(isDark),
    ]);
  }

  Widget _emptyMachines(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(22)),
         border: isDark
         ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Brand.royalBlue.withAlpha(10),
                    blurRadius: 14,
                    offset: const Offset(0, 5))
              ],
      ),
      child: Column(children: [
        Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
              borderRadius: BorderRadius.circular(Brand.r(22)),
              border: isDark ? Border.all(color: Brand.darkBorderLight) : null,
            ),
            child: Icon(Icons.precision_manufacturing_rounded,
                size: 36,
                color: isDark ? Brand.darkIconActive : Brand.royalBlue)),
        const SizedBox(height: 20),
        Text(S.of(context)!.homeNoMachines,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
        const SizedBox(height: 6),
        Text(S.of(context)!.homeBrowseCatalogDesc,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const CatalogPage())),
          icon: const Icon(Icons.storefront_rounded, size: 18),
          label: Text(S.of(context)!.homeBrowseCatalog,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          style: ElevatedButton.styleFrom(
            backgroundColor: isDark ? Brand.darkIconActive : Brand.royalBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(14))),
          ),
        ),
      ]),
    );
  }

  Widget _machineList(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
          children: _machines.map((m) {
        final name = m['machine_name'] as String? ?? 'Unknown';
        final model = m['model_number'] as String? ?? '';
        final status = (m['status'] as String? ?? 'active').toLowerCase();
        final brand = m['brand'] as String? ?? '';
        final img = m['product_image'] as String?;
        final svcDays = m['days_until_service'] as int?;
        final warranty = m['warranty_active'] as bool? ?? false;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const MyMachinesPage()))
                  .then((_) {
                if (mounted) _refreshIfStale();
              }),
              borderRadius: BorderRadius.circular(Brand.r(20)),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Brand.surface(isDark),
                  borderRadius: BorderRadius.circular(Brand.r(20)),
                  border: isDark ? Border.all(color: Brand.darkBorder) : null,
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                              color: Brand.royalBlue.withAlpha(10),
                              blurRadius: 12,
                              offset: const Offset(0, 4))
                        ],
                ),
                child: Row(children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Brand.darkCardElevated
                          : Brand.royalBlueSurface,
                      borderRadius: BorderRadius.circular(Brand.r(16)),
                      border: isDark
                          ? Border.all(color: Brand.darkBorderLight)
                          : null,
                    ),
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(Brand.r(16)),
                        child: img != null && img.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: img,
                                fit: BoxFit.cover,
                                width: 58,
                                height: 58,
                                placeholder: (_, __) => Icon(
                                    Icons.settings_suggest_rounded,
                                    color: isDark
                                        ? Brand.darkIconActive
                                        : Brand.royalBlue,
                                    size: 26),
                                errorWidget: (_, __, ___) => Icon(
                                    Icons.settings_suggest_rounded,
                                    color: isDark
                                        ? Brand.darkIconActive
                                        : Brand.royalBlue,
                                    size: 26),
                              )
                            : Icon(Icons.settings_suggest_rounded,
                                color: isDark
                                    ? Brand.darkIconActive
                                    : Brand.royalBlue,
                                size: 26)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(name,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Brand.darkTextPrimary
                                    : Brand.royalBlueDark),
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        Text('$brand · $model',
                            style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight,
                                fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 4, children: [
                          _badge(status.toUpperCase(),
                              _statusColor(status, isDark), isDark),
                          if (warranty)
                            _badge(
                                'WARRANTY',
                                isDark
                                    ? Brand.darkIconActive
                                    : Brand.royalBlueLight,
                                isDark,
                                icon: Icons.shield_rounded),
                          if (svcDays != null && svcDays <= 14)
                            _badge(
                                '${svcDays}d',
                                isDark
                                    ? const Color(0xFFFFB74D)
                                    : Colors.orange,
                                isDark,
                                icon: Icons.schedule_rounded),
                        ]),
                      ])),
                  Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Brand.darkCardElevated
                            : Brand.royalBlueSurface,
                        borderRadius: BorderRadius.circular(Brand.r(10)),
                      ),
                      child: Icon(Icons.chevron_right_rounded,
                          size: 20,
                          color: isDark
                              ? Brand.darkTextTertiary
                              : Brand.royalBlue.withAlpha(89))),
                ]),
              ),
            ),
          ),
        );
      }).toList()),
    );
  }

  Widget _badge(String text, Color c, bool isDark, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.withAlpha(isDark ? 31 : 20),
        borderRadius: BorderRadius.circular(Brand.r(6)),
        border: Border.all(color: c.withAlpha(isDark ? 51 : 38)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 10, color: c),
          const SizedBox(width: 3)
        ],
        Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: c,
                letterSpacing: 0.3)),
      ]),
    );
  }

  // ─── RECENT ACTIVITY ───────────────────────────────────────

  Widget _buildRecentActivity(bool isDark) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
        child: Row(children: [
          Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: isDark
                        ? [Brand.darkIconActive, Brand.royalBlueGlow]
                        : [Brand.royalBlue, Brand.royalBlueGlow],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter),
                borderRadius: BorderRadius.circular(Brand.r(2)),
              )),
          const SizedBox(width: 10),
          Text(S.of(context)!.homeRecentActivity,
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  letterSpacing: -0.4)),
          const Spacer(),
          _viewAllChip(
              isDark,
              () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SupportTicketsPage()))
                      .then((_) {
                    if (mounted) _refreshIfStale(force: true);
                  })),
        ]),
      ),
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
            // ✅ FIX-1: changed from .take(5) → .take(4)
            children: _recentActivity
                .take(4)
                .map((a) => _activityItem(a, isDark))
                .toList()),
      ),
    ]);
  }

  Widget _activityItem(Map<String, dynamic> a, bool isDark) {
    final type = a['activity_type'] as String? ?? 'support';
    final title = a['title'] as String? ?? '';
    final subtitle = a['subtitle'] as String? ?? '';
    final date = a['activity_date'] as String?;
    final status = a['status'] as String? ?? '';

    Widget Function(Color) iconWidget;
    Color ic;
    switch (type) {
      case 'support':
        iconWidget = (c) => IcChatGearIcon(color: c, size: 22);
        ic = isDark ? const Color(0xFFFF8A65) : const Color(0xFFE65100);
        break;
      case 'inquiry':
        iconWidget = (c) => IcChatGearIcon(color: c, size: 22);
        ic = isDark ? Brand.darkIconActive : Brand.royalBlueLight;
        break;
      case 'order':
        iconWidget = (c) => Icon(Icons.shopping_cart_rounded, color: c, size: 22);
        ic = isDark ? Brand.lightGreenBright : Brand.lightGreen;
        break;
      case 'message':
        iconWidget = (c) => Icon(Icons.chat_bubble_outline_rounded, color: c, size: 22);
        ic = isDark ? const Color(0xFFCE93D8) : const Color(0xFF6A1B9A);
        break;
      default:
        iconWidget = (c) => Icon(Icons.info_outline_rounded, color: c, size: 22);
        ic = isDark ? Brand.darkTextSecondary : Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            final id = a['related_id'] as String?;
            if (id != null) {
              Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => TicketDetailPage(ticketId: id)))
                  .then((_) {
                if (mounted) _refreshIfStale();
              });
            }
          },
          borderRadius: BorderRadius.circular(Brand.r(18)),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Brand.surface(isDark),
              borderRadius: BorderRadius.circular(Brand.r(18)),
              border: isDark ? Border.all(color: Brand.darkBorder) : null,
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                          color: Colors.black.withAlpha(5),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ],
            ),
            child: Row(children: [
              Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                      color: ic.withAlpha(isDark ? 26 : 20),
                      borderRadius: BorderRadius.circular(Brand.r(14)),
                      border: isDark
                          ? Border.all(color: ic.withAlpha(31), width: 1)
                          : null),
                  child: Center(child: iconWidget(ic))),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Brand.darkTextPrimary
                                : Brand.royalBlueDark),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight,
                            fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis),
                  ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                    date != null
                        ? TimeUtils.getTimeAgo(
                            DateTime.tryParse(date) ?? DateTime.now())
                        : '',
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Brand.darkTextTertiary : Colors.black38,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _ticketStatusColor(status, isDark)
                        .withAlpha(isDark ? 31 : 20),
                    borderRadius: BorderRadius.circular(Brand.r(6)),
                  ),
                  child: Text(status.toUpperCase().replaceAll('_', ' '),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _ticketStatusColor(status, isDark),
                          letterSpacing: 0.3)),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Color _statusColor(String s, bool isDark) {
    switch (s) {
      case 'active':
        return isDark ? Brand.lightGreenBright : Brand.lightGreen;
      case 'service':
        return isDark ? const Color(0xFFFFB74D) : Colors.orange;
      case 'inactive':
        return isDark ? const Color(0xFFFF6B6B) : Colors.red;
      default:
        return isDark ? Brand.lightGreenBright : Brand.lightGreen;
    }
  }

  Color _ticketStatusColor(String s, bool isDark) {
    switch (s) {
      case 'open':
        return isDark ? Brand.darkIconActive : Brand.royalBlueLight;
      case 'assigned':
        return isDark ? const Color(0xFF7986CB) : const Color(0xFF283593);
      case 'in_progress':
        return isDark ? const Color(0xFFFFB74D) : Colors.orange;
      case 'waiting_customer':
        return isDark ? const Color(0xFFCE93D8) : const Color(0xFF6A1B9A);
      case 'resolved':
        return isDark ? Brand.lightGreenBright : Brand.lightGreen;
      case 'closed':
        return isDark ? Brand.darkTextSecondary : Colors.grey;
      default:
        return isDark ? Brand.darkTextSecondary : Colors.grey;
    }
  }

  // ─── BOTTOM NAV ────────────────────────────────────────────
  // Removed in v22.1: HomePage now uses the shared `CustomerNavBar`
  // widget directly in its Scaffold.bottomNavigationBar (see build()).
  // The previous private `_buildBottomNav` / `_navCenter` / `_navItem`
  // were a near-duplicate of CustomerNavBar — having both caused two
  // bottom bars to render whenever HomePage embedded a sibling tab page
  // (MyMachinesPage / KnowledgeBasePage / ProfilePage), since each of
  // those pages already supplies its own CustomerNavBar.

  // ── Journey: load active suggestion ──────────────────────────

  Future<void> _loadSuggestion() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;
    if (!mounted) return;
    setState(() => _loadingSuggestion = true);
    try {
      final data = await SupabaseConfig.client
          .from('machine_suggestions')
          .select(
            'id, journey_score, stage_note, viewed_at, '
            'milestone_25_sent, milestone_50_sent, '
            'milestone_75_sent, milestone_100_sent, '
            'batch:suggestion_batches!batch_id('
            'id, note, '
            'machine:machine_catalog!machine_id(id, machine_name, image_url)'
            ')',
          )
          .eq('customer_id', userId)
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _suggestion = data != null ? Map<String, dynamic>.from(data) : null;
        _loadingSuggestion = false;
      });
      // Silently mark as viewed
      if (data != null && data['viewed_at'] == null) {
        try {
          await SupabaseConfig.client
              .from('machine_suggestions')
              .update({'viewed_at': DateTime.now().toUtc().toIso8601String()})
              .eq('id', data['id'] as String);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Journey suggestion load error: $e');
      if (!mounted) return;
      setState(() => _loadingSuggestion = false);
    }
  }

  Future<void> _navigateToSuggestedMachine(String machineId) async {
    try {
      final data = await SupabaseConfig.client
          .from('machine_catalog')
          .select()
          .eq('id', machineId)
          .maybeSingle();
      if (!mounted || data == null) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MachineDetailPage(machine: data)),
      );
    } catch (e) {
      debugPrint('Failed to navigate to suggested machine: $e');
    }
  }

  // ── Journey card widget ───────────────────────────────────────

  Widget _buildNextJourneyCard(bool isDark) {
    if (_loadingSuggestion) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Container(
          height: 130,
          decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius: BorderRadius.circular(Brand.r(20)),
            border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
          ),
          child: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Brand.royalBlue),
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }
    if (_suggestion == null) return const SizedBox.shrink();

    final batch = _suggestion!['batch'] as Map<String, dynamic>?;
    final machine = batch?['machine'] as Map<String, dynamic>?;
    if (machine == null) return const SizedBox.shrink();

    final machineName =
        machine['machine_name'] as String? ?? 'Machine';
    final machineId = machine['id'] as String?;
    final imageUrl = machine['image_url'] as String?;
    final score = (_suggestion!['journey_score'] as num?)?.toInt() ?? 0;
    final stageNote = _suggestion!['stage_note'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GestureDetector(
        onTap: machineId == null
            ? null
            : () => _navigateToSuggestedMachine(machineId),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [Brand.royalBlueDark, Brand.darkCard]
                  : [Brand.royalBlueSurface, Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(Brand.r(20)),
            border: Border.all(
              color: isDark
                  ? Brand.darkBorderLight
                  : Brand.royalBlue.withAlpha(51),
            ),
            boxShadow: [
              BoxShadow(
                color: Brand.royalBlue.withAlpha(26),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Brand.darkCardElevated
                          : Brand.royalBlueSurface,
                      borderRadius: BorderRadius.circular(Brand.r(14)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Brand.r(14)),
                      child: imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Icon(
                                Icons.precision_manufacturing_rounded,
                                color: Brand.royalBlue.withAlpha(102),
                                size: 26,
                              ),
                              errorWidget: (_, __, ___) => Icon(
                                Icons.precision_manufacturing_rounded,
                                color: Brand.royalBlue,
                                size: 26,
                              ),
                            )
                          : Icon(
                              Icons.precision_manufacturing_rounded,
                              color: Brand.royalBlue,
                              size: 26,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YOUR NEXT MACHINE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Brand.royalBlue,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          machineName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Brand.darkTextPrimary
                                : const Color(0xFF1A202C),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: score >= 100
                          ? Brand.lightGreen.withAlpha(230)
                          : Brand.royalBlue.withAlpha(score >= 75 ? 230 : 38),
                      borderRadius: BorderRadius.circular(Brand.r(20)),
                    ),
                    child: Text(
                      '$score%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: score >= 75
                            ? Colors.white
                            : (isDark
                                ? Brand.royalBlueLight
                                : Brand.royalBlue),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: score / 100.0),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (_, value, __) => ClipRRect(
                  borderRadius: BorderRadius.circular(Brand.r(6)),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 8,
                    backgroundColor: isDark
                        ? Brand.darkBorder
                        : Brand.royalBlueSurface,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      score >= 100 ? Brand.lightGreen : Brand.royalBlue,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _journeyDot('25%', score >= 25, isDark),
                  _journeyDot('50%', score >= 50, isDark),
                  _journeyDot('75%', score >= 75, isDark),
                  _journeyDot('100%', score >= 100, isDark),
                ],
              ),
              if (stageNote != null && stageNote.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 13,
                      color: isDark
                          ? Brand.darkTextSecondary
                          : Brand.subtleLight,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        stageNote,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Tap to view machine →',
                  style: TextStyle(
                    fontSize: 11,
                    color: Brand.royalBlue.withAlpha(179),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _journeyDot(String label, bool reached, bool isDark) {
    return Column(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: reached
                ? Brand.royalBlue
                : (isDark ? Brand.darkBorder : Brand.borderLight),
            border: Border.all(
              color: reached
                  ? Brand.royalBlue
                  : (isDark ? Brand.darkBorderLight : Brand.subtleLight),
              width: 1.5,
            ),
          ),
          child: reached
              ? const Icon(Icons.check_rounded, size: 10, color: Colors.white)
              : null,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: reached
                ? Brand.royalBlue
                : (isDark ? Brand.darkTextSecondary : Brand.subtleLight),
            fontWeight: reached ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }


}

// ─── QA DATA CLASS ───────────────────────────────────────────
class _QA {
  final String title, subtitle, route;
  final Widget Function(Color) iconWidget;
  final Color accent, bgColor;
  final String? badge;
  const _QA(this.title, this.subtitle, this.iconWidget, this.route, this.accent,
      this.bgColor, this.badge);
}
