// ═══════════════════════════════════════════════════════════════
// FILE: lib/widgets/admin/inquiry/internal_notes_card.dart
// UPDATED v18 — Full dark mode pass
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../config/admin_theme.dart';
import '../../../config/brand_colors.dart';
import '../section_label.dart';

class InternalNotesCard extends StatefulWidget {
  final String? initialNotes;
  final ValueChanged<String> onSave;

  const InternalNotesCard({super.key, this.initialNotes, required this.onSave});

  @override
  State<InternalNotesCard> createState() => _InternalNotesCardState();
}

class _InternalNotesCardState extends State<InternalNotesCard> {
  late final TextEditingController _controller;
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;
  Timer? _autoSaveTimer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNotes ?? '');
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (!_hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = true);
    }
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 3), _save);
  }

  Future<void> _save() async {
    if (!_hasUnsavedChanges) return;

    setState(() => _isSaving = true);
    widget.onSave(_controller.text.trim());

    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() {
        _isSaving = false;
        _hasUnsavedChanges = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(10),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            label: 'Internal Notes',
            icon: Icons.note_alt_rounded,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isSaving)
                  Row(
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AdminColors.accent,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Saving...',
                        style: TextStyle(
                          fontSize: 10,
                          color: AdminColors.accent,
                        ),
                      ),
                    ],
                  )
                else if (_hasUnsavedChanges)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AdminColors.warning.withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Unsaved',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: AdminColors.warning,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  Icons.lock_outline_rounded,
                  size: 14,
                  color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCardElevated : const Color(0xFFF4F6FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _controller,
              maxLines: 4,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B),
              ),
              decoration: InputDecoration(
                hintText: 'Add notes about this inquiry...',
                hintStyle: TextStyle(
                  color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: isDark
                    ? Brand.darkCardElevated
                    : const Color(0xFFF4F6FA),
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _isSaving || !_hasUnsavedChanges ? null : _save,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _hasUnsavedChanges
                    ? AdminColors.primary
                    : (isDark
                          ? Brand.darkBorderLight
                          : const Color(0xFFCBD5E1)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.save_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Save Notes',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
