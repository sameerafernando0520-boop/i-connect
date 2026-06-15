// lib/screens/admin/tickets_management_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/supabase_config.dart';

import '../../utils/time_utils.dart';
import '../../utils/string_utils.dart';
import 'admin_ticket_detail_page.dart';

class TicketsManagementPage extends StatefulWidget {
  const TicketsManagementPage({super.key});

  @override
  State<TicketsManagementPage> createState() => _TicketsManagementPageState();
}

class _TicketsManagementPageState extends State<TicketsManagementPage> {
  // ─── State ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _tickets = [];
  List<Map<String, dynamic>> _filteredTickets = [];
  List<Map<String, dynamic>> _engineers = [];
  bool _isLoading = true;

  String _filterStatus = 'all';
  String _filterPriority = 'all';
  String _sortBy = 'default';
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  Timer? _realtimeDebounce;
  StreamSubscription? _realtimeSubscription;

  // Computed summary
  int _totalTickets = 0;
  int _openCount = 0;
  int _assignedCount = 0;
  int _inProgressCount = 0;
  int _waitingCount = 0;
  int _resolvedCount = 0;
  int _closedCount = 0;
  int _activeCount = 0;
  int _urgentCount = 0;
  int _unassignedCount = 0;
  int _escalatedCount = 0;
  int _createdToday = 0;
  int _resolvedToday = 0;
  int _avgResponseMinutes = 0;

  // Selection mode
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  final _scrollController = ScrollController();
  bool _showScrollTop = false;

  // ─── Dark Mode ─────────────────────────────────────────────
  bool _isDark = false;

  Color get _scaffoldBg => Brand.canvas(_isDark);
  Color get _cardBg => Brand.surface(_isDark);
  Color get _textPrimary =>
      _isDark ? Brand.darkTextPrimary : AdminColors.textPrimary;
  Color get _textSecondary =>
      _isDark ? Brand.darkTextSecondary : Colors.grey.shade600;
  Color get _textMuted =>
      _isDark ? Brand.darkTextTertiary : Colors.grey.shade400;
  Color get _borderColor => Brand.cardBorder(_isDark);
  Color get _dividerColor =>
      _isDark ? Brand.darkBorderLight : Colors.grey.shade200;
  Color get _chipBg => _isDark ? Brand.darkCardElevated : Colors.white;
  Color get _sheetBg => _isDark ? Brand.darkCard : Colors.white;
  Color get _handleColor =>
      _isDark ? Brand.darkBorderLight : Colors.grey.shade300;
  Color get _searchFill => _isDark ? Brand.darkCardElevated : Colors.white;
  Color get _primaryColor =>
      _isDark ? Brand.royalBlueGlow : AdminColors.primary;
  Color get _accentColor =>
      _isDark ? Brand.lightGreenBright : AdminColors.accent;
  Color get _elevatedFill =>
      _isDark ? const Color(0xFF22272E) : Colors.grey.shade100;

