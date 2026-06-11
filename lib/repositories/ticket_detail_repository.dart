// lib/repositories/ticket_detail_repository.dart

import 'package:flutter/foundation.dart';
import '../config/supabase_config.dart';
import '../models/ticket_detail.dart';
import '../models/chat_message.dart';

class TicketDetailRepository {
  static const _ticketSelect = '''
    *,
    customer:user_id(
      id, full_name, email, phone_number,
      company_name, profile_photo
    ),
    engineer:assigned_to(
      id, full_name, email, phone_number,
      profile_photo, specializations, availability_status
    ),
    customer_machine:customer_machine_id(
      id, serial_number, status, purchase_date, warranty_end_date,
      catalog:catalog_machine_id(
        id, machine_name, brand, image_url, model_number, category
      )
    )
  ''';

  // ── Fetch ──

  Future<TicketDetail> fetchTicket(String ticketId) async {
    // maybeSingle() returns null (rather than throwing) when a ticket is
    // deleted mid-navigation or blocked by RLS. Throwing a clear exception
    // lets the UI show "not found" instead of a generic Postgrest error.
    final data = await SupabaseConfig.client
        .from('service_tickets')
        .select(_ticketSelect)
        .eq('id', ticketId)
        .maybeSingle();
    if (data == null) {
      throw Exception('Ticket not found or you no longer have access.');
    }
    return TicketDetail.fromJson(data);
  }

  Future<List<ChatMessage>> fetchMessages(String ticketId) async {
    final data = await SupabaseConfig.client.from('chat_messages').select('''
          *,
          sender:sender_id(id, full_name, profile_photo)
        ''').eq('ticket_id', ticketId).order('created_at', ascending: true);
    return (data as List).map((e) => ChatMessage.fromJson(e)).toList();
  }

  // ── Messages ──

  Future<void> markMessagesAsRead(String ticketId, String userId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await SupabaseConfig.client
          .from('chat_messages')
          .update({
            'is_read': true,
            'read_at': now,
            'delivered_at': now,
          })
          .eq('ticket_id', ticketId)
          .neq('sender_id', userId)
          .eq('is_read', false);
    } catch (_) {
      // Non-critical — silently ignore
    }
    // Clear the notification badge so the bell icon stops showing unread
    // for this ticket once the user has opened and read the messages.
    // Ticket notifications store the ticket ID in metadata->>'ticket_id'
    // (not in related_id which is NULL for ticket_update rows) — use the
    // JSONB filter so this update actually matches.
    try {
      await SupabaseConfig.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('type', 'ticket_update')
          .filter('metadata->>ticket_id', 'eq', ticketId)
          .eq('is_read', false);
    } catch (_) {
      // Non-critical — silently ignore
    }
  }

  Future<void> sendMessage({
    required String ticketId,
    required String senderId,
    required String senderType,
    required String message,
    bool isInternal = false,
    List<String> attachments = const [],
    String messageType = 'text',
    Map<String, dynamic>? metadata,
  }) async {
    await SupabaseConfig.client.from('chat_messages').insert({
      'ticket_id': ticketId,
      'sender_id': senderId,
      'sender_type': senderType,
      'message': message,
      'is_internal': isInternal,
      'message_type': messageType,
      if (attachments.isNotEmpty) 'attachments': attachments,
      if (metadata != null) 'metadata': metadata,
    });

    // Set first_response_at once — non-critical, never fail the message send.
    // Postgres row-level locking (EvalPlanQual under READ COMMITTED) makes the
    // conditional update atomic: concurrent writers both match `first_response_at
    // IS NULL` at plan time, but only the first to commit actually writes; the
    // second re-evaluates the WHERE on the new row version and affects 0 rows.
    if (!isInternal) {
      try {
        final now = DateTime.now().toUtc().toIso8601String();
        await SupabaseConfig.client
            .from('service_tickets')
            .update({
              'first_response_at': now,
              'updated_at': now,
            })
            .eq('id', ticketId)
            .isFilter('first_response_at', null);
      } catch (e) {
        debugPrint('⚠️ first_response_at update failed (non-critical): $e');
      }
    }
  }

  Future<void> addSystemMessage(String ticketId, String message) async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) return;
    await SupabaseConfig.client.from('chat_messages').insert({
      'ticket_id': ticketId,
      'sender_id': uid,
      'sender_type': 'system',
      'message': message,
      'is_internal': false,
    });
  }

  // ── Ticket updates ──

  Future<void> updateStatus(String ticketId, String status) async {
    final upd = <String, dynamic>{
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (status == 'resolved' || status == 'closed') {
      upd['closed_at'] = DateTime.now().toUtc().toIso8601String();
    }
    await SupabaseConfig.client
        .from('service_tickets')
        .update(upd)
        .eq('id', ticketId);
  }

  Future<void> updatePriority(String ticketId, String priority) async {
    await SupabaseConfig.client.from('service_tickets').update({
      'priority': priority,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', ticketId);
  }

  Future<void> updateAdminNotes(String ticketId, String notes) async {
    await SupabaseConfig.client.from('service_tickets').update({
      'admin_notes': notes,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', ticketId);
  }

  Future<void> assignEngineer(String ticketId, String engineerId) async {
    await SupabaseConfig.client.from('service_tickets').update({
      'assigned_to': engineerId,
      'status': 'assigned',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', ticketId);
  }

  // ── Archive (soft-delete) ──
  // Admin / engineering-admin only (enforced by a DB trigger). Archived
  // tickets are hidden from all lists/counts but retained in the DB.

  Future<void> archiveTicket(String ticketId) async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    await SupabaseConfig.client.from('service_tickets').update({
      'is_deleted': true,
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
      'deleted_by': uid,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', ticketId);
  }

  Future<void> archiveTickets(List<String> ticketIds) async {
    if (ticketIds.isEmpty) return;
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    await SupabaseConfig.client.from('service_tickets').update({
      'is_deleted': true,
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
      'deleted_by': uid,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).inFilter('id', ticketIds);
  }

  // ── Engineers ──

  Future<List<Map<String, dynamic>>> fetchEngineers() async {
    final data = await SupabaseConfig.client
        .from('users')
        .select('id, full_name, email, phone_number, profile_photo, '
            'availability_status, specializations')
        .eq('role', 'engineer')
        .order('full_name');
    return List<Map<String, dynamic>>.from(data);
  }

  // ── Quick replies ──

  List<String> getQuickReplies() => const [
        'Thank you for contacting us. We\'re looking into your request.',
        'Could you please provide more details about the issue?',
        'We\'ve assigned an engineer to your case.',
        'Your issue has been resolved. Please let us know if you need further assistance.',
        'We\'re waiting for the required parts. We\'ll update you once available.',
        'Our engineer will visit your location within 24-48 hours.',
        'Please share photos of the machine for better diagnosis.',
        'Your warranty covers this repair at no additional cost.',
      ];
}
