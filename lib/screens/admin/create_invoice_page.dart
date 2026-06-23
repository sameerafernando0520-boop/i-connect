import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/supabase_config.dart';

class CreateInvoicePage extends StatefulWidget {
  final String? customerId;
  final String? ticketId;
  final String? customerName;
  final String? customerCompany;

  const CreateInvoicePage({
    super.key,
    this.customerId,
    this.ticketId,
    this.customerName,
    this.customerCompany,
  });

  @override
  State<CreateInvoicePage> createState() => _CreateInvoicePageState();
}

class _CreateInvoicePageState extends State<CreateInvoicePage> {
  final _supabase = SupabaseConfig.client;
  final _fmt = NumberFormat('#,##0.00', 'en_US');

  // ── State ──
  bool _loading = true;
  bool _saving = false;

  String? _customerId;
  String? _customerName;
  String? _customerCompany;
  String? _ticketId;
  String? _ticketNumber;

  List<Map<String, dynamic>> _items = [];

  String _discountType = 'percentage'; // percentage | fixed
  double _discountValue = 0;
  double _taxRate = 0;

  late DateTime _issueDate;
  late DateTime _dueDate;

  final _notesCtrl = TextEditingController();
  final _termsCtrl = TextEditingController();
  final _internalCtrl = TextEditingController();
  // Persistent tax-rate controller — was previously instantiated inline
  // inside build() which recreated the controller every frame, causing
  // _dependents.isEmpty assertion crashes when the page rebuilt while
  // the field was focused.
  final _taxCtrl = TextEditingController();

  String? _currentUserId;

  // ── Computed ──
  double get _subtotal =>
      _items.fold(0, (s, i) => s + (_dbl(i['total_price'])));
  double get _discountAmount => _discountType == 'percentage'
      ? _subtotal * _discountValue / 100
      : _discountValue;
  double get _taxableAmount =>
      (_subtotal - _discountAmount).clamp(0, double.infinity);
  double get _taxAmount => _taxableAmount * _taxRate / 100;
  double get _total => _taxableAmount + _taxAmount;

