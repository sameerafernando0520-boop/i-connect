// ═══════════════════════════════════════════════════════════════
// FILE: lib/widgets/common/estimate_chat_card.dart
// In-chat itemized quotation card rendered for message_type='quote'.
// Shared between EA chat, customer chat, and engineer chat.
// metadata expected shape:
//   { 'kind': 'estimate',
//     'quotation_id': UUID,
//     'quotation_number': TEXT,
//     'total_amount': NUMERIC,
//     'items_count': INT,
//     'status': 'draft'|'sent'|'accepted'|'rejected'|'expired',
//     'currency': 'LKR' }
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';

const Color _kQuotationPurple = StatusColors.assigned;

class EstimateChatCard extends StatelessWidget {
  final Map<String, dynamic> message;
  final Map<String, dynamic> metadata;
  final bool isDark;
  final bool isCustomerView;
  final Future<void> Function()? onApprove;
  final Future<void> Function()? onReject;
  final VoidCallback? onTapDetails;

  const EstimateChatCard({
    super.key,
    required this.message,
    required this.metadata,
    required this.isDark,
    required this.isCustomerView,
    this.onApprove,
    this.onReject,
    this.onTapDetails,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    final total = (metadata['total_amount'] as num?)?.toDouble() ?? 0.0;
    final itemsCount = (metadata['items_count'] as num?)?.toInt() ?? 0;
    final qNumber = metadata['quotation_number'] as String? ?? 'Estimate';
    final status =
        (metadata['status'] as String?)?.toLowerCase() ?? 'sent';
    final currency = metadata['currency'] as String? ?? 'LKR';

    final statusColor = _statusColor(status);
    final statusLabel = _statusLabel(status);

    final canAct = isCustomerView &&
        (status == 'sent' || status == 'draft') &&
        onApprove != null &&
        onReject != null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _kQuotationPurple.withAlpha(isDark ? 77 : 51),
          width: 1.2,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: _kQuotationPurple.withAlpha(20),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
            decoration: BoxDecoration(
              color: _kQuotationPurple.withAlpha(isDark ? 38 : 26),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _kQuotationPurple,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.request_quote_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Estimate',
                        style: TextStyle(
                          color: AdminColors.text(context),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        qNumber,
                        style: TextStyle(
                          color: AdminColors.textSub(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(38),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$itemsCount line ${itemsCount == 1 ? "item" : "items"}',
                        style: TextStyle(
                          color: AdminColors.textSub(context),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$currency ${fmt.format(total)}',
                        style: TextStyle(
                          color: AdminColors.text(context),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTapDetails != null)
                  TextButton.icon(
                    onPressed: onTapDetails,
                    style: TextButton.styleFrom(
                      foregroundColor: _kQuotationPurple,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                    ),
                    icon: const Icon(Icons.list_alt_rounded, size: 16),
                    label: const Text(
                      'View',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),

          // Actions
          if (canAct) ...[
            Divider(height: 1, color: AdminColors.border(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await _confirm(
                          context,
                          title: 'Reject this estimate?',
                          message:
                              'The support team will be notified that you declined.',
                          confirmLabel: 'Reject',
                          confirmColor: AdminColors.error,
                        );
                        if (ok == true) await onReject!.call();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AdminColors.error,
                        side: BorderSide(
                            color: AdminColors.error.withAlpha(102), width: 1.2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text(
                        'Reject',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final ok = await _confirm(
                          context,
                          title: 'Approve this estimate?',
                          message:
                              'You agree to the total amount and authorize work to proceed.',
                          confirmLabel: 'Approve',
                          confirmColor: AdminColors.success,
                        );
                        if (ok == true) await onApprove!.call();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdminColors.success,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text(
                        'Approve',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (status == 'accepted' && isCustomerView) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'You approved this estimate. Engineers will be scheduled.',
                style: TextStyle(
                    color: AdminColors.success,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ] else if (status == 'rejected' && isCustomerView) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'You rejected this estimate.',
                style: TextStyle(
                    color: AdminColors.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'accepted':
        return AdminColors.success;
      case 'rejected':
      case 'expired':
        return AdminColors.error;
      case 'sent':
        return _kQuotationPurple;
      default:
        return AdminColors.textSecondary;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'accepted':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'expired':
        return 'Expired';
      case 'sent':
        return 'Awaiting';
      case 'draft':
        return 'Draft';
      default:
        return s;
    }
  }
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required Color confirmColor,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Container(
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 16 + MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AdminColors.border(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              title,
              style: TextStyle(
                color: AdminColors.text(context),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(
                  color: AdminColors.textSub(context), fontSize: 13),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetCtx, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(sheetCtx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: confirmColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(confirmLabel,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

// ────────────────────────────────────────────────────────────────────────────
// Helper API used by EA/customer/engineer chat screens
// ────────────────────────────────────────────────────────────────────────────
class EstimateChatActions {
  /// EA-side: creates a quotation + items via CreateQuotationPage (already
  /// built), then posts a chat_messages row of type='quote' with metadata
  /// pointing at the new quotation.
  ///
  /// Returns true if a quote chat message was posted.
  static Future<bool> postEstimateMessage({
    required String ticketId,
    required String quotationId,
    required String currentUserId,
  }) async {
    final q = await SupabaseConfig.client
        .from('quotations')
        .select(
            'id, quotation_number, total_amount, status, valid_until')
        .eq('id', quotationId)
        .maybeSingle();
    if (q == null) return false;

    final itemsRes = await SupabaseConfig.client
        .from('quotation_items')
        .select('id')
        .eq('quotation_id', quotationId);
    final itemsCount = (itemsRes as List).length;

    await SupabaseConfig.client.from('chat_messages').insert({
      'ticket_id': ticketId,
      'sender_id': currentUserId,
      'sender_type': 'admin',
      'message': 'Estimate sent — please review.',
      'message_type': 'quote',
      'metadata': {
        'kind': 'estimate',
        'quotation_id': quotationId,
        'quotation_number': q['quotation_number'],
        'total_amount': q['total_amount'],
        'items_count': itemsCount,
        'status': q['status'] ?? 'sent',
        'currency': 'LKR',
        'valid_until': q['valid_until'],
      },
    });
    return true;
  }

  /// Customer-side: approve. Updates quotation.status='accepted',
  /// patches all related chat_messages metadata to status='accepted',
  /// notifies the EA who created the quotation.
  static Future<void> approveEstimate({
    required String quotationId,
    required String ticketId,
    required String currentUserId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await SupabaseConfig.client.from('quotations').update({
      'status': 'accepted',
      'accepted_at': now,
    }).eq('id', quotationId);

    await _patchEstimateChatStatus(
        ticketId: ticketId,
        quotationId: quotationId,
        newStatus: 'accepted');

    // System message
    await SupabaseConfig.client.from('chat_messages').insert({
      'ticket_id': ticketId,
      'sender_id': currentUserId,
      'sender_type': 'system',
      'message': 'Customer approved the estimate.',
      'message_type': 'system',
      'metadata': {
        'kind': 'estimate_approved',
        'quotation_id': quotationId,
      },
    });

    // Notify the EA who created the quotation
    final q = await SupabaseConfig.client
        .from('quotations')
        .select('created_by, quotation_number')
        .eq('id', quotationId)
        .maybeSingle();
    final adminId = q?['created_by'] as String?;
    if (adminId != null) {
      await SupabaseConfig.client.from('notifications').insert({
        'user_id': adminId,
        'title': 'Estimate approved',
        'body':
            'Customer approved ${q?['quotation_number'] ?? "the estimate"}.',
        'type': 'quotation_approved',
        'notification_type': 'quotation_approved',
        'related_id': ticketId,
        'metadata': {
          'ticket_id': ticketId,
          'quotation_id': quotationId,
          'kind': 'estimate_approved',
        },
      });
    }
  }

  /// Customer-side: reject. Mirror of approveEstimate.
  static Future<void> rejectEstimate({
    required String quotationId,
    required String ticketId,
    required String currentUserId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await SupabaseConfig.client.from('quotations').update({
      'status': 'rejected',
      'rejected_at': now,
    }).eq('id', quotationId);

    await _patchEstimateChatStatus(
        ticketId: ticketId,
        quotationId: quotationId,
        newStatus: 'rejected');

    await SupabaseConfig.client.from('chat_messages').insert({
      'ticket_id': ticketId,
      'sender_id': currentUserId,
      'sender_type': 'system',
      'message': 'Customer rejected the estimate.',
      'message_type': 'system',
      'metadata': {
        'kind': 'estimate_rejected',
        'quotation_id': quotationId,
      },
    });

    final q = await SupabaseConfig.client
        .from('quotations')
        .select('created_by, quotation_number')
        .eq('id', quotationId)
        .maybeSingle();
    final adminId = q?['created_by'] as String?;
    if (adminId != null) {
      await SupabaseConfig.client.from('notifications').insert({
        'user_id': adminId,
        'title': 'Estimate rejected',
        'body':
            'Customer rejected ${q?['quotation_number'] ?? "the estimate"}.',
        'type': 'quotation_rejected',
        'notification_type': 'quotation_rejected',
        'related_id': ticketId,
        'metadata': {
          'ticket_id': ticketId,
          'quotation_id': quotationId,
          'kind': 'estimate_rejected',
        },
      });
    }
  }

  /// Updates the embedded status in every quote message for this quotation
  /// so historical cards in chat refresh to the new state.
  static Future<void> _patchEstimateChatStatus({
    required String ticketId,
    required String quotationId,
    required String newStatus,
  }) async {
    final rows = await SupabaseConfig.client
        .from('chat_messages')
        .select('id, metadata')
        .eq('ticket_id', ticketId)
        .eq('message_type', 'quote');

    for (final r in (rows as List)) {
      final md =
          Map<String, dynamic>.from(r['metadata'] as Map? ?? const {});
      if (md['quotation_id'] == quotationId) {
        md['status'] = newStatus;
        await SupabaseConfig.client
            .from('chat_messages')
            .update({'metadata': md}).eq('id', r['id']);
      }
    }
  }
}
