import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../widgets/admin/shimmer_loading.dart';

class ReferralRulesPage extends StatefulWidget {
  const ReferralRulesPage({super.key});

  @override
  State<ReferralRulesPage> createState() => _ReferralRulesPageState();
}

class _ReferralRulesPageState extends State<ReferralRulesPage> {
  final _supabase = SupabaseConfig.client;
  final _fmt = NumberFormat('#,##0.00', 'en_US');

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rules = [];

  double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  int _i(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _supabase
          .from('referral_commission_rules')
          .select()
          .order('priority', ascending: false)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _rules = List<Map<String, dynamic>>.from(res);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // FIX: Store error for display instead of silently swallowing
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ═══════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AdminColors.bg(context),
      appBar: DsPageHeader(
        title: 'Commission Rules',
        accent: HeroAccent.navy,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRuleEditor(null),
        backgroundColor: AdminColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text(
          'New Rule',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? _buildShimmer(isDark)
          : _error != null
              ? _buildError(isDark)
              : _rules.isEmpty
                  ? _buildEmpty(isDark)
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AdminColors.primary,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                        itemCount: _rules.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            _buildRuleCard(_rules[i], isDark),
                      ),
                    ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  RULE CARD
  // ═══════════════════════════════════════════════════════

  Widget _buildRuleCard(Map<String, dynamic> rule, bool isDark) {
    final active = rule['is_active'] == true;
    final type = rule['commission_type']?.toString() ?? 'percentage';
    final value = _d(rule['commission_value']);
    final priority = _i(rule['priority']);
    final rewardKind = rule['reward_kind']?.toString() ?? 'cash';
    final rewardLabel = rule['reward_label']?.toString();

    final cashDisplay = type == 'percentage'
        ? '${value.toStringAsFixed(1)}%'
        : 'Rs. ${_fmt.format(value)}';
    final valueDisplay =
        (rewardKind != 'cash' && (rewardLabel?.isNotEmpty ?? false))
            ? rewardLabel!
            : cashDisplay;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.card(context),
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: Border.all(
          color: active
              ? AdminColors.border(context)
              : AdminColors.error.withAlpha(40),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: active
                      ? AdminColors.primary.withAlpha(20)
                      : AdminColors.error.withAlpha(15),
                  borderRadius: BorderRadius.circular(Brand.r(12)),
                ),
                child: Icon(
                  Icons.rule_rounded,
                  size: 20,
                  color: active ? AdminColors.primary : AdminColors.error,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule['name']?.toString() ?? 'Unnamed Rule',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.text(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (rule['category'] != null)
                      Text(
                        rule['category'].toString(),
                        style: TextStyle(
                          fontSize: 12,
                          color: AdminColors.textSub(context),
                        ),
                      ),
                  ],
                ),
              ),
              // Active/inactive badge
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: active
                      ? AdminColors.success.withAlpha(20)
                      : AdminColors.error.withAlpha(15),
                  borderRadius: BorderRadius.circular(Brand.r(10)),
                ),
                child: Text(
                  active ? 'Active' : 'Inactive',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: active ? AdminColors.success : AdminColors.error,
                  ),
                ),
              ),
              // Active toggle
              Switch.adaptive(
                value: active,
                activeTrackColor: AdminColors.success,
                onChanged: (v) => _toggleRule(rule['id'] as String, v),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Details grid
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AdminColors.bg(context),
              borderRadius: BorderRadius.circular(Brand.r(12)),
              border: Border.all(color: AdminColors.border(context)),
            ),
            child: Row(
              children: [
                _ruleDetail(
                  rewardKind == 'cash' ? 'Commission' : 'Reward',
                  valueDisplay,
                  AdminColors.primary,
                ),
                _divider(),
                _ruleDetail(
                  'Min Purchase',
                  _d(rule['min_purchase']) > 0
                      ? 'Rs. ${_fmt.format(_d(rule['min_purchase']))}'
                      : 'None',
                  // FIX: Use AdminColors.accent for Min Purchase
                  AdminColors.accent,
                ),
                _divider(),
                _ruleDetail(
                  'Max Cap',
                  rule['max_commission'] != null
                      ? 'Rs. ${_fmt.format(_d(rule['max_commission']))}'
                      : 'No cap',
                  // FIX: Use AdminColors.warning instead of hardcoded
                  AdminColors.warning,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Bottom chip row
          Row(
            children: [
              _chipInfo(
                'Cooldown: ${_i(rule['cooldown_days'])}d',
                isDark,
              ),
              const SizedBox(width: 6),
              _chipInfo(
                'Expiry: ${_i(rule['expiry_days'])}d',
                isDark,
              ),
              const SizedBox(width: 6),
              _chipInfo('Priority: $priority', isDark),
              const Spacer(),
              // Edit button
              GestureDetector(
                onTap: () => _showRuleEditor(rule),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AdminColors.primary.withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    size: 16,
                    color: AdminColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Delete button
              GestureDetector(
                onTap: () => _deleteRule(rule),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AdminColors.error.withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    size: 16,
                    color: AdminColors.error,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ruleDetail(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AdminColors.textHint(context),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 30,
      color: AdminColors.border(context),
      margin: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  Widget _chipInfo(String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AdminColors.bg(context),
        borderRadius: BorderRadius.circular(Brand.r(10)),
        // FIX: Add border so chips are visible in dark mode
        border: Border.all(color: AdminColors.border(context)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AdminColors.textSub(context),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  RULE EDITOR SHEET
  // ═══════════════════════════════════════════════════════

  void _showRuleEditor(Map<String, dynamic>? existing) {
    final isEdit = existing != null;
    final nameCtrl =
        TextEditingController(text: existing?['name']?.toString() ?? '');
    final categoryCtrl =
        TextEditingController(text: existing?['category']?.toString() ?? '');
    // FIX: For new rule, start with empty string not '0.00'
    final valueCtrl = TextEditingController(
        text:
            isEdit ? _d(existing['commission_value']).toStringAsFixed(2) : '');
    final minCtrl = TextEditingController(
        text: _d(existing?['min_purchase']) > 0
            ? _d(existing?['min_purchase']).toStringAsFixed(2)
            : '');
    final maxCtrl = TextEditingController(
        text: existing?['max_commission'] != null
            ? _d(existing?['max_commission']).toStringAsFixed(2)
            : '');
    final cooldownCtrl =
        TextEditingController(text: '${_i(existing?['cooldown_days'] ?? 30)}');
    final expiryCtrl =
        TextEditingController(text: '${_i(existing?['expiry_days'] ?? 180)}');
    final priorityCtrl =
        TextEditingController(text: '${_i(existing?['priority'] ?? 0)}');
    final rewardLabelCtrl = TextEditingController(
        text: existing?['reward_label']?.toString() ?? '');

    String commType = existing?['commission_type']?.toString() ?? 'percentage';
    String rewardKind = existing?['reward_kind']?.toString() ?? 'cash';
    bool saving = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetCtx).size.height * 0.9,
                ),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AdminColors.card(sheetCtx),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AdminColors.border(sheetCtx),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        isEdit ? 'Edit Commission Rule' : 'New Commission Rule',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.text(sheetCtx),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _editorField(sheetCtx, nameCtrl, 'Rule Name *'),
                      const SizedBox(height: 12),
                      _editorField(
                        sheetCtx,
                        categoryCtrl,
                        'Category (e.g. Heavy Machinery)',
                      ),
                      const SizedBox(height: 14),
                      // Reward kind — what the referrer actually receives.
                      Text(
                        'Reward Type',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AdminColors.textSub(sheetCtx),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final k in const [
                            ['cash', 'Cash'],
                            ['discount', 'Discount'],
                            ['gift', 'Gift'],
                            ['points', 'Points'],
                            ['custom', 'Custom'],
                          ])
                            _kindChip(sheetCtx, k[1], rewardKind == k[0],
                                () => setSheet(() => rewardKind = k[0])),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _editorField(
                        sheetCtx,
                        rewardLabelCtrl,
                        rewardKind == 'cash'
                            ? 'Reward note (optional)'
                            : 'Reward description shown to customer *',
                      ),
                      const SizedBox(height: 14),
                      // Commission type toggle
                      Text(
                        'Commission Type',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AdminColors.textSub(sheetCtx),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _typeChip(
                            sheetCtx,
                            'Percentage',
                            commType == 'percentage',
                            () => setSheet(() => commType = 'percentage'),
                          ),
                          const SizedBox(width: 10),
                          _typeChip(
                            sheetCtx,
                            'Fixed Amount',
                            commType == 'fixed',
                            () => setSheet(() => commType = 'fixed'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _editorField(
                        sheetCtx,
                        valueCtrl,
                        commType == 'percentage'
                            ? 'Commission % *'
                            : 'Fixed Amount (Rs.) *',
                        keyboard: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _editorField(
                              sheetCtx,
                              minCtrl,
                              'Min Purchase (Rs.)',
                              keyboard: const TextInputType.numberWithOptions(
                                  decimal: true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _editorField(
                              sheetCtx,
                              maxCtrl,
                              'Max Commission (Rs.)',
                              keyboard: const TextInputType.numberWithOptions(
                                  decimal: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _editorField(
                              sheetCtx,
                              cooldownCtrl,
                              'Cooldown (days)',
                              keyboard: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _editorField(
                              sheetCtx,
                              expiryCtrl,
                              'Expiry (days)',
                              keyboard: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _editorField(
                        sheetCtx,
                        priorityCtrl,
                        'Priority (higher = preferred)',
                        keyboard: TextInputType.number,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  // FIX: Validate name AND value
                                  if (nameCtrl.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                      SnackBar(
                                        content:
                                            const Text('Rule name is required'),
                                        backgroundColor: AdminColors.error,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(Brand.r(12)),
                                        ),
                                        margin: const EdgeInsets.fromLTRB(
                                            16, 0, 16, 16),
                                      ),
                                    );
                                    return;
                                  }
                                  final commValue =
                                      double.tryParse(valueCtrl.text) ?? 0;
                                  final needsLabel = rewardKind == 'discount' ||
                                      rewardKind == 'gift' ||
                                      rewardKind == 'custom';
                                  final needsValue = rewardKind == 'cash' ||
                                      rewardKind == 'discount' ||
                                      rewardKind == 'points';
                                  if (needsLabel &&
                                      rewardLabelCtrl.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                      SnackBar(
                                        content: const Text(
                                            'Add a reward description for this reward type'),
                                        backgroundColor: AdminColors.error,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(Brand.r(12)),
                                        ),
                                        margin: const EdgeInsets.fromLTRB(
                                            16, 0, 16, 16),
                                      ),
                                    );
                                    return;
                                  }
                                  if (needsValue && commValue <= 0) {
                                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                      SnackBar(
                                        content: const Text(
                                            'Commission value must be greater than 0'),
                                        backgroundColor: AdminColors.error,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(Brand.r(12)),
                                        ),
                                        margin: const EdgeInsets.fromLTRB(
                                            16, 0, 16, 16),
                                      ),
                                    );
                                    return;
                                  }
                                  // FIX: Validate percentage ≤ 100
                                  if (commType == 'percentage' &&
                                      commValue > 100) {
                                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                      SnackBar(
                                        content: const Text(
                                            'Percentage cannot exceed 100%'),
                                        backgroundColor: AdminColors.error,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(Brand.r(12)),
                                        ),
                                        margin: const EdgeInsets.fromLTRB(
                                            16, 0, 16, 16),
                                      ),
                                    );
                                    return;
                                  }

                                  setSheet(() => saving = true);
                                  try {
                                    final res = await _supabase.rpc(
                                      'upsert_commission_rule',
                                      params: {
                                        'p_id': existing?['id'],
                                        'p_name': nameCtrl.text.trim(),
                                        'p_category':
                                            categoryCtrl.text.trim().isEmpty
                                                ? null
                                                : categoryCtrl.text.trim(),
                                        'p_commission_type': commType,
                                        'p_commission_value': commValue,
                                        'p_min_purchase':
                                            double.tryParse(minCtrl.text) ?? 0,
                                        'p_max_commission':
                                            maxCtrl.text.trim().isEmpty
                                                ? null
                                                : double.tryParse(maxCtrl.text),
                                        'p_cooldown_days':
                                            int.tryParse(cooldownCtrl.text) ??
                                                30,
                                        'p_expiry_days':
                                            int.tryParse(expiryCtrl.text) ??
                                                180,
                                        'p_is_active':
                                            existing?['is_active'] ?? true,
                                        'p_priority':
                                            int.tryParse(priorityCtrl.text) ??
                                                0,
                                        'p_reward_kind': rewardKind,
                                        'p_reward_label':
                                            rewardLabelCtrl.text.trim().isEmpty
                                                ? null
                                                : rewardLabelCtrl.text.trim(),
                                      },
                                    );
                                    // FIX: Check sheetCtx mounted
                                    if (!sheetCtx.mounted) {
                                      return;
                                    }
                                    // FIX: Safe cast
                                    final result = res is Map<String, dynamic>
                                        ? res
                                        : <String, dynamic>{};
                                    if (result['success'] == true) {
                                      Navigator.pop(sheetCtx);
                                      // FIX: Check parent mounted
                                      if (!mounted) return;
                                      _snack(isEdit
                                          ? 'Rule updated'
                                          : 'Rule created');
                                      await _load();
                                    } else {
                                      setSheet(() => saving = false);
                                      // FIX: Show error in sheet
                                      //      context not parent
                                      ScaffoldMessenger.of(sheetCtx)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            result['error']?.toString() ??
                                                'Failed to save rule',
                                          ),
                                          backgroundColor: AdminColors.error,
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(Brand.r(12)),
                                          ),
                                          margin: const EdgeInsets.fromLTRB(
                                              16, 0, 16, 16),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (!sheetCtx.mounted) {
                                      return;
                                    }
                                    setSheet(() => saving = false);
                                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                      SnackBar(
                                        content:
                                            const Text('Failed to save rule'),
                                        backgroundColor: AdminColors.error,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(Brand.r(12)),
                                        ),
                                        margin: const EdgeInsets.fromLTRB(
                                            16, 0, 16, 16),
                                      ),
                                    );
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AdminColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(Brand.r(14)),
                            ),
                          ),
                          child: saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  isEdit ? 'Update Rule' : 'Create Rule',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                        ),
                      ),
                      SizedBox(
                        height: MediaQuery.of(sheetCtx).padding.bottom + 8,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      // FIX: Always dispose all controllers after sheet dismissed
      nameCtrl.dispose();
      categoryCtrl.dispose();
      valueCtrl.dispose();
      minCtrl.dispose();
      maxCtrl.dispose();
      cooldownCtrl.dispose();
      expiryCtrl.dispose();
      priorityCtrl.dispose();
      rewardLabelCtrl.dispose();
    });
  }

  Widget _editorField(
    BuildContext ctx,
    TextEditingController ctrl,
    String label, {
    TextInputType? keyboard,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      style: TextStyle(color: AdminColors.text(ctx), fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AdminColors.textSub(ctx), fontSize: 13),
        filled: true,
        fillColor: AdminColors.bg(ctx),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.r(12)),
          borderSide: BorderSide.none,
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  Widget _typeChip(
    BuildContext ctx,
    String label,
    bool active,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? AdminColors.primary.withAlpha(25)
                : AdminColors.bg(ctx),
            borderRadius: BorderRadius.circular(Brand.r(10)),
            border: Border.all(
              color: active
                  ? AdminColors.primary.withAlpha(80)
                  : AdminColors.border(ctx),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? AdminColors.primary : AdminColors.textSub(ctx),
            ),
          ),
        ),
      ),
    );
  }

  // A compact (non-expanding) selectable chip for the reward-kind picker.
  Widget _kindChip(
    BuildContext ctx,
    String label,
    bool active,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color:
              active ? AdminColors.primary.withAlpha(25) : AdminColors.bg(ctx),
          borderRadius: BorderRadius.circular(Brand.r(10)),
          border: Border.all(
            color: active
                ? AdminColors.primary.withAlpha(80)
                : AdminColors.border(ctx),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? AdminColors.primary : AdminColors.textSub(ctx),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  TOGGLE / DELETE
  // ═══════════════════════════════════════════════════════

  Future<void> _toggleRule(String id, bool isActive) async {
    // Optimistic update using spread copy
    setState(() {
      final idx = _rules.indexWhere((r) => r['id'] == id);
      if (idx != -1) {
        // FIX: Full spread copy — new list + new item map
        final updated = List<Map<String, dynamic>>.from(_rules);
        updated[idx] = {
          ...updated[idx],
          'is_active': isActive,
        };
        _rules = updated;
      }
    });

    try {
      await _supabase.from('referral_commission_rules').update({
        'is_active': isActive,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
      if (!mounted) return;
      _snack(isActive ? 'Rule activated' : 'Rule deactivated');
    } catch (e) {
      if (!mounted) return;
      // Revert optimistic update on failure
      await _load();
      _snack('Failed to toggle rule', isError: true);
    }
  }

  Future<void> _deleteRule(Map<String, dynamic> rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.card(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(20))),
        title: Text(
          'Delete Rule?',
          style: TextStyle(color: AdminColors.text(ctx)),
        ),
        content: Text(
          'Delete "${rule['name']}"?\n\n'
          'Rules referenced by existing referrals cannot be deleted.',
          style: TextStyle(
            color: AdminColors.textSub(ctx),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AdminColors.textSub(ctx)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Brand.r(10))),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    // FIX: mounted check after dialog
    if (confirmed != true) return;
    if (!mounted) return;

    try {
      final res = await _supabase.rpc(
        'delete_commission_rule',
        params: {'p_rule_id': rule['id']},
      );
      if (!mounted) return;
      // FIX: Safe cast
      final result = res is Map<String, dynamic> ? res : <String, dynamic>{};
      if (result['success'] == true) {
        _snack('Rule deleted');
        await _load();
      } else {
        _snack(
          result['error']?.toString() ?? 'Failed to delete rule',
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to delete rule', isError: true);
    }
  }

  // ═══════════════════════════════════════════════════════
  //  SHARED
  // ═══════════════════════════════════════════════════════

  // FIX: Success snack uses AdminColors.success not .accent
  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? AdminColors.error : AdminColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  Widget _buildShimmer(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(
          3,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ShimmerLoading(
              child: Container(
                height: 160,
                decoration: BoxDecoration(
                  color: AdminColors.card(context),
                  borderRadius: BorderRadius.circular(Brand.r(16)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // FIX: Added error state widget
  Widget _buildError(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: AdminColors.textHint(context),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load rules',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AdminColors.text(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AdminColors.textSub(context),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Brand.r(12))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Icon(
              Icons.rule_rounded,
              size: 56,
              color: AdminColors.textHint(context),
            ),
            const SizedBox(height: 16),
            Text(
              'No commission rules',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AdminColors.text(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to create your first commission rule',
              style: TextStyle(
                fontSize: 13,
                color: AdminColors.textSub(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
