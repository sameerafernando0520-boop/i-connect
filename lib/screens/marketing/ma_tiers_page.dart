// lib/screens/marketing/ma_tiers_page.dart
// P3 — Loyalty Tiers: view + edit tier thresholds and benefits

import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../widgets/ds/ds_widgets.dart';

const Color _tierColor = AdminColors.warning;

class MaTiersPage extends StatefulWidget {
  const MaTiersPage({super.key});

  @override
  State<MaTiersPage> createState() => _MaTiersPageState();
}

class _MaTiersPageState extends State<MaTiersPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  List<Map<String, dynamic>> _thresholds = [];
  List<Map<String, dynamic>> _benefits = [];
  bool _loadingThresholds = true;
  bool _loadingBenefits = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadThresholds();
    _loadBenefits();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadThresholds() async {
    setState(() => _loadingThresholds = true);
    try {
      final res = await SupabaseConfig.client
          .from('tier_thresholds')
          .select()
          .order('min_points', ascending: true);
      if (!mounted) return;
      setState(() {
        _thresholds = List<Map<String, dynamic>>.from(res);
        _loadingThresholds = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingThresholds = false);
    }
  }

  Future<void> _loadBenefits() async {
    setState(() => _loadingBenefits = true);
    try {
      final res = await SupabaseConfig.client
          .from('tier_benefits')
          .select()
          .order('tier', ascending: true);
      if (!mounted) return;
      setState(() {
        _benefits = List<Map<String, dynamic>>.from(res);
        _loadingBenefits = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingBenefits = false);
    }
  }

  Future<void> _editThreshold(Map<String, dynamic> threshold) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ThresholdEditDialog(threshold: threshold),
    );
    if (result == null || !mounted) return;
    try {
      await SupabaseConfig.client.from('tier_thresholds').update({
        'min_points': result['min_points'],
        'max_points': result['max_points'],
        'multiplier': result['multiplier'],
      }).eq('id', threshold['id']);
      if (!mounted) return;
      _showSuccess('Threshold updated');
      _loadThresholds();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  Future<void> _editBenefit(Map<String, dynamic> benefit) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _BenefitEditDialog(benefit: benefit),
    );
    if (result == null || !mounted) return;
    try {
      await SupabaseConfig.client.from('tier_benefits').update({
        'benefit_description': result['benefit_description'],
        'is_active': result['is_active'],
      }).eq('id', benefit['id']);
      if (!mounted) return;
      _showSuccess('Benefit updated');
      _loadBenefits();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: AdminColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
    ));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
      ]),
      backgroundColor: AdminColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: DsPageHeader(
        title: 'Loyalty Tiers',
        accent: HeroAccent.violet,
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withAlpha(153),
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: 'Thresholds'),
            Tab(text: 'Benefits'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildThresholdsTab(isDark),
          _buildBenefitsTab(isDark),
        ],
      ),
    );
  }

  Widget _buildThresholdsTab(bool isDark) {
    return _loadingThresholds
        ? const Center(child: CircularProgressIndicator(color: _tierColor))
        : RefreshIndicator(
            onRefresh: _loadThresholds, color: _tierColor,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                // Summary cards
                _buildTierSummary(isDark),
                const SizedBox(height: 20),
                Text('TIER THRESHOLDS',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: isDark ? Brand.darkTextSecondary : Brand.subtleLight)),
                const SizedBox(height: 12),
                ..._thresholds.map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildThresholdCard(t, isDark),
                    )),
              ],
            ),
          );
  }

  Widget _buildTierSummary(bool isDark) {
    final tiers = ['Bronze', 'Silver', 'Gold', 'Platinum'];
    final colors = [
      TierColors.bronze,
      TierColors.silver,
      TierColors.gold,
      TierColors.platinum,
    ];
    final icons = [
      Icons.shield_outlined,
      Icons.shield_rounded,
      Icons.star_rounded,
      Icons.workspace_premium_rounded,
    ];

    return Row(
      children: List.generate(4, (i) {
        final threshold = _thresholds.length > i ? _thresholds[i] : null;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < 3 ? 8 : 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Brand.surface(isDark),
              borderRadius: BorderRadius.circular(Brand.r(14)),
              border: Border.all(color: colors[i].withAlpha(isDark ? 80 : 60)),
              boxShadow: isDark ? null : [
                BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 10, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(children: [
              Icon(icons[i], color: colors[i], size: 22),
              const SizedBox(height: 4),
              Text(tiers[i],
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colors[i])),
              if (threshold != null) ...[
                const SizedBox(height: 2),
                Text('${threshold['min_points']}+',
                    style: TextStyle(fontSize: 11, color: AdminColors.textHint(context))),
              ],
            ]),
          ),
        );
      }),
    );
  }

  Widget _buildThresholdCard(Map<String, dynamic> t, bool isDark) {
    final tierName = t['tier'] as String? ?? '—';
    final minPts = t['min_points'] as int? ?? 0;
    final maxPts = t['max_points'] as int?;
    final multiplier = t['multiplier'] ?? t['point_multiplier'];
    final color = _tierColorFor(tierName);

    return Container(
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(14)),
        border: Border.all(color: color.withAlpha(isDark ? 60 : 40)),
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 16, offset: const Offset(0, 2)),
          BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 6, offset: const Offset(0, 1)),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: color.withAlpha(isDark ? 30 : 15),
            borderRadius: BorderRadius.circular(Brand.r(12)),
          ),
          child: Center(
            child: Text(tierName[0],
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tierName,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
            const SizedBox(height: 3),
            Text(
              maxPts != null
                  ? '$minPts – $maxPts pts • ${multiplier}x multiplier'
                  : '$minPts+ pts • ${multiplier}x multiplier',
              style: TextStyle(fontSize: 12, color: AdminColors.textHint(context)),
            ),
          ]),
        ),
        IconButton(
          icon: Icon(Icons.edit_rounded, size: 18, color: color),
          onPressed: () => _editThreshold(t),
        ),
      ]),
    );
  }

  Widget _buildBenefitsTab(bool isDark) {
    // Group benefits by tier
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final b in _benefits) {
      final tier = b['tier'] as String? ?? 'Other';
      grouped.putIfAbsent(tier, () => []).add(b);
    }
    final tierOrder = ['Bronze', 'Silver', 'Gold', 'Platinum'];

    return _loadingBenefits
        ? const Center(child: CircularProgressIndicator(color: _tierColor))
        : RefreshIndicator(
            onRefresh: _loadBenefits, color: _tierColor,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: tierOrder.where((t) => grouped.containsKey(t)).expand((tier) {
                final items = grouped[tier]!;
                final color = _tierColorFor(tier);
                return [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Container(
                        width: 4, height: 16,
                        decoration: BoxDecoration(
                            color: color, borderRadius: BorderRadius.circular(Brand.r(2))),
                      ),
                      const SizedBox(width: 8),
                      Text(tier,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                              color: color)),
                      const SizedBox(width: 8),
                      Text('(${items.length} benefits)',
                          style: TextStyle(fontSize: 11, color: AdminColors.textHint(context))),
                    ]),
                  ),
                  ...items.map((b) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildBenefitCard(b, isDark, color),
                      )),
                  const SizedBox(height: 12),
                ];
              }).toList(),
            ),
          );
  }

  Widget _buildBenefitCard(Map<String, dynamic> b, bool isDark, Color color) {
    final isActive = b['is_active'] as bool? ?? true;
    final desc = b['benefit_description'] as String? ?? '—';
    final benefitType = b['benefit_type'] as String?;

    return Container(
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(12)),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 10, offset: const Offset(0, 1)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? color : AdminColors.textSecondary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(desc,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: isActive
                        ? (isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)
                        : AdminColors.textHint(context))),
            if (benefitType != null) ...[
              const SizedBox(height: 2),
              Text(_cap(benefitType),
                  style: TextStyle(fontSize: 11, color: AdminColors.textHint(context))),
            ],
          ]),
        ),
        IconButton(
          icon: Icon(Icons.edit_rounded, size: 16, color: AdminColors.textHint(context)),
          onPressed: () => _editBenefit(b),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        ),
      ]),
    );
  }

  Color _tierColorFor(String name) => TierColors.forTier(name);

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ─── Threshold Edit Dialog ─────────────────────────────────────────────────────

