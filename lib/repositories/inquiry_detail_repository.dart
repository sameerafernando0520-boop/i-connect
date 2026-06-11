// lib/repositories/inquiry_detail_repository.dart

import 'package:flutter/foundation.dart';
import '../config/supabase_config.dart';
import '../models/inquiry_detail.dart';
import '../models/chat_message.dart';
import 'admin_dashboard_repository.dart';

class InquiryDetailRepository {
  final _client = SupabaseConfig.client;

  // ═══════════════════════════════════════════════════════════
  //  FETCH
  // ═══════════════════════════════════════════════════════════

  /// Fetch inquiry with customer, machine, and assigned engineer.
  ///
  /// PostgREST FK hints (`!column_name`) disambiguate the two
  /// foreign keys from service_tickets → users (user_id & assigned_to).
  ///
  /// Response keys:
  ///   'users'              → customer (InquiryCustomer)
  ///   'machine_catalog'    → machine  (InquiryMachine, nullable)
  ///   'assigned_engineer'  → { full_name } (nullable)
  ///
  /// ⚠️ Requires `machine_catalog.price` column — run Phase 8I SQL.
  Future<InquiryDetail> fetchInquiry(String inquiryId) async {
    final data = await _client.from('service_tickets').select('''
      *,
      users!user_id(
        id, full_name, email, company_name,
        phone_number, city, profile_photo
      ),
      machine_catalog!catalog_machine_id(
        id, machine_name, brand, model_number, category,
        product_images, image_url, price
      ),
      assigned_engineer:users!assigned_to(
        full_name
      )
    ''').eq('id', inquiryId).maybeSingle();

    if (data == null) {
      throw Exception('Inquiry not found or you no longer have access.');
    }
    return InquiryDetail.fromJson(data);
  }

  /// Fetch chat messages for this inquiry (all, including internal).
  /// Includes sender profile via join.
  Future<List<ChatMessage>> fetchMessages(String inquiryId) async {
    final data = await _client.from('chat_messages').select('''
          *,
          sender:users!sender_id(
            full_name, role, profile_photo
          )
        ''').eq('ticket_id', inquiryId).order('created_at', ascending: true);

    return (data as List)
        .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Fetch activity log entries for this inquiry.
  /// Never throws — returns [] on network/RLS/format errors so the inquiry
  /// detail page always renders even if the activity feed is unavailable.
  Future<List<Map<String, dynamic>>> fetchActivities(String inquiryId) async {
    try {
      final data = await _client
          .from('ticket_activities')
          .select(
              'id, actor_id, actor_type, activity_type, old_value, new_value, description, created_at')
          .eq('ticket_id', inquiryId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data as List);
    } catch (e) {
      debugPrint('⚠️ fetchActivities($inquiryId) failed: $e');
      return const [];
    }
  }

  /// Fetch unread message count — only messages FROM customers.
  ///
  /// Uses direct query (NOT RPC) per handoff §22.
  Future<int> fetchUnreadCount(String inquiryId) async {
    try {
      final data = await _client
          .from('chat_messages')
          .select('id')
          .eq('ticket_id', inquiryId)
          .eq('is_read', false)
          .eq('sender_type', 'customer');
      return (data as List).length;
    } catch (_) {
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  MUTATIONS
  // ═══════════════════════════════════════════════════════════

  /// Update sales stage via RPC.
  ///
  /// The `update_inquiry_stage` RPC handles:
  ///   - Stage update + status sync + closed_at management
  ///   - last_activity_at + updated_at
  ///   - Activity log entry with old/new values
  Future<void> updateSalesStage(String inquiryId, String newStage) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final result = await _client.rpc('update_inquiry_stage', params: {
      'p_ticket_id': inquiryId,
      'p_new_stage': newStage,
      'p_user_id': userId,
    });

    if (result is Map && result['success'] != true) {
      throw Exception(result['error'] ?? 'Failed to update stage');
    }
    // H5: mutation succeeded — wipe dashboard caches so the next admin
    // view reflects the new stage/status instead of serving stale data.
    AdminDashboardRepository.invalidate();
  }

  /// Update admin notes.
  Future<void> updateNotes(String inquiryId, String notes) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('service_tickets').update({
      'admin_notes': notes,
      'last_activity_at': now,
      'updated_at': now,
    }).eq('id', inquiryId);
    AdminDashboardRepository.invalidate();
  }

  /// Update deal value. Pass `null` to clear.
  Future<void> updateDealValue(String inquiryId, double? value) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('service_tickets').update({
      'deal_value': value,
      'last_activity_at': now,
      'updated_at': now,
    }).eq('id', inquiryId);
    AdminDashboardRepository.invalidate();
  }

  /// Mark quote as sent — sets date, advances stage to 'quoted',
  /// and logs activity (fire-and-forget).
  Future<void> markQuoteSent(String inquiryId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final now = DateTime.now().toUtc().toIso8601String();

    // Primary operation — must succeed
    await _client.from('service_tickets').update({
      'quote_sent_date': now,
      'sales_stage': 'quoted',
      'last_activity_at': now,
      'updated_at': now,
    }).eq('id', inquiryId);
    AdminDashboardRepository.invalidate();

    // Secondary: activity log — fire and forget
    // Don't let its failure block the primary success, but do log it so
    // silent data-integrity issues surface in debug builds.
    _client
        .from('ticket_activities')
        .insert({
          'ticket_id': inquiryId,
          'actor_id': userId,
          'actor_type': 'admin',
          'activity_type': 'stage_change',
          'new_value': 'quoted',
          'description': 'Quote sent to customer',
        })
        .then((_) {})
        .catchError((e) {
          debugPrint('⚠️ Activity log (stage_change → quoted) failed: $e');
        });
  }

  /// Add a system/internal chat message (e.g., stage change log).
  ///
  /// Uses sender_type='admin' + is_internal=true so customers
  /// never see these messages.
  Future<void> addSystemMessage(String inquiryId, String message) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return; // Silently skip if not authenticated

    await _client.from('chat_messages').insert({
      'ticket_id': inquiryId,
      'sender_id': userId,
      'sender_type': 'admin',
      'message': message,
      'is_internal': true,
      'is_read': false,
    });
  }
}
