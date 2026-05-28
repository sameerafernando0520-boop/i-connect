// lib/services/attendance_service.dart
// v24 — Engineer self check-in / check-out
//
// Replaces the EA-driven "mark engineer present/absent" flow.  Engineers
// self-report arrival from their dashboard.  The EA attendance page becomes
// a read-only audit/override surface.
//
// Schema (verified live 2026-05-13):
//   engineer_attendance(
//     id uuid pk,
//     engineer_id uuid fk → users.id,
//     date date,
//     status text,                 -- present | absent | late | half_day | on_leave
//     check_in_time timestamptz,
//     check_out_time timestamptz,
//     ...
//   )
//
// All writes go through `SupabaseConfig.client` and gracefully no-op if the
// row already exists (upsert by (engineer_id, date)).

import '../config/supabase_config.dart';

class AttendanceService {
  AttendanceService._();
  static final AttendanceService instance = AttendanceService._();

  /// Returns today's attendance row for the current engineer, or `null` if
  /// nothing has been written yet today.
  Future<Map<String, dynamic>?> todayRecord() async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) return null;
    final today = _today();
    final row = await SupabaseConfig.client
        .from('engineer_attendance')
        .select()
        .eq('engineer_id', uid)
        .eq('date', today)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  /// Engineer presses "Check In".  If the row exists today (e.g. EA marked
  /// them late earlier), updates check_in_time; otherwise inserts.
  /// Returns the upserted row.
  Future<Map<String, dynamic>> checkIn() async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Not signed in');
    }
    final today = _today();
    final now = DateTime.now().toIso8601String();
    // Decide status: if current time after 09:30, mark as 'late'; otherwise 'present'.
    final t = DateTime.now();
    final isLate = t.hour > 9 || (t.hour == 9 && t.minute >= 30);

    final existing = await SupabaseConfig.client
        .from('engineer_attendance')
        .select('id')
        .eq('engineer_id', uid)
        .eq('date', today)
        .maybeSingle();

    if (existing == null) {
      final inserted = await SupabaseConfig.client
          .from('engineer_attendance')
          .insert({
            'engineer_id': uid,
            'date': today,
            'status': isLate ? 'late' : 'present',
            'check_in_time': now,
          })
          .select()
          .single();
      return Map<String, dynamic>.from(inserted);
    } else {
      final updated = await SupabaseConfig.client
          .from('engineer_attendance')
          .update({
            'status': isLate ? 'late' : 'present',
            'check_in_time': now,
          })
          .eq('id', existing['id'])
          .select()
          .single();
      return Map<String, dynamic>.from(updated);
    }
  }

  /// Engineer presses "Check Out".  Requires a check-in to exist already.
  Future<Map<String, dynamic>?> checkOut() async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Not signed in');
    }
    final today = _today();
    final now = DateTime.now().toIso8601String();
    final existing = await SupabaseConfig.client
        .from('engineer_attendance')
        .select('id')
        .eq('engineer_id', uid)
        .eq('date', today)
        .maybeSingle();
    if (existing == null) return null;
    final updated = await SupabaseConfig.client
        .from('engineer_attendance')
        .update({'check_out_time': now})
        .eq('id', existing['id'])
        .select()
        .single();
    return Map<String, dynamic>.from(updated);
  }

  String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
