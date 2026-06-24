// lib/screens/customer/catalog_page.dart
//
// ═══════════════════════════════════════════════════════════
//  CHANGES (v13 fix):
//   [FIX-1] Map mutation → spread copy in _fetchMachines
//   [FIX-2] Added price, brochure_url, video_url to select
//   [FIX-3] All withOpacity → withAlpha (deprecated API)
//   [FIX-4] Recently viewed: safe on-demand fetch fallback
//   [FIX-5] Parallelized owned+saved queries in _fetchMachines
//   [FIX-6] Removed redundant _fetchBrands API call
//   [FIX-7] Bottom sheet radius 24 → 28
// ═══════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../l10n/s.dart';
import '../../widgets/ds/ds_widgets.dart';
import 'machine_detail_page.dart';

// ── Custom Icons (private to this file) ──────────────────────
class _LaserIcon extends StatelessWidget {
  final Color color;
  final double size;
  const _LaserIcon({this.color = Brand.royalBlue, this.size = 20});
  @override
  Widget build(BuildContext context) => Semantics(
      label: 'Laser cutter',
      child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _LaserPainter(color: color))));
}

class _LaserPainter extends CustomPainter {
  final Color color;
  const _LaserPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final w = size.width, h = size.height;
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.05, h * 0.08)
          ..lineTo(w * 0.95, h * 0.08)
          ..lineTo(w * 0.85, h * 0.22)
          ..lineTo(w * 0.15, h * 0.22)
          ..close(),
        p);
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.30, h * 0.25)
          ..lineTo(w * 0.70, h * 0.25)
          ..lineTo(w * 0.62, h * 0.36)
          ..lineTo(w * 0.38, h * 0.36)
          ..close(),
        p);
    canvas.drawRect(Rect.fromLTWH(w * 0.40, h * 0.37, w * 0.20, h * 0.13), p);
    canvas.drawRect(Rect.fromLTWH(w * 0.465, h * 0.50, w * 0.07, h * 0.20), p);
    final sp = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeWidth = w * 0.05;
    _s(canvas, sp, Offset(w * 0.20, h * 0.60), Offset(w * 0.32, h * 0.57));
    _s(canvas, sp, Offset(w * 0.17, h * 0.70), Offset(w * 0.32, h * 0.68));
    _s(canvas, sp, Offset(w * 0.80, h * 0.60), Offset(w * 0.68, h * 0.57));
    _s(canvas, sp, Offset(w * 0.83, h * 0.70), Offset(w * 0.68, h * 0.68));
    canvas.drawRect(Rect.fromLTWH(w * 0.05, h * 0.76, w * 0.38, h * 0.16), p);
    canvas.drawRect(Rect.fromLTWH(w * 0.57, h * 0.76, w * 0.38, h * 0.16), p);
  }

  void _s(Canvas c, Paint p, Offset a, Offset b) {
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    final l = math.sqrt(dx * dx + dy * dy);
    final nx = -dy / l * p.strokeWidth / 2, ny = dx / l * p.strokeWidth / 2;
    c.drawPath(
        Path()
          ..moveTo(a.dx + nx, a.dy + ny)
          ..lineTo(b.dx + nx, b.dy + ny)
          ..lineTo(b.dx - nx, b.dy - ny)
          ..lineTo(a.dx - nx, a.dy - ny)
          ..close(),
        p..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_LaserPainter old) => old.color != color;
}

class _CncIcon extends StatelessWidget {
  final Color color;
  final double size;
  const _CncIcon({this.color = Brand.royalBlue, this.size = 20});
  @override
  Widget build(BuildContext context) => Semantics(
      label: 'CNC router',
      child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _CncPainter(color: color))));
}

class _CncPainter extends CustomPainter {
  final Color color;
  const _CncPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final w = size.width, h = size.height;
    final cx = w * 0.38,
        cy = h * 0.54,
        oR = w * 0.30,
        iR = w * 0.19,
        hR = w * 0.07;
    const teeth = 8;
    final gP = Path();
    for (int i = 0; i < teeth; i++) {
      final a1 = (2 * math.pi / teeth) * i - math.pi / 2;
      final a2 = a1 + (2 * math.pi / teeth) * 0.4;
      final a3 = a2 + (2 * math.pi / teeth) * 0.2;
      final a4 = a1 + (2 * math.pi / teeth);
      if (i == 0) {
        gP.moveTo(cx + oR * math.cos(a1), cy + oR * math.sin(a1));
      } else {
        gP.lineTo(cx + oR * math.cos(a1), cy + oR * math.sin(a1));
      }
      gP
        ..lineTo(cx + oR * math.cos(a2), cy + oR * math.sin(a2))
        ..lineTo(cx + iR * math.cos(a3), cy + iR * math.sin(a3))
        ..lineTo(cx + iR * math.cos(a4), cy + iR * math.sin(a4));
    }
    gP.close();
    canvas.drawPath(
        Path.combine(
            PathOperation.difference,
            gP,
            Path()
              ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: hR))),
        p);
    // ✅ FIX-3: withOpacity → withAlpha
    canvas.drawCircle(
        Offset(cx, cy), w * 0.025, Paint()..color = color.withAlpha(89));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.62, h * 0.06, w * 0.32, h * 0.20),
            const Radius.circular(3)),
        p);
    canvas.drawRect(Rect.fromLTWH(w * 0.63, h * 0.14, w * 0.30, h * 0.04),
        Paint()..color = Colors.white.withAlpha(89));
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.62, h * 0.28)
          ..lineTo(w * 0.94, h * 0.28)
          ..lineTo(w * 0.89, h * 0.46)
          ..lineTo(w * 0.67, h * 0.46)
          ..close(),
        p);
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.69, h * 0.47)
          ..lineTo(w * 0.87, h * 0.47)
          ..lineTo(w * 0.78, h * 0.64)
          ..close(),
        p);
  }

  @override
  bool shouldRepaint(_CncPainter old) => old.color != color;
}

// ══════════════════════════════════════════════════════════════
//  CATALOG PAGE
// ══════════════════════════════════════════════════════════════
class CatalogPage extends StatefulWidget {
  final String? initialCategory;
  final String? initialBrand;
  const CatalogPage({super.key, this.initialCategory, this.initialBrand});
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  List<Map<String, dynamic>> _allMachines = [];
  List<Map<String, dynamic>> _filteredMachines = [];
  List<Map<String, dynamic>> _recentlyViewed = [];
  Set<String> _savedMachineIds = {};
  Set<String> _ownedMachineIds = {};

  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  bool _isSearching = false;
  bool _isGridView = true;
  String _selectedCategory = 'All';
  String? _selectedSubCategory;
  String? _selectedBrand;
  String _sortBy = 'default';
  String _searchQuery = '';

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounceTimer;

  final List<String> _categories = [
    'All',
    'Digital Printers',
    'CNC Routers',
    'Laser Cutters',
    'Finishing Equipment',
  ];
  List<String> _subCategories = [];
  List<String> _brands = [];

