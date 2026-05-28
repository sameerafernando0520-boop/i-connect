import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../config/admin_theme.dart';
import '../../../config/supabase_config.dart';

class RecordPaymentSheet extends StatefulWidget {
  final String invoiceId;
  final double balanceDue;
  final VoidCallback onPaymentRecorded;

  const RecordPaymentSheet({
    super.key,
    required this.invoiceId,
    required this.balanceDue,
    required this.onPaymentRecorded,
  });

  static Future<void> show(
    BuildContext context, {
    required String invoiceId,
    required double balanceDue,
    required VoidCallback onPaymentRecorded,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RecordPaymentSheet(
        invoiceId: invoiceId,
        balanceDue: balanceDue,
        onPaymentRecorded: onPaymentRecorded,
      ),
    );
  }

  @override
  State<RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<RecordPaymentSheet> {
  final _supabase = SupabaseConfig.client;
  final _fmt = NumberFormat('#,##0.00', 'en_US');

  late final TextEditingController _amountCtrl;
  final _referenceCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _chequeNumCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _method = 'bank_transfer';
  DateTime? _chequeDate;
  bool _saving = false;

  String? get _userId => _supabase.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
        text:
            widget.balanceDue > 0 ? widget.balanceDue.toStringAsFixed(2) : '');
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _referenceCtrl.dispose();
    _bankNameCtrl.dispose();
    _chequeNumCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    if (amount <= 0) {
      _snack('Enter a valid amount', isError: true);
      return;
    }
    if (amount > widget.balanceDue) {
      _snack('Amount exceeds balance due', isError: true);
      return;
    }

    setState(() => _saving = true);

    try {
      final res = await _supabase.rpc('record_payment', params: {
        'p_invoice_id': widget.invoiceId,
        'p_amount': amount,
        'p_method': _method,
        'p_reference': _referenceCtrl.text.trim().isEmpty
            ? null
            : _referenceCtrl.text.trim(),
        'p_admin_id': _userId,
        'p_notes':
            _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'p_bank_name': _bankNameCtrl.text.trim().isEmpty
            ? null
            : _bankNameCtrl.text.trim(),
        'p_cheque_number': _chequeNumCtrl.text.trim().isEmpty
            ? null
            : _chequeNumCtrl.text.trim(),
        'p_cheque_date': _chequeDate?.toIso8601String().split('T')[0],
      });

      if (!mounted) return;
      final result = res as Map<String, dynamic>? ?? {};

      if (result['success'] == true) {
        widget.onPaymentRecorded();
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle_outline_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Payment recorded — ${result['payment_number'] ?? ''}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ]),
          backgroundColor: AdminColors.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ));
      } else {
        setState(() => _saving = false);
        _snack(result['error']?.toString() ?? 'Failed', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Failed: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {


    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AdminColors.card(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                    color: AdminColors.border(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Record Payment',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.text(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Balance due: Rs. ${_fmt.format(widget.balanceDue)}',
                style: TextStyle(
                  fontSize: 13,
                  color: widget.balanceDue > 0
                      ? AdminColors.error
                      : AdminColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),

              // Amount
              _field(
                ctrl: _amountCtrl,
                label: 'Amount (Rs.) *',
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                // L5: Hardware/software keyboards on Android don't always
                // respect `numberWithOptions` — some Samsung IMEs still
                // surface letters. Restrict the allowed characters to digits
                // and at most one decimal point at the input layer so bad
                // input never reaches the parser.
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
              ),
              const SizedBox(height: 14),

              // Method
              _label('Payment Method'),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AdminColors.bg(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _method,
                    isExpanded: true,
                    dropdownColor: AdminColors.card(context),
                    style: TextStyle(
                        color: AdminColors.text(context), fontSize: 14),
                    items: const [
                      DropdownMenuItem(
                          value: 'bank_transfer', child: Text('Bank Transfer')),
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                      DropdownMenuItem(value: 'card', child: Text('Card')),
                      DropdownMenuItem(value: 'online', child: Text('Online')),
                    ],
                    onChanged: (v) => setState(() => _method = v ?? _method),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Conditional: bank name
              if (_method == 'bank_transfer') ...[
                _field(ctrl: _bankNameCtrl, label: 'Bank Name'),
                const SizedBox(height: 14),
              ],

              // Conditional: cheque fields
              if (_method == 'cheque') ...[
                _field(
                  ctrl: _chequeNumCtrl,
                  label: 'Cheque Number',
                  // L5: Cheque numbers are always numeric — surface the
                  // digit keypad and reject non-digits.
                  keyboard: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate:
                          DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _chequeDate = d);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: AdminColors.bg(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_rounded,
                            size: 16, color: AdminColors.primary),
                        const SizedBox(width: 10),
                        Text(
                          _chequeDate != null
                              ? DateFormat('MMM d, yyyy').format(_chequeDate!)
                              : 'Cheque Date',
                          style: TextStyle(
                            fontSize: 14,
                            color: _chequeDate != null
                                ? AdminColors.text(context)
                                : AdminColors.textHint(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Reference
              _field(ctrl: _referenceCtrl, label: 'Payment Reference'),
              const SizedBox(height: 14),

              // Notes
              _field(ctrl: _notesCtrl, label: 'Notes', maxLines: 2),
              const SizedBox(height: 24),

              // Submit
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    _saving ? 'Recording…' : 'Record Payment',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    TextInputType? keyboard,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      style: TextStyle(color: AdminColors.text(context), fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            TextStyle(color: AdminColors.textSub(context), fontSize: 13),
        filled: true,
        fillColor: AdminColors.bg(context),
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

  Widget _label(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AdminColors.textSub(context),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ));
  }
}
