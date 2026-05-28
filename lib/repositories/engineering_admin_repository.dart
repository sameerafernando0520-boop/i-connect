// lib/repositories/engineering_admin_repository.dart
// Engineering Admin Repository — dashboard stats, engineer list, ticket list queries

import 'package:flutter/foundation.dart';
import '../config/supabase_config.dart';

class EngineeringAdminRepository {
  // ─────────────────────────────────────────────
  // DASHBOARD STATS
  // ─────────────────────────────────────────────

  /// Returns KPI values for the dashboard tiles.
  Future<Map<String, int>> getDashboardStats() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final results = await Future.wait<dynamic>([
      // 1. Engineers present today
      SupabaseConfig.client
          .from('engineer_attendance')
          .select('id')
          .eq('date', today)
          .inFilter('status', ['present', 'late', 'half_day']),

      // 2. Unassigned active tickets
      SupabaseConfig.client
          .from('service_tickets')
          .select('id')
          .inFilter('status', ['new', 'open'])
          .isFilter('assigned_to', null)
          .eq('is_deleted', false),

      // 3. Jobs in progress right now
      SupabaseConfig.client
          .from('job_records')
          .select('id')
          .eq('job_status', 'in_progress'),

      // 4. Pending leave requests
      SupabaseConfig.client
          .from('engineer_leaves')
          .select('id')
          .eq('status', 'pending'),

      // 5. Active machine installations (scheduled or in progress)
      SupabaseConfig.client
          .from('machine_installations')
          .select('id')
          .inFilter('status', ['scheduled', 'in_progress']),
    ]);

