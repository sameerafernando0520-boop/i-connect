// ============================================================
// FILE: lib/screens/customer/notification_list_page.dart
// Role-aware navigation (works for customer + admin + engineer)
// ============================================================


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show
        RealtimeChannel,
        PostgresChangeEvent,
        PostgresChangeFilter,
        PostgresChangeFilterType;
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../l10n/s.dart';
import '../../utils/time_utils.dart';
import 'notification_settings_page.dart';
import 'ticket_detail_page.dart';
import 'my_invoices_page.dart';
import 'customer_installments_page.dart';
import 'my_quotations_page.dart';
import 'my_schedule_page.dart';
import 'my_machines_page.dart';
import 'catalog_page.dart';
import 'referral_page.dart';
import '../admin/admin_ticket_detail_page.dart';
import '../admin/inquiry_detail_page.dart';
import '../admin/installment_detail_page.dart';
import '../engineer/engineer_ticket_detail_page.dart';

// ══════════════════════════════════════════════════════════════
//  NOTIFICATION TYPES & VISUAL CONFIG
// ══════════════════════════════════════════════════════════════
class _NType {
  final IconData icon;
  final Color color;
  const _NType(this.icon, this.color);

  static _NType of(String? type, bool isDark) {
    switch (type) {
      case 'ticket_update':
      case 'ticket_assigned':
      case 'ticket_resolved':
        return _NType(Icons.confirmation_num_rounded,
            isDark ? Brand.darkIconActive : Brand.royalBlue);
      case 'service_reminder':
      case 'service_scheduled':
      case 'service_completed':
        return _NType(Icons.build_circle_rounded,
            isDark ? const Color(0xFFFFB74D) : Colors.orange.shade700);
      case 'warranty_expiry':
      case 'warranty_extended':
        return _NType(Icons.shield_rounded,
            isDark ? const Color(0xFFCE93D8) : const Color(0xFF6A1B9A));
      case 'order_update':
      case 'order_confirmed':
      case 'order_shipped':
      case 'order_delivered':
        return _NType(Icons.local_shipping_rounded,
            isDark ? Brand.lightGreenBright : Brand.lightGreen);
      case 'points_earned':
      case 'tier_upgrade':
      case 'free_item':
        return _NType(Icons.star_rounded,
            isDark ? const Color(0xFFFFD54F) : Colors.amber.shade700);
      case 'promotion':
      case 'announcement':
      case 'broadcast':
        return _NType(Icons.campaign_rounded,
            isDark ? const Color(0xFFFF8A65) : const Color(0xFFE65100));
      case 'message':
      case 'chat':
      case 'new_message':
        return _NType(Icons.chat_bubble_rounded,
            isDark ? const Color(0xFF80CBC4) : const Color(0xFF00695C));
      case 'system':
      default:
        return _NType(Icons.notifications_rounded,
            isDark ? Brand.darkIconActive : Brand.royalBlue);
    }
  }
}

// ══════════════════════════════════════════════════════════════
//  NOTIFICATION LIST PAGE
// ══════════════════════════════════════════════════════════════
class NotificationListPage extends StatefulWidget {
  final String userRole; // 'customer' | 'admin' | 'engineer'

  const NotificationListPage({
    super.key,
    this.userRole = 'customer',
  });

  @override
  State<NotificationListPage> createState() => _NotificationListPageState();
}

