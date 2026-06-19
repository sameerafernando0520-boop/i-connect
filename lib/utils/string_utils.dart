// lib/utils/string_utils.dart

class StringUtils {
  static String getInitials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
  }

  static String truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  // BUG-38: Maps raw DB status strings to human-readable labels.
  // Add localised overloads when S.of(context) is available at call site.
  static String statusLabel(String? status) {
    switch (status) {
      case 'open':           return 'Open';
      case 'in_progress':    return 'In Progress';
      case 'resolved':       return 'Resolved';
      case 'closed':         return 'Closed';
      case 'pending':        return 'Pending';
      case 'scheduled':      return 'Scheduled';
      case 'confirmed':      return 'Confirmed';
      case 'completed':      return 'Completed';
      case 'cancelled':      return 'Cancelled';
      case 'rescheduled':    return 'Rescheduled';
      case 'draft':          return 'Draft';
      case 'sent':           return 'Sent';
      case 'accepted':       return 'Accepted';
      case 'rejected':       return 'Rejected';
      case 'expired':        return 'Expired';
      case 'converted':      return 'Converted';
      case 'paid':           return 'Paid';
      case 'overdue':        return 'Overdue';
      case 'active':         return 'Active';
      case 'inactive':       return 'Inactive';
      case 'new_install':    return 'New Install';
      case 'replacement':    return 'Replacement';
      case 'upgrade':        return 'Upgrade';
      case 'commissioning':  return 'Commissioning';
      case 'decommission':   return 'Decommission';
      default:               return status ?? '—';
    }
  }
}
