import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';

// Quotation accent — matches the purple used across quotation screens
const _kQuotationPurple = Color(0xFF8B5CF6);

class CreateQuotationPage extends StatefulWidget {
  final String? customerId;
  final String? ticketId;
  final String? customerName;
  final String? customerCompany;

  const CreateQuotationPage({
    super.key,
    this.customerId,
    this.ticketId,
    this.customerName,
    this.customerCompany,
  });

  @override
  State<CreateQuotationPage> createState() => _CreateQuotationPageState();
}

class _CreateQuotationPageState extends State<CreateQuotationPage> {
  final _supabase = SupabaseConfig.client;
  final _fmt = NumberFormat('#,##0.00', 'en_US');

  bool _loading = true;
  bool _saving = false;

  String? _customerId;
  String? _customerName;
  String? _customerCompany;
  String? _ticketId;
  String? _ticketNumber;

  List<Map<String, dynamic>> _items = [];

  String _discountType = 'percentage';
  double _discountValue = 0;
  double _taxRate = 0;

  late DateTime _issueDate;
  late DateTime _validUntil;

  final _notesCtrl = TextEditingController();
  final _termsCtrl = TextEditingController();
  final _internalCtrl = TextEditingController();

  // FIX: Persistent tax controller — avoids inline controller in build()
  late TextEditingController _taxCtrl;

  String? _currentUserId;

  // ── Computed ──
  double get _subtotal =>
      _items.fold(0.0, (s, i) => s + _dbl(i['total_price']));

  double get _discountAmount => _discountType == 'percentage'
      ? _subtotal * _discountValue / 100
      : _discountValue;

  double get _taxableAmount =>
      (_subtotal - _discountAmount).clamp(0.0, double.infinity);

  double get _taxAmount => _taxableAmount * _taxRate / 100;

  double get _total => _taxableAmount + _taxAmount;

