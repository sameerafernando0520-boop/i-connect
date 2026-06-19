// lib/screens/engineer/engineer_dashboard.dart

import 'dart:async';
import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart'; // ← FIXED #2
// NOTE: supabase_flutter needed for RealtimeChannel, PostgresChangeEvent types
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/brand_colors.dart'; // ← FIXED #1: use Brand
import '../../widgets/common/ic_icons.dart';
import '../../config/supabase_config.dart';
import '../../services/notification_service.dart'; // ← ADDED: for onLogout
import '../../utils/time_utils.dart'; // ← FIXED #6, #7
import '../../utils/string_utils.dart'; // ← FIXED #5
import '../../screens/auth/login_page.dart'; // ← FIXED #3: for MaterialPageRoute
import 'engineer_ticket_list_page.dart';
import 'engineer_ticket_detail_page.dart';
import 'engineer_profile_page.dart';
import 'engineer_schedule_page.dart';
import 'engineer_installation_list_page.dart';
import 'engineer_my_schedules_page.dart';
import '../customer/notification_list_page.dart';
import '../../widgets/common/offline_banner.dart';
import '../../widgets/engineer/engineer_checkin_card.dart';
import '../../widgets/ds/ds_widgets.dart';

// ── Engineer-specific colors not in Brand class ──────────────
const Color _engAccent = Color(0xFF22C55E); // Green (was cyan)
const Color _engAccentDark = Color(0xFF16A34A); // Dark green (was dark cyan)
const Color _darkCardHighlight = Color(0xFF22272E);

// ── Asset URLs ──────────────────────────────────────────────────
// TRI Engineering logo (navy/dark background variant)
const String _triLogoUrl = 'https://res.cloudinary.com/dlqzqponw/image/upload/q_auto/f_auto/v1775711293/Logo-04_gwnmsr.png';

// ══════════════════════════════════════════════════════════════
//  ENGINEER DASHBOARD
// ══════════════════════════════════════════════════════════════
class EngineerDashboard extends StatefulWidget {
  const EngineerDashboard({super.key});
  @override
  State<EngineerDashboard> createState() => _EngineerDashboardState();
}