    return {
      'present_today': (results[0] as List).length,
      'unassigned_tickets': (results[1] as List).length,
      'jobs_in_progress': (results[2] as List).length,
      'pending_leaves': (results[3] as List).length,
      'active_installations': (results[4] as List).length,
    };
  }

  // ─────────────────────────────────────────────
  // TODAY'S DISPATCH STATUS
  // ─────────────────────────────────────────────

  /// Active/recent tickets for today's dispatch status list.
  Future<List<Map<String, dynamic>>> getTodaysTickets() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final res = await SupabaseConfig.client
        .from('service_tickets')
        .select('''
          id, ticket_number, subject, status, priority,
          created_at, updated_at,
          customer:users!user_id(id, full_name, email),
          engineer:users!assigned_to(id, full_name, profile_photo)
        ''')
        .inFilter('status', ['new', 'open', 'assigned', 'in_progress', 'waiting_customer'])
        .gte('created_at', '${today}T00:00:00Z')
        .eq('is_deleted', false)
        .order('created_at', ascending: false)
        .limit(50);

    return List<Map<String, dynamic>>.from(res);
  }

  // ─────────────────────────────────────────────
  // ENGINEER AVAILABILITY STRIP
  // ─────────────────────────────────────────────

  /// Returns all engineers with today's attendance status for the avatar strip.
  Future<List<Map<String, dynamic>>> getEngineerAvailabilityToday() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // Get all engineers
    final engineers = await SupabaseConfig.client
        .from('users')
        .select('id, full_name, profile_photo, assigned_zone')
        .eq('role', 'engineer')
        .filter('date_terminated', 'is', null)
        .order('full_name');

    if (engineers.isEmpty) return [];

    final engineerIds = (engineers as List).map((e) => e['id'] as String).toList();

    // Get today's attendance for all engineers
    final attendance = await SupabaseConfig.client
        .from('engineer_attendance')
        .select('engineer_id, status, check_in_time, check_out_time')
        .eq('date', today)
        .inFilter('engineer_id', engineerIds);

    // Get active job counts for today
    final jobCounts = await SupabaseConfig.client
        .from('job_records')
        .select('engineer_id')
        .eq('job_date', today)
        .inFilter('job_status', ['in_progress', 'pending'])
        .inFilter('engineer_id', engineerIds);

    // Build lookup maps
    final attendanceMap = <String, Map<String, dynamic>>{};
    for (final a in (attendance as List)) {
      attendanceMap[a['engineer_id'] as String] = Map<String, dynamic>.from(a);
    }

    final jobCountMap = <String, int>{};
    for (final j in (jobCounts as List)) {
      final eid = j['engineer_id'] as String;
      jobCountMap[eid] = (jobCountMap[eid] ?? 0) + 1;
    }

    return engineers.map<Map<String, dynamic>>((e) {
      final eid = e['id'] as String;
      final att = attendanceMap[eid];
      return {
        ...Map<String, dynamic>.from(e as Map),
        'attendance_status': att?['status'] ?? 'absent',
        'check_in_time': att?['check_in_time'],
        'check_out_time': att?['check_out_time'],
        'active_jobs_today': jobCountMap[eid] ?? 0,
      };
    }).toList();
  }

  // ─────────────────────────────────────────────
  // RECENT ACTIVITY FEED
  // ─────────────────────────────────────────────

  /// Combines recent events from multiple tables into a chronological feed.
  Future<List<Map<String, dynamic>>> getRecentActivity({int limit = 20}) async {
    final since = DateTime.now().subtract(const Duration(hours: 24));
    final sinceStr = since.toIso8601String();

    final results = await Future.wait<dynamic>([
      // Recent machine installation updates
      SupabaseConfig.client
          .from('machine_installations')
          .select('''
            id, location, status, updated_at,
            customer:users!customer_id(id, full_name)
          ''')
          .inFilter('status', ['scheduled', 'in_progress', 'completed'])
          .gte('updated_at', sinceStr)
          .order('updated_at', ascending: false)
          .limit(10),

      // Engineer attendance check-ins today
      SupabaseConfig.client
          .from('engineer_attendance')
          .select('''
            id, status, check_in_time, date,
            engineer:users!engineer_id(id, full_name)
          ''')
          .gte('check_in_time', sinceStr)
          .not('check_in_time', 'is', null)
          .order('check_in_time', ascending: false)
          .limit(10),

      // New/updated tickets
      SupabaseConfig.client
          .from('service_tickets')
          .select('id, ticket_number, subject, status, created_at, updated_at')
          .gte('created_at', sinceStr)
          .eq('is_deleted', false)
          .order('created_at', ascending: false)
          .limit(10),
    ]);

    // Flatten + tag each event
    final List<Map<String, dynamic>> feed = [];

    for (final inst in (results[0] as List)) {
      final m = Map<String, dynamic>.from(inst as Map);
      m['event_type'] = 'installation_updated';
      m['event_time'] = m['updated_at'];
      feed.add(m);
    }

    for (final att in (results[1] as List)) {
      final m = Map<String, dynamic>.from(att as Map);
      m['event_type'] = 'checkin';
      m['event_time'] = m['check_in_time'];
      feed.add(m);
    }

    for (final ticket in (results[2] as List)) {
      final m = Map<String, dynamic>.from(ticket as Map);
      m['event_type'] = 'ticket_new';
      m['event_time'] = m['created_at'];
      feed.add(m);
    }

    // Sort by event_time descending
    feed.sort((a, b) {
      final ta = DateTime.tryParse(a['event_time'] as String? ?? '') ?? DateTime(2000);
      final tb = DateTime.tryParse(b['event_time'] as String? ?? '') ?? DateTime(2000);
      return tb.compareTo(ta);
    });

    return feed.take(limit).toList();
  }

  // ─────────────────────────────────────────────
  // ALERTS
  // ─────────────────────────────────────────────

  /// Returns current alerts for the EA dashboard.
  Future<List<Map<String, dynamic>>> getAlerts() async {
    final alerts = <Map<String, dynamic>>[];
    final today = DateTime.now().toIso8601String().substring(0, 10);

    try {
      final results = await Future.wait<dynamic>([
        // Urgent unassigned service tickets
        SupabaseConfig.client
            .from('service_tickets')
            .select('id, ticket_number, subject, status, priority, created_at')
            .inFilter('status', ['new', 'open'])
            .filter('assigned_to', 'is', null)
            .inFilter('priority', ['urgent', 'high'])
            .eq('is_deleted', false)
            .order('created_at', ascending: true)
            .limit(10),

        // Active engineers not yet checked in today
        SupabaseConfig.client
            .from('users')
            .select('id, full_name')
            .eq('role', 'engineer')
            .filter('date_terminated', 'is', null),

        // Pending machine installations past scheduled date
        SupabaseConfig.client
            .from('machine_installations')
            .select('id, location, scheduled_date, customer:users!customer_id(id, full_name)')
            .inFilter('status', ['pending', 'scheduled'])
            .lte('scheduled_date', today)
            .order('scheduled_date', ascending: true)
            .limit(10),
      ]);

      // Urgent unassigned tickets
      for (final ticket in (results[0] as List)) {
        alerts.add({
          'type': 'urgent_unassigned',
          'title': 'Urgent ticket needs assignment',
          'subtitle': 'Ticket ${ticket['ticket_number'] ?? ''}: ${ticket['subject'] ?? ''}',
          'ticket_id': ticket['id'],
          'priority': ticket['priority'],
          'severity': ticket['priority'] == 'urgent' ? 'high' : 'medium',
        });
      }

      // Not checked in (compare against today's attendance)
      final attendance = await SupabaseConfig.client
          .from('engineer_attendance')
          .select('engineer_id')
          .eq('date', today)
          .not('check_in_time', 'is', null);

      final checkedIn = Set<String>.from(
          (attendance as List).map((a) => a['engineer_id'] as String));
      final allEngineers = results[1] as List;
      final notCheckedIn = allEngineers
          .where((e) => !checkedIn.contains(e['id'] as String))
          .toList();

      if (notCheckedIn.isNotEmpty) {
        final hour = DateTime.now().hour;
        if (hour >= 9) {
          // Only alert after 9 AM
          alerts.add({
            'type': 'not_checked_in',
            'title': '${notCheckedIn.length} engineer${notCheckedIn.length == 1 ? '' : 's'} not yet checked in',
            'subtitle': notCheckedIn.take(3).map((e) => e['full_name']).join(', ') +
                (notCheckedIn.length > 3 ? ' +${notCheckedIn.length - 3} more' : ''),
            'severity': 'medium',
          });
        }
      }

      // Overdue installations
      for (final inst in (results[2] as List)) {
        final scheduledDate = inst['scheduled_date'] as String?;
        if (scheduledDate != null) {
          final daysOverdue = DateTime.now().difference(DateTime.parse(scheduledDate)).inDays;
          final customer = inst['customer'];
          alerts.add({
            'type': 'overdue_installation',
            'title': 'Installation overdue by $daysOverdue day${daysOverdue == 1 ? '' : 's'}',
            'subtitle': '${inst['location'] ?? 'Installation'} — ${customer?['full_name'] ?? 'Unknown customer'}',
            'installation_id': inst['id'],
            'severity': daysOverdue > 3 ? 'high' : 'medium',
          });
        }
      }
    } catch (e) {
      debugPrint('EngineeringAdminRepository.getAlerts error: $e');
    }

    return alerts;
  }

  // ─────────────────────────────────────────────
  // ENGINEER LIST
  // ─────────────────────────────────────────────

  /// Full engineer list with today's status and active job count.
  Future<List<Map<String, dynamic>>> getEngineerList({
    String? search,
    String? zone,
    String? employmentType,
  }) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);

    var query = SupabaseConfig.client
        .from('users')
        .select('''
          id, full_name, email, profile_photo, phone_number,
          employee_id, department, assigned_zone,
          employment_type, date_joined, date_terminated,
          avg_rating
        ''')
        .eq('role', 'engineer');

    if (zone != null && zone.isNotEmpty) {
      query = query.eq('assigned_zone', zone);
    }
    if (employmentType != null && employmentType.isNotEmpty) {
      query = query.eq('employment_type', employmentType);
    }

    final engineers = await query.order('full_name');

    if ((engineers as List).isEmpty) return [];

    final engineerIds = engineers.map((e) => e['id'] as String).toList();

    // Get today's attendance
    final attendance = await SupabaseConfig.client
        .from('engineer_attendance')
        .select('engineer_id, status, check_in_time')
        .eq('date', today)
        .inFilter('engineer_id', engineerIds);

    // Get active job counts
    final jobCounts = await SupabaseConfig.client
        .from('service_tickets')
        .select('assigned_to')
        .inFilter('status', ['assigned', 'in_progress'])
        .inFilter('assigned_to', engineerIds)
        .eq('is_deleted', false);

    final attendanceMap = <String, Map<String, dynamic>>{};
    for (final a in (attendance as List)) {
      attendanceMap[a['engineer_id'] as String] = Map<String, dynamic>.from(a);
    }

    final jobCountMap = <String, int>{};
    for (final j in (jobCounts as List)) {
      final eid = j['assigned_to'] as String?;
      if (eid != null) jobCountMap[eid] = (jobCountMap[eid] ?? 0) + 1;
    }

    var result = engineers.map<Map<String, dynamic>>((e) {
      final eid = e['id'] as String;
      final att = attendanceMap[eid];
      return {
        ...Map<String, dynamic>.from(e as Map),
        'attendance_status': att?['status'] ?? 'absent',
        'check_in_time': att?['check_in_time'],
        'active_jobs': jobCountMap[eid] ?? 0,
      };
    }).toList();

    // Client-side search filter
    if (search != null && search.isNotEmpty) {
      final q = search.toLowerCase();
      result = result.where((e) {
        final name  = (e['full_name'] ?? '').toString().toLowerCase();
        final email = (e['email']     ?? '').toString().toLowerCase();
        final empId = (e['employee_id'] ?? '').toString().toLowerCase();
        final zone_ = (e['assigned_zone'] ?? '').toString().toLowerCase();
        return name.contains(q) || email.contains(q) ||
               empId.contains(q) || zone_.contains(q);
      }).toList();
    }

    return result;
  }

  // ─────────────────────────────────────────────
  // TICKET LIST
  // ─────────────────────────────────────────────

  /// All service tickets for EA's ticket queue.
  Future<List<Map<String, dynamic>>> getTicketList({
    String statusFilter = 'all',
    String? search,
    int limit = 100,
  }) async {
    var query = SupabaseConfig.client
        .from('service_tickets')
        .select('''
          id, ticket_number, subject, status, priority,
          created_at, updated_at,
          customer:users!user_id(id, full_name),
          engineer:users!assigned_to(id, full_name, profile_photo),
          machine:customer_machines!customer_machine_id(
            id, machine_nickname,
            catalog:machine_catalog!catalog_machine_id(machine_name, category)
          )
        ''')
        .eq('is_deleted', false);

    if (statusFilter == 'unassigned') {
      query = query
          .inFilter('status', ['new', 'open'])
          .isFilter('assigned_to', null);
    } else if (statusFilter != 'all') {
      query = query.inFilter('status', [statusFilter]);
    }

    final res = await query
        .order('created_at', ascending: false)
        .limit(limit);

    var list = List<Map<String, dynamic>>.from(res);

    if (search != null && search.isNotEmpty) {
      final q = search.toLowerCase();
      list = list.where((t) {
        final subject = (t['subject'] ?? '').toString().toLowerCase();
        final num = (t['ticket_number'] ?? '').toString().toLowerCase();
        final customer = (t['customer']?['full_name'] ?? '').toString().toLowerCase();
        return subject.contains(q) || num.contains(q) || customer.contains(q);
      }).toList();
    }

    return list;
  }

  // ─────────────────────────────────────────────
  // CURRENT USER PROFILE
  // ─────────────────────────────────────────────

  Future<Map<String, dynamic>?> getCurrentProfile() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return null;
    return await SupabaseConfig.client
        .from('users')
        .select('id, full_name, email, profile_photo, employee_id, department')
        .eq('id', user.id)
        .maybeSingle();
  }
}
