// lib/repositories/admin_dashboard_repository.dart

import 'package:flutter/foundation.dart';
import '../config/supabase_config.dart';
import '../models/dashboard_stats.dart';
import '../services/safe_network.dart';

class AdminDashboardRepository {
  // Cache with TTL
  DashboardStats? _cachedStats;
  List<RecentInquiry>? _cachedInquiries;
  List<RecentCustomer>? _cachedCustomers;
  DateTime? _lastFetch;

  static const _cacheDuration = Duration(minutes: 2);

  // Tracks every live instance so mutation-site code can invalidate
  // all active dashboard caches after a write (see [invalidate]).
  static final Set<AdminDashboardRepository> _instances =
      <AdminDashboardRepository>{};

  AdminDashboardRepository() {
    _instances.add(this);
  }

  /// Call from any code path that mutates tickets/customers/etc. so the
  /// next fetch refreshes from the DB instead of returning stale cache.
  /// Safe to call from anywhere; idempotent.
  static void invalidate() {
    for (final repo in _instances) {
      repo.clearCache();
    }
  }

  bool get _isCacheValid =>
      _lastFetch != null &&
      DateTime.now().difference(_lastFetch!) < _cacheDuration;

  /// Get admin user name
  Future<String> getAdminName() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return 'Admin';

