// lib/screens/admin/admin_register_machine_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/supabase_config.dart';
import '../../services/points_service.dart';

class AdminRegisterMachinePage extends StatefulWidget {
  final String? preSelectedCustomerId;
  const AdminRegisterMachinePage({
    super.key,
    this.preSelectedCustomerId,
  });

  @override
  State<AdminRegisterMachinePage> createState() =>
      _AdminRegisterMachinePageState();
}

class _AdminRegisterMachinePageState extends State<AdminRegisterMachinePage> {
  // ── State ──
  bool _isLoading = true;
  bool _isSaving = false;
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _machines = [];
  Map<String, dynamic>? _selectedCustomer;
  Map<String, dynamic>? _selectedMachine;

  // ── Machine Details ──
  final _serialCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  DateTime? _purchaseDate;
  DateTime? _warrantyEnd;
  DateTime? _nextServiceDue;

  // ── Installment ──
  bool _hasInstallment = false;
  DateTime? _receiptDate;
  final _totalPriceCtrl = TextEditingController();
  final _downPaymentCtrl = TextEditingController();
  final _interestCtrl = TextEditingController();
  final _numInstCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _showSchedule = false;

  // ── Computed ──
  double get _totalPrice =>
      double.tryParse(
        _totalPriceCtrl.text.replaceAll(',', ''),
      ) ??
      0;
  double get _downPayment =>
      double.tryParse(
        _downPaymentCtrl.text.replaceAll(',', ''),
      ) ??
      0;
  double get _interestRate => double.tryParse(_interestCtrl.text) ?? 0;
  int get _numInst => int.tryParse(_numInstCtrl.text) ?? 0;
  double get _remaining =>
      (_totalPrice - _downPayment).clamp(0, double.infinity);
  double get _interestAmt => _remaining * (_interestRate / 100);
  double get _totalPayable => _remaining + _interestAmt;
  double get _monthlyAmt => _numInst > 0 ? _totalPayable / _numInst : 0;
  bool get _canPreview =>
      _totalPrice > 0 &&
      _downPayment >= 0 &&
      _downPayment < _totalPrice &&
      _numInst > 0;

  // ── Formatters ──
  final _cf = NumberFormat('#,##0.00', 'en_US');
  String _fmtCur(double v) => 'Rs. ${_cf.format(v)}';
  String _fmtDate(DateTime? d) =>
      d != null ? DateFormat('MMM dd, yyyy').format(d) : 'Not set';

  // ── Dark mode ──
  bool _isDark = false;

  // FIX: replaced AdminColors.background/surface/textPrimary (non-existent
  // static consts) with Brand equivalents + AdminColors context methods
  Color get _bg => Brand.canvas(_isDark);
  Color get _cardBg => Brand.surface(_isDark);
  Color get _inputBg => Brand.canvas(_isDark);
  Color get _primary => _isDark ? Brand.royalBlueGlow : AdminColors.primary;
  Color get _accent => _isDark ? Brand.lightGreenBright : AdminColors.accent;
  Color get _textPrimary =>
      _isDark ? Brand.darkTextPrimary : const Color(0xFF1A1A2E);
  Color get _textSecondary =>
      _isDark ? Brand.darkTextSecondary : const Color(0xFF64748B);
  Color get _textMuted =>
      _isDark ? Brand.darkTextTertiary : const Color(0xFF94A3B8);
  Color get _border => _isDark ? Brand.darkBorder : Brand.borderLight;
  Color get _handleColor =>
      _isDark ? Brand.darkBorderLight : const Color(0xFFCBD5E1);