class _EngineerDashboardState extends State<EngineerDashboard>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _isLoading = true;
  bool _hasError = false;

  Map<String, dynamic> _profile = {};
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _urgentTickets = [];
  List<Map<String, dynamic>> _recentTickets = [];
  int _unreadMessages = 0;

  RealtimeChannel? _ticketChannel;
  DateTime? _lastLoad;
  Timer? _realtimeDebounce; // ← ADDED #12: debounce rapid realtime events

  late AnimationController _heroAnim;
  late Animation<double> _heroFade;
  late Animation<Offset> _heroSlide;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _heroAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _heroFade = CurvedAnimation(parent: _heroAnim, curve: Curves.easeOut);
    _heroSlide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _heroAnim, curve: Curves.easeOutCubic));
    _loadAll();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heroAnim.dispose();
    _realtimeDebounce?.cancel(); // ← ADDED
    // ← FIXED #4: proper channel cleanup
    if (_ticketChannel != null) {
      SupabaseConfig.client.removeChannel(_ticketChannel!);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && mounted) {
      // ← FIXED #9: mounted check
      final now = DateTime.now();
      if (_lastLoad == null || now.difference(_lastLoad!).inSeconds > 30) {
        _loadAll();
      }
    }
  }

  // ─── DATA ─────────────────────────────────────────────────
  Future<void> _loadAll() async {
    try {
      final uid = SupabaseConfig.client.auth.currentUser?.id;
      if (uid == null) {
        _goLogin();
        return;
      }

      final results = await Future.wait<dynamic>([
        _fetchProfile(uid),
        _fetchStats(uid),
        _fetchUrgent(uid),
        _fetchRecent(uid),
        _fetchUnreadCount(uid),
      ]);

      if (!mounted) return; // ← IMPROVED: explicit check
      setState(() {
        _profile = results[0] as Map<String, dynamic>;
        _stats = results[1] as Map<String, dynamic>;
        _urgentTickets = results[2] as List<Map<String, dynamic>>;
        _recentTickets = results[3] as List<Map<String, dynamic>>;
        _unreadMessages = results[4] as int;
        _isLoading = false;
        _hasError = false;
      });
      if (!_heroAnim.isCompleted) _heroAnim.forward();
      _lastLoad = DateTime.now();
    } catch (e) {
      debugPrint('EngineerDashboard error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _fetchProfile(String uid) async {
    final r = await SupabaseConfig.client
        .from('users')
        .select('*')
        .eq('id', uid)
        .single();
    return Map<String, dynamic>.from(r);
  }

  Future<Map<String, dynamic>> _fetchStats(String uid) async {
    final tickets = await SupabaseConfig.client
        .from('service_tickets')
        .select('id, status, priority, closed_at, customer_rating')
        .eq('assigned_to', uid)
        .eq('is_deleted', false);
    final list = List<Map<String, dynamic>>.from(tickets);
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));

    int active = 0,
        resolvedToday = 0,
        resolvedWeek = 0,
        urgent = 0,
        waiting = 0;
    double rSum = 0;
    int rCount = 0;

    for (final t in list) {
      final s = t['status'] as String? ?? '';
      final p = t['priority'] as String? ?? '';
      final ca =
          t['closed_at'] != null ? DateTime.tryParse(t['closed_at']) : null;
      final r = t['customer_rating'];
      if (['open', 'assigned', 'in_progress', 'waiting_customer'].contains(s)) {
        active++;
      }
      if (s == 'waiting_customer') waiting++;
      if (['urgent', 'high'].contains(p) &&
          !['resolved', 'closed'].contains(s)) {
        urgent++;
      }
      if (['resolved', 'closed'].contains(s) && ca != null) {
        if (ca.isAfter(todayStart)) resolvedToday++;
        if (ca.isAfter(weekStart)) resolvedWeek++;
      }
      if (r != null) {
        rSum += (r as num).toDouble();
        rCount++;
      }
    }
    return {
      'active': active,
      'resolved_today': resolvedToday,
      'resolved_week': resolvedWeek,
      'urgent': urgent,
      'waiting': waiting,
      'avg_rating':
          rCount > 0 ? double.parse((rSum / rCount).toStringAsFixed(1)) : 0.0,
      'total_assigned': list.length,
    };
  }

  Future<List<Map<String, dynamic>>> _fetchUrgent(String uid) async {
    final r = await SupabaseConfig.client
        .from('service_tickets')
        .select('''
        id, ticket_number, subject, priority, status, ticket_type, created_at, updated_at,
        customer:users!service_tickets_user_id_fkey(full_name, company_name, phone_number),
        customer_machine:customer_machines(serial_number,
          catalog_machine:machine_catalog(machine_name, model_number))
      ''')
        .eq('assigned_to', uid)
        .eq('is_deleted', false)
        .inFilter('status', ['open', 'assigned', 'in_progress'])
        .inFilter('priority', ['urgent', 'high'])
        .order('created_at', ascending: true)
        .limit(5);
    return List<Map<String, dynamic>>.from(r);
  }

  Future<List<Map<String, dynamic>>> _fetchRecent(String uid) async {
    final r = await SupabaseConfig.client
        .from('service_tickets')
        .select('''
        id, ticket_number, subject, priority, status, ticket_type, updated_at,
        customer:users!service_tickets_user_id_fkey(full_name, company_name)
      ''')
        .eq('assigned_to', uid)
        .eq('is_deleted', false)
        .order('updated_at', ascending: false)
        .limit(15);
    return List<Map<String, dynamic>>.from(r);
  }

  Future<int> _fetchUnreadCount(String uid) async {
    try {
      final ids = await SupabaseConfig.client
          .from('service_tickets')
          .select('id')
          .eq('assigned_to', uid)
          .eq('is_deleted', false)
          .inFilter('status', ['open', 'assigned', 'in_progress']);
      final ticketIds = (ids as List).map((t) => t['id'] as String).toList();
      if (ticketIds.isEmpty) return 0;
      final msgs = await SupabaseConfig.client
          .from('chat_messages')
          .select('id')
          .inFilter('ticket_id', ticketIds)
          .eq('is_read', false)
          .neq('sender_type', 'engineer');
      return (msgs as List).length;
    } catch (_) {
      return 0;
    }
  }

  void _subscribeRealtime() {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) return;
    _ticketChannel = SupabaseConfig.client
        .channel('eng_dash_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'service_tickets',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'assigned_to',
              value: uid),
          callback: (_) {
            // ← FIXED #12: debounce rapid changes (e.g. bulk updates)
            _realtimeDebounce?.cancel();
            _realtimeDebounce = Timer(const Duration(seconds: 2), () {
              if (mounted) _loadAll();
            });
          },
        )
        .subscribe();
  }

  Future<void> _updateAvailability(String s) async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await SupabaseConfig.client
          .from('users')
          .update({'availability_status': s}).eq('id', uid);
      if (!mounted) return;
      // ← FIXED #10: create new map instead of mutating
      setState(() {
        _profile = {..._profile, 'availability_status': s};
      });
    } catch (_) {
      // Silently fail — user will see stale status until next refresh
    }
  }

  // ← FIXED #3: use MaterialPageRoute, not named routes
  void _goLogin() async {
    await NotificationService().onLogout(); // ← ADDED: cleanup FCM
    await SupabaseConfig.client.auth.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  // ─── HELPERS ──────────────────────────────────────────────
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color _availColor(String s) {
    switch (s) {
      case 'available':
        return Brand.lightGreenBright;
      case 'busy':
        return const Color(0xFFFFB74D);
      default:
        return Brand.darkTextSecondary;
    }
  }

  Color _priorityColor(String p) {
    switch (p) {
      case 'urgent':
        return const Color(0xFFFF4757);
      case 'high':
        return const Color(0xFFFFB74D);
      case 'medium':
        return Brand.lightGreenBright;
      default:
        return Brand.darkTextSecondary;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'open':
        return Brand.darkIconActive;
      case 'assigned':
        return const Color(0xFF7986CB);
      case 'in_progress':
        return const Color(0xFFFFB74D);
      case 'waiting_customer':
        return const Color(0xFFCE93D8);
      case 'resolved':
        return Brand.lightGreenBright;
      case 'closed':
        return Brand.darkTextSecondary;
      default:
        return Brand.darkTextSecondary;
    }
  }

  void _navigateTo(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page)).then((_) {
      if (mounted) _loadAll();
    });
  }

  // ─── BUILD ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = _isDark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? SystemUiOverlayStyle.light
              .copyWith(statusBarColor: Colors.transparent)
          : SystemUiOverlayStyle.dark
              .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Brand.canvas(isDark),
        body: _buildBody(isDark),
        bottomNavigationBar: _buildBottomNav(isDark),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    Widget page;
    switch (_selectedIndex) {
      case 1:
        page = const EngineerTicketListPage();
        break;
      case 2:
        page = const EngineerProfilePage();
        break;
      default:
        page = _dashTab(isDark);
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: KeyedSubtree(key: ValueKey(_selectedIndex), child: page),
    );
  }

  // ═══════════ DASHBOARD TAB ═══════════════════════════════
  Widget _dashTab(bool isDark) {
    return SafeArea(
        child: OfflineBanner(
            child: RefreshIndicator(
      color: isDark ? Brand.darkIconActive : Brand.royalBlue,
      backgroundColor: isDark ? Brand.darkCard : Colors.white,
      displacement: 60,
      onRefresh: _loadAll,
      child: _isLoading
          ? _skeleton(isDark)
          : _hasError
              ? _errorState(isDark)
              : CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  slivers: [
                    _headerSliver(isDark),
                    SliverToBoxAdapter(
                        child: SlideTransition(
                            position: _heroSlide,
                            child: FadeTransition(
                                opacity: _heroFade, child: _heroCard(isDark)))),
                    SliverToBoxAdapter(child: _statsRow(isDark)),
                    // v24: engineer self check-in / check-out
                    const SliverToBoxAdapter(child: EngineerCheckinCard()),
                    SliverToBoxAdapter(child: _engQuickActions(isDark)),
                    SliverToBoxAdapter(child: _schedulesBanner(isDark)),
                    SliverToBoxAdapter(child: _installationsBanner(isDark)),
                    if (_urgentTickets.isNotEmpty) ...[
                      SliverToBoxAdapter(
                          child: _sectionTitle('🚨 Urgent & High Priority',
                              _urgentTickets.length, isDark)),
                      SliverList(
                          delegate: SliverChildBuilderDelegate(
                              (_, i) => _ticketCard(_urgentTickets[i], isDark,
                                  isUrgent: true),
                              childCount: _urgentTickets.length)),
                    ],
                    SliverToBoxAdapter(
                        child: _sectionTitle(
                      '📋 My Tickets',
                      _recentTickets.length,
                      isDark,
                      onViewAll: () => setState(() => _selectedIndex = 1),
                    )),
                    _recentTickets.isEmpty
                        ? SliverToBoxAdapter(child: _emptyTickets(isDark))
                        : SliverList(
                            delegate: SliverChildBuilderDelegate(
                                (_, i) =>
                                    _ticketCard(_recentTickets[i], isDark),
                                // ← FIXED #11
                                childCount: min(_recentTickets.length, 5))),
                    const SliverToBoxAdapter(child: SizedBox(height: 120)),
                  ],
                ),
    )));
  }

  // ─── Quick Actions strip (v24) ──────────────────────────────
  Widget _engQuickActions(bool isDark) {
    final actions = <Map<String, dynamic>>[
      {
        'icon': Icons.event_note_rounded,
        'label': 'My Schedules',
        'color': const Color(0xFF3B82F6),
        'tap': () =>
            _navigateTo(const EngineerMySchedulesPage()),
      },
      {
        'icon': Icons.build_circle_rounded,
        'label': 'Installations',
        'color': const Color(0xFF8B5CF6),
        'tap': () =>
            _navigateTo(const EngineerInstallationListPage()),
      },
      {
        'icon': Icons.calendar_month_rounded,
        'label': 'My Calendar',
        'color': const Color(0xFF14B8A6),
        'tap': () =>
            _navigateTo(const EngineerSchedulePage()),
      },
      {
        'icon': Icons.notifications_active_rounded,
        'label': 'Alerts',
        'color': const Color(0xFFF59E0B),
        'tap': () =>
            _navigateTo(const NotificationListPage(userRole: 'engineer')),
      },
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(Brand.r(22)),
          border: Border.all(
            color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(6),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: actions.map((a) {
            return Expanded(
              child: InkWell(
                onTap: a['tap'] as VoidCallback,
                borderRadius: BorderRadius.circular(Brand.r(14)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 6),
                  child: Column(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              (a['color'] as Color)
                                  .withAlpha(isDark ? 60 : 35),
                              (a['color'] as Color)
                                  .withAlpha(isDark ? 30 : 15),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(Brand.r(16)),
                        ),
                        child: Icon(a['icon'] as IconData,
                            color: a['color'] as Color, size: 22),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        a['label'] as String,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ─── SLIVER HEADER ────────────────────────────────────────
  Widget _headerSliver(bool isDark) {
    final name = _profile['full_name'] as String? ?? 'Engineer';
    final photo = _profile['profile_photo'] as String?;
    final avail = _profile['availability_status'] as String? ?? 'available';

    return SliverAppBar(
      expandedHeight: 0,
      floating: true,
      snap: true,
      pinned: false,
      backgroundColor: Brand.splashNavyEdge,
      elevation: 0,
      automaticallyImplyLeading: false,
      toolbarHeight: 80,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -1.4),
              radius: 1.8,
              colors: [
                Brand.splashNavyGlow,
                Brand.splashNavyCore,
                Brand.splashNavyEdge,
              ],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            GestureDetector(
              onTap: () => setState(() => _selectedIndex = 2),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Brand.r(16)),
                  gradient: LinearGradient(
                    colors: isDark
                        ? [_engAccent, _engAccentDark]
                        : [Brand.royalBlue, Brand.royalBlueLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isDark ? _engAccent : Brand.royalBlue)
                          .withAlpha(77),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    )
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Brand.r(16)),
                  // ← FIXED #2: replaced Image.network
                  child: photo != null && photo.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: photo,
                          fit: BoxFit.cover,
                          width: 52,
                          height: 52,
                          placeholder: (_, __) => _avatarFallback(name, isDark),
                          errorWidget: (_, __, ___) =>
                              _avatarFallback(name, isDark),
                        )
                      : _avatarFallback(name, isDark),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // TRI Engineering logo
                  // Navy hero — always use the dark-background logo variant.
                  CachedNetworkImage(
                    imageUrl: _triLogoUrl,
                    height: 18,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                    placeholder: (_, __) => const Text('TRI Engineering',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF8FA3C8),
                          letterSpacing: 0.3,
                        )),
                    errorWidget: (_, __, ___) => const Text('TRI Engineering',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF8FA3C8),
                          letterSpacing: 0.3,
                        )),
                  ),
                  const SizedBox(height: 2),
                  Text(name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 5),
                  const DsLimeLine(width: 36),
                ])),
            // Availability chip
            GestureDetector(
              onTap: () => _availSheet(isDark),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: _availColor(avail).withAlpha(((isDark ? 0.12 : 0.1) * 255).toInt()),
                  borderRadius: BorderRadius.circular(Brand.r(20)),
                  border:
                      Border.all(color: _availColor(avail).withAlpha(89)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: _availColor(avail), shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(avail.toUpperCase(),
                      style: TextStyle(
                        color: _availColor(avail),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      )),
                  const SizedBox(width: 3),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      color: _availColor(avail), size: 13),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            // ── Schedule calendar button ──
            Tooltip(
              message: 'My Schedule',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(Brand.r(14)),
                  onTap: () => _navigateTo(const EngineerSchedulePage()),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(20),
                      borderRadius: BorderRadius.circular(Brand.r(14)),
                      border: Border.all(color: Colors.white.withAlpha(38)),
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // ← FIXED #8: Bell now shows unread count context
            Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(Brand.r(14)),
                  onTap: () {
                    // Navigate to ticket list filtered to show unread
                    setState(() => _selectedIndex = 1);
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(20),
                      borderRadius: BorderRadius.circular(Brand.r(14)),
                      border: Border.all(color: Colors.white.withAlpha(38)),
                    ),
                    child: Stack(children: [
                      const Center(
                          child: Icon(Icons.notifications_outlined,
                              color: Colors.white, size: 22)),
                      if (_unreadMessages > 0)
                        Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [
                                  Color(0xFFFF4757),
                                  Color(0xFFFF6B81)
                                ]),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Brand.splashNavyCore, width: 2),
                              ),
                              constraints: const BoxConstraints(
                                  minWidth: 16, minHeight: 16),
                              child: Center(
                                  child: Text(
                                _unreadMessages > 9 ? '9+' : '$_unreadMessages',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700),
                              )),
                            )),
                    ]),
                  ),
                )),
          ]),
        ),
      ),
    );
  }

  Widget _avatarFallback(String name, bool isDark) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
            gradient: LinearGradient(
          colors: isDark
              ? [_engAccent, _engAccentDark]
              : [Brand.royalBlue, Brand.royalBlueLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )),
        child: Center(
            child: Text(StringUtils.getInitials(name), // ← FIXED #5
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 20))),
      );

  // ─── HERO CARD ────────────────────────────────────────────
  Widget _heroCard(bool isDark) {
    final active = (_stats['active'] as num?)?.toInt() ?? 0;
    final resolvedWeek = (_stats['resolved_week'] as num?)?.toInt() ?? 0;
    final urgent = (_stats['urgent'] as num?)?.toInt() ?? 0;
    final rating = (_stats['avg_rating'] as num?)?.toDouble() ?? 0.0;
    final name = _profile['full_name'] as String? ?? '';
    final specs = (_profile['specializations'] as List?)?.cast<String>() ?? [];
    final specLabel = specs.isNotEmpty ? specs.first : 'Field Engineer';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Brand.r(26)),
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF052E16), const Color(0xFF14532D)]
              : [const Color(0xFF14532D), const Color(0xFF16A34A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: const Color(0xFF16A34A).withAlpha(89),
            blurRadius: 30,
            offset: const Offset(0, 12),
          )
        ],
      ),
      child: Stack(children: [
        Positioned(
            right: -35,
            top: -35,
            child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withAlpha(((isDark ? 0.015 : 0.04) * 255).toInt())))),
        Positioned(
            right: 25,
            bottom: -25,
            child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withAlpha(((isDark ? 0.01 : 0.025) * 255).toInt())))),
        Padding(
          padding: const EdgeInsets.all(24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _engAccent.withAlpha(((isDark ? 0.12 : 0.18) * 255).toInt()),
                  borderRadius: BorderRadius.circular(Brand.r(24)),
                  border: Border.all(
                      color: _engAccent.withAlpha(((isDark ? 0.2 : 0.3) * 255).toInt())),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.engineering_rounded,
                      color: _engAccent, size: 14),
                  const SizedBox(width: 5),
                  Text(specLabel,
                      style: const TextStyle(
                        color: _engAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      )),
                ]),
              ),
              const Spacer(),
              if (rating > 0)
                Row(children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                  const SizedBox(width: 4),
                  Text(rating.toStringAsFixed(1),
                      style: TextStyle(
                        color: isDark ? Brand.darkTextPrimary : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      )),
                ]),
            ]),
            const SizedBox(height: 20),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Active Tickets',
                    style: TextStyle(
                      color: isDark
                          ? Brand.darkTextSecondary
                          : Colors.white.withAlpha(140),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    )),
                const SizedBox(height: 4),
                Text('$active',
                    style: TextStyle(
                      color: isDark ? Brand.darkTextPrimary : Colors.white,
                      fontSize: 46,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                      letterSpacing: -2,
                    )),
              ]),
              const Spacer(),
              _heroStat(Icons.check_circle_outline_rounded, '$resolvedWeek',
                  'This Week', isDark),
              const SizedBox(width: 18),
              _heroStat(
                  Icons.warning_amber_rounded, '$urgent', 'Urgent', isDark),
            ]),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(((isDark ? 0.04 : 0.07) * 255).toInt()),
                borderRadius: BorderRadius.circular(Brand.r(12)),
                border: Border.all(
                    color: Colors.white.withAlpha(((isDark ? 0.05 : 0.08) * 255).toInt())),
              ),
              child: Row(children: [
                Icon(Icons.person_outline_rounded,
                    color: isDark
                        ? Brand.darkTextSecondary
                        : Colors.white.withAlpha(153),
                    size: 16),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(name,
                        style: TextStyle(
                          color: isDark ? Brand.darkTextPrimary : Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis)),
                Text('iFrontiers Engineer',
                    style: TextStyle(
                      color: isDark
                          ? Brand.darkTextSecondary
                          : Colors.white.withAlpha(115),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    )),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _heroStat(IconData icon, String val, String label, bool isDark) =>
      Column(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isDark ? _darkCardHighlight : Colors.white.withAlpha(18),
            borderRadius: BorderRadius.circular(Brand.r(14)),
            border: Border.all(
                color: isDark
                    ? Brand.darkBorderLight
                    : Colors.white.withAlpha(15)),
          ),
          child: Icon(icon, color: Brand.lightGreenBright, size: 22),
        ),
        const SizedBox(height: 7),
        Text(val,
            style: TextStyle(
              color: isDark ? Brand.darkTextPrimary : Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            )),
        Text(label,
            style: TextStyle(
              color: isDark
                  ? Brand.darkTextTertiary
                  : Colors.white.withAlpha(102),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            )),
      ]);

  // ─── MY SCHEDULES BANNER ─────────────────────────────────
  Widget _schedulesBanner(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GestureDetector(
        onTap: () => _navigateTo(const EngineerMySchedulesPage()),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1B2540), const Color(0xFF24326D)]
                  : [const Color(0xFFE3E9FF), const Color(0xFFC9D5FF)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(Brand.r(16)),
            border: Border.all(
              color: Brand.royalBlue.withAlpha(isDark ? 60 : 80),
            ),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Brand.royalBlue.withAlpha(isDark ? 40 : 30),
                borderRadius: BorderRadius.circular(Brand.r(12)),
              ),
              child: Icon(Icons.event_available_rounded,
                  color: isDark
                      ? Brand.royalBlueGlow
                      : Brand.royalBlue,
                  size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Schedules',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : Brand.royalBlueDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Today's visits — start, arrive, complete",
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Brand.darkTextSecondary
                          : Brand.royalBlue,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
              size: 22,
            ),
          ]),
        ),
      ),
    );
  }

  // ─── INSTALLATIONS BANNER ────────────────────────────────
  Widget _installationsBanner(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GestureDetector(
        onTap: () => _navigateTo(const EngineerInstallationListPage()),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF0E2A38), const Color(0xFF0B3544)]
                  : [const Color(0xFFE0F7FA), const Color(0xFFB2EBF2)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(Brand.r(16)),
            border: Border.all(
              color: _engAccent.withAlpha(isDark ? 60 : 80),
            ),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _engAccent.withAlpha(isDark ? 40 : 30),
                borderRadius: BorderRadius.circular(Brand.r(12)),
              ),
              child: const Icon(Icons.build_circle_rounded,
                  color: _engAccent, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Installations',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Brand.darkTextPrimary : const Color(0xFF006064),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'View assigned installation tasks',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Brand.darkTextSecondary : const Color(0xFF00838F),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? _engAccent : const Color(0xFF006064),
              size: 22,
            ),
          ]),
        ),
      ),
    );
  }

  // ─── STATS ROW ────────────────────────────────────────────
  Widget _statsRow(bool isDark) {
    final items = [
      _StatItem('Active', '${_stats['active'] ?? 0}',
          Icons.pending_actions_rounded, Brand.darkIconActive),
      _StatItem('Today', '${_stats['resolved_today'] ?? 0}',
          Icons.check_circle_rounded, Brand.lightGreenBright),
      _StatItem('Waiting', '${_stats['waiting'] ?? 0}',
          Icons.hourglass_top_rounded, const Color(0xFFCE93D8)),
      _StatItem('Urgent', '${_stats['urgent'] ?? 0}', Icons.warning_rounded,
          const Color(0xFFFF4757)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: items
            .asMap()
            .entries
            .map((e) => Expanded(
                    child: Padding(
                  padding: EdgeInsets.only(right: e.key < 3 ? 8 : 0),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                    decoration: BoxDecoration(
                      color: Brand.surface(isDark),
                      borderRadius: BorderRadius.circular(Brand.r(14)),
                      border: Border.all(
                          color: isDark
                              ? e.value.color.withAlpha(40)
                              : e.value.color.withAlpha(51)),
                      boxShadow: isDark
                          ? null
                          : [
                              BoxShadow(
                                color: e.value.color.withAlpha(10),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              )
                            ],
                    ),
                    child: Column(children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: e.value.color.withAlpha(((isDark ? 0.12 : 0.1) * 255).toInt()),
                          borderRadius: BorderRadius.circular(Brand.r(10)),
                        ),
                        child:
                            Icon(e.value.icon, color: e.value.color, size: 17),
                      ),
                      const SizedBox(height: 6),
                      Text(e.value.value,
                          style: TextStyle(
                            color: e.value.color,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                          )),
                      const SizedBox(height: 2),
                      Text(e.value.label.toUpperCase(),
                          style: TextStyle(
                            color: isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          )),
                    ]),
                  ),
                )))
            .toList(),
      ),
    );
  }

  // ─── SECTION TITLE ────────────────────────────────────────
  Widget _sectionTitle(String title, int count, bool isDark,
      {VoidCallback? onViewAll}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
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
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(Brand.r(2)),
          ),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            )),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: (isDark ? Brand.darkIconActive : Brand.royalBlue)
                .withAlpha(26),
            borderRadius: BorderRadius.circular(Brand.r(12)),
          ),
          child: Text('$count',
              style: TextStyle(
                color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              )),
        ),
        if (onViewAll != null) ...[
          const SizedBox(width: 8),
          Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onViewAll,
                borderRadius: BorderRadius.circular(Brand.r(20)),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Brand.darkCardElevated
                        : Brand.royalBlueSurface,
                    borderRadius: BorderRadius.circular(Brand.r(20)),
                    border: Border.all(
                        color: isDark
                            ? Brand.darkBorderLight
                            : Brand.royalBlue.withAlpha(31)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('View All',
                        style: TextStyle(
                          color:
                              isDark ? Brand.darkIconActive : Brand.royalBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded,
                        size: 14,
                        color: isDark ? Brand.darkIconActive : Brand.royalBlue),
                  ]),
                ),
              )),
        ],
      ]),
    );
  }

  // ─── TICKET CARD ──────────────────────────────────────────
  Widget _ticketCard(Map<String, dynamic> ticket, bool isDark,
      {bool isUrgent = false}) {
    final priority = ticket['priority'] as String? ?? 'medium';
    final status = ticket['status'] as String? ?? 'open';
    final customer = ticket['customer'] as Map<String, dynamic>?;
    final machine = ticket['customer_machine'] as Map<String, dynamic>?;
    final catalog = machine?['catalog_machine'] as Map<String, dynamic>?;
    final pColor = _priorityColor(priority);
    final sColor = _statusColor(status);
    final updatedAt = ticket['updated_at'] != null
        ? DateTime.tryParse(ticket['updated_at'].toString())
        : null;

    return GestureDetector(
      onTap: () =>
          _navigateTo(EngineerTicketDetailPage(ticketId: ticket['id'])),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(18)),
          border: Border.all(
            color: isUrgent
                ? pColor.withAlpha(115)
                : (isDark ? Brand.darkBorder : Brand.borderLight),
            width: isUrgent ? 1.5 : 1,
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: pColor.withAlpha(((isUrgent ? 0.07 : 0.03) * 255).toInt()),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _typeBox(ticket['ticket_type'] as String? ?? 'support', isDark),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('#${ticket['ticket_number'] ?? ''}',
                        style: TextStyle(
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight,
                          fontSize: 11,
                        )),
                    Text(ticket['subject'] ?? '',
                        style: TextStyle(
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ])),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                _badge(priority.toUpperCase(), pColor, isDark),
                const SizedBox(height: 4),
                _badge(
                    status.replaceAll('_', ' ').toUpperCase(), sColor, isDark),
              ]),
            ]),
            const SizedBox(height: 10),
            Divider(
                color: isDark ? Brand.darkBorder : Brand.borderLight,
                height: 1),
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.person_outline_rounded,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  size: 13),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(customer?['full_name'] ?? 'Unknown',
                      style: TextStyle(
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis)),
              if (catalog != null) ...[
                Icon(Icons.settings_suggest_rounded,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    size: 13),
                const SizedBox(width: 4),
                Expanded(
                    child: Text(catalog['machine_name'] ?? '',
                        style: TextStyle(
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis)),
              ],
              // ← FIXED #6: use TimeUtils
              if (updatedAt != null)
                Text(TimeUtils.getTimeAgo(updatedAt),
                    style: TextStyle(
                      color: isDark ? Brand.darkTextTertiary : Colors.black38,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    )),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _typeBox(String type, bool isDark) {
    IconData icon;
    Color c;
    switch (type) {
      case 'support':
        icon = Icons.build_rounded;
        c = const Color(0xFFFF8A65);
        break;
      case 'inquiry':
        icon = Icons.help_outline_rounded;
        c = Brand.darkIconActive;
        break;
      case 'order':
        icon = Icons.shopping_cart_rounded;
        c = Brand.lightGreenBright;
        break;
      default:
        icon = Icons.confirmation_num_outlined;
        c = Brand.darkTextSecondary;
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: c.withAlpha(((isDark ? 0.12 : 0.1) * 255).toInt()),
        borderRadius: BorderRadius.circular(Brand.r(12)),
        border: isDark ? Border.all(color: c.withAlpha(38)) : null,
      ),
      child: Icon(icon, color: c, size: 20),
    );
  }

  Widget _badge(String text, Color c, bool isDark) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withAlpha(isDark ? 31 : 20),
          borderRadius: BorderRadius.circular(Brand.r(10)),
          border: Border.all(color: c.withAlpha(isDark ? 51 : 38)),
        ),
        child: Text(text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: c,
              letterSpacing: 0.5,
            )),
      );

  Widget _emptyTickets(bool isDark) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(22)),
           border: isDark
           ? Border.all(color: Brand.darkBorder) : null,
        ),
        child: Column(children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCardElevated : Brand.lightGreenSurface,
              borderRadius: BorderRadius.circular(Brand.r(22)),
            ),
            child: Icon(Icons.check_circle_outline_rounded,
                size: 36,
                color: isDark ? Brand.lightGreenBright : Brand.lightGreen),
          ),
          const SizedBox(height: 18),
          Text('All caught up! 🎉',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              )),
          const SizedBox(height: 6),
          Text('No tickets assigned to you right now',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              )),
        ]),
      );

  Widget _errorState(bool isDark) => Center(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                  color: Colors.red.withAlpha(26),
                  borderRadius: BorderRadius.circular(Brand.r(24))),
              child: const Icon(Icons.cloud_off_rounded,
                  color: Colors.red, size: 40)),
          const SizedBox(height: 20),
          Text('Connection Error',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              )),
          const SizedBox(height: 8),
          Text('Pull down to retry',
              style: TextStyle(
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  fontSize: 14)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _isLoading = true;
                _hasError = false;
              });
              _loadAll();
            },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? Brand.darkIconActive : Brand.royalBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Brand.r(14))),
            ),
          ),
        ],
      ));

  Widget _skeleton(bool isDark) {
    Widget sk(double w, double h, double r) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: isDark
                ? Brand.darkBorderLight.withAlpha(77)
                : Brand.royalBlue.withAlpha(13),
            borderRadius: BorderRadius.circular(r),
          ),
        );
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          sk(52, 52, 16),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                sk(90, 12, 6),
                const SizedBox(height: 8),
                sk(150, 20, 8),
              ])),
          sk(90, 34, 17),
        ]),
        const SizedBox(height: 24),
        sk(double.infinity, 200, 24),
        const SizedBox(height: 20),
        Row(
            children: List.generate(
                4,
                (i) => Expanded(
                    child: Padding(
                        padding: EdgeInsets.only(right: i < 3 ? 10 : 0),
                        child: sk(double.infinity, 88, 16))))),
        const SizedBox(height: 24),
        sk(160, 20, 8),
        const SizedBox(height: 12),
        ...List.generate(
            3,
            (_) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: sk(double.infinity, 88, 18))),
      ]),
    );
  }

  // ─── AVAILABILITY SHEET ───────────────────────────────────
  void _availSheet(bool isDark) {
    final opts = [
      _AvailOption('available', 'Available', 'Ready to take new tickets',
          Icons.check_circle_rounded, Brand.lightGreenBright),
      _AvailOption('busy', 'Busy', 'Currently occupied',
          Icons.do_not_disturb_rounded, const Color(0xFFFFB74D)),
      _AvailOption('offline', 'Offline', 'Not available right now',
          Icons.offline_bolt_rounded, Brand.darkTextSecondary),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Brand.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetCtx) => Column(
          // ← FIXED: sheetCtx
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color:
                        isDark ? Brand.darkBorderLight : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(Brand.r(2)))),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Set Availability',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  )),
            ),
            const SizedBox(height: 12),
            ...opts.map((o) {
              final isCurrent =
                  (_profile['availability_status'] ?? 'available') == o.key;
              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                leading: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: o.color.withAlpha(((isDark ? 0.12 : 0.1) * 255).toInt()),
                    borderRadius: BorderRadius.circular(Brand.r(14)),
                  ),
                  child: Icon(o.icon, color: o.color, size: 22),
                ),
                title: Text(o.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    )),
                subtitle: Text(o.subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    )),
                trailing: isCurrent
                    ? Icon(Icons.check_rounded, color: o.color, size: 22)
                    : null,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _updateAvailability(o.key);
                },
              );
            }),
            const SizedBox(height: 24),
          ]),
    );
  }

  // ─── BOTTOM NAV ───────────────────────────────────────────
  Widget _buildBottomNav(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        border: Border(
            top: BorderSide(
                color: isDark ? Brand.darkBorder : Brand.borderLight)),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(15),
            blurRadius: 24,
            offset: const Offset(0, -6),
          )
        ],
      ),
      child: SafeArea(
          child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _navItem(Icons.dashboard_rounded, 'Dashboard', 0, isDark),
          _navCenter(isDark),
          _navItem(Icons.person_rounded, 'My Profile', 2, isDark),
        ]),
      )),
    );
  }

  Widget _navCenter(bool isDark) {
    final active = (_stats['active'] as num?)?.toInt() ?? 0;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedIndex = 1;
        // Clear the unread-messages bell badge optimistically when the
        // engineer navigates to the tickets list — they're going to see them.
        _unreadMessages = 0;
      }),
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [_engAccent, _engAccentDark]
                  : [Brand.royalBlue, Brand.royalBlueLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(Brand.r(20)),
            boxShadow: [
              BoxShadow(
                color:
                    (isDark ? _engAccent : Brand.royalBlue).withAlpha(115),
                blurRadius: 16,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: const IcTicketIcon(color: Colors.white, size: 28),
        ),
        if (active > 0)
          Positioned(
              top: -5,
              right: -5,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFFF4757), Color(0xFFFF6B81)]),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: isDark ? Brand.darkCard : Colors.white,
                      width: 2.5),
                ),
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                child: Center(
                    child: Text(active > 9 ? '9+' : '$active',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700))),
              )),
      ]),
    );
  }

  Widget _navItem(IconData icon, String label, int idx, bool isDark) {
    final sel = _selectedIndex == idx;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedIndex = idx);
        // When returning to the Dashboard tab, refresh all stats so the
        // active-ticket count and unread-message count stay accurate.
        if (idx == 0) _loadAll();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
          width: 90,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: sel
                    ? (isDark
                        ? _engAccent.withAlpha(31)
                        : Brand.royalBlueSurface)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(Brand.r(14)),
              ),
              child: Icon(
                icon,
                color: sel
                    ? (isDark ? _engAccent : Brand.royalBlue)
                    : (isDark
                        ? Brand.darkTextTertiary // ← FIXED #14
                        : Brand.subtleLight),
                size: 24,
              ),
            ),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  color: sel
                      ? (isDark ? _engAccent : Brand.royalBlue)
                      : (isDark
                          ? Brand.darkTextTertiary // ← FIXED #14
                          : Brand.subtleLight),
                )),
          ])),
    );
  }
}

// ── Helper classes ──────────────────────────────────────────
class _StatItem {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatItem(this.label, this.value, this.icon, this.color);
}

class _AvailOption {
  final String key, label, subtitle;
  final IconData icon;
  final Color color;
  const _AvailOption(
      this.key, this.label, this.subtitle, this.icon, this.color);
}