class _NotificationListPageState extends State<NotificationListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoading = true;
  bool _hasError = false;
  bool _isMarkingAll = false;

  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _unread = [];
  List<Map<String, dynamic>> _system = [];

  RealtimeChannel? _realtimeChannel;

  final Set<String> _markingIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadNotifications();
    _setupRealtime();
  }

  @override
  void dispose() {
    _tabController.dispose();
    if (_realtimeChannel != null) {
      SupabaseConfig.client.removeChannel(_realtimeChannel!);
    }
    super.dispose();
  }

  // ─── DATA LOADING ──────────────────────────────────────────
  Future<void> _loadNotifications() async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;

      List<dynamic> raw = [];
      try {
        raw = await SupabaseConfig.client
            .from('notifications')
            .select('*')
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(100);
      } catch (queryError) {
        debugPrint('❌ Notifications query error: $queryError');
        if (mounted) {
          setState(() {
            _all = [];
            _unread = [];
            _system = [];
            _isLoading = false;
            _hasError = false;
          });
        }
        return;
      }

      final all = (raw as List? ?? []).map((n) {
        final row = Map<String, dynamic>.from(n as Map);
        return {
          'id': row['id'] ?? '',
          'title': row['title'] ?? row['subject'] ?? 'Notification',
          'message': row['message'] ?? row['body'] ?? row['content'] ?? '',
          'type': row['type'] ?? row['notification_type'] ?? 'system',
          'is_read': row['is_read'] ?? row['read'] ?? false,
          'created_at': row['created_at'],
          'related_id':
              row['related_id'] ?? row['ticket_id'] ?? row['reference_id'],
          'related_type': row['related_type'] ?? row['reference_type'],
          'data': row['data'] ?? row['metadata'],
        };
      }).toList();

      if (mounted) {
        setState(() {
          _all = all;
          _unread = all.where((n) => n['is_read'] == false).toList();
          _system = all
              .where((n) =>
                  n['type'] == 'system' ||
                  n['type'] == 'announcement' ||
                  n['type'] == 'promotion' ||
                  n['type'] == 'broadcast')
              .toList();
          _isLoading = false;
          _hasError = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Notification load error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  void _setupRealtime() {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;

    _realtimeChannel = SupabaseConfig.client
        .channel('notif_list_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId),
          callback: (payload) {
            if (mounted && payload.newRecord.isNotEmpty) {
              final n = Map<String, dynamic>.from(payload.newRecord);
              setState(() {
                _all.insert(0, n);
                if (n['is_read'] == false) _unread.insert(0, n);
                if (['system', 'announcement', 'promotion', 'broadcast']
                    .contains(n['type'])) {
                  _system.insert(0, n);
                }
              });
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId),
          callback: (payload) {
            if (mounted) _loadNotifications();
          },
        )
        .subscribe();
  }

  // ─── MARK AS READ (single) ─────────────────────────────────
  Future<void> _markRead(String id) async {
    if (_markingIds.contains(id)) return;
    setState(() => _markingIds.add(id));
    try {
      await SupabaseConfig.client
          .from('notifications')
          .update({'is_read': true}).eq('id', id);

      if (mounted) {
        setState(() {
          void markInList(List<Map<String, dynamic>> list) {
            final idx = list.indexWhere((n) => n['id'] == id);
            if (idx != -1) {
              list[idx] = {...list[idx], 'is_read': true};
            }
          }

          markInList(_all);
          markInList(_system);
          _unread.removeWhere((n) => n['id'] == id);
          _markingIds.remove(id);
        });
      }
    } catch (e) {
      debugPrint('⚠️ Mark read error: $e');
      if (mounted) setState(() => _markingIds.remove(id));
    }
  }

  // ─── MARK ALL AS READ ──────────────────────────────────────
  Future<void> _markAllRead() async {
    if (_unread.isEmpty || _isMarkingAll) return;
    setState(() => _isMarkingAll = true);
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;

      await SupabaseConfig.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);

      if (mounted) {
        setState(() {
          _all = _all.map((n) => {...n, 'is_read': true}).toList();
          _system = _system.map((n) => {...n, 'is_read': true}).toList();
          _unread = [];
          _isMarkingAll = false;
        });
        _showSnack('All notifications marked as read', isSuccess: true);
      }
    } catch (e) {
      debugPrint('⚠️ Mark all read error: $e');
      if (mounted) {
        setState(() => _isMarkingAll = false);
        _showSnack('Failed to mark all as read');
      }
    }
  }

  // ─── HANDLE TAP ────────────────────────────────────────────
  void _handleTap(Map<String, dynamic> n) {
    if (n['is_read'] == false) {
      _markRead(n['id'] as String);
    }

    final type = n['type'] as String?;
    final relatedType = n['related_type'] as String?;

    // metadata is stored under the 'data' key (mapped from the DB 'metadata'
    // JSONB column in _loadNotifications). For ticket_update notifications the
    // ticket ID lives here rather than in related_id (which is NULL).
    final data = (n['data'] as Map<String, dynamic>?) ?? {};

    // related_id: populated for installment / invoice notifications.
    // For ticket_update notifications it is NULL — fall back to metadata.
    String relatedId = (n['related_id'] as String?) ?? '';
    if (relatedId.isEmpty && data['ticket_id'] != null) {
      relatedId = data['ticket_id'].toString();
    }

    // ticket_type from metadata tells us 'inquiry' vs 'support' for routing.
    final ticketType = (data['ticket_type'] as String?) ?? '';

    // ── Inquiries (admin-only routing) ───────────────────────
    // Route to InquiryDetailPage when the metadata or related_type says inquiry.
    if (relatedId.isNotEmpty &&
        (relatedType == 'inquiry' || ticketType == 'inquiry')) {
      _navigateToTicketDetail(relatedId, ticketType: 'inquiry');
      return;
    }

    // ── Tickets / chat ───────────────────────────────────────
    const ticketTypes = {
      'ticket_update',
      'ticket_assigned',
      'ticket_resolved',
      'ticket_closed',
      'ticket_reopened',
      'new_message',
      'message',
      'chat',
    };
    if (relatedId.isNotEmpty &&
        (ticketTypes.contains(type) ||
            relatedType == 'ticket' ||
            relatedType == 'service_ticket')) {
      _navigateToTicketDetail(relatedId, ticketType: ticketType);
      return;
    }

    // ── Invoices ─────────────────────────────────────────────
    const invoiceTypes = {
      'invoice',
      'invoice_created',
      'invoice_paid',
      'invoice_sent',
      'invoice_overdue',
    };
    if (invoiceTypes.contains(type) || relatedType == 'invoice') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MyInvoicesPage()),
      );
      return;
    }

    // ── Quotations ───────────────────────────────────────────
    const quotationTypes = {
      'quotation',
      'quotation_sent',
      'quotation_accepted',
      'quote_sent',
    };
    if (quotationTypes.contains(type) || relatedType == 'quotation') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MyQuotationsPage()),
      );
      return;
    }

    // ── Installments / payment receipts ──────────────────────
    // Deep-link directly to the plan detail when a plan-level related_id is
    // available. The DB stores related_type as 'installment' or
    // 'installment_plan' depending on the code path that created the row —
    // accept both so the user always lands on the right screen.
    const installmentTypes = {
      'installment',
      'installment_created',
      'installment_paid',
      'installment_due',
      'installment_due_today',
      'installment_overdue',
      'installment_reminder_3d',
      'payment_received',
      'payment_recorded',
      'payment_receipt_submitted',
      'payment_verified',
      'payment_rejected',
    };
    if (installmentTypes.contains(type) ||
        relatedType == 'installment_plan' ||
        relatedType == 'installment' ||
        relatedType == 'installment_payment') {
      // Deep-link when we have a plan-level id; fall back to the list page.
      if (relatedId.isNotEmpty &&
          (relatedType == 'installment_plan' ||
              relatedType == 'installment' ||
              installmentTypes.contains(type))) {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => InstallmentDetailPage(planId: relatedId)),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const CustomerInstallmentsPage()),
        );
      }
      return;
    }

    // ── Service schedules ────────────────────────────────────
    const scheduleTypes = {
      'service_reminder',
      'service_scheduled',
      'service_completed',
      'schedule_created',
      'schedule_confirmed',
      'schedule_reminder',
      'schedule_completed',
      'schedule_cancelled',
    };
    if (scheduleTypes.contains(type) || relatedType == 'service_schedule') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MySchedulePage()),
      );
      return;
    }

    // ── Warranty / machine ───────────────────────────────────
    const machineTypes = {
      'warranty_expiry',
      'warranty_extended',
      'machine_registered',
    };
    if (machineTypes.contains(type) ||
        relatedType == 'customer_machine' ||
        relatedType == 'machine') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MyMachinesPage()),
      );
      return;
    }

    // ── Referrals ────────────────────────────────────────────
    const referralTypes = {
      'referral_signup',
      'referral_qualified',
      'referral_approved',
      'referral_paid',
      'referral_expired',
      'referral_rejected',
    };
    if (referralTypes.contains(type) || relatedType == 'referral') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ReferralPage()),
      );
      return;
    }

    // ── Promotions / catalog ─────────────────────────────────
    const catalogTypes = {'promotion', 'broadcast', 'new_product'};
    if (catalogTypes.contains(type)) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CatalogPage()),
      );
      return;
    }

    // Fallback: nothing further to do — already marked read above.
  }

  // ─── ROLE-AWARE TICKET NAVIGATION ─────────────────────────
  // [ticketType] comes from the notification metadata ('inquiry' / 'support' / '').
  // For admins it decides between InquiryDetailPage and AdminTicketDetailPage.
  // When the type is empty we fetch the service_tickets row to read ticket_type
  // before routing — this guarantees admins always land on the correct screen
  // regardless of how the notification was created.
  void _navigateToTicketDetail(String ticketId, {String ticketType = ''}) {
    if (widget.userRole == 'admin') {
      if (ticketType == 'inquiry') {
        // Explicit inquiry — go straight to InquiryDetailPage.
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => InquiryDetailPage(inquiryId: ticketId)),
        );
      } else if (ticketType.isEmpty || ticketType == 'support') {
        // Ambiguous — fetch ticket_type from DB and route accordingly.
        _navigateAdminTicketAfterFetch(ticketId);
      } else {
        // Any other explicit type falls back to service ticket view.
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => AdminTicketDetailPage(ticketId: ticketId)),
        );
      }
      return;
    }

    // Engineer and customer always use their own detail pages.
    final Widget page = widget.userRole == 'engineer'
        ? EngineerTicketDetailPage(ticketId: ticketId)
        : TicketDetailPage(ticketId: ticketId);

    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  // Fetches ticket_type for [ticketId] and opens the correct admin page.
  // Falls back to AdminTicketDetailPage if the DB call fails.
  Future<void> _navigateAdminTicketAfterFetch(String ticketId) async {
    try {
      final row = await SupabaseConfig.client
          .from('service_tickets')
          .select('ticket_type')
          .eq('id', ticketId)
          .maybeSingle();

      if (!mounted) return;

      final ticketType = (row?['ticket_type'] as String?) ?? 'support';
      final Widget page = ticketType == 'inquiry'
          ? InquiryDetailPage(inquiryId: ticketId)
          : AdminTicketDetailPage(ticketId: ticketId);

      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    } catch (_) {
      // Fallback — service ticket is the safer default.
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => AdminTicketDetailPage(ticketId: ticketId)),
      );
    }
  }

  // ─── DELETE ────────────────────────────────────────────────
  Future<void> _deleteNotification(String id) async {
    try {
      await SupabaseConfig.client.from('notifications').delete().eq('id', id);
      if (mounted) {
        setState(() {
          _all.removeWhere((n) => n['id'] == id);
          _unread.removeWhere((n) => n['id'] == id);
          _system.removeWhere((n) => n['id'] == id);
        });
      }
    } catch (e) {
      debugPrint('⚠️ Delete error: $e');
      if (mounted) _showSnack('Failed to delete notification');
    }
  }

  // ─── HELPERS ───────────────────────────────────────────────
  void _showSnack(String msg, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(isSuccess ? Icons.check_circle : Icons.error_outline,
            color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: isSuccess ? Brand.lightGreen : Colors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  List<_ListItem> _buildItems(List<Map<String, dynamic>> list) {
    final result = <_ListItem>[];
    String? lastDate;
    for (final n in list) {
      final dateStr = n['created_at'] as String?;
      String header = '';
      if (dateStr != null) {
        try {
          final d = DateTime.parse(dateStr).toLocal();
          final now = DateTime.now();
          if (d.year == now.year && d.month == now.month && d.day == now.day) {
            header = 'Today';
          } else if (d.year == now.year &&
              d.month == now.month &&
              d.day == now.day - 1) {
            header = 'Yesterday';
          } else {
            header = '${_monthName(d.month)} ${d.day}, ${d.year}';
          }
        } catch (_) {}
      }
      if (header.isNotEmpty && header != lastDate) {
        result.add(_ListItem.header(header));
        lastDate = header;
      }
      result.add(_ListItem.notification(n));
    }
    return result;
  }

  String _monthName(int m) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[m];
  }

  String get _pageTitle {
    switch (widget.userRole) {
      case 'admin':
        return 'Admin Notifications';
      case 'engineer':
        return 'Notifications';
      default:
        return 'Notifications';
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unreadCount = _unread.length;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? SystemUiOverlayStyle.light
              .copyWith(statusBarColor: Colors.transparent)
          : SystemUiOverlayStyle.dark
              .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Brand.canvas(isDark),
        body: Column(
          children: [
            _buildTopBar(isDark, unreadCount),
            _buildTabBar(isDark, unreadCount),
            Expanded(
              child: _isLoading
                  ? _buildSkeleton(isDark)
                  : _hasError
                      ? _buildError(isDark)
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildList(_all, isDark),
                            _buildList(
                              _unread,
                              isDark,
                              emptyLabel:
                                  S.of(context)!.notificationNoNotificationsDesc,
                              emptySubLabel: S.of(context)!.notificationNoUnread,
                            ),
                            _buildList(
                              _system,
                              isDark,
                              emptyLabel: S.of(context)!.notificationNoSystem,
                              emptySubLabel:
                                  S.of(context)!.notificationSystemDesc,
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── TOP BAR ───────────────────────────────────────────────
  Widget _buildTopBar(bool isDark, int unreadCount) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: Row(children: [
          _iconBtn(Icons.arrow_back_ios_new_rounded, isDark,
              () => Navigator.pop(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_pageTitle,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                      letterSpacing: -0.5,
                    )),
                if (unreadCount > 0)
                  Text('$unreadCount unread',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                        fontWeight: FontWeight.w600,
                      )),
              ],
            ),
          ),
          if (unreadCount > 0)
            _isMarkingAll
                ? Container(
                    width: 44,
                    height: 44,
                    padding: const EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: isDark ? Brand.darkIconActive : Brand.royalBlue),
                  )
                : _iconBtn(
                    Icons.done_all_rounded,
                    isDark,
                    _markAllRead,
                    tooltip: S.of(context)!.notificationMarkAllRead,
                    activeColor:
                        isDark ? Brand.lightGreenBright : Brand.lightGreen,
                  ),
          const SizedBox(width: 6),
          if (widget.userRole == 'customer')
            _iconBtn(
              Icons.settings_outlined,
              isDark,
              () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const NotificationSettingsPage())),
              tooltip: S.of(context)!.notificationSettings,
            ),
        ]),
      ),
    );
  }

  Widget _iconBtn(IconData icon, bool isDark, VoidCallback onTap,
      {String? tooltip, Color? activeColor}) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Brand.surface(isDark),
              borderRadius: BorderRadius.circular(14),
              border: isDark ? Border.all(color: Brand.darkBorder) : null,
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                          color: Brand.royalBlue.withAlpha(((0.05) * 255).toInt()),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ],
            ),
            child: Icon(icon,
                size: 20,
                color: activeColor ??
                    (isDark ? Brand.darkTextSecondary : Brand.royalBlue)),
          ),
        ),
      ),
    );
  }

  // ─── TAB BAR ───────────────────────────────────────────────
  Widget _buildTabBar(bool isDark, int unreadCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(14),
           border: isDark
           ? Border.all(color: Brand.darkBorder) : null,
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            gradient: LinearGradient(
                colors: isDark
                    ? [Brand.darkIconActive, Brand.royalBlueGlow]
                    : [Brand.royalBlue, Brand.royalBlueLight]),
            borderRadius: BorderRadius.circular(10),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: const EdgeInsets.all(3),
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor:
              isDark ? Brand.darkTextSecondary : Brand.subtleLight,
          labelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          tabs: [
            Tab(text: S.of(context)!.notificationAll),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(S.of(context)!.notificationUnread),
                if (unreadCount > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$unreadCount',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ],
              ]),
            ),
            Tab(text: S.of(context)!.notificationSystem),
          ],
        ),
      ),
    );
  }

  // ─── NOTIFICATION LIST ─────────────────────────────────────
  Widget _buildList(
    List<Map<String, dynamic>> notifications,
    bool isDark, {
    String emptyLabel = 'No notifications yet',
    String emptySubLabel = 'New notifications will appear here',
  }) {
    if (notifications.isEmpty) {
      return _buildEmpty(emptyLabel, emptySubLabel, isDark);
    }

    final items = _buildItems(notifications);

    return RefreshIndicator(
      onRefresh: _loadNotifications,
      color: isDark ? Brand.darkIconActive : Brand.royalBlue,
      backgroundColor: isDark ? Brand.darkCard : Colors.white,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        itemCount: items.length,
        itemBuilder: (context, idx) {
          final item = items[idx];
          if (item.isHeader) {
            return _buildDateHeader(item.header!, isDark);
          }
          return _buildNotificationCard(item.notification!, isDark);
        },
      ),
    );
  }

  // ─── DATE HEADER ───────────────────────────────────────────
  Widget _buildDateHeader(String label, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
      child: Row(children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [Brand.darkIconActive, Brand.royalBlueGlow]
                  : [Brand.royalBlue, Brand.royalBlueGlow],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Brand.darkTextSecondary : Brand.royalBlue,
              letterSpacing: -0.2,
            )),
      ]),
    );
  }

  // ─── NOTIFICATION CARD ─────────────────────────────────────
  Widget _buildNotificationCard(Map<String, dynamic> n, bool isDark) {
    final id = n['id'] as String? ?? '';
    final title = n['title'] as String? ?? 'Notification';
    final message = n['message'] as String? ?? '';
    final type = n['type'] as String?;
    final isRead = n['is_read'] as bool? ?? true;
    final createdAt = n['created_at'] as String?;
    // hasRelated: show the chevron when there is a navigable target — either a
    // direct related_id (installments, invoices) or a ticket_id in metadata
    // (ticket_update notifications where related_id is NULL).
    final cardData = (n['data'] as Map<String, dynamic>?) ?? {};
    final hasRelated = ((n['related_id'] as String?)?.isNotEmpty ?? false) ||
        cardData.containsKey('ticket_id');
    final isMarking = _markingIds.contains(id);

    final ntype = _NType.of(type, isDark);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: Key('notif_$id'),
        direction: DismissDirection.endToStart,
        background: _dismissBg(isDark),
        confirmDismiss: (_) async {
          return await showDialog<bool>(
                context: context,
                builder: (dialogCtx) => AlertDialog(
                  backgroundColor: Brand.surface(isDark),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  title: Text(S.of(context)!.notificationDeleteConfirm,
                      style: TextStyle(
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark,
                          fontWeight: FontWeight.w700)),
                  content: Text(
                      S.of(context)!.notificationDeleteBody,
                      style: TextStyle(
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, false),
                        child: Text(S.of(context)!.commonCancel,
                            style: TextStyle(
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight))),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(dialogCtx, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                        child: Text(S.of(context)!.commonDelete,
                            style: const TextStyle(fontWeight: FontWeight.w700))),
                  ],
                ),
              ) ??
              false;
        },
        onDismissed: (_) => _deleteNotification(id),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _handleTap(n),
            borderRadius: BorderRadius.circular(18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isRead
                    ? (Brand.surface(isDark))
                    : (isDark
                        ? Brand.darkCardElevated
                        : ntype.color.withAlpha(((0.03) * 255).toInt())),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isRead
                      ? (isDark ? Brand.darkBorder : Brand.borderLight)
                      : ntype.color.withAlpha(((isDark ? 0.2 : 0.15) * 255).toInt()),
                  width: isRead ? 1 : 1.5,
                ),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: (isRead ? Brand.royalBlue : ntype.color)
                              .withAlpha(isRead ? 10 : 20),
                          blurRadius: isRead ? 12 : 16,
                          offset: const Offset(0, 4),
                        )
                      ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon with unread dot
                  Stack(clipBehavior: Clip.none, children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: ntype.color.withAlpha(((isDark ? 0.1 : 0.08) * 255).toInt()),
                        borderRadius: BorderRadius.circular(14),
                        border: isDark
                            ? Border.all(color: ntype.color.withAlpha(((0.12) * 255).toInt()))
                            : null,
                      ),
                      child: Icon(ntype.icon, color: ntype.color, size: 22),
                    ),
                    if (!isRead)
                      Positioned(
                        top: -3,
                        right: -3,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: isDark
                                    ? Brand.darkCardElevated
                                    : Colors.white,
                                width: 2),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(width: 12),
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(title,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isRead
                                        ? FontWeight.w500
                                        : FontWeight.w700,
                                    color: isDark
                                        ? Brand.darkTextPrimary
                                        : Brand.royalBlueDark,
                                    height: 1.3,
                                  )),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              createdAt != null
                                  ? TimeUtils.getTimeAgo(
                                      DateTime.parse(createdAt))
                                  : '',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Brand.darkTextTertiary
                                    : Colors.black38,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        if (message.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight,
                                height: 1.4,
                              )),
                        ],
                        const SizedBox(height: 8),
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: ntype.color
                                  .withAlpha(((isDark ? 0.15 : 0.10) * 255).toInt()),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: ntype.color
                                      .withAlpha(((isDark ? 0.35 : 0.30) * 255).toInt())),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: ntype.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(_typeLabel(type).toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: ntype.color,
                                      letterSpacing: 0.3,
                                    )),
                              ],
                            ),
                          ),
                          const Spacer(),
                          if (!isRead && !isMarking)
                            GestureDetector(
                              onTap: () => _markRead(id),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (isDark
                                          ? Brand.darkIconActive
                                          : Brand.royalBlue)
                                      .withAlpha(((0.08) * 255).toInt()),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: (isDark
                                              ? Brand.darkIconActive
                                              : Brand.royalBlue)
                                          .withAlpha(((0.15) * 255).toInt())),
                                ),
                                child: Text(S.of(context)!.notificationMarkRead,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Brand.darkIconActive
                                          : Brand.royalBlue,
                                    )),
                              ),
                            )
                          else if (isMarking)
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: isDark
                                    ? Brand.darkIconActive
                                    : Brand.royalBlue,
                              ),
                            ),
                          if (hasRelated) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.chevron_right_rounded,
                                size: 16,
                                color: isDark
                                    ? Brand.darkTextTertiary
                                    : Brand.subtleLight.withAlpha(((0.5) * 255).toInt())),
                          ],
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dismissBg(bool isDark) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.red.withAlpha(((isDark ? 0.2 : 0.1) * 255).toInt()),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.red.withAlpha(((isDark ? 0.3 : 0.2) * 255).toInt())),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.delete_outline_rounded,
              color: isDark ? const Color(0xFFFF6B6B) : Colors.red.shade400,
              size: 24),
          const SizedBox(height: 4),
          Text(S.of(context)!.commonDelete,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color:
                      isDark ? const Color(0xFFFF6B6B) : Colors.red.shade400)),
        ]),
      );

  String _typeLabel(String? type) {
    if (type == null) return 'GENERAL';
    return type.replaceAll('_', ' ').toUpperCase();
  }

  // ─── EMPTY STATE ───────────────────────────────────────────
  Widget _buildEmpty(String label, String sublabel, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCard : Brand.royalBlueSurface,
                borderRadius: BorderRadius.circular(24),
                border:
                    isDark ? Border.all(color: Brand.darkBorderLight) : null,
              ),
              child: Icon(
                Icons.notifications_off_outlined,
                size: 38,
                color: isDark ? Brand.darkIconActive : Brand.royalBlue,
              ),
            ),
            const SizedBox(height: 20),
            Text(label,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                )),
            const SizedBox(height: 8),
            Text(sublabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                )),
          ],
        ),
      ),
    );
  }

  // ─── ERROR STATE ───────────────────────────────────────────
  Widget _buildError(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(((isDark ? 0.15 : 0.1) * 255).toInt()),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.error_outline,
                  size: 34,
                  color: isDark ? const Color(0xFFFF6B6B) : Colors.red),
            ),
            const SizedBox(height: 16),
            Text(S.of(context)!.notificationLoadFailed,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                )),
            const SizedBox(height: 8),
            Text(S.of(context)!.notificationPullRetry,
                style: TextStyle(
                    fontSize: 13,
                    color:
                        isDark ? Brand.darkTextSecondary : Brand.subtleLight)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _hasError = false;
                });
                _loadNotifications();
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(S.of(context)!.commonRetry,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isDark ? Brand.darkIconActive : Brand.royalBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── SKELETON LOADER ───────────────────────────────────────
  Widget _buildSkeleton(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      itemCount: 7,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          height: 84,
          decoration: BoxDecoration(
            color: isDark
                ? Brand.darkBorderLight.withAlpha(((0.2) * 255).toInt())
                : Brand.royalBlue.withAlpha(((0.04) * 255).toInt()),
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: isDark
                    ? Brand.darkBorderLight.withAlpha(((0.3) * 255).toInt())
                    : Brand.royalBlue.withAlpha(((0.06) * 255).toInt()),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 12,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Brand.darkBorderLight.withAlpha(((0.3) * 255).toInt())
                          : Brand.royalBlue.withAlpha(((0.06) * 255).toInt()),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 10,
                    width: 180,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Brand.darkBorderLight.withAlpha(((0.2) * 255).toInt())
                          : Brand.royalBlue.withAlpha(((0.04) * 255).toInt()),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Data helper class ────────────────────────────────────────
class _ListItem {
  final String? header;
  final Map<String, dynamic>? notification;

  const _ListItem.header(this.header) : notification = null;
  const _ListItem.notification(this.notification) : header = null;

  bool get isHeader => header != null;
}