  List<BoxShadow> get _cardShadow => _isDark
      ? []
      : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ];

  List<BoxShadow> get _softShadow => _isDark
      ? []
      : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ];

  // ─── Lifecycle ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final show = _scrollController.offset > 200;
      if (show != _showScrollTop) setState(() => _showScrollTop = show);
    });
    _loadAll();
    _setupRealtime();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    _realtimeDebounce?.cancel();
    _realtimeSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // ─── REALTIME ──────────────────────────────────────────────
  void _setupRealtime() {
    _realtimeSubscription = SupabaseConfig.client
        .from('service_tickets')
        .stream(primaryKey: ['id']).listen((_) {
      if (!mounted || _isLoading) return;
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(seconds: 1), () {
        if (mounted) _loadAll(silent: true);
      });
    });
  }

  // ─── DATA LOADING ──────────────────────────────────────────
  Future<void> _loadAll({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);


    try {
      final results = await Future.wait<dynamic>([
        _fetchTickets(),
        _fetchEngineers(),
      ]);

      if (!mounted) return;

      setState(() {
        _tickets = results[0];
        _engineers = results[1];
        _computeSummary();
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('Error loading tickets: $e', isError: true);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchTickets() async {
    try {
      final data = await SupabaseConfig.client
          .from('service_tickets')
          .select('''
            *,
            customer:users!service_tickets_user_id_fkey(
              id, full_name, email, company_name, phone_number, profile_photo
            ),
            engineer:users!service_tickets_assigned_to_fkey(
              id, full_name, email, profile_photo
            ),
            customer_machines(
              serial_number,
              machine_catalog(machine_name, brand, model_number, category)
            )
          ''')
          .eq('ticket_type', 'support')
          .eq('is_deleted', false)
          .order('created_at', ascending: false);

      return _processTickets(List<Map<String, dynamic>>.from(data));
    } catch (_) {
      return _fetchTicketsFallback();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchTicketsFallback() async {
    try {
      final data = await SupabaseConfig.client
          .from('service_tickets')
          .select('''
            *,
            customer:users!service_tickets_user_id_fkey(
              id, full_name, email, company_name, phone_number
            ),
            customer_machines(
              serial_number,
              machine_catalog(machine_name, brand, model_number, category)
            )
          ''')
          .eq('ticket_type', 'support')
          .eq('is_deleted', false)
          .order('created_at', ascending: false);

      return _processTickets(List<Map<String, dynamic>>.from(data));
    } catch (_) {
      try {
        final data = await SupabaseConfig.client
            .from('service_tickets')
            .select('*')
            .eq('ticket_type', 'support')
            .eq('is_deleted', false)
            .order('created_at', ascending: false);
        return _processTickets(List<Map<String, dynamic>>.from(data));
      } catch (_) {
        return [];
      }
    }
  }

  List<Map<String, dynamic>> _processTickets(
      List<Map<String, dynamic>> rawList) {
    return rawList.map((t) {
      final customer = t['customer'] as Map<String, dynamic>?;
      final engineer = t['engineer'] as Map<String, dynamic>?;
      final cm = t['customer_machines'] as Map<String, dynamic>?;
      final mc = cm?['machine_catalog'] as Map<String, dynamic>?;
      final metadata = t['metadata'] as Map<String, dynamic>?;
      final createdAt =
          DateTime.tryParse(t['created_at'] ?? '') ?? DateTime.now();
      final now = DateTime.now();

      return {
        ...t,
        'customer_name': customer?['full_name'] ?? 'Unknown',
        'customer_email': customer?['email'] ?? '',
        'customer_company': customer?['company_name'] ?? '',
        'customer_phone': customer?['phone_number'] ?? '',
        'customer_photo': customer?['profile_photo'],
        'assigned_engineer_name': engineer?['full_name'],
        'assigned_engineer_email': engineer?['email'],
        'serial_number': cm?['serial_number'],
        'machine_name': mc?['machine_name'] ?? metadata?['machine_name'],
        'machine_brand': mc?['brand'] ?? '',
        'machine_model': mc?['model_number'] ?? '',
        'machine_category': mc?['category'] ?? '',
        'hours_open': now.difference(createdAt).inHours.toDouble(),
        'days_open': now.difference(createdAt).inDays,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchEngineers() async {
    try {
      final data = await SupabaseConfig.client
          .from('users')
          .select(
              'id, full_name, email, profile_photo, availability_status, specializations')
          .eq('role', 'engineer')
          .order('full_name');
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  // ─── COMPUTE SUMMARY ──────────────────────────────────────
  void _computeSummary() {
    _totalTickets = _tickets.length;
    _openCount = 0;
    _assignedCount = 0;
    _inProgressCount = 0;
    _waitingCount = 0;
    _resolvedCount = 0;
    _closedCount = 0;
    _urgentCount = 0;
    _unassignedCount = 0;
    _escalatedCount = 0;
    _createdToday = 0;
    _resolvedToday = 0;

    int responseTimeSum = 0;
    int responseTimeCount = 0;
    final todayStart =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    for (final t in _tickets) {
      final status = (t['status'] ?? 'open').toString();
      final priority = (t['priority'] ?? 'medium').toString();
      final isActive = status != 'resolved' && status != 'closed';

      switch (status) {
        case 'open':
          _openCount++;
          break;
        case 'assigned':
          _assignedCount++;
          break;
        case 'in_progress':
          _inProgressCount++;
          break;
        case 'waiting_customer':
          _waitingCount++;
          break;
        case 'resolved':
          _resolvedCount++;
          break;
        case 'closed':
          _closedCount++;
          break;
      }

      if (priority == 'urgent' && isActive) _urgentCount++;
      if (t['assigned_to'] == null && isActive) _unassignedCount++;
      if (t['escalated'] == true) _escalatedCount++;

      final createdAt =
          DateTime.tryParse(t['created_at'] ?? '') ?? DateTime.now();
      if (createdAt.isAfter(todayStart)) _createdToday++;

      final closedAt =
          t['closed_at'] != null ? DateTime.tryParse(t['closed_at']) : null;
      if (closedAt != null && closedAt.isAfter(todayStart)) _resolvedToday++;

      if (t['first_response_at'] != null) {
        final firstResponse = DateTime.tryParse(t['first_response_at']);
        if (firstResponse != null) {
          responseTimeSum += firstResponse.difference(createdAt).inMinutes;
          responseTimeCount++;
        }
      }
    }

    _activeCount = _totalTickets - _resolvedCount - _closedCount;
    _avgResponseMinutes =
        responseTimeCount > 0 ? (responseTimeSum ~/ responseTimeCount) : 0;
  }

  // ─── FILTERING & SORTING ──────────────────────────────────
  void _applyFilters() {
    var filtered = List<Map<String, dynamic>>.from(_tickets);

    if (_filterStatus == 'active') {
      filtered = filtered
          .where((t) => t['status'] != 'resolved' && t['status'] != 'closed')
          .toList();
    } else if (_filterStatus == 'unassigned') {
      filtered = filtered
          .where((t) =>
              t['assigned_to'] == null &&
              t['status'] != 'resolved' &&
              t['status'] != 'closed')
          .toList();
    } else if (_filterStatus == 'escalated') {
      filtered = filtered.where((t) => t['escalated'] == true).toList();
    } else if (_filterStatus != 'all') {
      filtered = filtered.where((t) => t['status'] == _filterStatus).toList();
    }

    if (_filterPriority != 'all') {
      filtered =
          filtered.where((t) => t['priority'] == _filterPriority).toList();
    }

    final query = _searchController.text.toLowerCase().trim();
    if (query.isNotEmpty) {
      filtered = filtered.where((t) {
        return [
          t['subject'],
          t['ticket_number'],
          t['customer_name'],
          t['customer_company'],
          t['customer_email'],
          t['machine_name'],
          t['machine_brand'],
          t['category'],
          t['assigned_engineer_name'],
        ].any((f) => f != null && f.toString().toLowerCase().contains(query));
      }).toList();
    }

    switch (_sortBy) {
      case 'newest':
        filtered.sort(
            (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
        break;
      case 'oldest':
        filtered.sort(
            (a, b) => (a['created_at'] ?? '').compareTo(b['created_at'] ?? ''));
        break;
      case 'priority':
        const pOrder = {'urgent': 0, 'high': 1, 'medium': 2, 'low': 3};
        filtered.sort((a, b) => (pOrder[a['priority'] ?? 'medium'] ?? 2)
            .compareTo(pOrder[b['priority'] ?? 'medium'] ?? 2));
        break;
      default:
        break;
    }

    _filteredTickets = filtered;
  }

  // ─── QUICK ACTIONS ─────────────────────────────────────────
  Future<void> _quickUpdateStatus(
      Map<String, dynamic> ticket, String newStatus) async {
    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    HapticFeedback.mediumImpact();

    try {
      final oldStatus = ticket['status'] ?? 'open';
      final updateData = <String, dynamic>{
        'status': newStatus,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (newStatus == 'resolved' || newStatus == 'closed') {
        updateData['closed_at'] = DateTime.now().toUtc().toIso8601String();
      }

      await SupabaseConfig.client
          .from('service_tickets')
          .update(updateData)
          .eq('id', ticket['id']);

      if (!mounted) return;

      await SupabaseConfig.client.from('ticket_activities').insert({
        'ticket_id': ticket['id'],
        'actor_id': currentUserId,
        'actor_type': 'admin',
        'activity_type': 'status_changed',
        'old_value': oldStatus,
        'new_value': newStatus,
        'description': 'Status changed from $oldStatus to $newStatus',
      });

      if (!mounted) return;

      _showSnackBar(
        'Status → ${_formatStatus(newStatus)}',
        icon: _getStatusIcon(newStatus),
        color: _getStatusColor(newStatus),
      );
      await _loadAll(silent: true);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to update: $e', isError: true);
    }
  }

  Future<void> _assignEngineer(
      Map<String, dynamic> ticket, Map<String, dynamic> engineer) async {
    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      await SupabaseConfig.client.from('service_tickets').update({
        'assigned_to': engineer['id'],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', ticket['id']);

      if (!mounted) return;

      await SupabaseConfig.client.from('ticket_activities').insert({
        'ticket_id': ticket['id'],
        'actor_id': currentUserId,
        'actor_type': 'admin',
        'activity_type': 'assigned',
        'new_value': engineer['id'],
        'description': 'Assigned to ${engineer['full_name']}',
      });

      if (!mounted) return;

      _showSnackBar(
        'Assigned to ${engineer['full_name']}',
        icon: Icons.person_add_rounded,
        color: AdminColors.accent,
      );
      await _loadAll(silent: true);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Assignment failed: $e', isError: true);
    }
  }

  Future<void> _bulkUpdateStatus(String newStatus) async {
    if (_selectedIds.isEmpty) return;
    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    final count = _selectedIds.length;
    final confirmed = await _showConfirmSheet(
      icon: _getStatusIcon(newStatus),
      iconColor: _getStatusColor(newStatus),
      title: 'Update $count tickets?',
      message:
          'All selected tickets will be set to "${_formatStatus(newStatus)}".',
      confirmLabel: 'Update All',
      confirmColor: _getStatusColor(newStatus),
    );

    if (confirmed != true || !mounted) return;

    try {
      final updateData = <String, dynamic>{
        'status': newStatus,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (newStatus == 'resolved' || newStatus == 'closed') {
        updateData['closed_at'] = DateTime.now().toUtc().toIso8601String();
      }

      final ids = List<String>.from(_selectedIds);
      for (final id in ids) {
        if (!mounted) return;

        await SupabaseConfig.client
            .from('service_tickets')
            .update(updateData)
            .eq('id', id);

        await SupabaseConfig.client.from('ticket_activities').insert({
          'ticket_id': id,
          'actor_id': currentUserId,
          'actor_type': 'admin',
          'activity_type': 'status_changed',
          'new_value': newStatus,
          'description': 'Bulk status change to $newStatus',
        });
      }

      if (!mounted) return;

      _showSnackBar('$count tickets updated', icon: Icons.check_circle_rounded);
      setState(() {
        _selectedIds.clear();
        _isSelectionMode = false;
      });
      await _loadAll(silent: true);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Bulk update failed: $e', isError: true);
    }
  }

  // ─── DELETE (soft-archive) ─────────────────────────────────
  Future<void> _archiveTicket(Map<String, dynamic> ticket) async {
    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    final confirmed = await _showConfirmSheet(
      icon: Icons.delete_forever_rounded,
      iconColor: AdminColors.error,
      title: 'Delete this ticket?',
      message:
          'Ticket ${ticket['ticket_number'] ?? ''} will be removed from the '
          'lists. It can be restored later if needed.',
      confirmLabel: 'Delete',
      confirmColor: AdminColors.error,
    );
    if (confirmed != true || !mounted) return;

    try {
      await SupabaseConfig.client.from('service_tickets').update({
        'is_deleted': true,
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'deleted_by': currentUserId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', ticket['id']);

      if (!mounted) return;
      setState(() {
        _tickets.removeWhere((t) => t['id'] == ticket['id']);
        _selectedIds.remove(ticket['id']);
        _computeSummary();
        _applyFilters();
      });
      _showSnackBar(
        'Ticket deleted',
        icon: Icons.check_circle_rounded,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          textColor: Colors.white,
          onPressed: () => _restoreTickets([ticket['id'] as String]),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Delete failed: $e', isError: true);
    }
  }

  Future<void> _bulkArchive() async {
    if (_selectedIds.isEmpty) return;
    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    final count = _selectedIds.length;
    final confirmed = await _showConfirmSheet(
      icon: Icons.delete_forever_rounded,
      iconColor: AdminColors.error,
      title: 'Delete $count tickets?',
      message:
          'All selected tickets will be removed from the lists. '
          'They can be restored later if needed.',
      confirmLabel: 'Delete All',
      confirmColor: AdminColors.error,
    );
    if (confirmed != true || !mounted) return;

    try {
      final ids = List<String>.from(_selectedIds);
      await SupabaseConfig.client.from('service_tickets').update({
        'is_deleted': true,
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'deleted_by': currentUserId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).inFilter('id', ids);

      if (!mounted) return;
      _showSnackBar(
        '$count tickets deleted',
        icon: Icons.check_circle_rounded,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          textColor: Colors.white,
          onPressed: () => _restoreTickets(ids),
        ),
      );
      setState(() {
        _selectedIds.clear();
        _isSelectionMode = false;
      });
      await _loadAll(silent: true);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Bulk delete failed: $e', isError: true);
    }
  }

  Future<void> _restoreTickets(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await SupabaseConfig.client.from('service_tickets').update({
        'is_deleted': false,
        'deleted_at': null,
        'deleted_by': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).inFilter('id', ids);
      if (!mounted) return;
      _showSnackBar(ids.length == 1 ? 'Ticket restored' : 'Tickets restored',
          icon: Icons.undo_rounded);
      await _loadAll(silent: true);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Restore failed: $e', isError: true);
    }
  }

  int _getActiveTicketCount(String engineerId) {
    return _tickets.where((t) {
      final s = t['status'] ?? '';
      return t['assigned_to'] == engineerId && s != 'resolved' && s != 'closed';
    }).length;
  }

  // ─── HELPERS ───────────────────────────────────────────────
  int _getFilterCount(String key) {
    switch (key) {
      case 'all':
        return _totalTickets;
      case 'active':
        return _activeCount;
      case 'unassigned':
        return _unassignedCount;
      case 'escalated':
        return _escalatedCount;
      case 'open':
        return _openCount;
      case 'assigned':
        return _assignedCount;
      case 'in_progress':
        return _inProgressCount;
      case 'waiting_customer':
        return _waitingCount;
      case 'resolved':
        return _resolvedCount;
      case 'closed':
        return _closedCount;
      default:
        return 0;
    }
  }

  String _formatStatus(String status) {
    return status.replaceAll('_', ' ').split(' ').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1);
    }).join(' ');
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return AdminColors.warning;
      case 'assigned':
        return AdminColors.info;
      case 'in_progress':
        return AdminColors.primary;
      case 'waiting_customer':
        return AdminColors.internal;
      case 'resolved':
        return AdminColors.accent;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return Icons.fiber_new_rounded;
      case 'assigned':
        return Icons.person_add_alt_1_rounded;
      case 'in_progress':
        return Icons.engineering_rounded;
      case 'waiting_customer':
        return Icons.hourglass_top_rounded;
      case 'resolved':
        return Icons.check_circle_rounded;
      case 'closed':
        return Icons.lock_rounded;
      default:
        return Icons.circle_rounded;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return AdminColors.error;
      case 'high':
        return const Color(0xFFF97316);
      case 'medium':
        return AdminColors.info;
      case 'low':
        return const Color(0xFF22C55E);
      default:
        return Colors.grey;
    }
  }

  IconData _getPriorityIcon(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return Icons.error_rounded;
      case 'high':
        return Icons.warning_rounded;
      case 'medium':
        return Icons.info_rounded;
      case 'low':
        return Icons.check_circle_rounded;
      default:
        return Icons.flag_rounded;
    }
  }

  String _formatDuration(int minutes) {
    if (minutes <= 0) return '0m';
    if (minutes < 60) return '${minutes}m';
    if (minutes < 1440) return '${(minutes / 60).toStringAsFixed(1)}h';
    return '${(minutes / 1440).toStringAsFixed(1)}d';
  }

  void _showSnackBar(String message,
      {bool isError = false,
      IconData? icon,
      Color? color,
      SnackBarAction? action,
      Duration? duration}) {
    if (!mounted) return;

    final effectiveIcon =
        icon ?? (isError ? Icons.error_outline_rounded : null);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (effectiveIcon != null) ...[
              Icon(effectiveIcon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(message,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
          ],
        ),
        action: action,
        backgroundColor:
            isError ? AdminColors.error : color ?? AdminColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
        margin: const EdgeInsets.all(16),
        duration: duration ?? Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  void _navigateTo(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page)).then((_) {
      if (mounted) _loadAll(silent: true);
    });
  }

  Future<bool?> _showConfirmSheet({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _sheetBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: _handleColor,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                  color: iconColor.withAlpha(((_isDark ? 0.15 : 0.1) * 255).toInt()),
                  borderRadius: BorderRadius.circular(Brand.r(18))),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: _textSecondary)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                          border: Border.all(color: _borderColor),
                          borderRadius: BorderRadius.circular(Brand.r(14))),
                      child: Center(
                        child: Text('Cancel',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _textSecondary)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                          color: confirmColor,
                          borderRadius: BorderRadius.circular(Brand.r(14))),
                      child: Center(
                        child: Text(confirmLabel,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    _isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: _scaffoldBg,
      floatingActionButton: _showScrollTop && !_isSelectionMode
          ? FloatingActionButton.small(
              onPressed: () => _scrollController.animateTo(0,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOut),
              backgroundColor: AdminColors.primary,
              child: const Icon(Icons.keyboard_arrow_up_rounded,
                  color: Colors.white),
            )
          : null,
      appBar: _isSelectionMode ? null : DsPageHeader(
        title: 'Support Tickets',
        subtitle: '${_tickets.length} tickets',
        showBack: false,
        accent: HeroAccent.navy,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white), onPressed: _loadAll),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_isSelectionMode) _buildSelectionHeader(),
            Expanded(
              child: _isLoading
                  ? _buildLoadingSkeleton()
                  : RefreshIndicator(
                      onRefresh: _loadAll,
                      color: _accentColor,
                      child: CustomScrollView(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(child: _buildAlertBanner()),
                          SliverToBoxAdapter(child: _buildSearchBar()),
                          SliverToBoxAdapter(child: _buildStatsRow()),
                          SliverToBoxAdapter(child: _buildStatusFilters()),
                          SliverToBoxAdapter(child: _buildResultsHeader()),
                          _filteredTickets.isEmpty
                              ? SliverFillRemaining(child: _buildEmptyState())
                              : SliverPadding(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 4, 20, 20),
                                  sliver: SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) => _buildTicketCard(
                                          _filteredTickets[index]),
                                      childCount: _filteredTickets.length,
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── SELECTION HEADER ──────────────────────────────────────
  Widget _buildSelectionHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      color: AdminColors.primary,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => setState(() {
              _isSelectionMode = false;
              _selectedIds.clear();
            }),
            child:
                const Icon(Icons.close_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Text('${_selectedIds.length} selected',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const Spacer(),
          _buildBulkActionBtn(Icons.play_arrow_rounded, 'In Progress',
              () => _bulkUpdateStatus('in_progress')),
          const SizedBox(width: 6),
          _buildBulkActionBtn(Icons.check_rounded, 'Resolve',
              () => _bulkUpdateStatus('resolved')),
          const SizedBox(width: 6),
          _buildBulkActionBtn(
              Icons.lock_rounded, 'Close', () => _bulkUpdateStatus('closed')),
          const SizedBox(width: 6),
          _buildBulkActionBtn(
              Icons.delete_outline_rounded, 'Delete', _bulkArchive),
        ],
      ),
    );
  }

  Widget _buildBulkActionBtn(
      IconData icon, String tooltip, VoidCallback onTap) {
    return GestureDetector(
      onTap: _selectedIds.isEmpty ? null : onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(38),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  // ─── ALERT BANNER ──────────────────────────────────────────
  Widget _buildAlertBanner() {
    if (_urgentCount == 0 && _unassignedCount == 0 && _escalatedCount == 0) {
      return const SizedBox.shrink();
    }

    final alerts = <Map<String, dynamic>>[];
    if (_urgentCount > 0) {
      alerts.add({
        'icon': Icons.error_rounded,
        'text':
            '$_urgentCount urgent ticket${_urgentCount > 1 ? 's' : ''} need attention',
        'color': AdminColors.error,
        'onTap': () => setState(() {
              _filterPriority = 'urgent';
              _filterStatus = 'active';
              _applyFilters();
            }),
      });
    }
    if (_unassignedCount > 0) {
      alerts.add({
        'icon': Icons.person_off_rounded,
        'text':
            '$_unassignedCount unassigned ticket${_unassignedCount > 1 ? 's' : ''}',
        'color': Colors.orange,
        'onTap': () => setState(() {
              _filterStatus = 'unassigned';
              _applyFilters();
            }),
      });
    }
    if (_escalatedCount > 0) {
      alerts.add({
        'icon': Icons.priority_high_rounded,
        'text':
            '$_escalatedCount escalated ticket${_escalatedCount > 1 ? 's' : ''}',
        'color': Colors.red.shade700,
        'onTap': () => setState(() {
              _filterStatus = 'escalated';
              _applyFilters();
            }),
      });
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      decoration: BoxDecoration(
        color: AdminColors.error.withAlpha(((_isDark ? 0.08 : 0.04) * 255).toInt()),
        borderRadius: BorderRadius.circular(Brand.r(14)),
        border: Border.all(
            color: AdminColors.error.withAlpha(((_isDark ? 0.2 : 0.12) * 255).toInt())),
      ),
      child: Column(
        children: alerts.map((alert) {
          return GestureDetector(
            onTap: alert['onTap'] as VoidCallback,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(alert['icon'] as IconData,
                      size: 18, color: alert['color'] as Color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(alert['text'] as String,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _isDark
                                ? Brand.darkTextPrimary
                                : Colors.red.shade700)),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 12, color: _textMuted),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── SEARCH BAR ────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      decoration: BoxDecoration(
        color: _searchFill,
        borderRadius: BorderRadius.circular(Brand.r(14)),
        border: _isDark ? Border.all(color: _borderColor) : null,
        boxShadow: _softShadow,
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: _textPrimary, fontSize: 14),
        onChanged: (_) {
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 300), () {
            if (mounted) setState(() => _applyFilters());
          });
        },
        decoration: InputDecoration(
          hintText: 'Search subject, ticket #, customer, machine...',
          hintStyle: TextStyle(color: _textMuted, fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded, color: _textMuted, size: 22),
          suffixIcon: _searchController.text.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _applyFilters());
                  },
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: _elevatedFill,
                        borderRadius: BorderRadius.circular(8)),
                    child:
                        Icon(Icons.close_rounded, color: _textMuted, size: 18),
                  ),
                )
              : null,
          filled: true,
          fillColor: _searchFill,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Brand.r(14)),
              borderSide: BorderSide.none),
        ),
      ),
    );
  }

  // ─── STATS ROW ─────────────────────────────────────────────
  Widget _buildStatsRow() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: _isDark ? Border.all(color: _borderColor) : null,
        boxShadow: _cardShadow,
      ),
      child: Row(
        children: [
          _buildStatItem('Open', '$_openCount', AdminColors.warning),
          _buildStatDivider(),
          _buildStatItem(
              'In Progress', '$_inProgressCount', AdminColors.primary),
          _buildStatDivider(),
          _buildStatItem('Resolved', '$_resolvedCount', AdminColors.accent),
          _buildStatDivider(),
          _buildStatItem(
            'Avg Response',
            _avgResponseMinutes > 0
                ? _formatDuration(_avgResponseMinutes)
                : '-',
            AdminColors.info,
          ),
          _buildStatDivider(),
          _buildStatItem(
            'Today',
            '+$_createdToday / ✓$_resolvedToday',
            const Color(0xFF8B5CF6),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: color),
              textAlign: TextAlign.center),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 11, color: _textMuted),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(width: 1, height: 28, color: _dividerColor);
  }

  // ─── STATUS FILTER CHIPS ───────────────────────────────────
  Widget _buildStatusFilters() {
    final filters = [
      {'key': 'all', 'label': 'All', 'icon': Icons.apps_rounded},
      {'key': 'active', 'label': 'Active', 'icon': Icons.pending_rounded},
      {'key': 'open', 'label': 'Open', 'icon': Icons.fiber_new_rounded},
      {
        'key': 'in_progress',
        'label': 'In Progress',
        'icon': Icons.engineering_rounded
      },
      {
        'key': 'waiting_customer',
        'label': 'Waiting',
        'icon': Icons.hourglass_top_rounded
      },
      {
        'key': 'unassigned',
        'label': 'Unassigned',
        'icon': Icons.person_off_rounded
      },
      {
        'key': 'escalated',
        'label': 'Escalated',
        'icon': Icons.priority_high_rounded
      },
      {
        'key': 'resolved',
        'label': 'Resolved',
        'icon': Icons.check_circle_rounded
      },
    ];

    final visible = filters.where((f) {
      final key = f['key'] as String;
      if (key == 'all' || key == _filterStatus) return true;
      return _getFilterCount(key) > 0;
    }).toList();

    return Container(
      height: 50,
      margin: const EdgeInsets.only(top: 14),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: visible.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = visible[index];
          final key = filter['key'] as String;
          final isSelected = _filterStatus == key;
          final color = key == 'all'
              ? _primaryColor
              : key == 'escalated'
                  ? AdminColors.error
                  : key == 'unassigned'
                      ? Colors.orange
                      : _getStatusColor(key);
          final count = _getFilterCount(key);

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _filterStatus = key;
                _applyFilters();
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? color : _chipBg,
                borderRadius: BorderRadius.circular(Brand.r(12)),
                border: Border.all(
                    color: isSelected ? color : _borderColor, width: 1.5),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                            color: color.withAlpha(77),
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ]
                    : _cardShadow,
              ),
              child: Row(
                children: [
                  Icon(filter['icon'] as IconData,
                      size: 14, color: isSelected ? Colors.white : color),
                  const SizedBox(width: 5),
                  Text(filter['label'] as String,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : _textSecondary)),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withAlpha(64)
                            : color.withAlpha(((_isDark ? 0.15 : 0.1) * 255).toInt()),
                        borderRadius: BorderRadius.circular(Brand.r(10))),
                    child: Text('$count',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : color)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── RESULTS HEADER ────────────────────────────────────────
  Widget _buildResultsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        children: [
          Text('${_filteredTickets.length} ',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _primaryColor)),
          Text(
              _filteredTickets.length == _tickets.length
                  ? 'tickets'
                  : 'of ${_tickets.length}',
              style: TextStyle(fontSize: 13, color: _textMuted)),
          const Spacer(),
          GestureDetector(
            onTap: _showSortOptions,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: _chipBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _borderColor)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort_rounded, size: 14, color: _textMuted),
                  const SizedBox(width: 4),
                  Text(_getSortLabel(_sortBy),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _textSecondary)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _showPriorityFilter,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _filterPriority != 'all'
                    ? _getPriorityColor(_filterPriority)
                        .withAlpha(((_isDark ? 0.15 : 0.1) * 255).toInt())
                    : _chipBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: _filterPriority != 'all'
                        ? _getPriorityColor(_filterPriority).withAlpha(77)
                        : _borderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flag_rounded,
                      size: 14,
                      color: _filterPriority != 'all'
                          ? _getPriorityColor(_filterPriority)
                          : _textMuted),
                  const SizedBox(width: 4),
                  Text(
                      _filterPriority != 'all'
                          ? _filterPriority[0].toUpperCase() +
                              _filterPriority.substring(1)
                          : 'Priority',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _filterPriority != 'all'
                              ? _getPriorityColor(_filterPriority)
                              : _textSecondary)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _isSelectionMode = !_isSelectionMode;
                if (!_isSelectionMode) _selectedIds.clear();
              });
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: _isSelectionMode
                      ? _primaryColor.withAlpha(26)
                      : _chipBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _borderColor)),
              child: Icon(Icons.checklist_rounded,
                  size: 16,
                  color: _isSelectionMode ? _primaryColor : _textMuted),
            ),
          ),
          if (_filterStatus != 'all' ||
              _filterPriority != 'all' ||
              _searchController.text.isNotEmpty) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                _searchController.clear();
                setState(() {
                  _filterStatus = 'all';
                  _filterPriority = 'all';
                  _sortBy = 'default';
                  _applyFilters();
                });
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: AdminColors.error.withAlpha(((_isDark ? 0.12 : 0.08) * 255).toInt()),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.close_rounded,
                    size: 14, color: AdminColors.error),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getSortLabel(String sort) {
    switch (sort) {
      case 'newest':
        return 'Newest';
      case 'oldest':
        return 'Oldest';
      case 'priority':
        return 'Priority';
      default:
        return 'Default';
    }
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
            color: _sheetBg,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: _handleColor,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text('Sort By',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor)),
            const SizedBox(height: 12),
            ...['default', 'newest', 'oldest', 'priority'].map((sort) {
              final icons = {
                'default': Icons.auto_awesome_rounded,
                'newest': Icons.arrow_downward_rounded,
                'oldest': Icons.arrow_upward_rounded,
                'priority': Icons.flag_rounded,
              };
              final labels = {
                'default': 'Smart (Priority + Status)',
                'newest': 'Newest First',
                'oldest': 'Oldest First',
                'priority': 'Highest Priority',
              };
              final isSelected = _sortBy == sort;

              return ListTile(
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: isSelected
                          ? _primaryColor.withAlpha(26)
                          : _elevatedFill,
                      borderRadius: BorderRadius.circular(Brand.r(10))),
                  child: Icon(icons[sort],
                      size: 18, color: isSelected ? _primaryColor : _textMuted),
                ),
                title: Text(labels[sort]!,
                    style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? _primaryColor : _textPrimary)),
                trailing: isSelected
                    ? Icon(Icons.check_circle_rounded,
                        color: _accentColor, size: 22)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _sortBy = sort;
                    _applyFilters();
                  });
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showPriorityFilter() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: _sheetBg,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: _handleColor,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text('Filter by Priority',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor)),
            const SizedBox(height: 20),
            _buildPriorityOption(
                ctx, 'all', 'All Priorities', Icons.flag_rounded, Colors.grey),
            _buildPriorityOption(ctx, 'urgent', 'Urgent', Icons.error_rounded,
                AdminColors.error),
            _buildPriorityOption(ctx, 'high', 'High', Icons.warning_rounded,
                const Color(0xFFF97316)),
            _buildPriorityOption(
                ctx, 'medium', 'Medium', Icons.info_rounded, AdminColors.info),
            _buildPriorityOption(ctx, 'low', 'Low', Icons.check_circle_rounded,
                const Color(0xFF22C55E)),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityOption(BuildContext sheetCtx, String value, String label,
      IconData icon, Color color) {
    final isSelected = _filterPriority == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _filterPriority = value;
          _applyFilters();
        });
        Navigator.pop(sheetCtx);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withAlpha(((_isDark ? 0.12 : 0.06) * 255).toInt())
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Brand.r(14)),
          border: isSelected
              ? Border.all(
                  color: color.withAlpha(((_isDark ? 0.3 : 0.2) * 255).toInt()), width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: color.withAlpha(((_isDark ? 0.15 : 0.1) * 255).toInt()),
                  borderRadius: BorderRadius.circular(Brand.r(10))),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? color : _textPrimary)),
            const Spacer(),
            if (isSelected)
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                    color: _accentColor,
                    borderRadius: BorderRadius.circular(7)),
                child: const Icon(Icons.check_rounded,
                    size: 16, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }

  // ─── TICKET CARD ───────────────────────────────────────────
  Widget _buildTicketCard(Map<String, dynamic> ticket) {
    final status = (ticket['status'] ?? 'open').toString();
    final priority = (ticket['priority'] ?? 'medium').toString();
    final statusColor = _getStatusColor(status);
    final priorityColor = _getPriorityColor(priority);
    final customerName = (ticket['customer_name'] ?? 'Unknown').toString();
    final customerCompany = (ticket['customer_company'] ?? '').toString();
    final machineName = ticket['machine_name']?.toString();
    final createdAt =
        DateTime.tryParse(ticket['created_at'] ?? '') ?? DateTime.now();
    final daysOpen = (ticket['days_open'] ?? 0) as int;
    final assignedName = ticket['assigned_engineer_name']?.toString();
    final isEscalated = ticket['escalated'] == true;
    final ticketId = ticket['id'].toString();
    final isSelected = _selectedIds.contains(ticketId);
    final isActive = status != 'resolved' && status != 'closed';

    return GestureDetector(
      onTap: _isSelectionMode
          ? () {
              HapticFeedback.selectionClick();
              setState(() {
                if (isSelected) {
                  _selectedIds.remove(ticketId);
                } else {
                  _selectedIds.add(ticketId);
                }
              });
            }
          : () => _navigateTo(AdminTicketDetailPage(ticketId: ticket['id'])),
      onLongPress: _isSelectionMode ? null : () => _showTicketActions(ticket),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(Brand.r(18)),
          border: isSelected
              ? Border.all(color: _primaryColor, width: 2)
              : isEscalated && isActive
                  ? Border.all(
                      color: AdminColors.error.withAlpha(((_isDark ? 0.4 : 0.3) * 255).toInt()),
                      width: 1.5)
                  : _isDark
                      ? Border.all(color: _borderColor)
                      : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: _primaryColor.withAlpha(20),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ]
              : _cardShadow,
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Priority bar
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: priorityColor,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(Brand.r(18)),
                    bottomLeft: Radius.circular(Brand.r(18)),
                  ),
                ),
              ),
              // Selection checkbox
              if (_isSelectionMode)
                Container(
                  width: 32,
                  alignment: Alignment.center,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isSelected ? _primaryColor : _elevatedFill,
                      borderRadius: BorderRadius.circular(6),
                      border:
                          isSelected ? null : Border.all(color: _borderColor),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 14)
                        : null,
                  ),
                ),
              // Content
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      _isSelectionMode ? 4 : 14, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Tags Row ──
                      Row(
                        children: [
                          _buildStatusChip(status, statusColor),
                          const SizedBox(width: 6),
                          _buildPriorityChip(priority, priorityColor),
                          if (isEscalated && isActive) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                  color: AdminColors.error
                                      .withAlpha(((_isDark ? 0.15 : 0.1) * 255).toInt()),
                                  borderRadius: BorderRadius.circular(Brand.r(10))),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.priority_high_rounded,
                                      size: 10, color: AdminColors.error),
                                  SizedBox(width: 3),
                                  Text('ESC',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: AdminColors.error,
                                          letterSpacing: 0.5)),
                                ],
                              ),
                            ),
                          ],
                          if (daysOpen > 3 && isActive) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                  color: Colors.orange
                                      .withAlpha(((_isDark ? 0.15 : 0.1) * 255).toInt()),
                                  borderRadius: BorderRadius.circular(Brand.r(10))),
                              child: Text('${daysOpen}d',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: Colors.orange.shade700)),
                            ),
                          ],
                          const Spacer(),
                          Text(TimeUtils.getTimeAgo(createdAt),
                              style:
                                  TextStyle(fontSize: 12, color: _textMuted)),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // ── Ticket number ──
                      Text(ticket['ticket_number'] ?? '',
                          style: TextStyle(
                              fontSize: 12,
                              color: _textMuted,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),

                      // ── Subject ──
                      Text(ticket['subject'] ?? 'No Subject',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _textPrimary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 10),

                      // ── Customer + Machine ──
                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [
                                AdminColors.primary
                                    .withAlpha(((_isDark ? 0.15 : 0.08) * 255).toInt()),
                                AdminColors.accent
                                    .withAlpha(((_isDark ? 0.15 : 0.08) * 255).toInt()),
                              ]),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Center(
                                child: Text(
                                    StringUtils.getInitials(customerName),
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: _primaryColor))),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(customerName,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: _textPrimary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                if (customerCompany.isNotEmpty)
                                  Text(customerCompany,
                                      style: TextStyle(
                                          fontSize: 12, color: _textMuted),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          if (machineName != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: _elevatedFill,
                                  borderRadius: BorderRadius.circular(8)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.precision_manufacturing_rounded,
                                      size: 12, color: _textMuted),
                                  const SizedBox(width: 4),
                                  ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 80),
                                    child: Text(machineName,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: _textSecondary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),

                      // ── Bottom info ──
                      if (assignedName != null ||
                          (isActive && ticket['assigned_to'] == null)) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            if (assignedName != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                    color: AdminColors.primary
                                        .withAlpha(((_isDark ? 0.1 : 0.06) * 255).toInt()),
                                    borderRadius: BorderRadius.circular(Brand.r(10))),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.engineering_rounded,
                                        size: 12, color: _primaryColor),
                                    const SizedBox(width: 4),
                                    Text(assignedName,
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: _primaryColor)),
                                  ],
                                ),
                              )
                            else if (isActive)
                              GestureDetector(
                                onTap: () => _showAssignEngineerSheet(ticket),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                      color: Colors.orange
                                          .withAlpha(((_isDark ? 0.12 : 0.08) * 255).toInt()),
                                      borderRadius: BorderRadius.circular(Brand.r(10)),
                                      border: Border.all(
                                          color:
                                              Colors.orange.withAlpha(38))),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.person_add_rounded,
                                          size: 12,
                                          color: Colors.orange.shade700),
                                      const SizedBox(width: 4),
                                      Text('Assign',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.orange.shade700)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],

                      // ── Quick advance ──
                      if (isActive && !_isSelectionMode) ...[
                        const SizedBox(height: 10),
                        _buildQuickStatusRow(ticket, status),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withAlpha(((_isDark ? 0.15 : 0.1) * 255).toInt()),
          borderRadius: BorderRadius.circular(Brand.r(10))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_getStatusIcon(status), size: 10, color: color),
          const SizedBox(width: 3),
          Text(status.toUpperCase().replaceAll('_', ' '),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildPriorityChip(String priority, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withAlpha(((_isDark ? 0.15 : 0.1) * 255).toInt()),
          borderRadius: BorderRadius.circular(Brand.r(10))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_getPriorityIcon(priority), size: 10, color: color),
          const SizedBox(width: 3),
          Text(priority.toUpperCase(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }

  // ─── QUICK STATUS BUTTONS ──────────────────────────────────
  Widget _buildQuickStatusRow(
      Map<String, dynamic> ticket, String currentStatus) {
    final nextStatuses = <String>[];
    switch (currentStatus) {
      case 'open':
        nextStatuses.addAll(['in_progress']);
        break;
      case 'assigned':
        nextStatuses.addAll(['in_progress']);
        break;
      case 'in_progress':
        nextStatuses.addAll(['waiting_customer', 'resolved']);
        break;
      case 'waiting_customer':
        nextStatuses.addAll(['in_progress', 'resolved']);
        break;
    }

    if (nextStatuses.isEmpty) return const SizedBox.shrink();

    return Row(
      children: nextStatuses.map((ns) {
        final color = _getStatusColor(ns);
        return Expanded(
          child: GestureDetector(
            onTap: () => _quickUpdateStatus(ticket, ns),
            child: Container(
              margin: EdgeInsets.only(right: ns != nextStatuses.last ? 6 : 0),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: color.withAlpha(((_isDark ? 0.1 : 0.06) * 255).toInt()),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: color.withAlpha(((_isDark ? 0.2 : 0.15) * 255).toInt())),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_getStatusIcon(ns), size: 12, color: color),
                  const SizedBox(width: 4),
                  Text(_formatStatus(ns),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── TICKET ACTIONS SHEET ──────────────────────────────────
  void _showTicketActions(Map<String, dynamic> ticket) {
    HapticFeedback.mediumImpact();
    final status = (ticket['status'] ?? 'open').toString();
    final isActive = status != 'resolved' && status != 'closed';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
            color: _sheetBg,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: _handleColor,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text(ticket['ticket_number'] ?? '',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor)),
            const SizedBox(height: 16),
            if (isActive)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    'open',
                    'assigned',
                    'in_progress',
                    'waiting_customer',
                    'resolved',
                    'closed'
                  ].map((s) {
                    final isCurrent = status == s;
                    final color = _getStatusColor(s);
                    return GestureDetector(
                      onTap: isCurrent
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              _quickUpdateStatus(ticket, s);
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? color
                              : color.withAlpha(((_isDark ? 0.12 : 0.1) * 255).toInt()),
                          borderRadius: BorderRadius.circular(Brand.r(10)),
                          border: Border.all(
                              color: color.withAlpha(((_isDark ? 0.3 : 0.25) * 255).toInt())),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_getStatusIcon(s),
                                size: 14,
                                color: isCurrent ? Colors.white : color),
                            const SizedBox(width: 6),
                            Text(_formatStatus(s),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isCurrent ? Colors.white : color)),
                            if (isCurrent) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.check_rounded,
                                  size: 14, color: Colors.white),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            Divider(height: 24, color: _dividerColor),
            if (isActive)
              _buildActionTile(
                Icons.person_add_rounded,
                'Assign Engineer',
                'Select an engineer for this ticket',
                AdminColors.primary,
                () {
                  Navigator.pop(ctx);
                  _showAssignEngineerSheet(ticket);
                },
              ),
            _buildActionTile(
              Icons.open_in_new_rounded,
              'View Details',
              'Full ticket details and chat',
              AdminColors.info,
              () {
                Navigator.pop(ctx);
                _navigateTo(AdminTicketDetailPage(ticketId: ticket['id']));
              },
            ),
            _buildActionTile(
              Icons.delete_outline_rounded,
              'Delete Ticket',
              'Remove from lists (recoverable)',
              AdminColors.error,
              () {
                Navigator.pop(ctx);
                _archiveTicket(ticket);
              },
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile(IconData icon, String title, String subtitle,
      Color color, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: color.withAlpha(((_isDark ? 0.15 : 0.1) * 255).toInt()),
            borderRadius: BorderRadius.circular(Brand.r(12))),
        child: Icon(icon, size: 20, color: color),
      ),
      title: Text(title,
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: _textPrimary)),
      subtitle:
          Text(subtitle, style: TextStyle(fontSize: 12, color: _textMuted)),
      trailing:
          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: _textMuted),
      onTap: onTap,
    );
  }

  // ─── ASSIGN ENGINEER SHEET ─────────────────────────────────
  void _showAssignEngineerSheet(Map<String, dynamic> ticket) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.6,
        ),
        decoration: BoxDecoration(
            color: _sheetBg,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: _handleColor,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text('Assign Engineer',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor)),
            const SizedBox(height: 4),
            Text('Ticket: ${ticket['ticket_number']}',
                style: TextStyle(fontSize: 12, color: _textMuted)),
            const SizedBox(height: 16),
            if (_engineers.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text('No engineers available',
                    style: TextStyle(color: _textMuted)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _engineers.length,
                  itemBuilder: (context, index) {
                    final eng = _engineers[index];
                    final activeCount =
                        _getActiveTicketCount(eng['id'].toString());
                    final isAssigned = ticket['assigned_to'] == eng['id'];
                    final availability =
                        eng['availability_status'] ?? 'available';
                    final isBusy = availability == 'busy';
                    final specializations =
                        (eng['specializations'] as List?)?.cast<String>() ?? [];

                    return ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isAssigned
                              ? AdminColors.accent
                                  .withAlpha(((_isDark ? 0.15 : 0.1) * 255).toInt())
                              : AdminColors.primary
                                  .withAlpha(((_isDark ? 0.12 : 0.08) * 255).toInt()),
                          borderRadius: BorderRadius.circular(Brand.r(12)),
                        ),
                        child: Center(
                          child: Text(
                            StringUtils.getInitials(eng['full_name'] ?? ''),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isAssigned ? _accentColor : _primaryColor,
                            ),
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(eng['full_name'] ?? '',
                                style: TextStyle(
                                    fontWeight: isAssigned
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    color: _textPrimary),
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (isBusy) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.orange
                                      .withAlpha(((_isDark ? 0.15 : 0.1) * 255).toInt()),
                                  borderRadius: BorderRadius.circular(4)),
                              child: Text('Busy',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange.shade700)),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$activeCount active tickets',
                            style: TextStyle(
                                fontSize: 12,
                                color: activeCount > 5
                                    ? Colors.orange
                                    : _textMuted),
                          ),
                          if (specializations.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                specializations.take(3).join(', '),
                                style:
                                    TextStyle(fontSize: 12, color: _textMuted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                      trailing: isAssigned
                          ? Icon(Icons.check_circle_rounded,
                              color: _accentColor, size: 22)
                          : Icon(Icons.arrow_forward_ios_rounded,
                              size: 14, color: _textMuted),
                      onTap: isAssigned
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              _assignEngineer(ticket, eng);
                            },
                    );
                  },
                ),
              ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  // ─── LOADING SKELETON ──────────────────────────────────────
  Widget _buildLoadingSkeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      children: [
        // Alert skeleton
        Container(
          height: 50,
          decoration: BoxDecoration(
            color: _isDark
                ? AdminColors.error.withAlpha(15)
                : Colors.red.shade50,
            borderRadius: BorderRadius.circular(Brand.r(14)),
          ),
        ),
        const SizedBox(height: 14),
        // Search skeleton
        Container(
          height: 50,
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(Brand.r(14)),
            border: _isDark ? Border.all(color: _borderColor) : null,
          ),
        ),
        const SizedBox(height: 14),
        // Stats row skeleton
        Container(
          height: 64,
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(Brand.r(16)),
            border: _isDark ? Border.all(color: _borderColor) : null,
          ),
        ),
        const SizedBox(height: 14),
        // Filter chips skeleton
        SizedBox(
          height: 42,
          child: Row(
            children: List.generate(
              4,
              (i) => Container(
                width: 80,
                height: 36,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color:
                      _isDark ? Brand.darkCardElevated : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(Brand.r(12)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Card skeletons
        ...List.generate(
          4,
          (i) => Container(
            height: 180,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(Brand.r(18)),
              border: _isDark ? Border.all(color: _borderColor) : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: [
                      AdminColors.error,
                      AdminColors.warning,
                      AdminColors.info,
                      AdminColors.accent,
                    ][i]
                        .withAlpha(77),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(Brand.r(18)),
                      bottomLeft: Radius.circular(Brand.r(18)),
                    ),
                  ),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── EMPTY STATE ───────────────────────────────────────────
  Widget _buildEmptyState() {
    final hasFilters = _filterStatus != 'all' ||
        _filterPriority != 'all' ||
        _searchController.text.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                  color: _primaryColor.withAlpha(((_isDark ? 0.1 : 0.06) * 255).toInt()),
                  borderRadius: BorderRadius.circular(Brand.r(24))),
              child: Icon(
                  hasFilters
                      ? Icons.filter_alt_off_rounded
                      : Icons.inbox_rounded,
                  size: 40,
                  color: _textMuted),
            ),
            const SizedBox(height: 20),
            Text(hasFilters ? 'No matching tickets' : 'No tickets yet',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: _textSecondary)),
            const SizedBox(height: 8),
            Text(
                hasFilters
                    ? 'Try adjusting your filters or search'
                    : 'Support tickets will appear here when customers submit them',
                style: TextStyle(fontSize: 13, color: _textMuted),
                textAlign: TextAlign.center),
            if (hasFilters) ...[
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() {
                    _filterStatus = 'all';
                    _filterPriority = 'all';
                    _sortBy = 'default';
                    _applyFilters();
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                      color: _accentColor.withAlpha(((_isDark ? 0.15 : 0.1) * 255).toInt()),
                      borderRadius: BorderRadius.circular(Brand.r(12))),
                  child: Text('Clear All Filters',
                      style: TextStyle(
                          color: _accentColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
