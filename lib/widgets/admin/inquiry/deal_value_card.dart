// ═══════════════════════════════════════════════════════════════
// FILE: lib/widgets/admin/inquiry/deal_value_card.dart
// UPDATED v18 — Full dark mode pass
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../config/admin_theme.dart';
import '../../../config/brand_colors.dart';
import '../section_label.dart';

class DealValueCard extends StatefulWidget {
  final double? initialValue;
  final ValueChanged<double?> onSave;

  const DealValueCard({super.key, this.initialValue, required this.onSave});

  @override
  State<DealValueCard> createState() => _DealValueCardState();
}

class _DealValueCardState extends State<DealValueCard> {
  late final TextEditingController _controller;
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue?.toStringAsFixed(2) ?? '',
    );
    _controller.addListener(() {
      final current = double.tryParse(_controller.text.trim());
      if (current != widget.initialValue) {
        if (!_hasUnsavedChanges) {
          setState(() => _hasUnsavedChanges = true);
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      final value = double.tryParse(text);
      if (value == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please enter a valid number'),
            backgroundColor: AdminColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
        return;
      }
      setState(() => _isSaving = true);
      widget.onSave(value);
    } else {
      setState(() => _isSaving = true);
      widget.onSave(null);
    }

    await Future.delayed(const Duration(milliseconds: 400));
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
        color: Brand.surface(isDark),
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
            label: 'Deal Value',
            icon: Icons.attach_money_rounded,
            trailing: _hasUnsavedChanges
                ? Container(
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
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AdminColors.warning,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? Brand.darkCardElevated
                        : AdminColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : Brand.darkCard,
                    ),
                    decoration: InputDecoration(
                      prefixText: 'Rs. ',
                      prefixStyle: TextStyle(
                        color: isDark
                            ? Brand.darkIconActive
                            : AdminColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                      hintText: 'Enter deal value',
                      hintStyle: TextStyle(
                        color: isDark
                            ? Brand.darkTextTertiary
                            : Brand.subtleLight,
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? Brand.darkCardElevated
                          : AdminColors.background,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _isSaving ? null : _save,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: _hasUnsavedChanges
                        ? AdminColors.accent
                        : (isDark
                              ? Brand.darkBorderLight
                              : AdminColors.borderLight),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Save',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