  double _dbl(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  // ── Lifecycle ──
  @override
  void initState() {
    super.initState();
    _currentUserId = _supabase.auth.currentUser?.id;
    _issueDate = DateTime.now();
    _validUntil = DateTime.now().add(const Duration(days: 30));
    _customerId = widget.customerId;
    _customerName = widget.customerName;
    _customerCompany = widget.customerCompany;
    _ticketId = widget.ticketId;
    _taxCtrl = TextEditingController();
    _loadDefaults();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _termsCtrl.dispose();
    _internalCtrl.dispose();
    _taxCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDefaults() async {
    try {
      // FIX: Explicit <dynamic> type on Future.wait
      final futures = <Future<dynamic>>[
        _supabase
            .from('tax_settings')
            .select('tax_rate')
            .eq('is_active', true)
            .eq('is_default', true)
            .maybeSingle(),
        _supabase
            .from('company_info')
            .select('terms_text')
            .limit(1)
            .maybeSingle(),
      ];

      if (_ticketId != null) {
        futures.add(
          _supabase
              .from('service_tickets')
              .select('ticket_number')
              .eq('id', _ticketId!)
              .maybeSingle(),
        );
      }

      final results = await Future.wait<dynamic>(futures);

      if (!mounted) return;

      final tax = results[0] as Map<String, dynamic>?;
      final company = results[1] as Map<String, dynamic>?;
      final ticket =
          results.length > 2 ? results[2] as Map<String, dynamic>? : null;

      final rate = _dbl(tax?['tax_rate']);

      setState(() {
        _taxRate = rate;
        // FIX: Sync persistent tax controller with loaded value
        if (rate > 0) _taxCtrl.text = rate.toString();
        if (company?['terms_text'] != null) {
          _termsCtrl.text = company!['terms_text'].toString();
        }
        if (ticket?['ticket_number'] != null) {
          _ticketNumber = ticket!['ticket_number'].toString();
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ═══════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Brand.darkBg : AdminColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AdminColors.primary,
                  strokeWidth: 3,
                ),
              )
            : Column(
                children: [
                  _buildTopHeader(isDark),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildCustomerSection(isDark),
                          if (_ticketNumber != null) ...[
                            const SizedBox(height: 12),
                            _buildLinkedTicket(isDark),
                          ],
                          const SizedBox(height: 20),
                          _buildItemsSection(isDark),
                          const SizedBox(height: 20),
                          _buildDiscountTax(isDark),
                          const SizedBox(height: 20),
                          _buildSummary(isDark),
                          const SizedBox(height: 20),
                          _buildDates(isDark),
                          const SizedBox(height: 20),
                          _buildNotes(isDark),
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ),
                  _buildBottomBar(isDark),
                ],
              ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  TOP HEADER (matches other admin pages)
  // ═══════════════════════════════════════════════════════

  Widget _buildTopHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Brand.royalBlue.withAlpha(15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: isDark ? Brand.darkIconActive : AdminColors.primary,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Create Quotation',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                color: isDark ? Brand.darkTextPrimary : AdminColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  1. CUSTOMER
  // ═══════════════════════════════════════════════════════

  Widget _buildCustomerSection(bool isDark) {
    return _card(
      child: InkWell(
        onTap: _selectCustomer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AdminColors.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _customerId != null
                      ? Icons.person_rounded
                      : Icons.person_add_rounded,
                  color: AdminColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _customerId != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _customerName ?? 'Customer',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AdminColors.text(context),
                            ),
                          ),
                          if (_customerCompany != null)
                            Text(
                              _customerCompany!,
                              style: TextStyle(
                                fontSize: 12,
                                color: AdminColors.textSub(context),
                              ),
                            ),
                        ],
                      )
                    : Text(
                        'Select Customer *',
                        style: TextStyle(
                          fontSize: 15,
                          color: AdminColors.textHint(context),
                        ),
                      ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AdminColors.textHint(context),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectCustomer() async {
    final searchCtrl = TextEditingController();
    // FIX: Declare debounce outside sheet so it can be cancelled on dismiss
    Timer? debounce;
    List<Map<String, dynamic>> results = [];
    bool searching = false;

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            return Container(
              height: MediaQuery.of(sheetCtx).size.height * 0.75,
              decoration: BoxDecoration(
                color: AdminColors.card(sheetCtx),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AdminColors.border(sheetCtx),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Text(
                      'Select Customer',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.text(sheetCtx),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      style: TextStyle(color: AdminColors.text(sheetCtx)),
                      decoration: InputDecoration(
                        hintText: 'Search by name, company, email…',
                        hintStyle:
                            TextStyle(color: AdminColors.textHint(sheetCtx)),
                        prefixIcon: Icon(Icons.search_rounded,
                            color: AdminColors.textHint(sheetCtx)),
                        filled: true,
                        fillColor: AdminColors.bg(sheetCtx),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onChanged: (v) {
                        debounce?.cancel();
                        debounce = Timer(
                          const Duration(milliseconds: 400),
                          () async {
                            if (v.trim().length < 2) {
                              setSheet(() => results = []);
                              return;
                            }
                            setSheet(() => searching = true);
                            try {
                              final res = await _supabase
                                  .from('users')
                                  .select(
                                    'id, full_name,'
                                    ' company_name, email',
                                  )
                                  .eq('role', 'customer')
                                  .or(
                                    'full_name.ilike.%${v.trim()}%,'
                                    'company_name.ilike.%${v.trim()}%,'
                                    'email.ilike.%${v.trim()}%',
                                  )
                                  .limit(15);
                              // FIX: Guard sheet context after await
                              if (!sheetCtx.mounted) return;
                              setSheet(() {
                                results = List<Map<String, dynamic>>.from(res);
                                searching = false;
                              });
                            } catch (_) {
                              if (!sheetCtx.mounted) return;
                              setSheet(() => searching = false);
                            }
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (searching)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                        color: AdminColors.primary,
                        strokeWidth: 2,
                      ),
                    )
                  else
                    Expanded(
                      child: results.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.person_search_rounded,
                                    size: 40,
                                    color: AdminColors.textHint(sheetCtx),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    searchCtrl.text.length < 2
                                        ? 'Type to search customers'
                                        : 'No customers found',
                                    style: TextStyle(
                                      color: AdminColors.textHint(sheetCtx),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: results.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (_, i) {
                                final c = results[i];
                                return ListTile(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  tileColor: AdminColors.bg(sheetCtx),
                                  leading: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: AdminColors.primary.withAlpha(20),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.person_rounded,
                                      color: AdminColors.primary,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    c['full_name'] as String? ?? '',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AdminColors.text(sheetCtx),
                                    ),
                                  ),
                                  subtitle: Text(
                                    c['company_name'] as String? ??
                                        c['email'] as String? ??
                                        '',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AdminColors.textSub(sheetCtx),
                                    ),
                                  ),
                                  onTap: () => Navigator.pop(sheetCtx, c),
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

    debounce?.cancel();
    searchCtrl.dispose();
    if (selected != null && mounted) {
      setState(() {
        _customerId = selected['id'] as String?;
        _customerName = selected['full_name'] as String?;
        _customerCompany = selected['company_name'] as String?;
      });
    }
  }

  // FIX: Improved label
  Widget _buildLinkedTicket(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminColors.accent.withAlpha(isDark ? 25 : 15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.accent.withAlpha(50)),
      ),
      child: Row(
        children: [
          const Icon(Icons.link_rounded, size: 18, color: AdminColors.accent),
          const SizedBox(width: 10),
          Text(
            'Linked to Ticket: $_ticketNumber',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AdminColors.accent,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  2. LINE ITEMS
  // ═══════════════════════════════════════════════════════

  Widget _buildItemsSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Line Items'),
        const SizedBox(height: 8),
        if (_items.isEmpty)
          _card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.add_shopping_cart_rounded,
                      size: 40,
                      color: AdminColors.textHint(context),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No items added yet',
                      style: TextStyle(
                        color: AdminColors.textHint(context),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap "Add Item" or pick from catalog',
                      style: TextStyle(
                        color: AdminColors.textHint(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ..._items.asMap().entries.map(
                (e) => _itemCard(e.key, e.value, isDark),
              ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Item'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AdminColors.primary,
                  side: BorderSide(color: AdminColors.primary.withAlpha(80)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickCatalog,
                icon:
                    const Icon(Icons.precision_manufacturing_rounded, size: 18),
                label: const Text('From Catalog'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AdminColors.accent,
                  side: BorderSide(color: AdminColors.accent.withAlpha(80)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _itemCard(int idx, Map<String, dynamic> item, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Index badge
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AdminColors.primary.withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '${idx + 1}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['description'] as String? ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.text(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Item type badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AdminColors.primary.withAlpha(12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            (item['item_type'] as String? ?? 'product')
                                .toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AdminColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${item['quantity']} × Rs. ${_fmt.format(_dbl(item['unit_price']))}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AdminColors.textSub(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Rs. ${_fmt.format(_dbl(item['total_price']))}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.text(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Edit button
                      GestureDetector(
                        onTap: () => _editItem(idx),
                        child: Icon(
                          Icons.edit_rounded,
                          size: 16,
                          color: AdminColors.primary.withAlpha(160),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // FIX: Use spread copy — never direct removeAt
                      GestureDetector(
                        onTap: () => setState(() {
                          _items = [
                            ..._items.sublist(0, idx),
                            ..._items.sublist(idx + 1),
                          ];
                        }),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AdminColors.error.withAlpha(180),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Add / Edit Item Sheet ──
  Future<void> _addItem({int? editIndex}) async {
    final existing = editIndex != null ? _items[editIndex] : null;

    final descCtrl =
        TextEditingController(text: existing?['description'] as String? ?? '');
    final qtyCtrl = TextEditingController(
        text: existing != null ? existing['quantity'].toString() : '1');
    final priceCtrl = TextEditingController(
        text: existing != null ? _dbl(existing['unit_price']).toString() : '');
    String itemType = existing?['item_type'] as String? ?? 'product';

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            final qty = int.tryParse(qtyCtrl.text) ?? 0;
            final price = double.tryParse(priceCtrl.text) ?? 0.0;
            final lineTotal = qty * price;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AdminColors.card(sheetCtx),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                ),
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
                      editIndex != null ? 'Edit Line Item' : 'Add Line Item',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.text(sheetCtx),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _sheetField(sheetCtx, descCtrl, 'Description *'),
                    const SizedBox(height: 12),
                    _sheetDropdown(
                      sheetCtx,
                      itemType,
                      'Type',
                      const [
                        ('product', 'Product'),
                        ('service', 'Service'),
                        ('parts', 'Parts'),
                        ('labor', 'Labor'),
                      ],
                      (v) => setSheet(() => itemType = v ?? itemType),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _sheetField(
                            sheetCtx,
                            qtyCtrl,
                            'Qty',
                            keyboard: TextInputType.number,
                            onChanged: (_) => setSheet(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _sheetField(
                            sheetCtx,
                            priceCtrl,
                            'Unit Price (Rs.)',
                            keyboard: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (_) => setSheet(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Line total preview
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AdminColors.bg(sheetCtx),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Line Total',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AdminColors.textSub(sheetCtx),
                            ),
                          ),
                          Text(
                            'Rs. ${_fmt.format(lineTotal)}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: lineTotal > 0
                                  ? AdminColors.text(sheetCtx)
                                  : AdminColors.textHint(sheetCtx),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          final trimDesc = descCtrl.text.trim();
                          if (trimDesc.isEmpty || qty <= 0 || price <= 0) {
                            ScaffoldMessenger.of(sheetCtx).showSnackBar(
                              SnackBar(
                                content:
                                    const Text('Fill all fields correctly'),
                                backgroundColor: AdminColors.error,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                margin:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              ),
                            );
                            return;
                          }
                          final newItem = {
                            'description': trimDesc,
                            'item_type': itemType,
                            'quantity': qty,
                            'unit_price': price,
                            'total_price': lineTotal,
                            'catalog_machine_id':
                                existing?['catalog_machine_id'],
                          };
                          Navigator.pop(sheetCtx, newItem);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          editIndex != null ? 'Update Item' : 'Add Item',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    descCtrl.dispose();
    qtyCtrl.dispose();
    priceCtrl.dispose();
    if (result != null && mounted) {
      setState(() {
        if (editIndex != null) {
          _items = [
            ..._items.sublist(0, editIndex),
            result,
            ..._items.sublist(editIndex + 1),
          ];
        } else {
          _items = [..._items, result];
        }
      });
    }
  }

  // FIX: Edit delegates to _addItem with editIndex
  void _editItem(int index) => _addItem(editIndex: index);

  Future<void> _pickCatalog() async {
    final searchCtrl = TextEditingController();
    Timer? debounce;
    List<Map<String, dynamic>> machines = [];
    bool searching = false;
    bool loadingInitial = true;

    // Load initial catalog on open
    Future<void> loadInitialCatalog(StateSetter setSheet) async {
      try {
        final res = await _supabase
            .from('machine_catalog')
            .select(
              'id, machine_name,'
              ' model_number, brand,'
              ' price, category',
            )
            .eq('is_active', true)
            .order('machine_name')
            .limit(20);
        if (mounted) {
          setSheet(() {
            machines = List<Map<String, dynamic>>.from(res);
            loadingInitial = false;
            searching = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setSheet(() {
            loadingInitial = false;
            searching = false;
          });
        }
      }
    }

    final catalogResult = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            // Load initial catalog on first build — set flag immediately
            // to prevent re-entry on rebuilds while async is in-flight
            if (loadingInitial) {
              loadingInitial = false;
              searching = true;
              loadInitialCatalog(setSheet);
            }

            return Container(
              height: MediaQuery.of(sheetCtx).size.height * 0.75,
              decoration: BoxDecoration(
                color: AdminColors.card(sheetCtx),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AdminColors.border(sheetCtx),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Text(
                      'Pick from Catalog',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.text(sheetCtx),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      style: TextStyle(color: AdminColors.text(sheetCtx)),
                      decoration: InputDecoration(
                        hintText: 'Search machines…',
                        hintStyle:
                            TextStyle(color: AdminColors.textHint(sheetCtx)),
                        prefixIcon: Icon(Icons.search_rounded,
                            color: AdminColors.textHint(sheetCtx)),
                        filled: true,
                        fillColor: AdminColors.bg(sheetCtx),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onChanged: (v) {
                        debounce?.cancel();
                        debounce = Timer(
                          const Duration(milliseconds: 400),
                          () async {
                            if (v.trim().length < 2) {
                              setSheet(() => machines = []);
                              return;
                            }
                            setSheet(() => searching = true);
                            try {
                              final res = await _supabase
                                  .from('machine_catalog')
                                  .select(
                                    'id, machine_name,'
                                    ' model_number, brand,'
                                    ' price, category',
                                  )
                                  .eq('is_active', true)
                                  .or(
                                    'machine_name.ilike.%${v.trim()}%,'
                                    'model_number.ilike.%${v.trim()}%,'
                                    'brand.ilike.%${v.trim()}%',
                                  )
                                  .limit(10);
                              // FIX: Guard sheet context after await
                              if (!sheetCtx.mounted) return;
                              setSheet(() {
                                machines = List<Map<String, dynamic>>.from(res);
                                searching = false;
                              });
                            } catch (_) {
                              if (!sheetCtx.mounted) return;
                              setSheet(() => searching = false);
                            }
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (searching)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                        color: AdminColors.primary,
                        strokeWidth: 2,
                      ),
                    )
                  else
                    Expanded(
                      child: machines.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.precision_manufacturing_rounded,
                                    size: 40,
                                    color: AdminColors.textHint(sheetCtx),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    searchCtrl.text.length < 2
                                        ? 'Type to search catalog'
                                        : 'No machines found',
                                    style: TextStyle(
                                      color: AdminColors.textHint(sheetCtx),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: machines.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (_, i) {
                                final m = machines[i];
                                final price = _dbl(m['price']);
                                return ListTile(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  tileColor: AdminColors.bg(sheetCtx),
                                  leading: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: AdminColors.accent.withAlpha(20),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.precision_manufacturing_rounded,
                                      color: AdminColors.accent,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    m['machine_name'] as String? ?? '',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AdminColors.text(sheetCtx),
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${m['brand'] ?? ''} '
                                            '${m['model_number'] ?? ''}'
                                        .trim(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AdminColors.textSub(sheetCtx),
                                    ),
                                  ),
                                  trailing: price > 0
                                      ? Text(
                                          'Rs. ${_fmt.format(price)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: AdminColors.text(sheetCtx),
                                            fontSize: 13,
                                          ),
                                        )
                                      : null,
                                  onTap: () {
                                    final name = '${m['machine_name'] ?? ''}'
                                        '${m['model_number'] != null ? ' - ${m['model_number']}' : ''}';
                                    Navigator.pop(sheetCtx, {
                                      'description': name.trim(),
                                      'item_type': 'product',
                                      'quantity': 1,
                                      'unit_price': price,
                                      'total_price': price,
                                      'catalog_machine_id': m['id'],
                                    });
                                  },
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
    debounce?.cancel();
    searchCtrl.dispose();
    if (catalogResult != null && mounted) {
      setState(() {
        _items = [..._items, catalogResult];
      });
    }
  }

  // ═══════════════════════════════════════════════════════
  //  3. DISCOUNT & TAX
  // ═══════════════════════════════════════════════════════

  Widget _buildDiscountTax(bool isDark) {
    return _card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Discount & Tax',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AdminColors.text(context),
              ),
            ),
            const SizedBox(height: 14),
            // Discount row
            Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AdminColors.bg(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AdminColors.border(context)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _toggleChip(
                        '%',
                        _discountType == 'percentage',
                        () => setState(() => _discountType = 'percentage'),
                      ),
                      _toggleChip(
                        'Rs.',
                        _discountType == 'fixed',
                        () => setState(() => _discountType = 'fixed'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: AdminColors.text(context)),
                    decoration: InputDecoration(
                      hintText:
                          _discountType == 'percentage' ? '0 %' : '0.00 Rs.',
                      hintStyle: TextStyle(
                        color: AdminColors.textHint(context),
                        fontSize: 13,
                      ),
                      prefixText: _discountType == 'fixed' ? 'Rs. ' : null,
                      suffixText: _discountType == 'percentage' ? '%' : null,
                      prefixStyle:
                          TextStyle(color: AdminColors.textSub(context)),
                      suffixStyle:
                          TextStyle(color: AdminColors.textSub(context)),
                      filled: true,
                      fillColor: AdminColors.bg(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    onChanged: (v) => setState(
                      () => _discountValue = double.tryParse(v) ?? 0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Tax row
            Row(
              children: [
                Text(
                  'Tax Rate',
                  style: TextStyle(
                    fontSize: 13,
                    color: AdminColors.textSub(context),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 90,
                  // FIX: Use persistent _taxCtrl
                  child: TextField(
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    controller: _taxCtrl,
                    style: TextStyle(
                      color: AdminColors.text(context),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle:
                          TextStyle(color: AdminColors.textHint(context)),
                      suffixText: '%',
                      suffixStyle:
                          TextStyle(color: AdminColors.textSub(context)),
                      filled: true,
                      fillColor: AdminColors.bg(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 12),
                    ),
                    onChanged: (v) => setState(
                      () => _taxRate = double.tryParse(v) ?? 0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color:
              active ? AdminColors.primary.withAlpha(25) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? AdminColors.primary : AdminColors.textHint(context),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  4. FINANCIAL SUMMARY
  // ═══════════════════════════════════════════════════════

  Widget _buildSummary(bool isDark) {
    return _card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _sumRow('Subtotal', _subtotal),
            if (_discountAmount > 0)
              _sumRow(
                'Discount'
                '${_discountType == 'percentage' ? ' (${_discountValue.toStringAsFixed(1)}%)' : ''}',
                -_discountAmount,
                color: AdminColors.success,
              ),
            if (_taxAmount > 0)
              _sumRow(
                'Tax (${_taxRate.toStringAsFixed(1)}%)',
                _taxAmount,
              ),
            Divider(
              height: 24,
              color: AdminColors.divider(context),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.text(context),
                  ),
                ),
                Text(
                  'Rs. ${_fmt.format(_total)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sumRow(String label, double amount, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AdminColors.textSub(context),
            ),
          ),
          Text(
            // FIX: Use proper Unicode minus sign
            '${amount < 0 ? '− ' : ''}Rs. ${_fmt.format(amount.abs())}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color ?? AdminColors.text(context),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  5. DATES
  // ═══════════════════════════════════════════════════════

  Widget _buildDates(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _dateCard(
            'Issue Date',
            _issueDate,
            () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _issueDate,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              // FIX: mounted check after await
              if (!mounted) return;
              if (d != null) setState(() => _issueDate = d);
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _dateCard(
            'Valid Until',
            _validUntil,
            () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _validUntil,
                firstDate: _issueDate,
                lastDate: DateTime.now().add(const Duration(days: 730)),
              );
              // FIX: mounted check after await
              if (!mounted) return;
              if (d != null) setState(() => _validUntil = d);
            },
          ),
        ),
      ],
    );
  }

  Widget _dateCard(String label, DateTime date, VoidCallback onTap) {
    return _card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: AdminColors.textSub(context),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.calendar_today_rounded,
                    size: 16,
                    color: AdminColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('MMM d, yyyy').format(date),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AdminColors.text(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  6. NOTES
  // ═══════════════════════════════════════════════════════

  Widget _buildNotes(bool isDark) {
    return _card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notes & Terms',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AdminColors.text(context),
              ),
            ),
            const SizedBox(height: 14),
            _multiline(_notesCtrl, 'Customer-visible notes'),
            const SizedBox(height: 12),
            _multiline(_termsCtrl, 'Terms & conditions'),
            const SizedBox(height: 12),
            _multiline(_internalCtrl, 'Internal notes (admin only)'),
          ],
        ),
      ),
    );
  }

  Widget _multiline(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      maxLines: 3,
      minLines: 2,
      style: TextStyle(color: AdminColors.text(context), fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: AdminColors.textHint(context), fontSize: 13),
        filled: true,
        fillColor: AdminColors.bg(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  7. BOTTOM BAR
  // ═══════════════════════════════════════════════════════

  Widget _buildBottomBar(bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: AdminColors.card(context),
        border: Border(top: BorderSide(color: AdminColors.border(context))),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => _save(false),
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminColors.primary,
                side: BorderSide(color: AdminColors.primary.withAlpha(80)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AdminColors.primary,
                      ),
                    )
                  : const Text(
                      'Save Draft',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _saving ? null : () => _save(true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: _saving
                      ? null
                      : const LinearGradient(
                          colors: [Color(0xFF6D28D9), _kQuotationPurple],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  color: _saving ? _kQuotationPurple : null,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: isDark || _saving
                      ? null
                      : [
                          BoxShadow(
                            color: _kQuotationPurple.withAlpha(89),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Center(
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.send_rounded,
                                size: 18, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'Send Quotation',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  SAVE
  // ═══════════════════════════════════════════════════════

  Future<void> _save(bool send) async {
    if (_currentUserId == null) {
      _snack('Session expired, please re-login', isError: true);
      return;
    }
    if (_customerId == null || _customerId!.trim().isEmpty) {
      _snack('Please select a customer', isError: true);
      return;
    }
    if (_items.isEmpty) {
      _snack('Add at least one item', isError: true);
      return;
    }
    if (_validUntil.isBefore(_issueDate)) {
      _snack('Valid-until date must be after issue date', isError: true);
      return;
    }
    // FIX: Discount validation
    if (_discountType == 'fixed' && _discountValue > _subtotal) {
      _snack('Discount cannot exceed subtotal', isError: true);
      return;
    }
    if (_discountType == 'percentage' && _discountValue > 100) {
      _snack('Percentage discount cannot exceed 100%', isError: true);
      return;
    }

    setState(() => _saving = true);

    try {
      // 1) Insert quotation
      final qRes = await _supabase
          .from('quotations')
          .insert({
            'customer_id': _customerId,
            'ticket_id': _ticketId,
            'subtotal': _subtotal,
            'discount_type': _discountType,
            'discount_value': _discountValue,
            'discount_amount': _discountAmount,
            'tax_rate': _taxRate,
            'tax_amount': _taxAmount,
            'total_amount': _total,
            'status': 'draft',
            'issue_date': _issueDate.toIso8601String().split('T')[0],
            'valid_until': _validUntil.toIso8601String().split('T')[0],
            'notes':
                _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
            'terms':
                _termsCtrl.text.trim().isEmpty ? null : _termsCtrl.text.trim(),
            'internal_notes': _internalCtrl.text.trim().isEmpty
                ? null
                : _internalCtrl.text.trim(),
            'created_by': _currentUserId,
          })
          .select('id')
          .single();

      if (!mounted) return;
      final qId = qRes['id'] as String;

      // 2) Batch-insert line items
      final itemInserts = _items
          .asMap()
          .entries
          .map(
            (e) => {
              'quotation_id': qId,
              'item_type': e.value['item_type'] ?? 'product',
              'description': e.value['description'],
              'catalog_machine_id': e.value['catalog_machine_id'],
              'quantity': e.value['quantity'],
              'unit_price': e.value['unit_price'],
              'total_price': e.value['total_price'],
              'display_order': e.key + 1,
            },
          )
          .toList();

      await _supabase.from('quotation_items').insert(itemInserts);
      if (!mounted) return;

      // 3) Optionally send (draft → sent)
      if (send) {
        try {
          await _supabase.rpc('send_quotation', params: {
            'p_quotation_id': qId,
            'p_admin_id': _currentUserId,
          });
        } catch (rpcErr) {
          debugPrint('send_quotation RPC failed, using fallback: $rpcErr');
          // Fallback if RPC not available
          await _supabase.from('quotations').update({
            'status': 'sent',
            'sent_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', qId);
        }
        if (!mounted) return;
      }

      _snack(send ? 'Quotation sent!' : 'Draft saved!');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('createQuotation save failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(
        'Failed to save quotation. Please try again.',
        isError: true,
      );
    }
  }

  // ═══════════════════════════════════════════════════════
  //  SHARED HELPERS
  // ═══════════════════════════════════════════════════════

  Widget _card({required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(AdminDimens.cardRadius),
         border: isDark
         ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(10),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AdminColors.text(context),
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _sheetField(
    BuildContext ctx,
    TextEditingController ctrl,
    String label, {
    TextInputType? keyboard,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      style: TextStyle(color: AdminColors.text(ctx), fontSize: 14),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AdminColors.textSub(ctx), fontSize: 13),
        filled: true,
        fillColor: AdminColors.bg(ctx),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  Widget _sheetDropdown(
    BuildContext ctx,
    String value,
    String label,
    List<(String, String)> items,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      items: items
          .map(
            (e) => DropdownMenuItem(
              value: e.$1,
              child: Text(
                e.$2,
                style: TextStyle(color: AdminColors.text(ctx), fontSize: 14),
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
      style: TextStyle(color: AdminColors.text(ctx), fontSize: 14),
      dropdownColor: AdminColors.card(ctx),
      icon: Icon(Icons.expand_more_rounded, color: AdminColors.textSub(ctx)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AdminColors.textSub(ctx), fontSize: 13),
        filled: true,
        fillColor: AdminColors.bg(ctx),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }
}
