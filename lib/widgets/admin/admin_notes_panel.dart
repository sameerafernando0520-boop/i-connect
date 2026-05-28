// lib/widgets/admin/admin_notes_panel.dart
// ✅ No critical changes needed — already uses AdminColors context methods
// Minor improvements: error border, discard button style

import 'package:flutter/material.dart';
import '../../config/admin_theme.dart';

class AdminNotesPanel extends StatefulWidget {
  final String? initialNotes;
  final ValueChanged<String> onSave;

  const AdminNotesPanel({
    super.key,
    this.initialNotes,
    required this.onSave,
  });

  @override
  State<AdminNotesPanel> createState() => _AdminNotesPanelState();
}

class _AdminNotesPanelState extends State<AdminNotesPanel> {
  late final TextEditingController _controller;
  bool _isExpanded = false;
  bool _hasUnsaved = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNotes ?? '');
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    final changed = _controller.text != (widget.initialNotes ?? '');
    if (changed != _hasUnsaved) {
      setState(() => _hasUnsaved = changed);
    }
  }

  void _save() {
    widget.onSave(_controller.text.trim());
    setState(() => _hasUnsaved = false);
  }

  void _discard() {
    _controller.text = widget.initialNotes ?? '';
    setState(() => _hasUnsaved = false);
  }

  @override
  Widget build(BuildContext context) {

    final hasNotes =
        widget.initialNotes != null && widget.initialNotes!.isNotEmpty;

    return Container(
      color: AdminColors.card(context),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        decoration: BoxDecoration(
          color: AdminColors.bg(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hasUnsaved
                ? AdminColors.warning.withAlpha(180)
                : AdminColors.border(context),
          ),
        ),
        child: Column(
          children: [
            // ── Header (always visible) ──
            GestureDetector(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.sticky_note_2_outlined,
                      size: 16,
                      color: AdminColors.textSub(context),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Admin Notes',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.textSub(context),
                      ),
                    ),
                    if (hasNotes && !_isExpanded) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.initialNotes!,
                          style: TextStyle(
                            fontSize: 11,
                            color: AdminColors.textHint(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ] else
                      const Spacer(),

                    // Unsaved indicator dot
                    if (_hasUnsaved)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: const BoxDecoration(
                          color: AdminColors.warning,
                          shape: BoxShape.circle,
                        ),
                      ),

                    Icon(
                      _isExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: AdminColors.textHint(context),
                    ),
                  ],
                ),
              ),
            ),

            // ── Expanded editor ──
            if (_isExpanded) ...[
              Divider(
                color: AdminColors.border(context),
                height: 1,
                indent: 14,
                endIndent: 14,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    TextField(
                      controller: _controller,
                      maxLines: 4,
                      minLines: 2,
                      style: TextStyle(
                        fontSize: 13,
                        color: AdminColors.text(context),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Add private notes about this ticket...',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: AdminColors.textHint(context),
                        ),
                        filled: true,
                        fillColor: AdminColors.card(context),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: AdminColors.border(context)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: AdminColors.border(context)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: AdminColors.primary, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    if (_hasUnsaved) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _discard,
                            style: TextButton.styleFrom(
                              foregroundColor: AdminColors.textSub(context),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                            ),
                            child: const Text(
                              'Discard',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _save,
                            style: FilledButton.styleFrom(
                              backgroundColor: AdminColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Save',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
