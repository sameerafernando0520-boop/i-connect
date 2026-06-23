// ═══════════════════════════════════════════════════════════════
// FILE: lib/widgets/admin/inquiry/sales_pipeline.dart
// UPDATED v18 — Full dark mode pass
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../config/admin_theme.dart';
import '../../../config/brand_colors.dart';
import '../../../config/sales_stage_config.dart';

class SalesPipeline extends StatelessWidget {
  final String currentStage;
  final ValueChanged<String> onStageChanged;
  final bool isReadOnly;

  const SalesPipeline({
    super.key,
    required this.currentStage,
    required this.onStageChanged,
    this.isReadOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final current = SalesStage.fromValue(currentStage);
    final validStages = SalesStage.validTransitions(currentStage);

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
          // Header
          Row(
            children: [
              Text(
                'Sales Pipeline',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Brand.darkTextPrimary : AdminColors.primary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: current.color.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${(current.progress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: current.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: current.progress),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: isDark
                      ? Brand.darkCardElevated
                      : const Color(0xFFF1F5F9),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    current.value == 'lost' ? AdminColors.error : current.color,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Step indicators
          _buildStepRow(current, isDark),
          const SizedBox(height: 16),

          // Stage chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: SalesStage.all.map((stage) {
              final isSelected = currentStage == stage.value;
              final isValid = validStages.contains(stage);
              final canTap = !isReadOnly && isValid;

              return GestureDetector(
                onTap: canTap ? () => onStageChanged(stage.value) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? stage.color : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? stage.color
                          : isValid
                          ? (isDark ? Brand.darkBorderLight : Brand.borderLight)
                          : (isDark
                                ? Brand.darkBorder
                                : const Color(0xFFE2E8F0)),
                      width: isSelected ? 2 : 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        stage.icon,
                        size: 14,
                        color: isSelected
                            ? Colors.white
                            : isValid
                            ? stage.color
                            : (isDark
                                  ? Brand.darkTextTertiary
                                  : Brand.subtleLight),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        stage.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : isValid
                              ? stage.color
                              : (isDark
                                    ? Brand.darkTextTertiary
                                    : Brand.subtleLight),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow(SalesStage current, bool isDark) {
    final flowStages = SalesStage.all.where((s) => s.value != 'lost').toList();
    final currentIndex = flowStages.indexWhere((s) => s.value == current.value);

    return Row(
      children: List.generate(flowStages.length * 2 - 1, (index) {
        if (index.isOdd) {
          final stageIndex = index ~/ 2;
          final isCompleted = stageIndex < currentIndex;
          return Expanded(
            child: Container(
              height: 2,
              color: isCompleted
                  ? AdminColors.accent
                  : (isDark ? Brand.darkBorderLight : const Color(0xFFE2E8F0)),
            ),
          );
        }

        final stageIndex = index ~/ 2;
        final stage = flowStages[stageIndex];
        final isCompleted = stageIndex < currentIndex;
        final isCurrent = stage.value == current.value;

        return Container(
          width: isCurrent ? 28 : 20,
          height: isCurrent ? 28 : 20,
          decoration: BoxDecoration(
            color: isCurrent
                ? stage.color
                : isCompleted
                ? AdminColors.accent
                : (isDark ? Brand.darkCardElevated : const Color(0xFFE2E8F0)),
            shape: BoxShape.circle,
            border: isCurrent
                ? Border.all(color: stage.color.withAlpha(75), width: 3)
                : null,
          ),
          child: Icon(
            isCompleted || isCurrent ? Icons.check_rounded : Icons.circle,
            size: isCurrent ? 14 : 10,
            color: isCompleted || isCurrent
                ? Colors.white
                : (isDark ? Brand.darkTextTertiary : Brand.subtleLight),
          ),
        );
      }),
    );
  }
}
