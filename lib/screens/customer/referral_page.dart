// ═══════════════════════════════════════════════════════════════
// FILE: lib/screens/customer/referral_page.dart
// Refer & Earn — Customer referral program page
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../l10n/s.dart';
import '../../utils/time_utils.dart';

class ReferralPage extends StatefulWidget {
  const ReferralPage({super.key});
  @override
  State<ReferralPage> createState() => _ReferralPageState();
}

class _ReferralPageState extends State<ReferralPage> {
  bool _isLoading = true;


  String? _referralCode;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _referrals = [];
  List<Map<String, dynamic>> _commissionRules = [];

  static final _lkrFormat = NumberFormat('#,##0', 'en_US');

  String? get _userId => SupabaseConfig.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final uid = _userId;
    if (uid == null) return;

    setState(() => _isLoading = true);

    try {
      await Future.wait<dynamic>([
        _ensureReferralCode(uid),
        _fetchDashboard(uid),
        _fetchCommissionRules(),
      ]);
    } catch (e) {
      debugPrint('❌ Referral page load error: $e');
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _ensureReferralCode(String userId) async {
    try {
      final result = await SupabaseConfig.client
          .rpc('generate_referral_code', params: {'p_user_id': userId});

      if (!mounted) return;
      if (result is List && result.isNotEmpty) {
        setState(() => _referralCode = result[0]['code'] as String?);
      }
    } catch (e) {
      debugPrint('⚠️ Generate referral code error: $e');
    }
  }

  Future<void> _fetchDashboard(String userId) async {
    try {
      final result = await SupabaseConfig.client
          .rpc('get_referral_dashboard', params: {'p_user_id': userId});

      if (!mounted) return;
      if (result is Map) {
        final data = Map<String, dynamic>.from(result);
        setState(() {
          _referralCode ??= data['code'] as String?;
          _stats = data['stats'] is Map
              ? Map<String, dynamic>.from(data['stats'] as Map)
              : {};
          _referrals = data['referrals'] is List
              ? List<Map<String, dynamic>>.from((data['referrals'] as List)
                  .map((r) => Map<String, dynamic>.from(r as Map)))
              : [];
        });
      }
    } catch (e) {
      debugPrint('⚠️ Referral dashboard error: $e');
    }
  }

  Future<void> _fetchCommissionRules() async {
    try {
      final result = await SupabaseConfig.client
          .from('referral_commission_rules')
          .select()
          .eq('is_active', true)
          .order('priority', ascending: false);

      if (!mounted) return;
      setState(() {
        _commissionRules = List<Map<String, dynamic>>.from(result);
      });
    } catch (e) {
      debugPrint('⚠️ Commission rules error: $e');
    }
  }

  void _copyCode() {
    if (_referralCode == null) return;
    Clipboard.setData(ClipboardData(text: _referralCode!));
    _showSnack('Referral code copied!', icon: Icons.copy_rounded);
  }

  void _shareViaWhatsApp() {
    final msg = _buildShareMessage();
    SharePlus.instance.share(ShareParams(text: msg, subject: 'Join iFrontiers Connect'));
  }

  void _shareViaSMS() {
    final msg = _buildShareMessage();
    SharePlus.instance.share(ShareParams(text: msg, subject: 'iFrontiers Connect Referral'));
  }

  void _showCodeSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Brand.cardLight,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(S.of(context)!.referralMyCode,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                )),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [Brand.darkCardElevated, Brand.darkCard]
                      : [Brand.royalBlueSurface, Colors.white],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: isDark
                        ? Brand.darkBorderLight
                        : Brand.royalBlue.withAlpha(31)),
              ),
              child: Column(
                children: [
                  Icon(Icons.qr_code_2_rounded,
                      size: 80,
                      color: isDark ? Brand.darkIconActive : Brand.royalBlue),
                  const SizedBox(height: 16),
                  Text(
                    _referralCode ?? '---',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Share this code with friends',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _copyCode();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [Brand.darkIconActive, Brand.royalBlueGlow]
                            : [Brand.royalBlue, Brand.royalBlueLight],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                        child: Text(S.of(context)!.referralCopyCode,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700))),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _shareViaWhatsApp();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Brand.lightGreen,
                          Brand.lightGreenBright,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                        child: Text(S.of(context)!.commonShare,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700))),
                  ),
                ),
              ),
            ]),
            SizedBox(height: MediaQuery.of(sheetCtx).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  String _buildShareMessage() {
    return '🏭 I use iFrontiers Connect for all my industrial machinery needs. '
        'Join using my referral code ${_referralCode ?? ''} and we both win — '
        'you get 250 welcome points to start, and I earn a reward when you buy!\n\n'
        'My referral code: ${_referralCode ?? ''}\n'
        'Download: https://play.google.com/store/apps/details?id=com.ifrontiers.iconnect';
  }

  String _formatLKR(dynamic amount) {
    if (amount == null) return 'Rs. 0';
    final val = amount is num
        ? amount.toDouble()
        : double.tryParse(amount.toString()) ?? 0;
    return 'Rs. ${_lkrFormat.format(val)}';
  }

  void _showSnack(String msg, {IconData? icon}) {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        if (icon != null) ...[
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
        ],
        Expanded(
            child:
                Text(msg, style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
      backgroundColor: isDark ? Brand.darkIconActive : Brand.royalBlue,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
    ));
  }

  Color _statusColor(String status, bool isDark) {
    switch (status) {
      case 'signed_up':
        return isDark ? Brand.darkIconActive : Brand.royalBlueLight;
      case 'cooling':
      case 'qualified':
        return isDark ? const Color(0xFFFFB74D) : Colors.orange;
      case 'approved':
      case 'paid':
        return isDark ? Brand.lightGreenBright : Brand.lightGreen;
      case 'expired':
        return isDark ? Brand.darkTextSecondary : Brand.subtleLight;
      case 'rejected':
        return isDark ? const Color(0xFFFF6B6B) : Colors.red;
      default:
        return isDark ? Brand.darkTextSecondary : Brand.subtleLight;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'signed_up':
        return 'Signed Up';
      case 'cooling':
        return 'Qualifying';
      case 'qualified':
        return 'Qualified';
      case 'approved':
        return 'Approved';
      case 'paid':
        return 'Paid';
      case 'expired':
        return 'Expired';
      case 'rejected':
        return 'Declined';
      default:
        return status.toUpperCase();
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'signed_up':
        return Icons.person_add_rounded;
      case 'cooling':
      case 'qualified':
        return Icons.hourglass_top_rounded;
      case 'approved':
      case 'paid':
        return Icons.check_circle_rounded;
      case 'expired':
        return Icons.timer_off_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.circle_rounded;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Brand.darkBg : Brand.scaffoldLight,
      body: _isLoading ? _buildSkeleton(isDark) : _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadAll,
        color: isDark ? Brand.darkIconActive : Brand.royalBlue,
        backgroundColor: isDark ? Brand.darkCard : Colors.white,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(isDark)),
            SliverToBoxAdapter(child: _buildHeroBanner(isDark)),
            SliverToBoxAdapter(child: _buildCodeCard(isDark)),
            SliverToBoxAdapter(child: _buildShareButtons(isDark)),
            SliverToBoxAdapter(child: _buildStatsRow(isDark)),
            if (_commissionRules.isNotEmpty)
              SliverToBoxAdapter(child: _buildCommissionRates(isDark)),
            if (_referrals.isNotEmpty)
              SliverToBoxAdapter(child: _buildReferralsList(isDark)),
            if (_referrals.isEmpty)
              SliverToBoxAdapter(child: _buildEmptyReferrals(isDark)),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  // ─── HEADER ──────────────────────────────────────────────

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 20, 0),
      child: Row(children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCard : Brand.cardLight,
                borderRadius: BorderRadius.circular(14),
                border: isDark ? Border.all(color: Brand.darkBorder) : null,
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  size: 18),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(S.of(context)!.referralReferEarn,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  letterSpacing: -0.5,
                )),
            Text(S.of(context)!.referralTagline,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                )),
          ]),
        ),
      ]),
    );
  }

  // ─── HERO BANNER ─────────────────────────────────────────

  Widget _buildHeroBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: isDark
              ? [Brand.darkCard, Brand.darkCardElevated]
              : [Brand.royalBlueDark, Brand.royalBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: isDark ? Border.all(color: Brand.darkBorderLight) : null,
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(77),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.amber.withAlpha(isDark ? 31 : 46),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.card_giftcard_rounded,
              color: Colors.amber, size: 32),
        ),
        const SizedBox(height: 16),
        Text(S.of(context)!.referralHeroTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: isDark ? Brand.darkTextPrimary : Colors.white,
              height: 1.3,
              letterSpacing: -0.3,
            )),
        const SizedBox(height: 8),
        Text(
          'Your friend gets 250 welcome points — and you earn a reward when they buy.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color:
                isDark ? Brand.darkTextSecondary : Colors.white.withAlpha(179),
          ),
        ),
      ]),
    );
  }

  // ─── CODE CARD ───────────────────────────────────────────

  Widget _buildCodeCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(22),
         border: isDark
         ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Brand.royalBlue.withAlpha(13),
                    blurRadius: 14,
                    offset: const Offset(0, 5))
              ],
      ),
      child: Column(children: [
        Text(S.of(context)!.referralMyCode.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              letterSpacing: 1.0,
            )),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _copyCode,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Brand.darkBorderLight
                    : Brand.royalBlue.withAlpha(31),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    _referralCode ?? 'Generating...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                      letterSpacing: 2.5,
                    ),
                  ),
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Brand.darkIconActive.withAlpha(26)
                        : Brand.royalBlue.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.copy_rounded,
                      color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                      size: 20),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ─── SHARE BUTTONS ───────────────────────────────────────

  Widget _buildShareButtons(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(children: [
        _shareBtn(Icons.message_rounded, 'WhatsApp', const Color(0xFF25D366),
            isDark, _shareViaWhatsApp),
        const SizedBox(width: 10),
        _shareBtn(
            Icons.sms_rounded,
            'SMS',
            isDark ? Brand.darkIconActive : Brand.royalBlue,
            isDark,
            _shareViaSMS),
        const SizedBox(width: 10),
        _shareBtn(
            Icons.copy_rounded,
            'Copy',
            isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            isDark,
            _copyCode),
        const SizedBox(width: 10),
        _shareBtn(
            Icons.qr_code_2_rounded,
            'QR Code',
            isDark ? const Color(0xFFFFB74D) : Colors.orange,
            isDark,
            _showCodeSheet),
      ]),
    );
  }

  Widget _shareBtn(
      IconData icon, String label, Color c, bool isDark, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: c.withAlpha(isDark ? 20 : 15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.withAlpha(isDark ? 38 : 31)),
          ),
          child: Column(children: [
            Icon(icon, color: c, size: 24),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: c)),
          ]),
        ),
      ),
    );
  }

  // ─── STATS ROW ───────────────────────────────────────────

  Widget _buildStatsRow(bool isDark) {
    final totalRefs = (_stats['total_referrals'] as num?)?.toInt() ?? 0;
    final successRefs = (_stats['successful_referrals'] as num?)?.toInt() ?? 0;
    final totalEarned = _stats['total_earned'] ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Row(children: [
        _statCard('Invited', '$totalRefs', Icons.people_rounded,
            isDark ? Brand.darkIconActive : Brand.royalBlue, isDark),
        const SizedBox(width: 10),
        _statCard('Qualified', '$successRefs', Icons.verified_rounded,
            isDark ? Brand.lightGreenBright : Brand.lightGreen, isDark),
        const SizedBox(width: 10),
        _statCard(
            'Earned',
            _formatLKR(totalEarned),
            Icons.account_balance_wallet_rounded,
            isDark ? const Color(0xFFFFB74D) : Colors.orange,
            isDark),
      ]),
    );
  }

  Widget _statCard(
      String label, String value, IconData icon, Color c, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Brand.cardLight,
          borderRadius: BorderRadius.circular(18),
           border: isDark
           ? Border.all(color: Brand.darkBorder) : null,
        ),
        child: Column(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.withAlpha(isDark ? 26 : 20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: c, size: 20),
          ),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              )),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              )),
        ]),
      ),
    );
  }

  // ─── COMMISSION RATES ────────────────────────────────────

  Widget _buildCommissionRates(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
          child: Row(children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [Brand.darkIconActive, Brand.royalBlueGlow]
                      : [Brand.royalBlue, Brand.royalBlueGlow],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text(S.of(context)!.referralCommissionRates,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  letterSpacing: -0.3,
                )),
          ]),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: isDark ? Brand.darkCard : Brand.cardLight,
            borderRadius: BorderRadius.circular(18),
            border: isDark ? Border.all(color: Brand.darkBorder) : null,
          ),
          child: Column(
            children: _commissionRules.asMap().entries.map((entry) {
              final i = entry.key;
              final rule = entry.value;
              final isLast = i == _commissionRules.length - 1;
              final name = rule['name'] ?? rule['category'] ?? 'General';
              final type = rule['commission_type'] ?? 'percentage';
              final value = rule['commission_value'] ?? 0;
              final minPurchase = rule['min_purchase'] ?? 0;
              final rewardKind = rule['reward_kind']?.toString() ?? 'cash';
              final rewardLabel = rule['reward_label']?.toString();

              String rateText;
              if (rewardKind != 'cash' &&
                  rewardLabel != null &&
                  rewardLabel.isNotEmpty) {
                rateText = rewardLabel;
              } else if (type == 'percentage') {
                rateText =
                    '${(value as num).toStringAsFixed(value == (value).toInt() ? 0 : 1)}% of price';
              } else {
                rateText = _formatLKR(value);
              }

              return Column(children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Brand.lightGreen.withAlpha(isDark ? 20 : 15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.percent_rounded,
                          color: Brand.lightGreenBright, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name.toString(),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Brand.darkTextPrimary
                                      : Brand.royalBlueDark,
                                )),
                            if ((minPurchase as num) > 0)
                              Text(S.of(context)!.referralMinPurchase(_formatLKR(minPurchase)),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Brand.darkTextTertiary
                                        : Brand.subtleLight,
                                  )),
                          ]),
                    ),
                    Text(rateText,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Brand.lightGreenBright
                              : Brand.lightGreenDark,
                        )),
                  ]),
                ),
                if (!isLast)
                  Divider(
                      height: 1,
                      color: isDark ? Brand.darkBorder : Brand.borderLight),
              ]);
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ─── REFERRALS LIST ──────────────────────────────────────

  Widget _buildReferralsList(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
          child: Row(children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [Brand.darkIconActive, Brand.royalBlueGlow]
                      : [Brand.royalBlue, Brand.royalBlueGlow],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text(S.of(context)!.referralHistory,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  letterSpacing: -0.3,
                )),
            const Spacer(),
            Text('${_referrals.length}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                )),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: _referrals.map((ref) {
              final status = ref['status'] as String? ?? 'signed_up';
              final name = ref['referred_name'] as String? ?? 'Unknown';

              final commission = ref['commission_amount'];
              final createdAt = ref['created_at'] as String?;
              final sc = _statusColor(status, isDark);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Brand.darkCard : Brand.cardLight,
                    borderRadius: BorderRadius.circular(18),
                    border: isDark ? Border.all(color: Brand.darkBorder) : null,
                  ),
                  child: Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: sc.withAlpha(isDark ? 26 : 20),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(_statusIcon(status), color: sc, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Brand.darkTextPrimary
                                      : Brand.royalBlueDark,
                                )),
                            const SizedBox(height: 2),
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: sc.withAlpha(isDark ? 26 : 18),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(_statusLabel(status),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: sc,
                                      letterSpacing: 0.3,
                                    )),
                              ),
                              if (commission != null) ...[
                                const SizedBox(width: 8),
                                Text(_formatLKR(commission),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Brand.lightGreenBright
                                          : Brand.lightGreenDark,
                                    )),
                              ],
                            ]),
                          ]),
                    ),
                    if (createdAt != null)
                      Text(
                        TimeUtils.getTimeAgo(
                            DateTime.tryParse(createdAt) ?? DateTime.now()),
                        style: TextStyle(
                          fontSize: 11,
                          color:
                              isDark ? Brand.darkTextTertiary : Colors.black38,
                        ),
                      ),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ─── EMPTY STATE ─────────────────────────────────────────

  Widget _buildEmptyReferrals(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(22),
         border: isDark
         ? Border.all(color: Brand.darkBorder) : null,
      ),
      child: Column(children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Icon(Icons.people_outline_rounded,
              size: 36, color: isDark ? Brand.darkIconActive : Brand.royalBlue),
        ),
        const SizedBox(height: 18),
        Text(S.of(context)!.referralNoReferrals,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            )),
        const SizedBox(height: 6),
        Text(S.of(context)!.referralNoReferralsDesc,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            )),
      ]),
    );
  }

  // ─── SKELETON ────────────────────────────────────────────

  Widget _buildSkeleton(bool isDark) {
    Widget sk(double w, double h, double r) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: isDark
                ? Brand.darkBorderLight.withAlpha(77)
                : Brand.royalBlue.withAlpha(13),
            borderRadius: BorderRadius.circular(r),
          ),
        );

    return SafeArea(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              sk(44, 44, 14),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                sk(120, 20, 8),
                const SizedBox(height: 6),
                sk(180, 12, 6),
              ]),
            ]),
            const SizedBox(height: 20),
            sk(double.infinity, 180, 24),
            const SizedBox(height: 20),
            sk(double.infinity, 100, 22),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: sk(double.infinity, 70, 16)),
              const SizedBox(width: 10),
              Expanded(child: sk(double.infinity, 70, 16)),
              const SizedBox(width: 10),
              Expanded(child: sk(double.infinity, 70, 16)),
              const SizedBox(width: 10),
              Expanded(child: sk(double.infinity, 70, 16)),
            ]),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: sk(double.infinity, 120, 18)),
              const SizedBox(width: 10),
              Expanded(child: sk(double.infinity, 120, 18)),
              const SizedBox(width: 10),
              Expanded(child: sk(double.infinity, 120, 18)),
            ]),
            const SizedBox(height: 28),
            sk(150, 18, 8),
            const SizedBox(height: 14),
            sk(double.infinity, 180, 18),
          ],
        ),
      ),
    );
  }
}