  final Map<String, String> _sortOptions = {
    'default': 'Default',
    'name_asc': 'Name A-Z',
    'name_desc': 'Name Z-A',
    'brand': 'By Brand',
    'newest': 'Newest First',
  };

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null &&
        _categories.contains(widget.initialCategory)) {
      _selectedCategory = widget.initialCategory!;
    }
    _selectedBrand = widget.initialBrand;
    _loadAllData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  //  DATA
  // ═══════════════════════════════════════════════════════════

  Future<void> _loadAllData() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
      final userId = SupabaseConfig.client.auth.currentUser?.id;

      // ✅ FIX-6: removed _fetchBrands — extracted from loaded machines
      final results = await Future.wait<dynamic>([
        _fetchMachines(userId),
        _fetchRecentlyViewed(userId),
      ]);

      if (!mounted) return;
      setState(() {
        _allMachines = results[0];
        _recentlyViewed = results[1];

        _savedMachineIds = _allMachines
            .where((m) => m['is_saved'] == true)
            .map((m) => m['id'].toString())
            .toSet();
        _ownedMachineIds = _allMachines
            .where((m) => m['is_owned'] == true)
            .map((m) => m['id'].toString())
            .toSet();

        // ✅ FIX-6: extract brands from loaded machines (no extra query)
        _brands = _allMachines
            .map((m) => m['brand'] as String? ?? '')
            .where((b) => b.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

        _updateSubCategories();
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Unable to load catalog. Pull down to retry.';
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchMachines(String? userId) async {
    try {
      // ✅ FIX-2: added price, brochure_url, video_url
      final data = await SupabaseConfig.client
          .from('machine_catalog')
          .select(
              'id, machine_name, model_number, category, sub_category, brand, '
              'description, specifications, features, applications, '
              'price, brochure_url, video_url, '
              'product_images, image_url, images, '
              'is_active, display_order, created_at')
          .eq('is_active', true)
          .order('display_order');

      final machines = List<Map<String, dynamic>>.from(data);

      Set<String> ownedCatalogIds = {};
      Set<String> savedCatalogIds = {};

      // ✅ FIX-5: parallelized owned + saved queries
      if (userId != null) {
        final userResults = await Future.wait<dynamic>([
          SupabaseConfig.client
              .from('customer_machines')
              .select('catalog_machine_id')
              .eq('user_id', userId)
              .then((r) => List<Map<String, dynamic>>.from(r)
                  .map((m) => m['catalog_machine_id']?.toString() ?? '')
                  .where((id) => id.isNotEmpty)
                  .toSet())
              .catchError((_) => <String>{}),
          SupabaseConfig.client
              .from('saved_machines')
              .select('catalog_machine_id')
              .eq('user_id', userId)
              .then((r) => List<Map<String, dynamic>>.from(r)
                  .map((m) => m['catalog_machine_id']?.toString() ?? '')
                  .where((id) => id.isNotEmpty)
                  .toSet())
              .catchError((_) => <String>{}),
        ]);
        ownedCatalogIds = userResults[0];
        savedCatalogIds = userResults[1];
      }

      // ✅ FIX-1: spread copy instead of direct mutation
      return machines.map((m) {
        final id = m['id']?.toString() ?? '';
        return {
          ...m,
          'is_saved': savedCatalogIds.contains(id),
          'is_owned': ownedCatalogIds.contains(id),
        };
      }).toList();
    } catch (e) {
      debugPrint('⚠️ Fetch machines error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRecentlyViewed(
      String? userId) async {
    if (userId == null) return [];
    try {
      final result = await SupabaseConfig.client
          .from('recently_viewed_machines')
          .select('catalog_machine_id, viewed_at, '
              'machine_catalog!inner(id, machine_name, brand, category, product_images)')
          .eq('user_id', userId)
          .order('viewed_at', ascending: false)
          .limit(6);

      return List<Map<String, dynamic>>.from(result).map((r) {
        final catalog = r['machine_catalog'] as Map<String, dynamic>? ?? {};
        final images = catalog['product_images'];
        return {
          'machine_id': catalog['id'],
          'machine_name': catalog['machine_name'],
          'brand': catalog['brand'],
          'category': catalog['category'],
          'product_image':
              (images is List && images.isNotEmpty) ? images[0] : null,
        };
      }).toList();
    } catch (e) {
      debugPrint('⚠️ Recently viewed not available: $e');
      return [];
    }
  }

  void _updateSubCategories() {
    if (_selectedCategory == 'All') {
      _subCategories = [];
      _selectedSubCategory = null;
      return;
    }
    _subCategories = _allMachines
        .where((m) => m['category'] == _selectedCategory)
        .map((m) => m['sub_category'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (_selectedSubCategory != null &&
        !_subCategories.contains(_selectedSubCategory)) {
      _selectedSubCategory = null;
    }
  }

  void _applyFilters() {
    var result = List<Map<String, dynamic>>.from(_allMachines);
    if (_selectedCategory != 'All') {
      result = result.where((m) => m['category'] == _selectedCategory).toList();
    }
    if (_selectedSubCategory != null) {
      result = result
          .where((m) => m['sub_category'] == _selectedSubCategory)
          .toList();
    }
    if (_selectedBrand != null) {
      result = result.where((m) => m['brand'] == _selectedBrand).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((m) {
        final n = (m['machine_name'] ?? '').toString().toLowerCase();
        final mo = (m['model_number'] ?? '').toString().toLowerCase();
        final b = (m['brand'] ?? '').toString().toLowerCase();
        final d = (m['description'] ?? '').toString().toLowerCase();
        final s = (m['sub_category'] ?? '').toString().toLowerCase();
        return n.contains(q) ||
            mo.contains(q) ||
            b.contains(q) ||
            d.contains(q) ||
            s.contains(q);
      }).toList();
    }
    switch (_sortBy) {
      case 'name_asc':
        result.sort((a, b) => (a['machine_name'] ?? '')
            .toString()
            .compareTo((b['machine_name'] ?? '').toString()));
        break;
      case 'name_desc':
        result.sort((a, b) => (b['machine_name'] ?? '')
            .toString()
            .compareTo((a['machine_name'] ?? '').toString()));
        break;
      case 'brand':
        result.sort((a, b) => (a['brand'] ?? '')
            .toString()
            .compareTo((b['brand'] ?? '').toString()));
        break;
      case 'newest':
        result.sort((a, b) => (b['created_at'] ?? '')
            .toString()
            .compareTo((a['created_at'] ?? '').toString()));
        break;
      default:
        result.sort((a, b) {
          final aOrder = (a['display_order'] as num?)?.toInt() ?? 0;
          final bOrder = (b['display_order'] as num?)?.toInt() ?? 0;
          return aOrder.compareTo(bOrder);
        });
    }
    _filteredMachines = result;
  }

  void _onSearchChanged(String v) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        setState(() {
          _searchQuery = v;
          _applyFilters();
        });
      }
    });
  }

  Future<void> _toggleSaved(String machineId) async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;
    final was = _savedMachineIds.contains(machineId);
    setState(() {
      if (was) {
        _savedMachineIds.remove(machineId);
      } else {
        _savedMachineIds.add(machineId);
      }
    });
    try {
      if (was) {
        await SupabaseConfig.client
            .from('saved_machines')
            .delete()
            .eq('user_id', userId)
            .eq('catalog_machine_id', machineId);
      } else {
        await SupabaseConfig.client
            .from('saved_machines')
            .insert({'user_id': userId, 'catalog_machine_id': machineId});
      }
      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(was
              ? S.of(context)!.catalogRemoveSaved
              : S.of(context)!.catalogAddedSaved),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12)))));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (was) {
          _savedMachineIds.add(machineId);
        } else {
          _savedMachineIds.remove(machineId);
        }
      });
    }
  }

  Future<void> _trackView(String machineId) async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await SupabaseConfig.client.from('recently_viewed_machines').upsert(
        {
          'user_id': userId,
          'catalog_machine_id': machineId,
          'viewed_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,catalog_machine_id',
      );
    } catch (_) {}
  }

  // ✅ FIX-4: Safe navigation for recently viewed machines
  Future<void> _navigateToRecentMachine(Map<String, dynamic> recentItem) async {
    final machineId = recentItem['machine_id'] as String?;
    if (machineId == null) return;

    // Try to find full data in loaded machines
    final matches = _allMachines.where((x) => x['id'] == machineId);
    Map<String, dynamic> machine;

    if (matches.isNotEmpty) {
      machine = matches.first;
    } else {
      // Machine not in active catalog — fetch on demand
      try {
        final data = await SupabaseConfig.client
            .from('machine_catalog')
            .select()
            .eq('id', machineId)
            .maybeSingle();
        if (!mounted || data == null) return;
        machine = Map<String, dynamic>.from(data);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(S.of(context)!.catalogMachineUnavailable),
            behavior: SnackBarBehavior.floating));
        return;
      }
    }

    if (!mounted) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => MachineDetailPage(machine: machine))).then((_) {
      if (mounted) _loadAllData();
    });
  }

  // ═══════════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════════

  String? _img(Map<String, dynamic> m) {
    final pi = m['product_images'];
    if (pi is List && pi.isNotEmpty) return pi[0];
    if (m['image_url'] != null && m['image_url'].toString().isNotEmpty) {
      return m['image_url'];
    }
    if (m['images'] is List && (m['images'] as List).isNotEmpty) {
      return (m['images'] as List)[0];
    }
    return null;
  }

  int _imgCount(Map<String, dynamic> m) {
    final pi = m['product_images'];
    if (pi is List) return pi.length;
    if (m['images'] is List) return (m['images'] as List).length;
    return 0;
  }

  int _catCount(String c) => c == 'All'
      ? _allMachines.length
      : _allMachines.where((m) => m['category'] == c).length;

  String _shortCat(String? c) {
    switch (c) {
      case 'Digital Printers':
        return 'PRINTER';
      case 'CNC Routers':
        return 'CNC';
      case 'Laser Cutters':
        return 'LASER';
      case 'Finishing Equipment':
        return 'FINISHING';
      default:
        return 'OTHER';
    }
  }

  bool _hasFilters() =>
      _selectedCategory != 'All' ||
      _selectedSubCategory != null ||
      _selectedBrand != null ||
      _searchQuery.isNotEmpty;

  void _clearAll() {
    setState(() {
      _selectedCategory = 'All';
      _selectedSubCategory = null;
      _selectedBrand = null;
      _searchQuery = '';
      _searchController.clear();
      _isSearching = false;
      _sortBy = 'default';
      _updateSubCategories();
      _applyFilters();
    });
  }

  String _keySpec(Map<String, dynamic> m) {
    final s = m['specifications'];
    if (s == null || s is! Map) return '';
    final sm = Map<String, dynamic>.from(s);
    for (final k in [
      'print_width',
      'working_area',
      'print_area',
      'laser_type',
      'power',
      'working_width',
    ]) {
      if (sm.containsKey(k)) return sm[k].toString();
    }
    return sm.isNotEmpty ? sm.values.first.toString() : '';
  }

  Widget _catIcon(String? cat, Color color, double size) {
    switch (cat) {
      case 'Laser Cutters':
        return _LaserIcon(color: color, size: size);
      case 'CNC Routers':
        return _CncIcon(color: color, size: size);
      case 'Digital Printers':
        return Icon(Icons.print_rounded, color: color, size: size);
      case 'Finishing Equipment':
        return Icon(Icons.construction_rounded, color: color, size: size);
      default:
        return Icon(Icons.inventory_2_rounded, color: color, size: size);
    }
  }

  Color _catAccent(String? cat) {
    switch (cat) {
      case 'Digital Printers':
        return Brand.royalBlue;
      case 'CNC Routers':
        return AdminColors.internal;
      case 'Laser Cutters':
        return AdminColors.primary;
      case 'Finishing Equipment':
        return Brand.lightGreen;
      default:
        return Brand.royalBlueLight;
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? SystemUiOverlayStyle.light
              .copyWith(statusBarColor: Colors.transparent)
          : SystemUiOverlayStyle.dark
              .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Brand.canvas(isDark),
        body: SafeArea(
          top: false,
          child: Column(children: [
            _buildTopBar(isDark),
            if (_isSearching) _buildSearchBar(isDark),
            _buildCategoryChips(isDark),
            if (_subCategories.isNotEmpty && _selectedCategory != 'All')
              _buildSubCategoryChips(isDark),
            _buildFilterBar(isDark),
            Expanded(
                child: _isLoading
                    ? _buildSkeleton(isDark)
                    : _hasError
                        ? _buildError(isDark)
                        : _filteredMachines.isEmpty
                            ? _buildEmpty(isDark)
                            : _buildContent(isDark)),
          ]),
        ),
      ),
    );
  }

  // ── TOP BAR — Navy Glow hero ───────────────────────────────
  Widget _buildTopBar(bool isDark) {
    return DsPageHeader(
      title: S.of(context)!.catalogTitle,
      subtitle: _selectedCategory == 'All'
          ? '${_allMachines.length} machines available'
          : '$_selectedCategory${_selectedSubCategory != null ? ' · $_selectedSubCategory' : ''}',
      actions: [
        _hBtn(_isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
            () {
          HapticFeedback.selectionClick();
          setState(() => _isGridView = !_isGridView);
        }),
        const SizedBox(width: 6),
        _hBtn(_isSearching ? Icons.close_rounded : Icons.search_rounded, () {
          setState(() {
            _isSearching = !_isSearching;
            if (!_isSearching) {
              _searchController.clear();
              _searchQuery = '';
              _applyFilters();
            }
          });
        }, isActive: _isSearching),
      ],
    );
  }

  /// Frosted hero action button (sits on the navy header).
  Widget _hBtn(IconData icon, VoidCallback onTap, {bool isActive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isActive ? Brand.lime.withAlpha(46) : Colors.white.withAlpha(18),
          borderRadius: BorderRadius.circular(Brand.r(12)),
          border: Border.all(
              color: isActive ? Brand.lime : Brand.royalBlue),
        ),
        child: Icon(icon,
            color: isActive ? Brand.lime : Colors.white, size: 19),
      ),
    );
  }

  // ── SEARCH BAR ─────────────────────────────────────────────
  Widget _buildSearchBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(16)),
          border: Border.all(
              color: isDark
                  ? Brand.darkBorderLight
                  : Brand.royalBlue.withAlpha(38)),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                      color: Brand.royalBlue.withAlpha(15),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]),
      child: TextField(
          controller: _searchController,
          autofocus: true,
          onChanged: _onSearchChanged,
          style: TextStyle(
              fontSize: 14,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              fontWeight: FontWeight.w500),
          decoration: InputDecoration(
              hintText: S.of(context)!.catalogSearch,
              hintStyle: TextStyle(
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  fontSize: 14),
              prefixIcon: Icon(Icons.search_rounded,
                  color: isDark
                      ? Brand.darkTextSecondary
                      : Brand.royalBlue.withAlpha(128),
                  size: 22),
              suffixIcon: _searchQuery.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _applyFilters();
                        });
                      },
                      child: Container(
                          margin: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: (isDark ? Colors.white : Brand.royalBlue)
                                  .withAlpha(20),
                              borderRadius: BorderRadius.circular(Brand.r(8))),
                          child: Icon(Icons.clear_rounded,
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight,
                              size: 18)))
                  : null,
              enabledBorder: InputBorder.none,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Brand.r(16)),
                borderSide: BorderSide(
                  color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                  width: 1.5,
                ),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14))),
    );
  }

  // ── CATEGORY CHIPS ─────────────────────────────────────────
  Widget _buildCategoryChips(bool isDark) {
    return Container(
      height: 108,
      margin: const EdgeInsets.only(top: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final sel = cat == _selectedCategory;
          final count = _catCount(cat);
          final accent = _catAccent(cat);

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _selectedCategory = cat;
                _selectedSubCategory = null;
                _updateSubCategories();
                _applyFilters();
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              width: 88,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: sel
                      ? (isDark
                          ? Brand.royalBlue.withAlpha(38)
                          : Brand.royalBlue)
                      : (Brand.surface(isDark)),
                  borderRadius: BorderRadius.circular(Brand.r(20)),
                  border: Border.all(
                      color: sel
                          ? (isDark
                              ? Brand.royalBlueLight.withAlpha(77)
                              : Brand.royalBlue)
                          : (isDark ? Brand.darkBorder : Brand.borderLight),
                      width: sel ? 1.5 : 1),
                  boxShadow: sel
                      ? [
                          BoxShadow(
                              color: (isDark
                                      ? Brand.royalBlueLight
                                      : Brand.royalBlue)
                                  .withAlpha(64),
                              blurRadius: 14,
                              offset: const Offset(0, 5))
                        ]
                      : isDark
                          ? null
                          : [
                              BoxShadow(
                                  color: Brand.royalBlue.withAlpha(10),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2))
                            ]),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: sel
                                ? Colors.white.withAlpha(isDark ? 20 : 38)
                                : accent.withAlpha(isDark ? 26 : 15),
                            borderRadius: BorderRadius.circular(Brand.r(13))),
                        child: Center(
                            child: cat == 'All'
                                ? Icon(Icons.apps_rounded,
                                    color: sel
                                        ? Brand.lightGreenBright
                                        : (isDark
                                            ? Brand.royalBlueGlow
                                            : accent),
                                    size: 30)
                                : _catIcon(
                                    cat,
                                    sel
                                        ? Brand.lightGreenBright
                                        : (isDark
                                            ? Brand.royalBlueGlow
                                            : accent),
                                    30))),
                    const SizedBox(height: 8),
                    Text(cat == 'All' ? 'All' : cat.split(' ').first,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
                            color: sel
                                ? Colors.white
                                : (isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight))),
                    const SizedBox(height: 2),
                    Text('$count items',
                        style: TextStyle(
                            fontSize: 11,
                            color: sel
                                ? Colors.white.withAlpha(153)
                                : (isDark
                                    ? Brand.darkTextTertiary
                                    : Brand.subtleLight.withAlpha(128)))),
                  ]),
            ),
          );
        },
      ),
    );
  }

  // ── SUB-CATEGORY CHIPS ─────────────────────────────────────
  Widget _buildSubCategoryChips(bool isDark) {
    return Container(
      height: 42,
      margin: const EdgeInsets.only(top: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: _subCategories.length + 1,
        itemBuilder: (context, index) {
          final isAll = index == 0;
          final sub = isAll ? null : _subCategories[index - 1];
          final sel = isAll
              ? _selectedSubCategory == null
              : _selectedSubCategory == sub;
          return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _selectedSubCategory = isAll ? null : sub;
                  _applyFilters();
                });
              },
              child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                      color: sel
                          ? Brand.royalBlue.withAlpha(isDark ? 51 : 26)
                          : (Brand.surface(isDark)),
                      borderRadius: BorderRadius.circular(Brand.r(20)),
                      border: Border.all(
                          color: sel
                              ? Brand.royalBlue.withAlpha(102)
                              : (isDark ? Brand.darkBorder : Brand.borderLight),
                          width: sel ? 1.5 : 1)),
                  child: Center(
                      child: Text(isAll ? 'All Types' : sub!,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  sel ? FontWeight.w700 : FontWeight.w500,
                              color: sel
                                  ? (isDark
                                      ? Brand.royalBlueGlow
                                      : Brand.royalBlue)
                                  : (isDark
                                      ? Brand.darkTextSecondary
                                      : Brand.subtleLight))))));
        },
      ),
    );
  }

  // ── FILTER BAR ─────────────────────────────────────────────
  Widget _buildFilterBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(children: [
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: isDark
                    ? Brand.darkCardElevated
                    : Brand.royalBlueSurface.withAlpha(128),
                borderRadius: BorderRadius.circular(Brand.r(8))),
            child: RichText(
                text: TextSpan(children: [
              TextSpan(
                  text: '${_filteredMachines.length} ',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : Brand.royalBlueDark)),
              TextSpan(
                  text: _filteredMachines.length == 1 ? 'machine' : 'machines',
                  style: TextStyle(
                      fontSize: 13,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      fontWeight: FontWeight.w500)),
            ]))),
        const Spacer(),
        if (_brands.isNotEmpty)
          _chipBtn(Icons.filter_list_rounded, _selectedBrand ?? 'Brand', isDark,
              isActive: _selectedBrand != null,
              onTap: () => _showBrandFilter(isDark),
              onClear: _selectedBrand != null
                  ? () {
                      setState(() {
                        _selectedBrand = null;
                        _applyFilters();
                      });
                    }
                  : null),
        const SizedBox(width: 8),
        _chipBtn(Icons.sort_rounded, _sortOptions[_sortBy] ?? 'Sort', isDark,
            isActive: _sortBy != 'default',
            onTap: () => _showSortOptions(isDark)),
        if (_hasFilters()) ...[
          const SizedBox(width: 8),
          Material(
              color: Colors.transparent,
              child: InkWell(
                  onTap: _clearAll,
                  borderRadius: BorderRadius.circular(Brand.r(10)),
                  child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                          color: StatusColors.danger.withAlpha(20),
                          borderRadius: BorderRadius.circular(Brand.r(10)),
                          border: Border.all(color: StatusColors.danger.withAlpha(38))),
                      child: const Icon(Icons.filter_alt_off_rounded,
                          size: 16, color: StatusColors.danger))))
        ],
      ]),
    );
  }

  Widget _chipBtn(IconData icon, String label, bool isDark,
      {bool isActive = false,
      required VoidCallback onTap,
      VoidCallback? onClear}) {
    return Material(
        color: Colors.transparent,
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Brand.r(10)),
            child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                    color: isActive
                        ? Brand.royalBlue.withAlpha(isDark ? 38 : 20)
                        : (Brand.surface(isDark)),
                    borderRadius: BorderRadius.circular(Brand.r(10)),
                    border: Border.all(
                        color: isActive
                            ? Brand.royalBlue.withAlpha(77)
                            : (isDark ? Brand.darkBorder : Brand.borderLight))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon,
                      size: 14,
                      color: isActive
                          ? (isDark ? Brand.royalBlueGlow : Brand.royalBlue)
                          : (isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight)),
                  const SizedBox(width: 5),
                  Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isActive
                              ? (isDark ? Brand.royalBlueGlow : Brand.royalBlue)
                              : (isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight))),
                  if (onClear != null) ...[
                    const SizedBox(width: 5),
                    GestureDetector(
                        onTap: onClear,
                        child: Icon(Icons.close,
                            size: 14,
                            color:
                                isDark ? Brand.royalBlueGlow : Brand.royalBlue))
                  ],
                ]))));
  }

  // ── BRAND FILTER SHEET ─────────────────────────────────────
  void _showBrandFilter(bool isDark) {
    showModalBottomSheet(
        context: context,
        backgroundColor: Brand.surface(isDark),
        // ✅ FIX-7: radius 24 → 28
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (sheetCtx) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                      child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                              color: isDark
                                  ? Brand.darkTextTertiary
                                  : Brand.subtleLight.withAlpha(77),
                              borderRadius: BorderRadius.circular(Brand.r(2))))),
                  const SizedBox(height: 20),
                  Text(S.of(context)!.catalogFilterBrand,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark)),
                  const SizedBox(height: 16),
                  _brandOpt(null, 'All Brands', isDark),
                  Divider(
                      color: isDark ? Brand.darkBorder : Brand.borderLight,
                      height: 1),
                  ..._brands.map((b) {
                    final c = _allMachines.where((m) => m['brand'] == b).length;
                    return _brandOpt(b, '$b ($c)', isDark);
                  }),
                  const SizedBox(height: 8),
                ])));
  }

  Widget _brandOpt(String? brand, String label, bool isDark) {
    final sel = _selectedBrand == brand;
    return ListTile(
        onTap: () {
          setState(() {
            _selectedBrand = brand;
            _applyFilters();
          });
          Navigator.pop(context);
        },
        leading: Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off,
            color: sel
                ? (isDark ? Brand.royalBlueGlow : Brand.royalBlue)
                : (isDark ? Brand.darkTextSecondary : Brand.subtleLight),
            size: 22),
        title: Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                color: sel
                    ? (isDark ? Brand.royalBlueGlow : Brand.royalBlue)
                    : (isDark ? Brand.darkTextPrimary : Brand.royalBlueDark))),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4));
  }

  // ── SORT SHEET ─────────────────────────────────────────────
  void _showSortOptions(bool isDark) {
    showModalBottomSheet(
        context: context,
        backgroundColor: Brand.surface(isDark),
        // ✅ FIX-7: radius 24 → 28
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (sheetCtx) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                      child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                              color: isDark
                                  ? Brand.darkTextTertiary
                                  : Brand.subtleLight.withAlpha(77),
                              borderRadius: BorderRadius.circular(Brand.r(2))))),
                  const SizedBox(height: 20),
                  Text(S.of(context)!.catalogSort,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark)),
                  const SizedBox(height: 12),
                  ..._sortOptions.entries.map((e) {
                    final sel = _sortBy == e.key;
                    return ListTile(
                        onTap: () {
                          setState(() {
                            _sortBy = e.key;
                            _applyFilters();
                          });
                          Navigator.pop(context);
                        },
                        leading: Icon(
                            sel
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: sel
                                ? (isDark
                                    ? Brand.royalBlueGlow
                                    : Brand.royalBlue)
                                : (isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight),
                            size: 22),
                        title: Text(e.value,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight:
                                    sel ? FontWeight.w700 : FontWeight.normal,
                                color: sel
                                    ? (isDark
                                        ? Brand.royalBlueGlow
                                        : Brand.royalBlue)
                                    : (isDark
                                        ? Brand.darkTextPrimary
                                        : Brand.royalBlueDark))),
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4));
                  }),
                  const SizedBox(height: 8),
                ])));
  }

  // ── CONTENT ────────────────────────────────────────────────
  Widget _buildContent(bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: isDark ? Brand.darkIconActive : Brand.royalBlue,
      backgroundColor: Brand.surface(isDark),
      child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          slivers: [
            if (_recentlyViewed.isNotEmpty && !_hasFilters())
              SliverToBoxAdapter(child: _buildRecent(isDark)),
            _isGridView
                ? SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.56,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12),
                        delegate: SliverChildBuilderDelegate(
                            (_, i) => _gridCard(_filteredMachines[i], isDark),
                            childCount: _filteredMachines.length)))
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                            (_, i) => _listCard(_filteredMachines[i], isDark),
                            childCount: _filteredMachines.length))),
          ]),
    );
  }

  // ── RECENTLY VIEWED ────────────────────────────────────────
  Widget _buildRecent(bool isDark) {
    return Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                        color: Brand.royalBlue,
                        borderRadius: BorderRadius.circular(Brand.r(2)))),
                const SizedBox(width: 8),
                Text(S.of(context)!.catalogRecentlyViewed,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight)),
              ])),
          const SizedBox(height: 10),
          SizedBox(
              height: 82,
              child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _recentlyViewed.length,
                  itemBuilder: (_, i) {
                    final m = _recentlyViewed[i];
                    final imgUrl = m['product_image'] as String?;
                    return GestureDetector(
                        // ✅ FIX-4: safe navigation with on-demand fetch
                        onTap: () => _navigateToRecentMachine(m),
                        child: Container(
                            width: 155,
                            margin: const EdgeInsets.only(right: 10),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color:
                                    Brand.surface(isDark),
                                borderRadius: BorderRadius.circular(Brand.r(14)),
                                border: Border.all(
                                    color: isDark
                                        ? Brand.darkBorder
                                        : Brand.borderLight)),
                            child: Row(children: [
                              Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                      color: isDark
                                          ? Brand.darkCardElevated
                                          : Brand.royalBlueSurface,
                                      borderRadius: BorderRadius.circular(Brand.r(12))),
                                  child: ClipRRect(
                                      borderRadius: BorderRadius.circular(Brand.r(12)),
                                      child: imgUrl != null
                                          ? CachedNetworkImage(
                                              imageUrl: imgUrl,
                                              fit: BoxFit.cover,
                                              width: 50,
                                              height: 50,
                                              errorWidget: (_, __, ___) =>
                                                  _catIcon(
                                                      m['category'],
                                                      isDark
                                                          ? Brand.royalBlueGlow
                                                          : Brand.royalBlue,
                                                      22),
                                            )
                                          : _catIcon(
                                              m['category'],
                                              isDark
                                                  ? Brand.royalBlueGlow
                                                  : Brand.royalBlue,
                                              22))),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                    Text(m['machine_name'] ?? '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? Brand.darkTextPrimary
                                                : Brand.royalBlueDark)),
                                    Text(m['brand'] ?? '',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: isDark
                                                ? Brand.darkTextSecondary
                                                : Brand.subtleLight)),
                                  ])),
                            ])));
                  })),
        ]));
  }

  // ── GRID CARD ──────────────────────────────────────────────
  Widget _gridCard(Map<String, dynamic> machine, bool isDark) {
    final imageUrl = _img(machine);
    final imageCount = _imgCount(machine);
    final id = machine['id'].toString();
    final saved = _savedMachineIds.contains(id);
    final owned = _ownedMachineIds.contains(id);
    final spec = _keySpec(machine);
    final accent = _catAccent(machine['category']);

    return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _trackView(id);
            Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => MachineDetailPage(machine: machine)))
                .then((_) {
              if (mounted) _loadAllData();
            });
          },
          borderRadius: BorderRadius.circular(Brand.r(22)),
          child: Container(
            decoration: BoxDecoration(
                color: Brand.surface(isDark),
                borderRadius: BorderRadius.circular(Brand.r(22)),
                border: Border.all(
                    color: owned
                        ? Brand.lightGreen.withAlpha(102)
                        : (isDark ? Brand.darkBorder : Brand.borderLight),
                    width: owned ? 1.5 : 1),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                            color: Brand.royalBlue.withAlpha(15),
                            blurRadius: 14,
                            offset: const Offset(0, 5))
                      ]),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  height: 125,
                  decoration: BoxDecoration(
                      color: isDark
                          ? Brand.darkCardElevated
                          : Brand.royalBlueSurface.withAlpha(128),
                      borderRadius: BorderRadius.vertical(
                          top: Radius.circular(Brand.r(22)))),
                  child: Stack(children: [
                    ClipRRect(
                        borderRadius: BorderRadius.vertical(
                            top: Radius.circular(Brand.r(22))),
                        child: imageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: imageUrl,
                                width: double.infinity,
                                height: 125,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Center(
                                    child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                            color: Brand.royalBlue,
                                            strokeWidth: 2))),
                                errorWidget: (_, __, ___) =>
                                    _placeholder(machine['category'], isDark),
                              )
                            : _placeholder(machine['category'], isDark)),
                    if (imageCount > 1)
                      Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 4),
                              decoration: BoxDecoration(
                                  color: Colors.black.withAlpha(140),
                                  borderRadius: BorderRadius.circular(Brand.r(10))),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.photo_library_rounded,
                                        size: 11, color: Colors.white),
                                    const SizedBox(width: 3),
                                    Text('$imageCount',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700))
                                  ]))),
                    Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: accent.withAlpha(224),
                                borderRadius: BorderRadius.circular(Brand.r(8))),
                            child: Text(_shortCat(machine['category']),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.4)))),
                    Positioned(
                        bottom: 8,
                        right: 8,
                        child: GestureDetector(
                            onTap: () => _toggleSaved(id),
                            child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                    color: saved
                                        ? Brand.royalBlue
                                        : Colors.black.withAlpha(89),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: saved
                                            ? Brand.royalBlueLight.withAlpha(77)
                                            : Colors.white.withAlpha(38),
                                        width: 1.5)),
                                child: Icon(
                                    saved
                                        ? Icons.bookmark_rounded
                                        : Icons.bookmark_border_rounded,
                                    color: Colors.white,
                                    size: 16)))),
                    if (owned)
                      Positioned(
                          bottom: 8,
                          left: 8,
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [
                                    Brand.lightGreen,
                                    Brand.lightGreenBright
                                  ]),
                                  borderRadius: BorderRadius.circular(Brand.r(8))),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.check_circle,
                                        size: 10, color: Colors.white),
                                    const SizedBox(width: 3),
                                    Text(S.of(context)!.catalogOwned,
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700))
                                  ]))),
                  ])),
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                    color: accent.withAlpha(isDark ? 31 : 15),
                                    borderRadius: BorderRadius.circular(Brand.r(10)),
                                    border: Border.all(
                                        color: accent.withAlpha(26))),
                                child: Text(machine['brand'] ?? 'iFrontiers',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: accent,
                                        letterSpacing: 0.3))),
                            const SizedBox(height: 7),
                            Text(machine['machine_name'] ?? 'Unknown',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.1,
                                    color: isDark
                                        ? Brand.darkTextPrimary
                                        : Brand.royalBlueDark,
                                    height: 1.25)),
                            const SizedBox(height: 3),
                            Text(machine['model_number'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Brand.darkTextSecondary
                                        : Brand.subtleLight,
                                    fontWeight: FontWeight.w500)),
                            if (spec.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(children: [
                                Icon(Icons.info_outline_rounded,
                                    size: 11,
                                    color: isDark
                                        ? Brand.darkTextSecondary
                                        : Brand.subtleLight),
                                const SizedBox(width: 4),
                                Expanded(
                                    child: Text(spec,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: isDark
                                                ? Brand.darkTextSecondary
                                                : Brand.subtleLight,
                                            fontStyle: FontStyle.italic)))
                              ])
                            ],
                            const Spacer(),
                            Row(children: [
                              Expanded(
                                  child: Container(
                                      height: 36,
                                      decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                              colors: [
                                                Brand.royalBlue,
                                                Brand.royalBlueLight
                                              ]),
                                          borderRadius:
                                              BorderRadius.circular(Brand.r(12))),
                                      child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                              onTap: () {
                                                _trackView(id);
                                                Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                            builder: (_) =>
                                                                MachineDetailPage(
                                                                    machine:
                                                                        machine)))
                                                    .then((_) {
                                                  if (mounted) {
                                                    _loadAllData();
                                                  }
                                                });
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(Brand.r(12)),
                                              child: Center(
                                                  child: Text(S.of(context)!.machineViewDetails,
                                                      style: const TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: Colors
                                                              .white))))))),
                              const SizedBox(width: 7),
                              Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                      color: accent.withAlpha(isDark ? 31 : 15),
                                      borderRadius: BorderRadius.circular(Brand.r(12)),
                                      border: Border.all(
                                          color: accent.withAlpha(51))),
                                  child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                          onTap: () =>
                                              _quickInquire(machine, isDark),
                                          borderRadius:
                                              BorderRadius.circular(Brand.r(12)),
                                          child: Icon(
                                              Icons.chat_bubble_outline_rounded,
                                              color: accent,
                                              size: 16)))),
                            ]),
                          ]))),
            ]),
          ),
        ));
  }

  // ── LIST CARD ──────────────────────────────────────────────
  Widget _listCard(Map<String, dynamic> machine, bool isDark) {
    final imageUrl = _img(machine);
    final id = machine['id'].toString();
    final saved = _savedMachineIds.contains(id);
    final owned = _ownedMachineIds.contains(id);
    final spec = _keySpec(machine);
    final sub = machine['sub_category'] as String?;
    final accent = _catAccent(machine['category']);

    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
            color: Colors.transparent,
            child: InkWell(
                onTap: () {
                  _trackView(id);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              MachineDetailPage(machine: machine))).then((_) {
                    if (mounted) _loadAllData();
                  });
                },
                borderRadius: BorderRadius.circular(Brand.r(20)),
                child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Brand.surface(isDark),
                        borderRadius: BorderRadius.circular(Brand.r(20)),
                        border: Border.all(
                            color: owned
                                ? Brand.lightGreen.withAlpha(102)
                                : (isDark
                                    ? Brand.darkBorder
                                    : Brand.borderLight),
                            width: owned ? 1.5 : 1),
                        boxShadow: isDark
                            ? null
                            : [
                                BoxShadow(
                                    color: Brand.royalBlue.withAlpha(10),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3))
                              ]),
                    child: Row(children: [
                      Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                              color: isDark
                                  ? Brand.darkCardElevated
                                  : Brand.royalBlueSurface.withAlpha(128),
                              borderRadius: BorderRadius.circular(Brand.r(16))),
                          child: Stack(children: [
                            ClipRRect(
                                borderRadius: BorderRadius.circular(Brand.r(16)),
                                child: imageUrl != null
                                    ? CachedNetworkImage(
                                        imageUrl: imageUrl,
                                        width: 90,
                                        height: 90,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) =>
                                            _placeholder(
                                                machine['category'], isDark),
                                      )
                                    : _placeholder(
                                        machine['category'], isDark)),
                            if (owned)
                              Positioned(
                                  top: 4,
                                  left: 4,
                                  child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: const BoxDecoration(
                                          gradient: LinearGradient(colors: [
                                            Brand.lightGreen,
                                            Brand.lightGreenBright
                                          ]),
                                          shape: BoxShape.circle),
                                      child: const Icon(Icons.check,
                                          size: 10, color: Colors.white))),
                          ])),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Row(children: [
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: accent.withAlpha(isDark ? 31 : 15),
                                      borderRadius: BorderRadius.circular(Brand.r(5)),
                                      border: Border.all(
                                          color: accent.withAlpha(26))),
                                  child: Text(machine['brand'] ?? '',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: accent))),
                              if (sub != null) ...[
                                const SizedBox(width: 6),
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white.withAlpha(10)
                                            : Brand.royalBlueSurface
                                                .withAlpha(128),
                                        borderRadius: BorderRadius.circular(Brand.r(5))),
                                    child: Text(sub,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: isDark
                                                ? Brand.darkTextSecondary
                                                : Brand.subtleLight)))
                              ],
                            ]),
                            const SizedBox(height: 6),
                            Text(machine['machine_name'] ?? 'Unknown',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.1,
                                    color: isDark
                                        ? Brand.darkTextPrimary
                                        : Brand.royalBlueDark)),
                            const SizedBox(height: 2),
                            Text(machine['model_number'] ?? '',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Brand.darkTextSecondary
                                        : Brand.subtleLight)),
                            if (spec.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(children: [
                                Icon(Icons.info_outline_rounded,
                                    size: 12,
                                    color: isDark
                                        ? Brand.darkTextSecondary
                                        : Brand.subtleLight),
                                const SizedBox(width: 4),
                                Expanded(
                                    child: Text(spec,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: isDark
                                                ? Brand.darkTextSecondary
                                                : Brand.subtleLight,
                                            fontStyle: FontStyle.italic)))
                              ])
                            ],
                          ])),
                      Column(children: [
                        GestureDetector(
                            onTap: () => _toggleSaved(id),
                            child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                    color: saved
                                        ? Brand.royalBlue
                                            .withAlpha(isDark ? 38 : 20)
                                        : (isDark
                                            ? Colors.white.withAlpha(10)
                                            : Brand.royalBlueSurface
                                                .withAlpha(128)),
                                    borderRadius: BorderRadius.circular(Brand.r(12))),
                                child: Icon(
                                    saved
                                        ? Icons.bookmark_rounded
                                        : Icons.bookmark_border_rounded,
                                    color: saved
                                        ? (isDark
                                            ? Brand.royalBlueGlow
                                            : Brand.royalBlue)
                                        : (isDark
                                            ? Brand.darkTextSecondary
                                            : Brand.subtleLight),
                                    size: 18))),
                        const SizedBox(height: 6),
                        Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withAlpha(10)
                                    : Brand.royalBlueSurface.withAlpha(128),
                                borderRadius: BorderRadius.circular(Brand.r(12))),
                            child: Icon(Icons.chevron_right_rounded,
                                size: 18,
                                color: isDark
                                    ? Brand.darkTextTertiary
                                    : Brand.subtleLight.withAlpha(102))),
                      ]),
                    ])))));
  }

  // ── QUICK INQUIRE ──────────────────────────────────────────
  void _quickInquire(Map<String, dynamic> machine, bool isDark) {
    showModalBottomSheet(
        context: context,
        backgroundColor: Brand.surface(isDark),
        // ✅ FIX-7: radius 24 → 28
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (sheetCtx) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: isDark
                              ? Brand.darkTextTertiary
                              : Brand.subtleLight.withAlpha(77),
                          borderRadius: BorderRadius.circular(Brand.r(2))))),
              const SizedBox(height: 20),
              Row(children: [
                Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                        color: isDark
                            ? Brand.darkCardElevated
                            : Brand.royalBlueSurface,
                        borderRadius: BorderRadius.circular(Brand.r(16))),
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(Brand.r(16)),
                        child: _img(machine) != null
                            ? CachedNetworkImage(
                                imageUrl: _img(machine)!,
                                fit: BoxFit.cover,
                                width: 60,
                                height: 60,
                                errorWidget: (_, __, ___) => _catIcon(
                                    machine['category'],
                                    isDark
                                        ? Brand.royalBlueGlow
                                        : Brand.royalBlue,
                                    26),
                              )
                            : _catIcon(
                                machine['category'],
                                isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                                26))),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(machine['machine_name'] ?? '',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Brand.darkTextPrimary
                                  : Brand.royalBlueDark)),
                      Text('${machine['brand']} · ${machine['model_number']}',
                          style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight)),
                    ])),
              ]),
              const SizedBox(height: 24),
              _qaBtn(
                  Icons.chat_bubble_outline_rounded,
                  'Inquire About This Machine',
                  'Get pricing and availability details',
                  Brand.royalBlue,
                  isDark, () {
                Navigator.pop(sheetCtx);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => MachineDetailPage(machine: machine)));
              }),
              const SizedBox(height: 10),
              _qaBtn(
                  Icons.shopping_cart_outlined,
                  'Place an Order',
                  'Request to purchase this machine',
                  Brand.lightGreen,
                  isDark, () {
                Navigator.pop(sheetCtx);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => MachineDetailPage(machine: machine)));
              }),
              const SizedBox(height: 10),
              _qaBtn(
                  Icons.phone_outlined,
                  'Call Sales Team',
                  '0777 244 882',
                  AdminColors.accent,
                  isDark,
                  () => Navigator.pop(sheetCtx)),
              const SizedBox(height: 16),
            ])));
  }

  Widget _qaBtn(IconData icon, String title, String sub, Color c, bool isDark,
      VoidCallback onTap) {
    return Material(
        color: Colors.transparent,
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Brand.r(16)),
            child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: c.withAlpha(isDark ? 20 : 10),
                    borderRadius: BorderRadius.circular(Brand.r(16)),
                    border: Border.all(color: c.withAlpha(38))),
                child: Row(children: [
                  Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                          color: c.withAlpha(isDark ? 31 : 20),
                          borderRadius: BorderRadius.circular(Brand.r(14))),
                      child: Icon(icon, color: c, size: 22)),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(title,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Brand.darkTextPrimary
                                    : Brand.royalBlueDark)),
                        Text(sub,
                            style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight)),
                      ])),
                  Icon(Icons.chevron_right_rounded,
                      color: c.withAlpha(128), size: 22),
                ]))));
  }

  // ── SKELETON ───────────────────────────────────────────────
  Widget _buildSkeleton(bool isDark) {
    return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.56,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12),
        itemCount: 6,
        itemBuilder: (_, __) => Container(
            decoration: BoxDecoration(
                color: Brand.surface(isDark),
                borderRadius: BorderRadius.circular(Brand.r(22)),
                border: isDark ? Border.all(color: Brand.darkBorder) : null),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  height: 125,
                  decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withAlpha(8)
                          : Brand.royalBlue.withAlpha(10),
                      borderRadius: BorderRadius.vertical(
                          top: Radius.circular(Brand.r(22))))),
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sk(50, 16, 6, isDark),
                        const SizedBox(height: 8),
                        _sk(double.infinity, 14, 4, isDark),
                        const SizedBox(height: 4),
                        _sk(80, 12, 4, isDark),
                        const SizedBox(height: 12),
                        _sk(double.infinity, 36, 12, isDark),
                      ])),
            ])));
  }

  Widget _sk(double w, double h, double r, bool isDark) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withAlpha(10)
              : Brand.royalBlue.withAlpha(13),
          borderRadius: BorderRadius.circular(r)));

  // ── ERROR STATE ────────────────────────────────────────────
  Widget _buildError(bool isDark) {
    return Center(
        child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
                color: Brand.surface(isDark),
                borderRadius: BorderRadius.circular(Brand.r(24)),
                border: isDark ? Border.all(color: Brand.darkBorder) : null),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                      color: StatusColors.danger.withAlpha(26),
                      borderRadius: BorderRadius.circular(Brand.r(22))),
                  child: const Icon(Icons.error_outline,
                      size: 34, color: StatusColors.danger)),
              const SizedBox(height: 20),
              Text(S.of(context)!.commonSomethingWentWrong,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : Brand.royalBlueDark)),
              const SizedBox(height: 8),
              Text(_errorMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? Brand.darkTextSecondary
                          : Brand.subtleLight)),
              const SizedBox(height: 20),
              ElevatedButton(
                  onPressed: _loadAllData,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Brand.royalBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Brand.r(14))),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12)),
                  child: Text(S.of(context)!.commonTryAgain,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14))),
            ])));
  }

  // ── EMPTY STATE ────────────────────────────────────────────
  Widget _buildEmpty(bool isDark) {
    return Center(
        child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
                color: Brand.surface(isDark),
                borderRadius: BorderRadius.circular(Brand.r(24)),
                border: isDark ? Border.all(color: Brand.darkBorder) : null,
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                            color: Brand.royalBlue.withAlpha(10),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ]),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                      color: isDark
                          ? Brand.royalBlue.withAlpha(26)
                          : Brand.royalBlueSurface,
                      borderRadius: BorderRadius.circular(Brand.r(22))),
                  child: Icon(Icons.inventory_2_outlined,
                      size: 34,
                      color: isDark ? Brand.royalBlueGlow : Brand.royalBlue)),
              const SizedBox(height: 20),
              Text(S.of(context)!.catalogNoMachines,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : Brand.royalBlueDark)),
              const SizedBox(height: 8),
              Text(
                  _hasFilters()
                      ? 'Try adjusting your filters or search'
                      : S.of(context)!.catalogNoMachinesAvailable,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      height: 1.4)),
              if (_hasFilters()) ...[
                const SizedBox(height: 16),
                Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      if (_selectedCategory != 'All')
                        _filterTag(_selectedCategory, isDark, () {
                          setState(() {
                            _selectedCategory = 'All';
                            _selectedSubCategory = null;
                            _updateSubCategories();
                            _applyFilters();
                          });
                        }),
                      if (_selectedSubCategory != null)
                        _filterTag(_selectedSubCategory!, isDark, () {
                          setState(() {
                            _selectedSubCategory = null;
                            _applyFilters();
                          });
                        }),
                      if (_selectedBrand != null)
                        _filterTag(_selectedBrand!, isDark, () {
                          setState(() {
                            _selectedBrand = null;
                            _applyFilters();
                          });
                        }),
                      if (_searchQuery.isNotEmpty)
                        _filterTag('"$_searchQuery"', isDark, () {
                          setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                            _applyFilters();
                          });
                        }),
                    ])
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                  onPressed: _clearAll,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Brand.royalBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Brand.r(14))),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12)),
                  child: Text(S.of(context)!.machineClearFilters,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14))),
            ])));
  }

  Widget _filterTag(String label, bool isDark, VoidCallback onRemove) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: Brand.royalBlue.withAlpha(isDark ? 31 : 15),
            borderRadius: BorderRadius.circular(Brand.r(20)),
            border: Border.all(color: Brand.royalBlue.withAlpha(51))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Brand.royalBlueGlow : Brand.royalBlue)),
          const SizedBox(width: 4),
          GestureDetector(
              onTap: onRemove,
              child: Icon(Icons.close,
                  size: 14,
                  color: isDark ? Brand.royalBlueGlow : Brand.royalBlue)),
        ]));
  }

  // ── PLACEHOLDER IMAGE ──────────────────────────────────────
  Widget _placeholder(String? cat, bool isDark) {
    return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
              color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
              borderRadius: BorderRadius.circular(Brand.r(14))),
          child: Center(
              child: _catIcon(
                  cat,
                  isDark
                      ? Brand.royalBlueGlow.withAlpha(77)
                      : Brand.royalBlue.withAlpha(64),
                  24))),
      const SizedBox(height: 6),
      Text(S.of(context)!.machineNoImage,
          style: TextStyle(
              fontSize: 11,
              color: isDark
                  ? Brand.darkTextTertiary
                  : Brand.subtleLight.withAlpha(128))),
    ]));
  }
}
