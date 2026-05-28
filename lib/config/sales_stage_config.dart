// lib/config/sales_stage_config.dart

import 'package:flutter/material.dart';
// ← FIXED: removed 'import admin_theme.dart'
// AdminColors may not be const — using direct Color values
// to guarantee const-correctness in the static list.

class SalesStage {
  final String value;
  final String label;
  final Color color;
  final IconData icon;
  final double progress;
  final bool isTerminal;

  const SalesStage({
    required this.value,
    required this.label,
    required this.color,
    required this.icon,
    required this.progress,
    this.isTerminal = false,
  });

  // ── All stages ────────────────────────────────────────────
  // Colors & icons aligned with inquiry_management_page.dart
  // so stage badges look identical everywhere.
  static const all = [
    SalesStage(
      value: 'new',
      label: 'New',
      color: Color(0xFF3B82F6), // ← FIXED: was AdminColors.info
      icon: Icons.fiber_new_rounded,
      progress: 0.15,
    ),
    SalesStage(
      value: 'contacted',
      label: 'Contacted',
      color: Color(0xFF8B5CF6), // ← FIXED: was 0xFF8E24AA (mismatched)
      icon: Icons
          .phone_callback_rounded, // ← FIXED: was phone_rounded (mismatched)
      progress: 0.30,
    ),
    SalesStage(
      value: 'quoted',
      label: 'Quoted',
      color: Color(0xFFF59E0B), // ← FIXED: was AdminColors.warning
      icon: Icons.receipt_long_rounded,
      progress: 0.55, // ← FIXED: was 0.50, aligned with management page
    ),
    SalesStage(
      value: 'negotiating',
      label: 'Negotiating',
      color: Color(0xFFEF8C22), // ← FIXED: was 0xFFFF8F00 (mismatched)
      icon: Icons.handshake_rounded,
      progress: 0.75, // ← FIXED: was 0.70, aligned with management page
    ),
    SalesStage(
      value: 'won',
      label: 'Won',
      color: Color(
          0xFF7CB342), // ← FIXED: was AdminColors.accent (Brand.lightGreen)
      icon: Icons
          .emoji_events_rounded, // ← FIXED: was check_circle_rounded (mismatched)
      progress: 1.0,
      isTerminal: true,
    ),
    SalesStage(
      value: 'lost',
      label: 'Lost',
      color: Color(0xFFE53935), // ← FIXED: was AdminColors.error
      icon: Icons.cancel_rounded,
      progress: 1.0,
      isTerminal: true,
    ),
  ];

  // ── Lookup by value ────────────────────────────────────────
  static SalesStage fromValue(String value) {
    return all.firstWhere(
      (s) => s.value == value,
      orElse: () => all.first,
    );
  }

  // ── Non-terminal stages only ─────────────────────────────── ← ADDED
  static List<SalesStage> get active =>
      all.where((s) => !s.isTerminal).toList();

  // ── Valid transitions from current stage ───────────────────
  static List<SalesStage> validTransitions(String currentStage) {
    // Terminal → can switch between won/lost or reopen to negotiating
    if (currentStage == 'won' || currentStage == 'lost') {
      return all
          .where((s) =>
              s.value == 'won' || s.value == 'lost' || s.value == 'negotiating')
          .toList();
    }
    return all;
  }

  // ── Next stage in the pipeline ────────────────────────────── ← ADDED
  static String nextStage(String currentStage) {
    const order = ['new', 'contacted', 'quoted', 'negotiating', 'won'];
    final idx = order.indexOf(currentStage);
    if (idx < 0 || idx >= order.length - 1) return currentStage;
    return order[idx + 1];
  }
}
