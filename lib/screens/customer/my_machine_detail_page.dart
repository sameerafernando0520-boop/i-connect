// ============================================================
// FILE: lib/screens/customer/my_machine_detail_page.dart
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../widgets/common/ic_icons.dart';

class MyMachineDetailPage extends StatefulWidget {
  final Map<String, dynamic> machine;
  const MyMachineDetailPage({super.key, required this.machine});

  @override
  State<MyMachineDetailPage> createState() => _MyMachineDetailPageState();
}

class _MyMachineDetailPageState extends State<MyMachineDetailPage>
    with SingleTickerProviderStateMixin {
  late Map<String, dynamic> _machine;
  late TabController _tabController;

  bool _isSaving = false;
  bool _isEditingNickname = false;
  final _nicknameCtrl = TextEditingController();
  int _currentImageIndex = 0;

  @override
  void initState() {
    super.initState();
    _machine = Map<String, dynamic>.from(widget.machine);
    _tabController = TabController(length: 3, vsync: this);
    final nickname = _machine['machine_nickname'];
    if (nickname != null) {
      _nicknameCtrl.text = nickname.toString();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nicknameCtrl.dispose();
    super.dispose();
  }

  // ─── DATA HELPERS ─────────────────────────────────────────

  Map<String, dynamic> get _catalog =>
      (_machine['machine_catalog'] as Map<String, dynamic>?) ?? {};

  String get _machineName =>
      _catalog['machine_name']?.toString() ?? 'Unknown Machine';

  String get _brand => _catalog['brand']?.toString() ?? '';

  String get _model => _catalog['model_number']?.toString() ?? '';

  String get _category => _catalog['category']?.toString() ?? '';

  String get _subCategory => _catalog['sub_category']?.toString() ?? '';

  String? get _description => _catalog['description']?.toString();

  List<String> get _images {
    final imgs = _catalog['images'];
    if (imgs is List && imgs.isNotEmpty) {
      return imgs.map((e) => e.toString()).toList();
    }
    final url = _catalog['image_url']?.toString();
    if (url != null && url.isNotEmpty) return [url];
    return [];
  }

  Map<String, dynamic> get _specifications {
    final specs = _catalog['specifications'];
    if (specs is Map) return Map<String, dynamic>.from(specs);
    return {};
  }

  String get _serialNumber => _machine['serial_number']?.toString() ?? 'N/A';

  String get _status => (_machine['status'] ?? 'active').toString();

  String? get _purchaseDate => _machine['purchase_date']?.toString();

  String? get _warrantyDate =>
      (_machine['warranty_end_date'] ?? _machine['warranty_expiry'])
          ?.toString();

  String? get _nextServiceDue => _machine['next_service_due']?.toString();

  String? get _installationAddress =>
      _machine['installation_address']?.toString();

  String? get _nickname => _machine['machine_nickname']?.toString();

  bool get _isFavorite => _machine['is_favorite'] == true;

  bool get _warrantyValid {
    if (_warrantyDate == null) return false;
    try {
      return DateTime.parse(_warrantyDate!).isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  int get _warrantyDaysLeft {
    if (_warrantyDate == null) return 0;
    try {
      return DateTime.parse(_warrantyDate!).difference(DateTime.now()).inDays;
    } catch (_) {
      return 0;
    }
  }

  double get _warrantyProgress {
    if (_purchaseDate == null || _warrantyDate == null) return 0;
    try {
      final start = DateTime.parse(_purchaseDate!);
      final end = DateTime.parse(_warrantyDate!);
      final now = DateTime.now();
      final total = end.difference(start).inDays;
      final elapsed = now.difference(start).inDays;
      if (total <= 0) return 0;
      return (elapsed / total).clamp(0.0, 1.0);
    } catch (_) {
      return 0;
    }
  }

  int? get _serviceDaysLeft {
    if (_nextServiceDue == null) return null;
    try {
      return DateTime.parse(_nextServiceDue!).difference(DateTime.now()).inDays;
    } catch (_) {
      return null;
    }
  }

  // ─── HELPERS ──────────────────────────────────────────────

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      final dt = DateTime.parse(dateStr);
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }

  Color _statusColor(String status, bool isDark) {
    switch (status) {
      case 'active':
        return isDark ? Brand.lightGreenBright : Brand.lightGreen;
      case 'service':
        return isDark ? const Color(0xFFFFB74D) : const Color(0xFFFF9800);
      case 'inactive':
        return isDark ? const Color(0xFFFF6B6B) : const Color(0xFFE53935);
      default:
        return isDark ? Brand.darkTextSecondary : Colors.grey;
    }
  }

  IconData _categoryIcon(String? cat) {
    switch (cat) {
      case 'Digital Printers':
        return Icons.print_rounded;
      case 'CNC Routers':
        return Icons.precision_manufacturing_rounded;
      case 'Laser Cutters':
        return Icons.content_cut_rounded;
      case 'Finishing Equipment':
        return Icons.construction_rounded;
      default:
        return Icons.settings_suggest_rounded;
    }
  }

  // ─── ACTIONS ──────────────────────────────────────────────

  Future<void> _toggleFavorite() async {
    HapticFeedback.lightImpact();
    final newVal = !_isFavorite;
    setState(() => _machine['is_favorite'] = newVal);
    try {
      await SupabaseConfig.client.from('customer_machines').update({
        'is_favorite': newVal,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _machine['id']);
      if (mounted) {
        _showSnack(
          newVal ? 'Added to favorites' : 'Removed from favorites',
          isSuccess: true,
        );
      }
    } catch (e) {
      setState(() => _machine['is_favorite'] = !newVal);
      if (mounted) _showSnack('Failed to update favorite');
    }
  }

  Future<void> _saveNickname() async {
    final val = _nicknameCtrl.text.trim();
    setState(() => _isSaving = true);
    try {
      await SupabaseConfig.client.from('customer_machines').update({
        'machine_nickname': val.isEmpty ? null : val,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _machine['id']);
      setState(() {
        _machine['machine_nickname'] = val.isEmpty ? null : val;
        _isEditingNickname = false;
        _isSaving = false;
      });
      if (mounted) _showSnack('Nickname updated', isSuccess: true);
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) _showSnack('Failed to save nickname');
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    try {
      await SupabaseConfig.client.from('customer_machines').update({
        'status': newStatus,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _machine['id']);
      setState(() => _machine['status'] = newStatus);
      if (mounted) {
        _showSnack('Status updated to ${newStatus.toUpperCase()}',
            isSuccess: true);
      }
    } catch (e) {
      if (mounted) _showSnack('Failed to update status');
    }
  }

  void _showSnack(String msg, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          isSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          color: Colors.white,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: isSuccess ? Brand.lightGreen : const Color(0xFFE53935),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ─── BUILD ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = _statusColor(_status, isDark);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? SystemUiOverlayStyle.light
              .copyWith(statusBarColor: Colors.transparent)
          : SystemUiOverlayStyle.dark
              .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: isDark ? Brand.darkBg : Brand.scaffoldLight,
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            _buildSliverAppBar(isDark, statusColor),
          ],
          body: Column(children: [
            _buildTabBar(isDark),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(isDark),
                  _buildSpecsTab(isDark),
                  _buildServiceTab(isDark),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ─── SLIVER APP BAR ───────────────────────────────────────

  Widget _buildSliverAppBar(bool isDark, Color statusColor) {
    return SliverAppBar(
      expandedHeight: _images.isEmpty ? 200 : 280,
      pinned: true,
      backgroundColor: isDark ? Brand.darkCard : Brand.cardLight,
      surfaceTintColor: Colors.transparent,
      leading: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.pop(context),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark
                  ? Brand.darkCard.withAlpha(204)
                  : Colors.white.withAlpha(230),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark),
          ),
        ),
      ),
      actions: [
        // Favorite button
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _toggleFavorite,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark
                    ? Brand.darkCard.withAlpha(204)
                    : Colors.white.withAlpha(230),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                color: _isFavorite
                    ? const Color(0xFFFF9800)
                    : (isDark ? Brand.darkTextSecondary : Brand.subtleLight),
                size: 20,
              ),
            ),
          ),
        ),
        // More options
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showOptions(isDark),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 8, right: 12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark
                    ? Brand.darkCard.withAlpha(204)
                    : Colors.white.withAlpha(230),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.more_vert_rounded,
                  size: 20,
                  color:
                      isDark ? Brand.darkTextSecondary : Brand.royalBlueDark),
            ),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: _buildHeroSection(isDark, statusColor),
      ),
    );
  }

  Widget _buildHeroSection(bool isDark, Color statusColor) {
    return Stack(
      children: [
        // Image / gradient background
        if (_images.isNotEmpty)
          PageView.builder(
            itemCount: _images.length,
            onPageChanged: (i) => setState(() => _currentImageIndex = i),
            itemBuilder: (_, i) => CachedNetworkImage(
              imageUrl: _images[i],
              fit: BoxFit.cover,
              width: double.infinity,
              placeholder: (_, __) => Container(
                color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
                child: Center(
                  child: Icon(_categoryIcon(_category),
                      size: 60,
                      color: isDark
                          ? Brand.darkIconActive.withAlpha(77)
                          : Brand.royalBlue.withAlpha(51)),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
                child: Center(
                  child: Icon(_categoryIcon(_category),
                      size: 60,
                      color: isDark
                          ? Brand.darkIconActive.withAlpha(77)
                          : Brand.royalBlue.withAlpha(51)),
                ),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [Brand.darkCardElevated, Brand.darkCard]
                    : [Brand.royalBlueSurface, Brand.cardLight],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Center(
              child: Icon(
                _categoryIcon(_category),
                size: 80,
                color: isDark
                    ? Brand.darkIconActive.withAlpha(64)
                    : Brand.royalBlue.withAlpha(51),
              ),
            ),
          ),

        // Bottom gradient overlay
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  (isDark ? Brand.darkBg : Brand.scaffoldLight)
                      .withAlpha(242),
                ],
              ),
            ),
          ),
        ),

        // Machine name + status at bottom
        Positioned(
          bottom: 16,
          left: 20,
          right: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Brand + category chips
              Row(children: [
                if (_brand.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Brand.darkIconActive.withAlpha(38)
                          : Brand.royalBlue.withAlpha(26),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_brand,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color:
                              isDark ? Brand.darkIconActive : Brand.royalBlue,
                        )),
                  ),
                if (_subCategory.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(51),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_subCategory,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        )),
                  ),
                ],
                const Spacer(),
                // Status badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                          color: statusColor.withAlpha(102),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      Text(_status.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          )),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              // Machine name / nickname
              if (_nickname != null && _nickname!.isNotEmpty)
                Text(_nickname!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                    )),
              Text(
                _machineName,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  letterSpacing: -0.5,
                  height: 1.2,
                ),
              ),
              if (_model.isNotEmpty)
                Text(_model,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      fontWeight: FontWeight.w500,
                    )),
            ],
          ),
        ),

        // Image pagination dots
        if (_images.length > 1)
          Positioned(
            bottom: 90,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _images.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _currentImageIndex ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _currentImageIndex
                        ? Colors.white
                        : Colors.white.withAlpha(102),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── TAB BAR ──────────────────────────────────────────────

  Widget _buildTabBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(14),
         border: isDark
         ? Border.all(color: Brand.darkBorder) : null,
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: LinearGradient(
              colors: isDark
                  ? [Brand.darkIconActive, Brand.royalBlueGlow]
                  : [Brand.royalBlue, Brand.royalBlueLight]),
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(3),
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor:
            isDark ? Brand.darkTextSecondary : Brand.subtleLight,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(text: 'Overview'),
          Tab(text: 'Specs'),
          Tab(text: 'Service'),
        ],
      ),
    );
  }

  // ─── OVERVIEW TAB ─────────────────────────────────────────

  Widget _buildOverviewTab(bool isDark) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        // ── Quick stats row ──
        _buildQuickStats(isDark),
        const SizedBox(height: 20),

        // ── Nickname editor ──
        _buildNicknameCard(isDark),
        const SizedBox(height: 14),

        // ── Machine details card ──
        _buildDetailCard('Machine Details', isDark, [
          _detailRow(
              Icons.qr_code_rounded, 'Serial Number', _serialNumber, isDark),
          _detailRow(Icons.calendar_today_rounded, 'Purchase Date',
              _formatDate(_purchaseDate), isDark),
          if (_installationAddress != null && _installationAddress!.isNotEmpty)
            _detailRow(Icons.location_on_rounded, 'Installation Address',
                _installationAddress!, isDark),
          _detailRow(Icons.category_rounded, 'Category', _category, isDark),
          if (_subCategory.isNotEmpty)
            _detailRow(
                Icons.label_rounded, 'Sub-Category', _subCategory, isDark),
        ]),
        const SizedBox(height: 14),

        // ── Warranty card ──
        _buildWarrantyCard(isDark),

        // ── Description ──
        if (_description != null && _description!.isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildDescriptionCard(isDark),
        ],
      ],
    );
  }

  Widget _buildQuickStats(bool isDark) {
    final svcDays = _serviceDaysLeft;
    final svcColor = svcDays == null
        ? (isDark ? Brand.darkTextSecondary : Colors.grey)
        : svcDays < 0
            ? (isDark ? const Color(0xFFFF6B6B) : const Color(0xFFE53935))
            : svcDays <= 7
                ? (isDark ? const Color(0xFFFFB74D) : const Color(0xFFFF9800))
                : (isDark ? Brand.lightGreenBright : Brand.lightGreen);

    return Row(children: [
      _statCard(
        icon: Icons.verified_user_rounded,
        label: 'Warranty',
        value: _warrantyDate == null
            ? 'N/A'
            : _warrantyValid
                ? '${_warrantyDaysLeft}d left'
                : 'Expired',
        color: _warrantyDate == null
            ? (isDark ? Brand.darkTextSecondary : Colors.grey)
            : _warrantyValid
                ? (isDark ? Brand.lightGreenBright : Brand.lightGreen)
                : (isDark ? const Color(0xFFFF6B6B) : const Color(0xFFE53935)),
        isDark: isDark,
      ),
      const SizedBox(width: 10),
      _statCard(
        icon: Icons.build_circle_rounded,
        label: 'Next Service',
        value: svcDays == null
            ? 'Not set'
            : svcDays < 0
                ? 'Overdue'
                : '${svcDays}d',
        color: svcColor,
        isDark: isDark,
      ),
      const SizedBox(width: 10),
      _statCard(
        icon: Icons.star_rounded,
        label: 'Favorite',
        value: _isFavorite ? 'Yes' : 'No',
        color: _isFavorite
            ? const Color(0xFFFF9800)
            : (isDark ? Brand.darkTextSecondary : Colors.grey),
        isDark: isDark,
      ),
    ]);
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Brand.cardLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isDark ? Brand.darkBorder : color.withAlpha(26)),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                      color: color.withAlpha(15),
                      blurRadius: 10,
                      offset: const Offset(0, 3))
                ],
        ),
        child: Column(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withAlpha(((isDark ? 0.12 : 0.08) * 255).toInt()),
              borderRadius: BorderRadius.circular(11),
              border:
                  isDark ? Border.all(color: color.withAlpha(38)) : null,
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              )),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                fontWeight: FontWeight.w600,
              )),
        ]),
      ),
    );
  }

  Widget _buildNicknameCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(18),
         border: isDark
         ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Brand.royalBlue.withAlpha(10),
                    blurRadius: 10,
                    offset: const Offset(0, 3))
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.badge_rounded,
                size: 16,
                color: isDark ? Brand.darkIconActive : Brand.royalBlue),
            const SizedBox(width: 8),
            Text('Machine Nickname',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                )),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() {
                _isEditingNickname = !_isEditingNickname;
                if (_isEditingNickname && _nickname != null) {
                  _nicknameCtrl.text = _nickname!;
                }
              }),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? Brand.darkIconActive.withAlpha(26)
                      : Brand.royalBlue.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _isEditingNickname ? 'Cancel' : 'Edit',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          if (_isEditingNickname) ...[
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _nicknameCtrl,
                  autofocus: true,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. Office Printer, Workshop CNC...',
                    hintStyle: TextStyle(
                        color:
                            isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                        fontSize: 13),
                    filled: true,
                    fillColor: isDark
                        ? Brand.darkCardElevated
                        : Brand.royalBlueSurface,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: isDark ? Brand.darkBorder : Brand.borderLight),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: isDark ? Brand.darkBorder : Brand.borderLight),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color:
                              isDark ? Brand.darkIconActive : Brand.royalBlue,
                          width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _isSaving ? null : _saveNickname,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: isDark
                            ? [Brand.darkIconActive, Brand.royalBlueGlow]
                            : [Brand.royalBlue, Brand.royalBlueLight]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: Brand.royalBlue.withAlpha(77),
                          blurRadius: 8,
                          offset: const Offset(0, 3))
                    ],
                  ),
                  child: _isSaving
                      ? const Center(
                          child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2)))
                      : const Icon(Icons.check_rounded,
                          color: Colors.white, size: 20),
                ),
              ),
            ]),
          ] else
            Text(
              _nickname != null && _nickname!.isNotEmpty
                  ? _nickname!
                  : 'No nickname set — tap Edit to add one',
              style: TextStyle(
                fontSize: 14,
                fontWeight: _nickname != null && _nickname!.isNotEmpty
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: _nickname != null && _nickname!.isNotEmpty
                    ? (isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)
                    : (isDark ? Brand.darkTextTertiary : Brand.subtleLight),
                fontStyle: _nickname != null && _nickname!.isNotEmpty
                    ? FontStyle.normal
                    : FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWarrantyCard(bool isDark) {
    if (_warrantyDate == null) return const SizedBox.shrink();

    final warrantyColor = _warrantyValid
        ? (isDark ? Brand.lightGreenBright : Brand.lightGreen)
        : (isDark ? const Color(0xFFFF6B6B) : const Color(0xFFE53935));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: warrantyColor.withAlpha(((isDark ? 0.2 : 0.15) * 255).toInt())),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: warrantyColor.withAlpha(15),
                    blurRadius: 10,
                    offset: const Offset(0, 3))
              ],
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: warrantyColor.withAlpha(((isDark ? 0.12 : 0.08) * 255).toInt()),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.verified_user_rounded,
                color: warrantyColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _warrantyValid ? 'Warranty Active' : 'Warranty Expired',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: warrantyColor,
                  ),
                ),
                Text(
                  _warrantyValid
                      ? 'Expires ${_formatDate(_warrantyDate)} · $_warrantyDaysLeft days left'
                      : 'Expired on ${_formatDate(_warrantyDate)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ]),
        if (_warrantyValid) ...[
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: _warrantyProgress,
              minHeight: 6,
              backgroundColor: isDark
                  ? Brand.darkBorderLight.withAlpha(77)
                  : Brand.subtleLight.withAlpha(26),
              valueColor: AlwaysStoppedAnimation<Color>(
                _warrantyDaysLeft <= 30
                    ? (isDark
                        ? const Color(0xFFFFB74D)
                        : const Color(0xFFFF9800))
                    : warrantyColor,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Purchase date',
                style: TextStyle(
                    fontSize: 11,
                    color:
                        isDark ? Brand.darkTextTertiary : Brand.subtleLight)),
            Text('Expiry date',
                style: TextStyle(
                    fontSize: 11,
                    color:
                        isDark ? Brand.darkTextTertiary : Brand.subtleLight)),
          ]),
        ],
      ]),
    );
  }

  Widget _buildDescriptionCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(18),
         border: isDark
         ? Border.all(color: Brand.darkBorder) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.description_rounded,
              size: 16, color: isDark ? Brand.darkIconActive : Brand.royalBlue),
          const SizedBox(width: 8),
          Text('About this machine',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              )),
        ]),
        const SizedBox(height: 10),
        Text(_description!,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              height: 1.6,
            )),
      ]),
    );
  }

  Widget _buildDetailCard(String title, bool isDark, List<Widget> rows) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(18),
         border: isDark
         ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Brand.royalBlue.withAlpha(10),
                    blurRadius: 10,
                    offset: const Offset(0, 3))
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                letterSpacing: 0.3,
              )),
          const SizedBox(height: 12),
          ...rows,
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isDark
                ? Brand.darkIconActive.withAlpha(20)
                : Brand.royalBlue.withAlpha(15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon,
              size: 16, color: isDark ? Brand.darkIconActive : Brand.royalBlue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                  fontWeight: FontWeight.w500,
                )),
            const SizedBox(height: 1),
            Text(value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                )),
          ]),
        ),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: value));
            _showSnack('Copied: $value', isSuccess: true);
          },
          child: Icon(Icons.copy_rounded,
              size: 15,
              color: isDark
                  ? Brand.darkTextTertiary
                  : Brand.subtleLight.withAlpha(128)),
        ),
      ]),
    );
  }

  // ─── SPECS TAB ────────────────────────────────────────────

  Widget _buildSpecsTab(bool isDark) {
    final specs = _specifications;

    if (specs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(Icons.list_alt_rounded,
                  size: 34,
                  color: isDark ? Brand.darkIconActive : Brand.royalBlue),
            ),
            const SizedBox(height: 16),
            Text('No specifications available',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color:
                        isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
            const SizedBox(height: 6),
            Text('Specifications will appear here when available',
                style: TextStyle(
                    fontSize: 12,
                    color:
                        isDark ? Brand.darkTextSecondary : Brand.subtleLight)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        Container(
          decoration: BoxDecoration(
            color: isDark ? Brand.darkCard : Brand.cardLight,
            borderRadius: BorderRadius.circular(18),
            border: isDark ? Border.all(color: Brand.darkBorder) : null,
          ),
          child: Column(
            children: specs.entries.toList().asMap().entries.map((e) {
              final i = e.key;
              final entry = e.value;
              final isLast = i == specs.length - 1;
              final label = entry.key
                  .toString()
                  .replaceAll('_', ' ')
                  .split(' ')
                  .map((w) =>
                      w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
                  .join(' ');

              return Column(children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(label,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight,
                              fontWeight: FontWeight.w500,
                            )),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: Text(
                          entry.value?.toString() ?? 'N/A',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Brand.darkTextPrimary
                                : Brand.royalBlueDark,
                          ),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Divider(
                      height: 1,
                      color: isDark ? Brand.darkBorder : Brand.borderLight,
                      indent: 16,
                      endIndent: 16),
              ]);
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ─── SERVICE TAB ──────────────────────────────────────────

  Widget _buildServiceTab(bool isDark) {
    final svcDays = _serviceDaysLeft;
    final isOverdue = svcDays != null && svcDays < 0;
    final isDueSoon = svcDays != null && svcDays >= 0 && svcDays <= 7;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        // ── Next service card ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? Brand.darkCard : Brand.cardLight,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isOverdue
                  ? (isDark
                      ? const Color(0xFFFF6B6B).withAlpha(77)
                      : const Color(0xFFE53935).withAlpha(51))
                  : isDueSoon
                      ? (isDark
                          ? const Color(0xFFFFB74D).withAlpha(77)
                          : const Color(0xFFFF9800).withAlpha(51))
                      : (isDark ? Brand.darkBorder : Brand.borderLight),
            ),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (isOverdue
                          ? (isDark
                              ? const Color(0xFFFF6B6B)
                              : const Color(0xFFE53935))
                          : isDueSoon
                              ? (isDark
                                  ? const Color(0xFFFFB74D)
                                  : const Color(0xFFFF9800))
                              : (isDark
                                  ? Brand.lightGreenBright
                                  : Brand.lightGreen))
                      .withAlpha(((isDark ? 0.12 : 0.08) * 255).toInt()),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  isOverdue ? Icons.error_rounded : Icons.build_circle_rounded,
                  size: 22,
                  color: isOverdue
                      ? (isDark
                          ? const Color(0xFFFF6B6B)
                          : const Color(0xFFE53935))
                      : isDueSoon
                          ? (isDark
                              ? const Color(0xFFFFB74D)
                              : const Color(0xFFFF9800))
                          : (isDark
                              ? Brand.lightGreenBright
                              : Brand.lightGreen),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOverdue
                            ? 'Service Overdue!'
                            : isDueSoon
                                ? 'Service Due Soon'
                                : 'Next Service',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isOverdue
                              ? (isDark
                                  ? const Color(0xFFFF6B6B)
                                  : const Color(0xFFE53935))
                              : isDueSoon
                                  ? (isDark
                                      ? const Color(0xFFFFB74D)
                                      : const Color(0xFFFF9800))
                                  : (isDark
                                      ? Brand.darkTextPrimary
                                      : Brand.royalBlueDark),
                        ),
                      ),
                      Text(
                        _nextServiceDue == null
                            ? 'No service date scheduled'
                            : isOverdue
                                ? 'Was due ${_formatDate(_nextServiceDue)} (${svcDays.abs()} days ago)'
                                : 'Scheduled for ${_formatDate(_nextServiceDue)}${svcDays != null ? ' · ${svcDays}d' : ''}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ]),
              ),
            ]),
          ]),
        ),

        const SizedBox(height: 14),

        // ── Status update card ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? Brand.darkCard : Brand.cardLight,
            borderRadius: BorderRadius.circular(18),
            border: isDark ? Border.all(color: Brand.darkBorder) : null,
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Update Status',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  letterSpacing: 0.3,
                )),
            const SizedBox(height: 12),
            Row(children: [
              _statusBtn(
                  'active', 'Active', Icons.check_circle_rounded, isDark),
              const SizedBox(width: 8),
              _statusBtn('service', 'In Service', Icons.build_rounded, isDark),
              const SizedBox(width: 8),
              _statusBtn('inactive', 'Inactive', Icons.cancel_rounded, isDark),
            ]),
          ]),
        ),

        const SizedBox(height: 14),

        // ── Support CTA ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [Brand.darkCard, Brand.darkCardElevated]
                  : [Brand.royalBlueDark, Brand.royalBlue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                        color: Brand.royalBlue.withAlpha(77),
                        blurRadius: 14,
                        offset: const Offset(0, 5))
                  ],
            border: isDark ? Border.all(color: Brand.darkBorderLight) : null,
          ),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isDark
                    ? Brand.darkIconActive.withAlpha(31)
                    : Colors.white.withAlpha(38),
                borderRadius: BorderRadius.circular(14),
              ),
              child: IcChatGearIcon(
                  size: 24,
                  color: isDark ? Brand.darkIconActive : Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Need Support?',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Brand.darkTextPrimary : Colors.white,
                        )),
                    Text('Contact iFrontiers for service assistance',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Colors.white.withAlpha(179),
                          fontWeight: FontWeight.w500,
                        )),
                  ]),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 16,
                color: isDark
                    ? Brand.darkTextTertiary
                    : Colors.white.withAlpha(153)),
          ]),
        ),
      ],
    );
  }

  Widget _statusBtn(String status, String label, IconData icon, bool isDark) {
    final isSelected = _status == status;
    final color = _statusColor(status, isDark);

    return Expanded(
      child: GestureDetector(
        onTap: () => _updateStatus(status),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? color
                : (isDark ? Brand.darkCardElevated : Brand.scaffoldLight),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? color
                  : (isDark ? Brand.darkBorder : Brand.borderLight),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                        color: color.withAlpha(77),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ]
                : null,
          ),
          child: Column(children: [
            Icon(icon, size: 18, color: isSelected ? Colors.white : color),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Brand.darkTextSecondary : Brand.subtleLight),
                )),
          ]),
        ),
      ),
    );
  }

  // ─── OPTIONS SHEET ────────────────────────────────────────

  void _showOptions(bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Brand.darkCard : Brand.cardLight,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? Brand.darkTextTertiary
                    : Brand.subtleLight.withAlpha(77),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _optionItem(
            icon: _isFavorite ? Icons.star_border_rounded : Icons.star_rounded,
            label: _isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
            color: const Color(0xFFFF9800),
            isDark: isDark,
            onTap: () {
              Navigator.pop(ctx);
              _toggleFavorite();
            },
          ),
          _optionItem(
            icon: Icons.edit_rounded,
            label: 'Edit Nickname',
            color: isDark ? Brand.darkIconActive : Brand.royalBlue,
            isDark: isDark,
            onTap: () {
              Navigator.pop(ctx);
              setState(() {
                _isEditingNickname = true;
                _tabController.animateTo(0);
              });
            },
          ),
          _optionItem(
            icon: Icons.copy_rounded,
            label: 'Copy Serial Number',
            color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            isDark: isDark,
            onTap: () {
              Clipboard.setData(ClipboardData(text: _serialNumber));
              Navigator.pop(ctx);
              _showSnack('Copied: $_serialNumber', isSuccess: true);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _optionItem({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withAlpha(((isDark ? 0.1 : 0.08) * 255).toInt()),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              fontSize: 14)),
      trailing: Icon(Icons.arrow_forward_ios_rounded,
          size: 14,
          color: isDark
              ? Brand.darkTextTertiary
              : Brand.subtleLight.withAlpha(102)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
