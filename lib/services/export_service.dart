// lib/services/export_service.dart
// v24 (CSV edition) — Admin export service
//
// Generates RFC-4180 CSV files using nothing but the Dart core SDK.  Files
// land in the app's temp dir via path_provider, then are shared through
// share_plus.  CSV opens natively in Excel, Google Sheets, Numbers, and any
// text editor.
//
// Why CSV (and not .xlsx)?
//   The earlier .xlsx implementation pulled in the `excel` package.  Its
//   pure-Dart source code was large enough to push the Dart frontend
//   compiler past its heap ceiling on low-RAM build machines
//   (`runtime/vm/zone.cc: 96: error: Out of memory`).  CSV gives the same
//   user-visible result (file opens in Excel, all data present) without
//   adding any dependency weight.
//
// Public API identical to the .xlsx version:
//   ExportService.instance.exportCustomers(list)
//   ExportService.instance.exportInquiries(list)
//   ExportService.instance.exportServiceTickets(list)
//   ExportService.showResult(context, path)

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();

  // ── Generic CSV builder ──────────────────────────────────────────────────

  /// Build a CSV file with one header row + `rows`, write to temp, share it.
  /// Returns the absolute file path, or `null` on error.
  Future<String?> exportRows({
    required List<String> headers,
    required List<List<dynamic>> rows,
    required String fileBaseName,
    String? shareText,
  }) async {
    try {
      final buf = StringBuffer();
      // BOM so Excel opens UTF-8 cleanly (otherwise non-ASCII characters
      // render as mojibake on the default Windows locale).
      buf.write('﻿');
      buf.writeln(headers.map(_csvEscape).join(','));
      for (final r in rows) {
        buf.writeln(r.map((v) => _csvEscape(_stringify(v))).join(','));
      }

      final dir = await getTemporaryDirectory();
      final today = DateTime.now();
      final stamp =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final file = File('${dir.path}/${fileBaseName}_$stamp.csv');
      await file.writeAsString(buf.toString(), flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: shareText ?? '${fileBaseName.replaceAll('_', ' ')} export',
      );
      return file.path;
    } catch (e, st) {
      debugPrint('[ExportService] export failed: $e\n$st');
      return null;
    }
  }

  /// Escapes a single CSV cell per RFC 4180:
  /// - wrap in quotes if it contains comma, quote, or newline;
  /// - double up internal quotes.
  String _csvEscape(String v) {
    final needsQuotes =
        v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r');
    if (!needsQuotes) return v;
    return '"${v.replaceAll('"', '""')}"';
  }

  String _stringify(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is DateTime) {
      return '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')} '
          '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';
    }
    return v.toString();
  }

  // ── Domain-specific helpers ──────────────────────────────────────────────

  Future<String?> exportCustomers(List<Map<String, dynamic>> customers) {
    final headers = [
      'Full Name', 'Email', 'Phone', 'Province', 'District',
      'Tier', 'Points', 'Machines', 'Joined',
    ];
    final rows = customers.map((c) {
      return <dynamic>[
        c['full_name'] ?? '',
        c['email'] ?? '',
        c['phone_number'] ?? '',
        c['province'] ?? '',
        c['district'] ?? '',
        c['current_tier'] ?? c['tier'] ?? '',
        c['total_points'] ?? c['points'] ?? 0,
        c['machine_count'] ?? 0,
        _parseDate(c['date_joined'] ?? c['created_at']),
      ];
    }).toList();
    return exportRows(
      headers: headers,
      rows: rows,
      fileBaseName: 'iconnect_customers',
      shareText: 'iConnect customer list export',
    );
  }

  Future<String?> exportInquiries(List<Map<String, dynamic>> inquiries) {
    final headers = [
      'Ticket #', 'Subject', 'Customer', 'Machine of interest',
      'Status', 'Priority', 'Created', 'Assigned To',
    ];
    final rows = inquiries.map((t) {
      final customer = t['customer'] as Map<String, dynamic>?;
      final engineer = t['assigned_engineer'] as Map<String, dynamic>?;
      final machine = t['machine'] as Map<String, dynamic>?;
      final catalog = machine?['catalog'] as Map<String, dynamic>?;
      return <dynamic>[
        t['ticket_number'] ?? '',
        t['subject'] ?? '',
        customer?['full_name'] ?? '',
        catalog?['machine_name'] ?? machine?['machine_nickname'] ?? '',
        t['status'] ?? '',
        t['priority'] ?? '',
        _parseDate(t['created_at']),
        engineer?['full_name'] ?? '',
      ];
    }).toList();
    return exportRows(
      headers: headers,
      rows: rows,
      fileBaseName: 'iconnect_inquiries',
      shareText: 'iConnect inquiries export',
    );
  }

  Future<String?> exportServiceTickets(List<Map<String, dynamic>> tickets) {
    final headers = [
      'Ticket #', 'Subject', 'Customer', 'Machine',
      'Status', 'Priority', 'Created', 'Assigned Engineer',
    ];
    final rows = tickets.map((t) {
      final customer = t['customer'] as Map<String, dynamic>?;
      final engineer = t['assigned_engineer'] as Map<String, dynamic>?;
      final machine = t['machine'] as Map<String, dynamic>?;
      final catalog = machine?['catalog'] as Map<String, dynamic>?;
      return <dynamic>[
        t['ticket_number'] ?? '',
        t['subject'] ?? '',
        customer?['full_name'] ?? '',
        catalog?['machine_name'] ?? machine?['machine_nickname'] ?? '',
        t['status'] ?? '',
        t['priority'] ?? '',
        _parseDate(t['created_at']),
        engineer?['full_name'] ?? '',
      ];
    }).toList();
    return exportRows(
      headers: headers,
      rows: rows,
      fileBaseName: 'iconnect_service_tickets',
      shareText: 'iConnect service tickets export',
    );
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  /// Convenience: show a SnackBar after an export attempt.
  static void showResult(BuildContext context, String? path) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(SnackBar(
      content: Text(path == null
          ? 'Export failed. Please try again.'
          : 'Export ready — share or open from the dialog.'),
      backgroundColor:
          path == null ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
      behavior: SnackBarBehavior.floating,
    ));
  }
}