  List<BoxShadow> get _cardShadow => _isDark
      ? []
      : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ];

  // ── Lifecycle ──
  @override
  void initState() {
    super.initState();
    _loadData();
    for (final c in [
      _totalPriceCtrl,
      _downPaymentCtrl,
      _interestCtrl,
      _numInstCtrl,
    ]) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    for (final c in [
      _serialCtrl,
      _addressCtrl,
      _totalPriceCtrl,
      _downPaymentCtrl,
      _interestCtrl,
      _numInstCtrl,
      _notesCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Data Loading ──
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait<dynamic>([
        SupabaseConfig.client
            .from('users')
            .select(
              'id, full_name, email, phone_number, company_name',
            )
            .eq('role', 'customer')
            .order('full_name'),
        SupabaseConfig.client
            .from('machine_catalog')
            .select()
            .eq('is_active', true)
            .order('machine_name'),
      ]);
      if (!mounted) return;
      final customers = List<Map<String, dynamic>>.from(results[0] as List);
      final machines = List<Map<String, dynamic>>.from(results[1] as List);

      Map<String, dynamic>? preSelected;
      if (widget.preSelectedCustomerId != null) {
        try {
          preSelected = customers.firstWhere(
            (c) => c['id'] == widget.preSelectedCustomerId,
          );
        } catch (_) {
          preSelected = null;
        }
      }

      setState(() {
        _customers = customers;
        _machines = machines;
        _isLoading = false;
        if (preSelected != null) {
          _selectedCustomer = preSelected;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack('Failed to load data: $e', isError: true);
    }
  }

  // ── Date Helpers ──
  DateTime _addMonths(DateTime d, int m) {
    var nm = d.month + m;
    var ny = d.year + (nm - 1) ~/ 12;
    nm = ((nm - 1) % 12) + 1;
    var day = d.day;
    final last = DateTime(ny, nm + 1, 0).day;
    if (day > last) day = last;
    return DateTime(ny, nm, day);
  }

  List<Map<String, dynamic>> _buildSchedule() {
    if (!_canPreview || _receiptDate == null) return [];
    final mo = double.parse(_monthlyAmt.toStringAsFixed(2));
    return List.generate(_numInst, (i) {
      final n = i + 1;
      return {
        'number': n,
        'due_date': _addMonths(_receiptDate!, n),
        'amount': n == _numInst
            ? double.parse(
                (_totalPayable - mo * (_numInst - 1)).toStringAsFixed(2),
              )
            : mo,
      };
    });
  }

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime> onPicked,
    DateTime? first,
    DateTime? last,
  }) async {
    final d = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: first ?? DateTime(2020),
      lastDate: last ?? DateTime(2040),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: AdminColors.primary,
              brightness: Theme.of(ctx).brightness,
            ),
          ),
          child: child!,
        );
      },
    );
    if (d != null && mounted) {
      setState(() => onPicked(d));
    }
  }

  // ── Register ──
  Future<void> _register() async {
    if (_selectedCustomer == null) {
      _snack('Select a customer', isError: true);
      return;
    }
    if (_selectedMachine == null) {
      _snack('Select a machine', isError: true);
      return;
    }
    if (_purchaseDate == null) {
      _snack('Set purchase date', isError: true);
      return;
    }
    if (_hasInstallment) {
      if (_receiptDate == null) {
        _snack('Set receipt date', isError: true);
        return;
      }
      if (_totalPrice <= 0) {
        _snack('Enter total price', isError: true);
        return;
      }
      if (_downPayment >= _totalPrice) {
        _snack(
          'Down payment must be less than total',
          isError: true,
        );
        return;
      }
      if (_numInst <= 0) {
        _snack(
          'Enter number of installments',
          isError: true,
        );
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final result = await SupabaseConfig.client.rpc(
        'register_machine_with_installment',
        params: {
          'p_user_id': _selectedCustomer!['id'],
          'p_catalog_machine_id': _selectedMachine!['id'],
          'p_serial_number': _serialCtrl.text.isEmpty ? null : _serialCtrl.text,
          'p_purchase_date': _purchaseDate?.toIso8601String().split('T').first,
          'p_warranty_end_date':
              _warrantyEnd?.toIso8601String().split('T').first,
          'p_next_service_due':
              _nextServiceDue?.toIso8601String().split('T').first,
          'p_installation_address':
              _addressCtrl.text.isEmpty ? null : _addressCtrl.text,
          'p_has_installment': _hasInstallment,
          'p_receipt_date': _receiptDate?.toIso8601String().split('T').first,
          'p_total_price': _hasInstallment ? _totalPrice : 0,
          'p_down_payment': _hasInstallment ? _downPayment : 0,
          'p_interest_rate': _hasInstallment ? _interestRate : 0,
          'p_num_installments': _hasInstallment ? _numInst : 1,
          'p_notes': _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
        },
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final customerId = _selectedCustomer!['id'] as String;
        final machineId = (result['machine_id'] as String?) ?? '';
        final category =
            (_selectedMachine?['category'] as String?) ?? 'general';
        final amount = _hasInstallment ? _totalPrice : 0.0;

        // Fire-and-forget — never block UI on points
        PointsService.machinePurchase(
          customerId: customerId,
          machineId: machineId,
          amount: amount,
          category: category,
        );

        _snack(result['message'] ?? 'Registered ✅');
        Navigator.pop(context, true);
      } else {
        _snack(
          result['error'] ?? 'Registration failed',
          isError: true,
        );
        if (mounted) setState(() => _isSaving = false);
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Error: $e', isError: true);
      setState(() => _isSaving = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? AdminColors.error : AdminColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.r(12)),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  SELECTOR SHEETS
  // ════════════════════════════════════════════════════════

  void _showCustomerSelector() {
    String q = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSS) {
            final list = _customers.where((c) {
              final s = q.toLowerCase();
              return (c['full_name'] ?? '')
                      .toString()
                      .toLowerCase()
                      .contains(s) ||
                  (c['email'] ?? '').toString().toLowerCase().contains(s);
            }).toList();

            return Container(
              height: MediaQuery.of(sheetCtx).size.height * 0.7,
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  _handle(),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      12,
                      20,
                      0,
                    ),
                    child: Text(
                      'Select Customer',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _textPrimary,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: _searchField(
                      hint: 'Search name or email...',
                      onChanged: (v) => setSS(() => q = v),
                    ),
                  ),
                  Expanded(
                    child: list.isEmpty
                        ? Center(
                            child: Text(
                              'No customers found',
                              style: TextStyle(
                                color: _textSecondary,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final c = list[i];
                              final sel = c['id'] == _selectedCustomer?['id'];
                              return ListTile(
                                leading: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: _primary.withAlpha(20),
                                    borderRadius: BorderRadius.circular(Brand.r(12)),
                                  ),
                                  child: Center(
                                    child: Text(
                                      (c['full_name'] ?? 'C')[0].toUpperCase(),
                                      style: TextStyle(
                                        color: _primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                title: Text(
                                  c['full_name'] ?? 'Unnamed',
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  c['email'] ?? '',
                                  style: TextStyle(
                                    color: _textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                                trailing: sel
                                    ? Icon(
                                        Icons.check_circle_rounded,
                                        color: _accent,
                                        size: 22,
                                      )
                                    : Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 14,
                                        color: _textMuted,
                                      ),
                                onTap: () {
                                  setState(() => _selectedCustomer = c);
                                  Navigator.pop(sheetCtx);
                                },
                              );
                            },
                          ),
                  ),
                  SizedBox(
                    height: MediaQuery.of(sheetCtx).padding.bottom + 8,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showMachineSelector() {
    String q = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSS) {
            final list = _machines.where((m) {
              final s = q.toLowerCase();
              return (m['machine_name'] ?? '')
                      .toString()
                      .toLowerCase()
                      .contains(s) ||
                  (m['model_number'] ?? '')
                      .toString()
                      .toLowerCase()
                      .contains(s) ||
                  (m['brand'] ?? '').toString().toLowerCase().contains(s);
            }).toList();

            return Container(
              height: MediaQuery.of(sheetCtx).size.height * 0.7,
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  _handle(),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      12,
                      20,
                      0,
                    ),
                    child: Text(
                      'Select Machine',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _textPrimary,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: _searchField(
                      hint: 'Search machine...',
                      onChanged: (v) => setSS(() => q = v),
                    ),
                  ),
                  Expanded(
                    child: list.isEmpty
                        ? Center(
                            child: Text(
                              'No machines found',
                              style: TextStyle(
                                color: _textSecondary,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final m = list[i];
                              final sel = m['id'] == _selectedMachine?['id'];
                              return ListTile(
                                leading: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: _accent.withAlpha(20),
                                    borderRadius: BorderRadius.circular(Brand.r(12)),
                                    border: Border.all(
                                      color: _accent.withAlpha(38),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.precision_manufacturing_rounded,
                                    color: _accent,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  m['machine_name'] ?? '',
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${m['brand'] ?? ''} • ${m['model_number'] ?? ''}',
                                  style: TextStyle(
                                    color: _textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                                trailing: sel
                                    ? Icon(
                                        Icons.check_circle_rounded,
                                        color: _accent,
                                        size: 22,
                                      )
                                    : m['price'] != null
                                        ? Text(
                                            _fmtCur(
                                              (m['price'] as num).toDouble(),
                                            ),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: _textSecondary,
                                            ),
                                          )
                                        : Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            size: 14,
                                            color: _textMuted,
                                          ),
                                onTap: () {
                                  setState(() {
                                    _selectedMachine = m;
                                    if (m['price'] != null) {
                                      _totalPriceCtrl.text =
                                          m['price'].toString();
                                    }
                                  });
                                  Navigator.pop(sheetCtx);
                                },
                              );
                            },
                          ),
                  ),
                  SizedBox(
                    height: MediaQuery.of(sheetCtx).padding.bottom + 8,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    _isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: _bg,
      appBar: DsPageHeader(
        title: 'Register Machine',
        accent: HeroAccent.navy,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? _buildLoadingSkeleton()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        20,
                        16,
                        20,
                        40,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── 1. Customer ──
                          _buildSectionCard(
                            icon: Icons.person_outline_rounded,
                            title: 'Customer',
                            child: _buildSelectorTile(
                              label: _selectedCustomer?['full_name'] ??
                                  'Select Customer',
                              subtitle: _selectedCustomer?['email'],
                              icon: Icons.person_add_rounded,
                              hasValue: _selectedCustomer != null,
                              onTap: _showCustomerSelector,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // ── 2. Machine ──
                          _buildSectionCard(
                            icon: Icons.precision_manufacturing_rounded,
                            title: 'Machine',
                            child: _buildSelectorTile(
                              label: _selectedMachine?['machine_name'] ??
                                  'Select Machine',
                              subtitle: _selectedMachine != null
                                  ? '${_selectedMachine!['brand'] ?? ''} • ${_selectedMachine!['model_number'] ?? ''}'
                                  : null,
                              icon: Icons.build_circle_rounded,
                              hasValue: _selectedMachine != null,
                              onTap: _showMachineSelector,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // ── 3. Machine Details ──
                          _buildSectionCard(
                            icon: Icons.info_outline_rounded,
                            title: 'Machine Details',
                            child: Column(
                              children: [
                                _inputField(
                                  _serialCtrl,
                                  'Serial Number',
                                  hint: 'Enter serial number',
                                  icon: Icons.tag_rounded,
                                ),
                                const SizedBox(height: 12),
                                _dateField(
                                  'Purchase Date *',
                                  _purchaseDate,
                                  () => _pickDate(
                                    current: _purchaseDate,
                                    onPicked: (d) => _purchaseDate = d,
                                  ),
                                  icon: Icons.calendar_today_rounded,
                                ),
                                const SizedBox(height: 12),
                                _dateField(
                                  'Warranty End',
                                  _warrantyEnd,
                                  () => _pickDate(
                                    current: _warrantyEnd,
                                    onPicked: (d) => _warrantyEnd = d,
                                  ),
                                  icon: Icons.verified_outlined,
                                ),
                                const SizedBox(height: 12),
                                _dateField(
                                  'Next Service Due',
                                  _nextServiceDue,
                                  () => _pickDate(
                                    current: _nextServiceDue,
                                    onPicked: (d) => _nextServiceDue = d,
                                  ),
                                  icon: Icons.build_rounded,
                                ),
                                const SizedBox(height: 12),
                                _inputField(
                                  _addressCtrl,
                                  'Installation Address',
                                  hint: 'Delivery / install address',
                                  icon: Icons.location_on_rounded,
                                  maxLines: 2,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // ── 4. Payment Plan ──
                          _buildSectionCard(
                            icon: Icons.payments_rounded,
                            title: 'Payment Plan',
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _hasInstallment
                                      ? 'Installment'
                                      : 'Full Payment',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        _hasInstallment ? _accent : _textMuted,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Switch(
                                  value: _hasInstallment,
                                  onChanged: (v) => setState(
                                    () => _hasInstallment = v,
                                  ),
                                  activeThumbColor: _accent,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ],
                            ),
                            child: !_hasInstallment
                                ? Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: _primary.withAlpha(10),
                                      borderRadius: BorderRadius.circular(Brand.r(12)),
                                      border: Border.all(color: _border),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.info_outline_rounded,
                                          size: 16,
                                          color: _textMuted,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Toggle on for installment payments',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: _textSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Column(
                                    children: [
                                      _dateField(
                                        'Receipt Date *',
                                        _receiptDate,
                                        () => _pickDate(
                                          current: _receiptDate,
                                          onPicked: (d) => _receiptDate = d,
                                        ),
                                        icon: Icons.receipt_long_rounded,
                                      ),
                                      const SizedBox(height: 12),
                                      _inputField(
                                        _totalPriceCtrl,
                                        'Total Price *',
                                        prefix: 'Rs. ',
                                        icon: Icons.attach_money_rounded,
                                        keyboard: const TextInputType
                                            .numberWithOptions(
                                          decimal: true,
                                        ),
                                        fmt: [
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r'^\d*\.?\d{0,2}'),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      _inputField(
                                        _downPaymentCtrl,
                                        'Down Payment *',
                                        prefix: 'Rs. ',
                                        icon: Icons.trending_down_rounded,
                                        keyboard: const TextInputType
                                            .numberWithOptions(
                                          decimal: true,
                                        ),
                                        fmt: [
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r'^\d*\.?\d{0,2}'),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      _inputField(
                                        _interestCtrl,
                                        'Interest Rate % (0 = none)',
                                        hint: 'e.g. 10',
                                        icon: Icons.percent_rounded,
                                        keyboard: const TextInputType
                                            .numberWithOptions(
                                          decimal: true,
                                        ),
                                        fmt: [
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r'^\d*\.?\d{0,2}'),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      _inputField(
                                        _numInstCtrl,
                                        'Number of Installments *',
                                        hint: 'e.g. 12',
                                        icon:
                                            Icons.format_list_numbered_rounded,
                                        keyboard: TextInputType.number,
                                        fmt: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      _inputField(
                                        _notesCtrl,
                                        'Notes',
                                        hint: 'Optional notes',
                                        icon: Icons.notes_rounded,
                                        maxLines: 2,
                                      ),
                                    ],
                                  ),
                          ),

                          // ── 5. Preview ──
                          if (_hasInstallment && _canPreview) ...[
                            const SizedBox(height: 14),
                            _buildPreviewCard(),
                            const SizedBox(height: 14),
                            _buildSchedulePreview(),
                          ],

                          const SizedBox(height: 28),

                          // ── 6. Register Button ──
                          _buildRegisterButton(),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  REGISTER BUTTON
  // ════════════════════════════════════════════════════════

  Widget _buildRegisterButton() {
    return GestureDetector(
      onTap: _isSaving ? null : _register,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          // FIX: AdminColors.primaryLight does NOT exist
          // → use Brand.royalBlueLight instead
          gradient: _isSaving
              ? null
              : LinearGradient(
                  colors: _isDark
                      ? [Brand.royalBlue, Brand.royalBlueLight]
                      : [Brand.royalBlue, Brand.royalBlueLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: _isSaving ? _border : null,
          borderRadius: BorderRadius.circular(Brand.r(16)),
          boxShadow: _isSaving
              ? []
              : [
                  BoxShadow(
                    color: Brand.royalBlue.withAlpha(102),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Center(
          child: _isSaving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_business_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Register Machine',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }


  // ════════════════════════════════════════════════════════
  //  SECTION CARD
  // ════════════════════════════════════════════════════════

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(Brand.r(20)),
        border: _isDark ? Border.all(color: _border) : null,
        boxShadow: _cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(Brand.r(10)),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: _primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
          Container(height: 1, color: _border),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }

  // ── Selector tile ──
  Widget _buildSelectorTile({
    required String label,
    String? subtitle,
    required IconData icon,
    required bool hasValue,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _inputBg,
          borderRadius: BorderRadius.circular(Brand.r(14)),
          border: Border.all(
            color: hasValue ? _primary.withAlpha(77) : _border,
            width: hasValue ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: hasValue
                    ? _primary.withAlpha(20)
                    : (_isDark
                        ? Brand.darkBorderLight
                        : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(Brand.r(10)),
              ),
              child: Icon(
                icon,
                size: 20,
                color: hasValue ? _primary : _textMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                      color: hasValue ? _textPrimary : _textMuted,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: _textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Icon(
              hasValue
                  ? Icons.check_circle_rounded
                  : Icons.chevron_right_rounded,
              color: hasValue ? _accent : _textMuted,
              size: hasValue ? 20 : 22,
            ),
          ],
        ),
      ),
    );
  }

  // ── Input field ──
  Widget _inputField(
    TextEditingController ctrl,
    String label, {
    String? hint,
    String? prefix,
    IconData icon = Icons.edit_rounded,
    TextInputType? keyboard,
    List<TextInputFormatter>? fmt,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _inputBg,
        borderRadius: BorderRadius.circular(Brand.r(14)),
        border: Border.all(color: _border),
      ),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboard,
        inputFormatters: fmt,
        maxLines: maxLines,
        style: TextStyle(color: _textPrimary),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixText: prefix,
          labelStyle: TextStyle(color: _textMuted),
          hintStyle: TextStyle(
            color: _textMuted,
            fontSize: 13,
          ),
          prefixIcon:
              prefix == null ? Icon(icon, color: _textMuted, size: 20) : null,
          prefixIconConstraints: const BoxConstraints(
            minWidth: 48,
            minHeight: 48,
          ),
          filled: true,
          fillColor: _inputBg,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Brand.r(14)),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Brand.r(14)),
            borderSide: BorderSide(
              color: _primary,
              width: 1.5,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Brand.r(14)),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // ── Date field ──
  Widget _dateField(
    String label,
    DateTime? val,
    VoidCallback onTap, {
    IconData icon = Icons.calendar_today_rounded,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: _inputBg,
          borderRadius: BorderRadius.circular(Brand.r(14)),
          border: Border.all(
            color: val != null ? _primary.withAlpha(77) : _border,
            width: val != null ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: val != null ? _primary : _textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: _textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    val != null ? _fmtDate(val) : 'Select date',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          val != null ? FontWeight.w600 : FontWeight.w400,
                      color: val != null ? _textPrimary : _textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: _textMuted,
            ),
          ],
        ),
      ),
    );
  }

  // ── Search field ──
  Widget _searchField({
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _inputBg,
        borderRadius: BorderRadius.circular(Brand.r(14)),
        border: Border.all(color: _border),
      ),
      child: TextField(
        onChanged: onChanged,
        style: TextStyle(color: _textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: _textMuted,
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: _textMuted,
            size: 22,
          ),
          filled: true,
          fillColor: _inputBg,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Brand.r(14)),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // ── Sheet handle ──
  Widget _handle() => Center(
        child: Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: _handleColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  // ════════════════════════════════════════════════════════
  //  PREVIEW CARD
  // ════════════════════════════════════════════════════════

  Widget _buildPreviewCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isDark
              ? [Brand.royalBlueDark, Brand.royalBlue]
              : [Brand.royalBlue, Brand.royalBlueLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(Brand.r(20)),
        boxShadow: [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(89),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _isDark ? Brand.lightGreenBright : Brand.lightGreen,
                  borderRadius: BorderRadius.circular(Brand.r(20)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calculate_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Payment Preview',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Icon(
                Icons.insights_rounded,
                color: Colors.white.withAlpha(77),
                size: 28,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _prevRow('Total Price', _fmtCur(_totalPrice)),
          _prevRow(
            'Down Payment',
            '− ${_fmtCur(_downPayment)}',
          ),
          Divider(
            color: Colors.white.withAlpha(51),
            height: 20,
          ),
          _prevRow('Remaining', _fmtCur(_remaining)),
          if (_interestRate > 0) ...[
            _prevRow(
              'Interest (${_interestRate.toStringAsFixed(1)}%)',
              '+ ${_fmtCur(_interestAmt)}',
              highlight: true,
            ),
            Divider(
              color: Colors.white.withAlpha(51),
              height: 20,
            ),
          ],
          _prevRow(
            'Total Payable',
            _fmtCur(_totalPayable),
            bold: true,
          ),
          const SizedBox(height: 12),

          // Monthly amount highlight
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(26),
              borderRadius: BorderRadius.circular(Brand.r(14)),
              border: Border.all(
                color: Colors.white.withAlpha(38),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Monthly Installment',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (_receiptDate != null)
                      Text(
                        'First due: ${_fmtDate(_addMonths(_receiptDate!, 1))}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                Text(
                  _fmtCur(
                    double.parse(
                      _monthlyAmt.toStringAsFixed(2),
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _isDark
                        ? Brand.lightGreenBright
                        : Brand.lightGreenBright,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _prevRow(
    String label,
    String value, {
    bool bold = false,
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: highlight
                  ? const Color(0xFFFCD34D) // amber-300
                  : Colors.white70,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: highlight
                  ? const Color(0xFFFCD34D) // amber-300
                  : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  SCHEDULE PREVIEW
  // ════════════════════════════════════════════════════════

  Widget _buildSchedulePreview() {
    final schedule = _buildSchedule();
    if (schedule.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(Brand.r(20)),
        border: _isDark ? Border.all(color: _border) : null,
        boxShadow: _cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _showSchedule = !_showSchedule),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(Brand.r(10)),
                    ),
                    child: Icon(
                      Icons.event_note_rounded,
                      size: 18,
                      color: _primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Payment Schedule (${schedule.length})',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _inputBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _border),
                    ),
                    child: Icon(
                      _showSchedule
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: _textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showSchedule) ...[
            Container(height: 1, color: _border),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                12,
                16,
                16,
              ),
              child: Column(
                children: schedule.map((s) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _primary.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _primary.withAlpha(38),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${s['number']}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _fmtDate(
                              s['due_date'] as DateTime,
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              color: _textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          _fmtCur(s['amount'] as double),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _textPrimary,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Loading skeleton ──
  Widget _buildLoadingSkeleton() {
    final shimmerColor =
        _isDark ? Brand.darkCardElevated : const Color(0xFFEEF0F5);

    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        // Customer card skeleton
        _skeletonCard(height: 110, color: shimmerColor),
        const SizedBox(height: 14),
        // Machine card skeleton
        _skeletonCard(height: 110, color: shimmerColor),
        const SizedBox(height: 14),
        // Machine details skeleton
        _skeletonCard(height: 240, color: shimmerColor),
        const SizedBox(height: 14),
        // Payment plan skeleton
        _skeletonCard(height: 130, color: shimmerColor),
        const SizedBox(height: 28),
        // Button skeleton
        Container(
          height: 54,
          decoration: BoxDecoration(
            color: shimmerColor,
            borderRadius: BorderRadius.circular(Brand.r(16)),
          ),
        ),
      ],
    );
  }

  Widget _skeletonCard({
    required double height,
    required Color color,
  }) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(Brand.r(20)),
        border: _isDark ? Border.all(color: Brand.darkBorder) : null,
      ),
    );
  }
}