    try {
      // maybeSingle() returns null for 0 rows instead of throwing; protects
      // against RLS-filtered or freshly-deleted users crashing the screen.
      final data = await SupabaseConfig.client
          .from('users')
          .select('full_name')
          .eq('id', userId)
          .maybeSingle();
      if (data == null) return 'Admin';
      return (data['full_name'] as String?) ?? 'Admin';
    } catch (e) {
      debugPrint('⚠️ getAdminName failed: $e');
      return 'Admin';
    }
  }

  /// Fetch dashboard stats - tries RPC first, falls back to individual queries
  /// Uses SafeNetwork for offline support with automatic cache + connectivity toggle
  Future<DashboardStats> fetchStats({bool forceRefresh = false}) async {
    if (!forceRefresh && _isCacheValid && _cachedStats != null) {
      return _cachedStats!;
    }

    try {
      final result = await SafeNetwork.read<DashboardStats>(
        cacheKey: 'dashboard_stats',
        fetch: () async {
          // Try optimized RPC call first
          final rpcResult =
              await SupabaseConfig.client.rpc('get_admin_dashboard_stats');
          if (rpcResult is Map<String, dynamic>) {
            return DashboardStats.fromRpc(rpcResult);
          } else {
            debugPrint(
                '⚠️ RPC get_admin_dashboard_stats returned unexpected type: ${rpcResult.runtimeType} — falling back to manual queries');
            return await _fetchStatsManually();
          }
        },
      );
      _cachedStats = result;
      _lastFetch = DateTime.now();
      return _cachedStats ?? DashboardStats.empty;
    } catch (e) {
      debugPrint('⚠️ fetchStats failed: $e');
      // SafeNetwork already marked offline if needed; return empty stats
      return DashboardStats.empty;
    }
  }

  Future<DashboardStats> _fetchStatsManually() async {
    // Run all queries in parallel
    final results = await Future.wait<dynamic>([
      SupabaseConfig.client
          .from('machine_catalog')
          .select('id')
          .eq('is_active', true),
      SupabaseConfig.client
          .from('users')
          .select('id, created_at')
          .eq('role', 'customer'),
      SupabaseConfig.client
          .from('service_tickets')
          .select('id, priority')
          .inFilter('status',
              ['open', 'assigned', 'in_progress', 'waiting_customer'])
          .eq('is_deleted', false),
      SupabaseConfig.client
          .from('service_tickets')
          .select('id')
          .inFilter('status', ['resolved', 'closed'])
          .eq('is_deleted', false),
      SupabaseConfig.client
          .from('service_tickets')
          .select('id, status')
          .eq('ticket_type', 'inquiry')
          .eq('is_deleted', false),
      SupabaseConfig.client
          .from('service_tickets')
          .select('id')
          .eq('ticket_type', 'order')
          .eq('is_deleted', false),
    ]);

    // H3: safe unpacking — if any query returned an unexpected type
    // (error shape, null, etc.), fall back to [] instead of a hard cast
    // crash that would blow up the entire dashboard.
    List asList(dynamic v) => v is List ? v : const [];
    final machines = asList(results[0]);
    final customers = asList(results[1]);
    final openTickets = asList(results[2]);
    final resolved = asList(results[3]);
    final inquiries = asList(results[4]);
    final orders = asList(results[5]);

    // Compare in UTC to stay consistent with the DB's `created_at` values,
    // which are stored in UTC (ISO 8601 with `Z`).
    final nowUtc = DateTime.now().toUtc();
    final monthStartUtc = DateTime.utc(nowUtc.year, nowUtc.month, 1);

    final newThisMonth = customers.where((c) {
      try {
        final createdRaw = c is Map ? c['created_at'] : null;
        if (createdRaw == null) return false;
        return DateTime.parse(createdRaw.toString())
            .toUtc()
            .isAfter(monthStartUtc);
      } catch (_) {
        return false;
      }
    }).length;

    final urgent = openTickets.where((t) => t['priority'] == 'urgent').length;

    final pendingInq = inquiries
        .where((i) => i['status'] == 'open' || i['status'] == 'assigned')
        .length;

    return DashboardStats(
      totalMachines: machines.length,
      totalCustomers: customers.length,
      openTickets: openTickets.length,
      totalInquiries: inquiries.length,
      resolvedTickets: resolved.length,
      newCustomersThisMonth: newThisMonth,
      urgentTickets: urgent,
      pendingInquiries: pendingInq,
      totalOrders: orders.length,
    );
  }

  /// Fetch recent inquiries
  /// Uses SafeNetwork for offline support with automatic cache + connectivity toggle
  Future<List<RecentInquiry>> fetchRecentInquiries({
    bool forceRefresh = false,
    int limit = 5,
  }) async {
    if (!forceRefresh && _isCacheValid && _cachedInquiries != null) {
      return _cachedInquiries!;
    }

    try {
      final result = await SafeNetwork.read<List<RecentInquiry>>(
        cacheKey: 'recent_inquiries:$limit',
        fetch: () async {
          final data = await SupabaseConfig.client
              .from('service_tickets')
              .select('''
                *,
                users!service_tickets_user_id_fkey(full_name, company_name, email),
                machine_catalog!service_tickets_catalog_machine_id_fkey(machine_name, brand)
              ''')
              .eq('ticket_type', 'inquiry')
              .eq('is_deleted', false)
              .order('created_at', ascending: false)
              .limit(limit);

          return (data as List)
              .map((e) => RecentInquiry.fromJson(e as Map<String, dynamic>))
              .toList();
        },
      );
      _cachedInquiries = result;
      _lastFetch = DateTime.now();
      return _cachedInquiries ?? [];
    } catch (e) {
      debugPrint('⚠️ fetchRecentInquiries failed: $e');
      return [];
    }
  }

  /// Fetch recent customers
  /// Uses SafeNetwork for offline support with automatic cache + connectivity toggle
  Future<List<RecentCustomer>> fetchRecentCustomers({
    bool forceRefresh = false,
    int limit = 5,
  }) async {
    if (!forceRefresh && _isCacheValid && _cachedCustomers != null) {
      return _cachedCustomers!;
    }

    try {
      final result = await SafeNetwork.read<List<RecentCustomer>>(
        cacheKey: 'recent_customers:$limit',
        fetch: () async {
          // H2: explicit column list — avoids leaking password hashes, internal
          // flags, or other sensitive columns even if RLS is misconfigured.
          final data = await SupabaseConfig.client
              .from('users')
              .select(
                  'id, full_name, email, company_name, phone_number, city, profile_photo, created_at')
              .eq('role', 'customer')
              .order('created_at', ascending: false)
              .limit(limit);

          return (data as List)
              .map((e) => RecentCustomer.fromJson(e as Map<String, dynamic>))
              .toList();
        },
      );
      _cachedCustomers = result;
      _lastFetch = DateTime.now();
      return _cachedCustomers ?? [];
    } catch (e) {
      debugPrint('⚠️ fetchRecentCustomers failed: $e');
      return [];
    }
  }

  /// Clear all cache
  void clearCache() {
    _cachedStats = null;
    _cachedInquiries = null;
    _cachedCustomers = null;
    _lastFetch = null;
  }

  /// Fetch unread notification count for badge
  /// Uses SafeNetwork for offline support with automatic cache + connectivity toggle
  Future<int> fetchUnreadNotificationCount() async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return 0;

      final result = await SafeNetwork.read<int>(
        cacheKey: 'unread_notifications:$userId',
        fetch: () async {
          final data = await SupabaseConfig.client
              .from('notifications')
              .select('id')
              .eq('user_id', userId)
              .eq('is_read', false);

          return (data as List).length;
        },
      );
      return result ?? 0;
    } catch (e) {
      debugPrint('⚠️ fetchUnreadNotificationCount failed: $e');
      return 0;
    }
  }
}
