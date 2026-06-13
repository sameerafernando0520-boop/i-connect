// ============================================================
// iFrontiers Connect — Order Form Page
// Customer places machine / parts orders
// Creates service_ticket with type='order' + metadata JSONB
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../services/points_service.dart';
import '../../widgets/ds/ds_widgets.dart';

class OrderFormPage extends StatefulWidget {
  final Map<String, dynamic>? preselectedMachine;

  const OrderFormPage({super.key, this.preselectedMachine});

  @override
  State<OrderFormPage> createState() => _OrderFormPageState();
}

class _OrderFormPageState extends State<OrderFormPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _companyCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // State
  List<Map<String, dynamic>> _catalogMachines = [];
  Map<String, dynamic>? _selectedMachine;
  int _quantity = 1;
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedMachine = widget.preselectedMachine;
    _loadData();
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    _contactCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────
  Future<void> _loadData() async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;

      final results = await Future.wait<dynamic>([
        SupabaseConfig.client
            .from('machine_catalog')
            .select()
            .eq('is_active', true)
            .order('machine_name'),
        if (userId != null)
          SupabaseConfig.client
              .from('users')
              .select('company_name, phone_number')
              .eq('id', userId)
              .single()
        else
          Future<Map<String, dynamic>>.value(<String, dynamic>{}),
      ]);

      if (!mounted) return;
      setState(() {
        _catalogMachines = List<Map<String, dynamic>>.from(results[0] as List);
        final profile = results[1] as Map<String, dynamic>? ?? {};
        if (_companyCtrl.text.isEmpty) {
          _companyCtrl.text = (profile['company_name'] as String?) ?? '';
        }
        if (_contactCtrl.text.isEmpty) {
          _contactCtrl.text = (profile['phone_number'] as String?) ?? '';
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('OrderForm load error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // ── Machine Image Helper ─────────────────────────────────
  String? _getMachineImage(Map<String, dynamic> machine) {
    final productImages = machine['product_images'] as List?;
    if (productImages != null && productImages.isNotEmpty) {
      return productImages.first.toString();
    }
    final images = machine['images'] as List?;
    if (images != null && images.isNotEmpty) {
      return images.first.toString();
    }
    return machine['image_url'] as String?;
  }

  // ── Machine Selector Bottom Sheet ────────────────────────
  void _showMachineSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            final filtered = _catalogMachines.where((m) {
              if (searchQuery.isEmpty) return true;
              final name = (m['machine_name'] as String?)?.toLowerCase() ?? '';
              final model = (m['model_number'] as String?)?.toLowerCase() ?? '';
              final cat = (m['category'] as String?)?.toLowerCase() ?? '';
              final q = searchQuery.toLowerCase();
              return name.contains(q) || model.contains(q) || cat.contains(q);
            }).toList();

            return Container(
              height: MediaQuery.of(sheetCtx).size.height * 0.75,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCard : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 14, bottom: 16),
                    decoration: BoxDecoration(
                      color:
                          isDark ? Brand.darkBorderLight : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Select Machine',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Search
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: TextField(
                      style: TextStyle(
                        color: isDark ? Brand.darkTextPrimary : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search machines...',
                        hintStyle: TextStyle(
                          color: isDark
                              ? Brand.darkTextTertiary
                              : Colors.grey.shade400,
                        ),
                        prefixIcon: Icon(Icons.search_rounded,
                            color:
                                isDark ? Brand.darkTextSecondary : Colors.grey),
                        filled: true,
                        fillColor: isDark ? Brand.darkBg : Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                      onChanged: (v) => setSheet(() => searchQuery = v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // List
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'No machines found',
                              // L3: bound to single line — centered prompt
                              // shouldn't wrap onto multiple rows on narrow
                              // devices, and definitely shouldn't overflow.
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Colors.grey,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final m = filtered[i];
                              final imageUrl = _getMachineImage(m);
                              final isSelected =
                                  _selectedMachine?['id'] == m['id'];

                              return Container(
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Brand.royalBlue
                                          .withAlpha(((isDark ? 0.2 : 0.08) * 255).toInt())
                                      : (isDark
                                          ? Brand.darkCardElevated
                                          : Colors.grey.shade50),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? Brand.royalBlueLight
                                        : (isDark
                                            ? Brand.darkBorder
                                            : Colors.grey.shade200),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 6),
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SizedBox(
                                      width: 52,
                                      height: 52,
                                      child: imageUrl != null
                                          ? CachedNetworkImage(
                                              imageUrl: imageUrl,
                                              fit: BoxFit.cover,
                                              placeholder: (_, __) => Container(
                                                color: isDark
                                                    ? Brand.darkBg
                                                    : Colors.grey.shade200,
                                              ),
                                              errorWidget: (_, __, ___) =>
                                                  _machineIcon(isDark),
                                            )
                                          : _machineIcon(isDark),
                                    ),
                                  ),
                                  // L3: bind ListTile text to 1–2 lines so a
                                  // long machine_name / category / price from
                                  // the DB can't push the row out of layout
                                  // or overflow into sibling columns.
                                  title: Text(
                                    m['machine_name'] ?? 'Unknown',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: isDark
                                          ? Brand.darkTextPrimary
                                          : Colors.black87,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${m['model_number'] ?? ''} • ${m['category'] ?? ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Brand.darkTextSecondary
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                  trailing: m['price'] != null
                                      ? Text(
                                          'Rs. ${_formatPrice(m['price'])}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Brand.lightGreenDark,
                                          ),
                                        )
                                      : null,
                                  onTap: () {
                                    setState(() => _selectedMachine = m);
                                    Navigator.pop(sheetCtx);
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _machineIcon(bool isDark) => Container(
        color: isDark ? Brand.darkBg : Colors.grey.shade100,
        child: Icon(Icons.precision_manufacturing_rounded,
            color: isDark ? Brand.darkTextSecondary : Colors.grey.shade400,
            size: 26),
      );

  String _formatPrice(dynamic price) {
    if (price == null) return '0.00';
    final p = double.tryParse(price.toString()) ?? 0;
    return p.toStringAsFixed(2).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  // ── Submit Order ─────────────────────────────────────────
  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMachine == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('Please select a machine'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final userId = SupabaseConfig.client.auth.currentUser!.id;
      final machine = _selectedMachine!;

      final unitPrice = double.tryParse(machine['price']?.toString() ?? '');
      final totalPrice = unitPrice != null ? unitPrice * _quantity : null;

      final metadata = {
        'machine_name': machine['machine_name'],
        'model_number': machine['model_number'],
        'category': machine['category'],
        'unit_price': machine['price'],
        'quantity': _quantity,
        'total_price': totalPrice,
        'company_name': _companyCtrl.text.trim(),
        'contact_number': _contactCtrl.text.trim(),
        'additional_notes': _notesCtrl.text.trim(),
      };

      await SupabaseConfig.client.from('service_tickets').insert({
        'user_id': userId,
        'catalog_machine_id': machine['id'],
        'ticket_type': 'order',
        'subject': 'Order: ${machine['machine_name']} (x$_quantity)',
        'description': 'Machine: ${machine['machine_name']}\n'
            'Model: ${machine['model_number'] ?? 'N/A'}\n'
            'Quantity: $_quantity\n'
            'Company: ${_companyCtrl.text.trim()}\n'
            'Contact: ${_contactCtrl.text.trim()}\n'
            'Delivery Address: ${_addressCtrl.text.trim()}\n'
            '${_notesCtrl.text.trim().isNotEmpty ? 'Notes: ${_notesCtrl.text.trim()}' : ''}',
        'status': 'open',
        'priority': 'medium',
        'quantity': _quantity,
        'delivery_address': _addressCtrl.text.trim(),
        'deal_value': totalPrice,
        'metadata': metadata,
      });

      // ── Award ticket creation points ──
      PointsService.award('create_ticket', 25, 'Submitted order inquiry');

      if (!mounted) return;
      _showOrderSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('Failed to place order: $e')),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  void _showOrderSuccess() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: isDark ? Brand.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Brand.lightGreen.withAlpha(((0.12) * 255).toInt()),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Brand.lightGreen, size: 48),
            ),
            const SizedBox(height: 20),
            Text(
              'Order Placed!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Your order has been submitted successfully. Our team will review and get back to you shortly.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Brand.darkTextSecondary : Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Brand.royalBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Done',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────
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
        body: Column(children: [
          const DsPageHeader(title: 'Place Order'),
          Expanded(
            child: _isLoading
            ? _buildShimmer(isDark)
            : RefreshIndicator(
                color: Brand.royalBlue,
                backgroundColor: Brand.surface(isDark),
                onRefresh: _loadData,
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                    children: [
                      // ── Machine Selection ──
                      _sectionTitle('Select Machine *', isDark),
                      const SizedBox(height: 10),
                      _buildMachineSelector(isDark),

                      const SizedBox(height: 24),

                      // ── Quantity ──
                      _sectionTitle('Quantity', isDark),
                      const SizedBox(height: 10),
                      _buildQuantitySelector(isDark),

                      const SizedBox(height: 24),

                      // ── Company ──
                      _sectionTitle('Company Name *', isDark),
                      const SizedBox(height: 10),
                      _buildTextField(
                        controller: _companyCtrl,
                        hint: 'Your company name',
                        isDark: isDark,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Company name is required'
                            : null,
                      ),

                      const SizedBox(height: 20),

                      // ── Contact ──
                      _sectionTitle('Contact Number *', isDark),
                      const SizedBox(height: 10),
                      _buildTextField(
                        controller: _contactCtrl,
                        hint: '+94 XX XXX XXXX',
                        isDark: isDark,
                        keyboardType: TextInputType.phone,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Contact number is required'
                            : null,
                      ),

                      const SizedBox(height: 20),

                      // ── Address ──
                      _sectionTitle('Delivery Address *', isDark),
                      const SizedBox(height: 10),
                      _buildTextField(
                        controller: _addressCtrl,
                        hint: 'Full delivery address',
                        isDark: isDark,
                        maxLines: 3,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Delivery address is required'
                            : null,
                      ),

                      const SizedBox(height: 20),

                      // ── Notes ──
                      _sectionTitle('Additional Notes', isDark),
                      const SizedBox(height: 10),
                      _buildTextField(
                        controller: _notesCtrl,
                        hint: 'Special requirements, preferred date, etc.',
                        isDark: isDark,
                        maxLines: 3,
                      ),

                      // ── Summary ──
                      if (_selectedMachine != null) ...[
                        const SizedBox(height: 28),
                        _buildOrderSummary(isDark),
                      ],

                      const SizedBox(height: 32),

                      // ── Submit ──
                      GestureDetector(
                        onTap: _isSubmitting ? null : _submitOrder,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: double.infinity,
                          height: 54,
                          decoration: BoxDecoration(
                            gradient: _isSubmitting
                                ? null
                                : const LinearGradient(
                                    colors: [
                                      Brand.royalBlueDark,
                                      Brand.royalBlueLight
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                            color: _isSubmitting ? Brand.royalBlue : null,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: isDark || _isSubmitting
                                ? null
                                : [
                                    BoxShadow(
                                      color: Brand.royalBlue.withAlpha(89),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                          ),
                          child: Center(
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                          Icons.shopping_cart_checkout_rounded,
                                          size: 20,
                                          color: Colors.white),
                                      SizedBox(width: 10),
                                      Text(
                                        'Place Order',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ),
        ]),
      ),
    );
  }

  // ── Section Title ──
  Widget _sectionTitle(String text, bool isDark) => Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: isDark ? Brand.darkTextSecondary : Colors.grey.shade700,
        ),
      );

  // ── Machine Selector Card ──
  Widget _buildMachineSelector(bool isDark) {
    if (_selectedMachine != null) {
      final m = _selectedMachine!;
      final imageUrl = _getMachineImage(m);

      return Container(
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Brand.royalBlueLight.withAlpha(((0.5) * 255).toInt()),
            width: 2,
          ),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: Brand.royalBlue.withAlpha(((0.08) * 255).toInt()),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _showMachineSelector,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                  color: isDark
                                      ? Brand.darkBg
                                      : Colors.grey.shade200),
                              errorWidget: (_, __, ___) => _machineIcon(isDark),
                            )
                          : _machineIcon(isDark),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m['machine_name'] ?? 'Unknown',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Brand.darkTextPrimary
                                : Brand.royalBlueDark,
                          ),
                        ),
                        if (m['model_number'] != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            m['model_number'],
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                        if (m['category'] != null) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Brand.royalBlueSurface
                                  .withAlpha(((isDark ? 0.15 : 1) * 255).toInt()),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              m['category'],
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Brand.royalBlueLight,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.swap_horiz_rounded,
                      color: Brand.royalBlueLight, size: 22),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Not selected
    return Container(
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Brand.darkBorder : Colors.grey.shade300,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _showMachineSelector,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_circle_outline_rounded,
                    color: Brand.royalBlueLight, size: 24),
                SizedBox(width: 12),
                Text(
                  'Tap to select a machine',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Brand.royalBlueLight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Quantity Selector ──
  Widget _buildQuantitySelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Brand.darkBorder : Colors.grey.shade300,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Quantity',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? Brand.darkTextPrimary : Colors.black87,
            ),
          ),
          Row(
            children: [
              _quantityButton(
                icon: Icons.remove_rounded,
                isDark: isDark,
                onTap: () {
                  if (_quantity > 1) setState(() => _quantity--);
                },
              ),
              Container(
                width: 52,
                alignment: Alignment.center,
                child: Text(
                  '$_quantity',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                ),
              ),
              _quantityButton(
                icon: Icons.add_rounded,
                isDark: isDark,
                onTap: () => setState(() => _quantity++),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quantityButton({
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: Brand.royalBlue),
        ),
      ),
    );
  }

  // ── Text Field ──
  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required bool isDark,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.sentences,
      style: TextStyle(
        color: isDark ? Brand.darkTextPrimary : Colors.black87,
        fontSize: 15,
      ),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? Brand.darkTextTertiary : Colors.grey.shade400,
          fontSize: 14,
        ),
        filled: true,
        fillColor: Brand.surface(isDark),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? Brand.darkBorder : Colors.grey.shade300,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? Brand.darkBorder : Colors.grey.shade300,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Brand.royalBlueLight, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
    );
  }

  // ── Order Summary ──
  Widget _buildOrderSummary(bool isDark) {
    final m = _selectedMachine!;
    final unitPrice = double.tryParse(m['price']?.toString() ?? '');
    final total = unitPrice != null ? unitPrice * _quantity : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Brand.darkBorder : Brand.lightGreenSurface,
          width: isDark ? 1 : 2,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Brand.lightGreen.withAlpha(((0.08) * 255).toInt()),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded,
                  color: Brand.lightGreenDark, size: 20),
              const SizedBox(width: 8),
              Text(
                'Order Summary',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _summaryRow('Machine', m['machine_name'] ?? 'N/A', isDark),
          if (m['model_number'] != null)
            _summaryRow('Model', m['model_number'], isDark),
          _summaryRow('Quantity', '$_quantity', isDark),
          if (unitPrice != null) ...[
            _summaryRow('Unit Price', 'Rs. ${_formatPrice(unitPrice)}', isDark),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Estimated Total',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                ),
                Text(
                  'Rs. ${_formatPrice(total)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Brand.lightGreenDark,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Brand.darkTextSecondary : Colors.grey.shade600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Brand.darkTextPrimary : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // ── Shimmer ──
  Widget _buildShimmer(bool isDark) {
    final base = isDark ? Brand.darkCard : Colors.grey.shade200;
    Widget box(double w, double h, {double r = 14}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
              color: base, borderRadius: BorderRadius.circular(r)),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        box(100, 16),
        const SizedBox(height: 10),
        box(double.infinity, 100, r: 18),
        const SizedBox(height: 24),
        box(80, 16),
        const SizedBox(height: 10),
        box(double.infinity, 52, r: 16),
        const SizedBox(height: 24),
        box(120, 16),
        const SizedBox(height: 10),
        box(double.infinity, 52),
        const SizedBox(height: 20),
        box(130, 16),
        const SizedBox(height: 10),
        box(double.infinity, 52),
        const SizedBox(height: 20),
        box(140, 16),
        const SizedBox(height: 10),
        box(double.infinity, 90),
      ],
    );
  }
}