  double _dbl(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  // M1: Round currency values to 2 decimals for persistence. Floating-point
  // arithmetic on subtotal/tax/discount accumulates imprecision (e.g. 19.999999
  // instead of 20.00). Always round before INSERT so the DB holds clean values
  // regardless of display formatting.
  double _round2(double v) => (v * 100).roundToDouble() / 100;

  // ── Lifecycle ──
  @override
  void initState() {
    super.initState();
    _currentUserId = _supabase.auth.currentUser?.id;
    _issueDate = DateTime.now();
    _dueDate = DateTime.now().add(const Duration(days: 30));
    _customerId = widget.customerId;
    _customerName = widget.customerName;
    _customerCompany = widget.customerCompany;
    _ticketId = widget.ticketId;
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
      final results = await Future.wait(<Future<dynamic>>[
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
        if (_ticketId != null)
          _supabase
              .from('service_tickets')
              .select('ticket_number')
              .eq('id', _ticketId!)
              .maybeSingle()
        else
          Future.value(null),
      ]);

      if (!mounted) return;
      final tax = results[0] as Map<String, dynamic>?;
      final company = results[1] as Map<String, dynamic>?;
      final ticket = results[2] as Map<String, dynamic>?;

      setState(() {
        _taxRate = _dbl(tax?['tax_rate']);
        _taxCtrl.text = _taxRate > 0 ? _taxRate.toString() : '';
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

  // ═════════════════════════════════════════════════════════
  //  BUILD
  // ═════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Brand.darkBg : AdminColors.background,
      appBar: DsPageHeader(
        title: 'Create Invoice',
        accent: HeroAccent.navy,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                    color: AdminColors.primary, strokeWidth: 3))
            : Column(
                children: [
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
                          _buildFinancialSummary(isDark),
                          const SizedBox(height: 20),
                          _buildDates(isDark),
                          const SizedBox(height: 20),
                          _buildNotesSection(isDark),
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

  // ═════════════════════════════════════════════════════════
  //  1. CUSTOMER SELECTION

  // ═════════════════════════════════════════════════════════

  Widget _buildCustomerSection(bool isDark) {
    return _card(
      isDark: isDark,
      child: InkWell(
        onTap: _selectCustomer,
        borderRadius: BorderRadius.circular(Brand.r(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AdminColors.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(Brand.r(12)),
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
              Icon(Icons.chevron_right_rounded,
                  color: AdminColors.textHint(context), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectCustomer() async {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool searching = false;
    Timer? debounce;

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            return Container(
              height: MediaQuery.of(sheetCtx).size.height * 0.7,
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
                      borderRadius: BorderRadius.circular(Brand.r(2)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
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
                          borderRadius: BorderRadius.circular(Brand.r(14)),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onChanged: (v) {
                        debounce?.cancel();
                        debounce =
                            Timer(const Duration(milliseconds: 400), () async {
                          if (v.trim().length < 2) {
                            setSheet(() => results = []);
                            return;
                          }
                          setSheet(() => searching = true);
                          try {
                            final res = await _supabase
                                .from('users')
                                .select('id, full_name, company_name, email')
                                .eq('role', 'customer')
                                .or('full_name.ilike.%${v.trim()}%,'
                                    'company_name.ilike.%${v.trim()}%,'
                                    'email.ilike.%${v.trim()}%')
                                .limit(15);
                            if (!sheetCtx.mounted) return;
                            setSheet(() {
                              results = List<Map<String, dynamic>>.from(res);
                              searching = false;
                            });
                          } catch (_) {
                            if (!sheetCtx.mounted) return;
                            setSheet(() => searching = false);
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (searching)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                          color: AdminColors.primary, strokeWidth: 2),
                    )
                  else
                    Expanded(
                      child: results.isEmpty
                          ? Center(
                              child: Text(
                                searchCtrl.text.length < 2
                                    ? 'Type to search customers'
                                    : 'No customers found',
                                style: TextStyle(
                                    color: AdminColors.textHint(sheetCtx)),
                              ),
                            )
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: results.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (_, i) {
                                final c = results[i];
                                return ListTile(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(Brand.r(14)),
                                  ),
                                  tileColor: AdminColors.bg(sheetCtx),
                                  leading: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: AdminColors.primary.withAlpha(20),
                                      borderRadius: BorderRadius.circular(Brand.r(10)),
                                    ),
                                    child: const Icon(Icons.person_rounded,
                                        color: AdminColors.primary, size: 20),
                                  ),
                                  title: Text(
                                    c['full_name'] ?? '',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AdminColors.text(sheetCtx),
                                    ),
                                  ),
                                  subtitle: Text(
                                    c['company_name'] ?? c['email'] ?? '',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AdminColors.textSub(sheetCtx),
                                    ),
                                  ),
                                  onTap: () {
                                    debounce?.cancel();
                                    Navigator.pop(sheetCtx, c);
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
    if (selected != null && mounted) {
      setState(() {
        _customerId = selected['id'];
        _customerName = selected['full_name'];
        _customerCompany = selected['company_name'];
      });
    }
  }

  // ═════════════════════════════════════════════════════════
  //  2. LINKED TICKET
  // ═════════════════════════════════════════════════════════

  Widget _buildLinkedTicket(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminColors.accent.withAlpha(isDark ? 20 : 12),
        borderRadius: BorderRadius.circular(Brand.r(12)),
        border: Border.all(color: AdminColors.accent.withAlpha(40)),
      ),
      child: Row(
        children: [
          const Icon(Icons.link_rounded, size: 18, color: AdminColors.accent),
          const SizedBox(width: 10),
          Text(
            'Linked: $_ticketNumber',
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

  // ═════════════════════════════════════════════════════════
  //  3. LINE ITEMS
  // ═════════════════════════════════════════════════════════

  Widget _buildItemsSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Line Items', isDark),
        const SizedBox(height: 8),
        if (_items.isEmpty)
          _card(
            isDark: isDark,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.add_shopping_cart_rounded,
                        size: 36, color: AdminColors.textHint(context)),
                    const SizedBox(height: 8),
                    Text(
                      'No items added yet',
                      style: TextStyle(color: AdminColors.textHint(context)),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ..._items
              .asMap()
              .entries
              .map((e) => _buildItemCard(e.key, e.value, isDark)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _addItem(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Item'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AdminColors.primary,
                  side: BorderSide(color: AdminColors.primary.withAlpha(80)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Brand.r(12))),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickFromCatalog(),
                icon:
                    const Icon(Icons.precision_manufacturing_rounded, size: 18),
                label: const Text('From Catalog'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AdminColors.accent,
                  side: BorderSide(color: AdminColors.accent.withAlpha(80)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Brand.r(12))),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildItemCard(int index, Map<String, dynamic> item, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => _editItem(index),
        child: _card(
          isDark: isDark,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AdminColors.primary.withAlpha(15),
                    borderRadius: BorderRadius.circular(Brand.r(8)),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
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
                        item['description'] ?? '',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AdminColors.text(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item['quantity']} × Rs. ${_fmt.format(_dbl(item['unit_price']))}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AdminColors.textSub(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Rs. ${_fmt.format(_dbl(item['total_price']))}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.text(context),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _items.removeAt(index)),
                  child: Icon(Icons.close_rounded,
                      size: 18, color: AdminColors.error.withAlpha(180)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Add/Edit Item Sheet ──
  Future<void> _addItem({int? editIndex}) async {
    final isEditing = editIndex != null;
    final existing = isEditing ? _items[editIndex] : null;

    final descCtrl = TextEditingController(
      text: existing?['description'] ?? '',
    );
    final qtyCtrl = TextEditingController(
      text: '${existing?['quantity'] ?? 1}',
    );
    final priceCtrl = TextEditingController(
      text: existing?['unit_price']?.toString() ?? '',
    );
    String itemType = existing?['item_type'] ?? 'product';

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            final qty = int.tryParse(qtyCtrl.text) ?? 0;
            final price = double.tryParse(priceCtrl.text) ?? 0;
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
                          borderRadius: BorderRadius.circular(Brand.r(2)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      isEditing ? 'Edit Line Item' : 'Add Line Item',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.text(sheetCtx),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _sheetField(
                      ctx: sheetCtx,
                      ctrl: descCtrl,
                      label: 'Description *',
                      hint: 'e.g. Industrial Compressor XR-500',
                    ),
                    const SizedBox(height: 12),
                    _sheetDropdown(
                      ctx: sheetCtx,
                      value: itemType,
                      label: 'Type',
                      items: const [
                        ('product', 'Product'),
                        ('service', 'Service'),
                        ('parts', 'Parts'),
                        ('labor', 'Labor'),
                      ],
                      onChanged: (v) =>
                          setSheet(() => itemType = v ?? itemType),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _sheetField(
                            ctx: sheetCtx,
                            ctrl: qtyCtrl,
                            label: 'Qty',
                            keyboard: TextInputType.number,
                            // H7: strip anything that isn't a digit so users
                            // literally can't type a leading `-` or decimal
                            // and end up with a negative / fractional qty.
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (_) => setSheet(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _sheetField(
                            ctx: sheetCtx,
                            ctrl: priceCtrl,
                            label: 'Unit Price (Rs.)',
                            keyboard: const TextInputType.numberWithOptions(
                                decimal: true),
                            // H7: allow only digits + a single decimal point
                            // → no minus signs, no exponents, no currency chars.
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.]')),
                            ],
                            onChanged: (_) => setSheet(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AdminColors.bg(sheetCtx),
                        borderRadius: BorderRadius.circular(Brand.r(12)),
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
                              color: AdminColors.text(sheetCtx),
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
                          // H7: give the user concrete feedback instead of a
                          // silent no-op when validation fails, and block
                          // negative/zero amounts from producing bogus totals.
                          String? err;
                          if (descCtrl.text.trim().isEmpty) {
                            err = 'Please enter a description.';
                          } else if (qty <= 0) {
                            err = 'Quantity must be greater than zero.';
                          } else if (price <= 0) {
                            err = 'Unit price must be greater than zero.';
                          }
                          if (err != null) {
                            ScaffoldMessenger.of(sheetCtx).showSnackBar(
                              SnackBar(
                                content: Text(err),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }
                          final newItem = {
                            'description': descCtrl.text.trim(),
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
                            borderRadius: BorderRadius.circular(Brand.r(14)),
                          ),
                        ),
                        child: Text(
                          isEditing ? 'Update Item' : 'Add Item',
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
        if (isEditing) {
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

  // ── Edit Item ──
  void _editItem(int index) => _addItem(editIndex: index);

  // ── Catalog Picker ──
  Future<void> _pickFromCatalog() async {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> machines = [];
    bool searching = false;
    bool loadingInitial = true;
    Timer? debounce;

    // Load initial catalog on open
    Future<void> loadInitialCatalog(
        StateSetter setSheet, BuildContext ctx) async {
      try {
        final res = await _supabase
            .from('machine_catalog')
            .select('id, machine_name, model_number, brand, price')
            .eq('is_active', true)
            .order('machine_name')
            .limit(20);
        if (ctx.mounted) {
          setSheet(() {
            machines = List<Map<String, dynamic>>.from(res);
            loadingInitial = false;
            searching = false;
          });
        }
      } catch (_) {
        if (ctx.mounted) {
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
              loadInitialCatalog(setSheet, sheetCtx);
            }

            return Container(
              height: MediaQuery.of(sheetCtx).size.height * 0.7,
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
                      borderRadius: BorderRadius.circular(Brand.r(2)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
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
                          borderRadius: BorderRadius.circular(Brand.r(14)),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (v) {
                        debounce?.cancel();
                        debounce =
                            Timer(const Duration(milliseconds: 400), () async {
                          if (v.trim().length < 2) {
                            setSheet(() => machines = []);
                            return;
                          }
                          setSheet(() => searching = true);
                          try {
                            final res = await _supabase
                                .from('machine_catalog')
                                .select(
                                    'id, machine_name, model_number, brand, price')
                                .eq('is_active', true)
                                .or('machine_name.ilike.%${v.trim()}%,'
                                    'model_number.ilike.%${v.trim()}%,'
                                    'brand.ilike.%${v.trim()}%')
                                .limit(10);
                            if (!sheetCtx.mounted) return;
                            setSheet(() {
                              machines = List<Map<String, dynamic>>.from(res);
                              searching = false;
                            });
                          } catch (_) {
                            if (!sheetCtx.mounted) return;
                            setSheet(() => searching = false);
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (searching)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                          color: AdminColors.primary, strokeWidth: 2),
                    )
                  else
                    Expanded(
                      child: machines.isEmpty
                          ? Center(
                              child: Text(
                                searchCtrl.text.length < 2
                                    ? 'Type to search catalog'
                                    : 'No machines found',
                                style: TextStyle(
                                    color: AdminColors.textHint(sheetCtx)),
                              ),
                            )
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: machines.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (_, i) {
                                final m = machines[i];
                                final price = _dbl(m['price']);
                                return ListTile(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(Brand.r(14)),
                                  ),
                                  tileColor: AdminColors.bg(sheetCtx),
                                  leading: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: AdminColors.accent.withAlpha(20),
                                      borderRadius: BorderRadius.circular(Brand.r(10)),
                                    ),
                                    child: const Icon(
                                        Icons.precision_manufacturing_rounded,
                                        color: AdminColors.accent,
                                        size: 20),
                                  ),
                                  title: Text(
                                    m['machine_name'] ?? '',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AdminColors.text(sheetCtx),
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${m['brand'] ?? ''} ${m['model_number'] ?? ''}'
                                        .trim(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AdminColors.textSub(sheetCtx),
                                    ),
                                  ),
                                  trailing: Text(
                                    price > 0
                                        ? 'Rs. ${_fmt.format(price)}'
                                        : '',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AdminColors.text(sheetCtx),
                                    ),
                                  ),
                                  onTap: () {
                                    debounce?.cancel();
                                    final name = '${m['machine_name'] ?? ''}'
                                        '${m['model_number'] != null ? ' - ${m['model_number']}' : ''}';
                                    Navigator.pop(sheetCtx, {
                                      'description': name,
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

  // ═════════════════════════════════════════════════════════
  //  4. DISCOUNT & TAX
  // ═════════════════════════════════════════════════════════

  Widget _buildDiscountTax(bool isDark) {
    return _card(
      isDark: isDark,
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
                // Type toggle
                Container(
                  decoration: BoxDecoration(
                    color: AdminColors.bg(context),
                    borderRadius: BorderRadius.circular(Brand.r(10)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _toggleChip(
                        label: '%',
                        active: _discountType == 'percentage',
                        onTap: () =>
                            setState(() => _discountType = 'percentage'),
                      ),
                      _toggleChip(
                        label: 'Rs.',
                        active: _discountType == 'fixed',
                        onTap: () => setState(() => _discountType = 'fixed'),
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
                      hintText: 'Discount value',
                      hintStyle: TextStyle(
                          color: AdminColors.textHint(context), fontSize: 13),
                      filled: true,
                      fillColor: AdminColors.bg(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Brand.r(10)),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    onChanged: (v) => setState(
                        () => _discountValue = double.tryParse(v) ?? 0),
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
                  width: 80,
                  child: TextField(
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    controller: _taxCtrl,
                    style: TextStyle(
                        color: AdminColors.text(context), fontSize: 14),
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
                        borderRadius: BorderRadius.circular(Brand.r(10)),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 12),
                    ),
                    onChanged: (v) =>
                        setState(() => _taxRate = double.tryParse(v) ?? 0),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleChip(
      {required String label,
      required bool active,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color:
              active ? AdminColors.primary.withAlpha(25) : Colors.transparent,
          borderRadius: BorderRadius.circular(Brand.r(8)),
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

  // ═════════════════════════════════════════════════════════
  //  5. FINANCIAL SUMMARY
  // ═════════════════════════════════════════════════════════

  Widget _buildFinancialSummary(bool isDark) {
    return _card(
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _summaryRow('Subtotal', _subtotal, isDark),
            if (_discountAmount > 0)
              _summaryRow(
                  'Discount${_discountType == 'percentage' ? ' (${_discountValue.toStringAsFixed(1)}%)' : ''}',
                  -_discountAmount,
                  isDark,
                  color: AdminColors.success),
            if (_taxAmount > 0)
              _summaryRow(
                  'Tax (${_taxRate.toStringAsFixed(1)}%)', _taxAmount, isDark),
            const Divider(height: 20),
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

  Widget _summaryRow(String label, double amount, bool isDark, {Color? color}) {
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
            '${amount < 0 ? '- ' : ''}Rs. ${_fmt.format(amount.abs())}',
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

  // ═════════════════════════════════════════════════════════
  //  6. DATES
  // ═════════════════════════════════════════════════════════

  Widget _buildDates(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _dateCard(
            isDark: isDark,
            label: 'Issue Date',
            date: _issueDate,
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _issueDate,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (d != null) setState(() => _issueDate = d);
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _dateCard(
            isDark: isDark,
            label: 'Due Date',
            date: _dueDate,
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _dueDate,
                firstDate: _issueDate,
                lastDate: DateTime.now().add(const Duration(days: 730)),
              );
              if (d != null) setState(() => _dueDate = d);
            },
          ),
        ),
      ],
    );
  }

  Widget _dateCard({
    required bool isDark,
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return _card(
      isDark: isDark,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Brand.r(16)),
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
                  const Icon(Icons.calendar_today_rounded,
                      size: 16, color: AdminColors.primary),
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

  // ═════════════════════════════════════════════════════════
  //  7. NOTES
  // ═════════════════════════════════════════════════════════

  Widget _buildNotesSection(bool isDark) {
    return _card(
      isDark: isDark,
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
            _multilineField(context, _notesCtrl, 'Customer-visible notes'),
            const SizedBox(height: 12),
            _multilineField(context, _termsCtrl, 'Terms & conditions'),
            const SizedBox(height: 12),
            _multilineField(
                context, _internalCtrl, 'Internal notes (admin only)'),
          ],
        ),
      ),
    );
  }

  Widget _multilineField(
      BuildContext ctx, TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      maxLines: 3,
      minLines: 2,
      style: TextStyle(color: AdminColors.text(ctx), fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AdminColors.textHint(ctx), fontSize: 13),
        filled: true,
        fillColor: AdminColors.bg(ctx),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.r(12)),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  //  8. BOTTOM ACTION BAR
  // ═════════════════════════════════════════════════════════

  Widget _buildBottomBar(bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: AdminColors.card(context),
        border: Border(
          top: BorderSide(color: AdminColors.border(context)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => _saveInvoice(false),
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminColors.primary,
                side: BorderSide(color: AdminColors.primary.withAlpha(80)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Brand.r(14))),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AdminColors.primary),
                    )
                  : const Text('Save Draft',
                      style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _saving ? null : () => _saveInvoice(true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: _saving
                      ? null
                      : const LinearGradient(
                          colors: [Brand.royalBlueDark, Brand.royalBlueLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  color: _saving ? AdminColors.primary : null,
                  borderRadius: BorderRadius.circular(Brand.r(14)),
                  boxShadow: isDark || _saving
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
                              'Send Invoice',
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

  // ═════════════════════════════════════════════════════════
  //  SAVE
  // ═════════════════════════════════════════════════════════

  Future<void> _saveInvoice(bool send) async {
    // M3: Re-entry guard. The Save/Send buttons already disable when _saving is
    // true, but a rapid double-tap can fire this callback twice before setState
    // reaches the next frame. Without this early return we'd insert two
    // invoices for one user action.
    if (_saving) return;

    if (_customerId == null) {
      _snack('Please select a customer', isError: true);
      return;
    }
    if (_items.isEmpty) {
      _snack('Please add at least one item', isError: true);
      return;
    }
    if (_dueDate.isBefore(_issueDate)) {
      _snack('Due date cannot be before issue date', isError: true);
      return;
    }

    setState(() => _saving = true);

    try {
      // M1: Snapshot rounded monetary values once so every derived field
      // (balance_due, totals) stays internally consistent at the cent level.
      final subtotal = _round2(_subtotal);
      final discountAmount = _round2(_discountAmount);
      final taxAmount = _round2(_taxAmount);
      final total = _round2(_total);

      // 1) Insert invoice (trigger auto-generates number)
      final invoiceRes = await _supabase
          .from('invoices')
          .insert({
            'customer_id': _customerId,
            'ticket_id': _ticketId,
            'subtotal': subtotal,
            'discount_type': _discountType,
            'discount_value': _discountValue,
            'discount_amount': discountAmount,
            'tax_rate': _taxRate,
            'tax_amount': taxAmount,
            'total_amount': total,
            'amount_paid': 0,
            'balance_due': total,
            'status': 'draft',
            'issue_date': _issueDate.toIso8601String().split('T')[0],
            'due_date': _dueDate.toIso8601String().split('T')[0],
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
      final invoiceId = invoiceRes['id'] as String;

      // 2) Batch-insert line items
      final itemInserts = _items
          .asMap()
          .entries
          .map((e) => {
                'invoice_id': invoiceId,
                'item_type': e.value['item_type'] ?? 'product',
                'description': e.value['description'],
                'catalog_machine_id': e.value['catalog_machine_id'],
                'quantity': e.value['quantity'],
                'unit_price': e.value['unit_price'],
                'total_price': e.value['total_price'],
                'display_order': e.key + 1,
              })
          .toList();

      await _supabase.from('invoice_items').insert(itemInserts);
      if (!mounted) return;

      // 3) Optionally send
      if (send) {
        await _supabase.rpc('send_invoice', params: {
          'p_invoice_id': invoiceId,
          'p_admin_id': _currentUserId,
        });
        if (!mounted) return;
      }

      _snack(send ? 'Invoice sent!' : 'Draft saved');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Failed: $e', isError: true);
    }
  }

  // ═════════════════════════════════════════════════════════
  //  SHARED HELPERS
  // ═════════════════════════════════════════════════════════

  Widget _card({required bool isDark, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
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

  Widget _sectionTitle(String text, bool isDark) {
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

  Widget _sheetField({
    required BuildContext ctx,
    required TextEditingController ctrl,
    required String label,
    TextInputType? keyboard,
    ValueChanged<String>? onChanged,
    String? hint,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      inputFormatters: inputFormatters,
      style: TextStyle(color: AdminColors.text(ctx), fontSize: 14),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: AdminColors.textSub(ctx), fontSize: 13),
        hintStyle: TextStyle(color: AdminColors.textHint(ctx), fontSize: 13),
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

  Widget _sheetDropdown({
    required BuildContext ctx,
    required String value,
    required String label,
    required List<(String, String)> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      items: items
          .map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2)))
          .toList(),
      onChanged: onChanged,
      style: TextStyle(color: AdminColors.text(ctx), fontSize: 14),
      dropdownColor: AdminColors.card(ctx),
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

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          isError
              ? Icons.error_outline_rounded
              : Icons.check_circle_outline_rounded,
          color: Colors.white,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: const TextStyle(fontSize: 13))),
      ]),
      backgroundColor: isError ? AdminColors.error : AdminColors.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ));
  }
}