class _ThresholdEditDialog extends StatefulWidget {
  final Map<String, dynamic> threshold;
  const _ThresholdEditDialog({required this.threshold});

  @override
  State<_ThresholdEditDialog> createState() => _ThresholdEditDialogState();
}

class _ThresholdEditDialogState extends State<_ThresholdEditDialog> {
  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  final _multiplierCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _minCtrl.text = (widget.threshold['min_points'] ?? '').toString();
    _maxCtrl.text = (widget.threshold['max_points'] ?? '').toString();
    final mult = widget.threshold['multiplier'] ?? widget.threshold['point_multiplier'];
    _multiplierCtrl.text = (mult ?? '').toString();
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    _multiplierCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tier = widget.threshold['tier'] ?? 'Tier';
    return AlertDialog(
      title: Text('Edit $tier Threshold'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _minCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Min Points', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _maxCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Max Points (empty = unlimited)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _multiplierCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Point Multiplier', border: OutlineInputBorder(),
                hintText: 'e.g. 1.5'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, {
            'min_points': int.tryParse(_minCtrl.text) ?? 0,
            'max_points': _maxCtrl.text.isEmpty ? null : int.tryParse(_maxCtrl.text),
            'multiplier': double.tryParse(_multiplierCtrl.text) ?? 1.0,
          }),
          style: ElevatedButton.styleFrom(
              backgroundColor: _tierColor, foregroundColor: Colors.white),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ─── Benefit Edit Dialog ───────────────────────────────────────────────────────

class _BenefitEditDialog extends StatefulWidget {
  final Map<String, dynamic> benefit;
  const _BenefitEditDialog({required this.benefit});

  @override
  State<_BenefitEditDialog> createState() => _BenefitEditDialogState();
}

class _BenefitEditDialogState extends State<_BenefitEditDialog> {
  final _descCtrl = TextEditingController();
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    _descCtrl.text = widget.benefit['benefit_description'] as String? ?? '';
    _isActive = widget.benefit['is_active'] as bool? ?? true;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Benefit'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _descCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
              labelText: 'Description', border: OutlineInputBorder(),
              alignLabelWithHint: true),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Active'),
          value: _isActive,
          onChanged: (v) => setState(() => _isActive = v),
          activeThumbColor: _tierColor,
          contentPadding: EdgeInsets.zero,
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, {
            'benefit_description': _descCtrl.text.trim(),
            'is_active': _isActive,
          }),
          style: ElevatedButton.styleFrom(
              backgroundColor: _tierColor, foregroundColor: Colors.white),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
