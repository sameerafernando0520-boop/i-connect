// ============================================================
// FILE: lib/widgets/customer/submit_payment_sheet.dart
// Customer sheet to submit an installment payment (with receipts).
// ============================================================

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';

class SubmitPaymentSheet extends StatefulWidget {
  final String planId;
  final double suggestedAmount;
  final String? nextDueDate;
  final int? nextDueNumber;

  const SubmitPaymentSheet({
    super.key,
    required this.planId,
    required this.suggestedAmount,
    this.nextDueDate,
    this.nextDueNumber,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String planId,
    required double suggestedAmount,
    String? nextDueDate,
    int? nextDueNumber,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SubmitPaymentSheet(
        planId: planId,
        suggestedAmount: suggestedAmount,
        nextDueDate: nextDueDate,
        nextDueNumber: nextDueNumber,
      ),
    );
  }

  @override
  State<SubmitPaymentSheet> createState() => _SubmitPaymentSheetState();
}

class _SubmitPaymentSheetState extends State<SubmitPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  DateTime _paidDate = DateTime.now();
  String _method = 'bank_transfer';
  bool _submitting = false;

  final List<_PickedReceipt> _receipts = [];
  List<Map<String, dynamic>> _bankAccounts = [];
  bool _loadingBanks = true;

  @override
  void initState() {
    super.initState();
    _amountCtrl.text = widget.suggestedAmount.toStringAsFixed(2);
    _loadBankAccounts();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _referenceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBankAccounts() async {
    try {
      final rows = await SupabaseConfig.client
          .from('company_bank_accounts')
          .select('*')
          .eq('is_active', true)
          .order('display_order');
      if (!mounted) return;
      setState(() {
        _bankAccounts = List<Map<String, dynamic>>.from(rows);
        _loadingBanks = false;
      });
    } catch (e) {
      debugPrint('Bank accounts load failed: $e');
      if (!mounted) return;
      setState(() => _loadingBanks = false);
    }
  }

  Future<void> _pickReceipts() async {
    try {
      final files = await ImagePicker().pickMultiImage(imageQuality: 75);
      if (files.isEmpty) return;
      final newOnes = <_PickedReceipt>[];
      for (final f in files) {
        newOnes.add(_PickedReceipt(
          name: f.name,
          bytes: await f.readAsBytes(),
          mimeType: f.mimeType ?? 'image/jpeg',
        ));
      }
      setState(() => _receipts.addAll(newOnes));
    } catch (e) {
      debugPrint('pick receipts failed: $e');
      _snack('Could not pick images', isError: true);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_receipts.isEmpty) {
      _snack('Please attach at least one receipt', isError: true);
      return;
    }
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) {
      _snack('Session expired — please re-login', isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      final amount = double.parse(_amountCtrl.text.trim());

      // Find the existing scheduled row for this installment number
      String? paymentId;
      final query = SupabaseConfig.client
          .from('installment_payments')
          .select('id')
          .eq('plan_id', widget.planId);
      final existing = widget.nextDueNumber != null
          ? await query
              .eq('installment_number', widget.nextDueNumber!)
              .maybeSingle()
          : await query
              .inFilter('status', ['pending', 'overdue'])
              .order('due_date')
              .limit(1)
              .maybeSingle();

      if (existing != null) {
        paymentId = existing['id'] as String;
        await SupabaseConfig.client.from('installment_payments').update({
          'amount': amount,
          'paid_date': _paidDate.toIso8601String().substring(0, 10),
          'payment_method': _method,
          'payment_reference': _referenceCtrl.text.trim().isEmpty
              ? null
              : _referenceCtrl.text.trim(),
          'notes':
              _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          'status': 'submitted',
          'submitted_by': userId,
          'submitted_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', paymentId);
      } else {
        final inserted = await SupabaseConfig.client
            .from('installment_payments')
            .insert({
              'plan_id': widget.planId,
              'user_id': userId,
              'installment_number': widget.nextDueNumber,
              'amount': amount,
              'due_date': widget.nextDueDate,
              'paid_date': _paidDate.toIso8601String().substring(0, 10),
              'payment_method': _method,
              'payment_reference': _referenceCtrl.text.trim().isEmpty
                  ? null
                  : _referenceCtrl.text.trim(),
              'notes': _notesCtrl.text.trim().isEmpty
                  ? null
                  : _notesCtrl.text.trim(),
              'status': 'submitted',
              'submitted_by': userId,
              'submitted_at': DateTime.now().toUtc().toIso8601String(),
            })
            .select()
            .single();
        paymentId = inserted['id'] as String;
      }

      // Upload receipts to private storage bucket
      for (int i = 0; i < _receipts.length; i++) {
        final r = _receipts[i];
        final ext = r.name.contains('.') ? r.name.split('.').last : 'jpg';
        final path =
            '$userId/$paymentId/${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
        await SupabaseConfig.client.storage
            .from('payment-receipts')
            .uploadBinary(
              path,
              r.bytes,
              fileOptions: FileOptions(
                upsert: false,
                contentType: r.mimeType,
              ),
            );
        await SupabaseConfig.client.from('payment_receipts').insert({
          'payment_id': paymentId,
          'file_url': path,
          'file_name': r.name,
          'file_size_bytes': r.bytes.length,
          'mime_type': r.mimeType,
          'uploaded_by': userId,
          'uploaded_at': DateTime.now().toUtc().toIso8601String(),
        });
      }

      // Admin notification is handled by the trg_notify_payment_submission
      // triggers on installment_payments — RLS blocks customers from
      // inserting notifications for other users.

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Payment submitted for verification'),
          backgroundColor: Brand.lightGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('submit payment failed: $e');
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack('Failed to submit: $e', isError: true);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? StatusColors.danger : Brand.royalBlue,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        maxChildSize: 0.95,
        minChildSize: 0.6,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Brand.royalBlue.withAlpha(28),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.payments_rounded,
                          color: Brand.royalBlue, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Submit Payment',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Brand.darkTextPrimary
                                    : Brand.royalBlueDark,
                              )),
                          Text('Upload your receipt for verification',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight,
                              )),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildBankAccountsCard(isDark),
                        const SizedBox(height: 18),
                        _sectionLabel('Amount (Rs.)', isDark),
                        TextFormField(
                          controller: _amountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: _fieldDecoration(
                              isDark, '0.00', Icons.attach_money_rounded),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Enter amount';
                            }
                            final d = double.tryParse(v.trim());
                            if (d == null || d <= 0) return 'Invalid amount';
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        _sectionLabel('Date Paid', isDark),
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _paidDate,
                              firstDate: DateTime.now()
                                  .subtract(const Duration(days: 365)),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setState(() => _paidDate = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: _fieldDecoration(
                                isDark, '', Icons.event_rounded),
                            child: Text(
                              DateFormat('MMM dd, yyyy').format(_paidDate),
                              style: TextStyle(
                                color: isDark
                                    ? Brand.darkTextPrimary
                                    : Brand.royalBlueDark,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _sectionLabel('Payment Method', isDark),
                        _buildMethodPicker(isDark),
                        const SizedBox(height: 14),
                        _sectionLabel('Reference Number', isDark),
                        TextFormField(
                          controller: _referenceCtrl,
                          decoration: _fieldDecoration(isDark,
                              'Bank slip ref / txn ID', Icons.tag_rounded),
                        ),
                        const SizedBox(height: 14),
                        _sectionLabel('Notes (optional)', isDark),
                        TextFormField(
                          controller: _notesCtrl,
                          maxLines: 2,
                          decoration: _fieldDecoration(
                              isDark, 'Any details…', Icons.notes_rounded),
                        ),
                        const SizedBox(height: 18),
                        _sectionLabel('Receipts', isDark),
                        _buildReceiptsPicker(isDark),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _submitting ? null : _submit,
                            icon: _submitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_rounded),
                            label: Text(_submitting
                                ? 'Submitting…'
                                : 'Submit for Verification'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Brand.royalBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
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
    );
  }

  Widget _sectionLabel(String s, bool isDark) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          s,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            letterSpacing: 0.2,
          ),
        ),
      );

  InputDecoration _fieldDecoration(bool isDark, String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon,
          color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
          size: 20),
      filled: true,
      fillColor: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            BorderSide(color: isDark ? Brand.darkBorder : Brand.borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            BorderSide(color: isDark ? Brand.darkBorder : Brand.borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.royalBlue, width: 1.4),
      ),
    );
  }

  Widget _buildMethodPicker(bool isDark) {
    const options = [
      ['bank_transfer', 'Bank Transfer', Icons.account_balance_rounded],
      ['card', 'Card Payment', Icons.credit_card_rounded],
      ['cheque', 'Cheque', Icons.description_rounded],
      ['cash', 'Cash', Icons.payments_outlined],
      ['online', 'Online Transfer', Icons.phone_rounded],
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((o) {
        final selected = _method == o[0];
        return GestureDetector(
          onTap: () => setState(() => _method = o[0] as String),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? Brand.royalBlue.withAlpha(30)
                  : (isDark ? Brand.darkCardElevated : Brand.scaffoldLight),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? Brand.royalBlue
                    : (isDark ? Brand.darkBorder : Brand.borderLight),
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(o[2] as IconData,
                    size: 16,
                    color: selected ? Brand.royalBlue : Brand.subtleLight),
                const SizedBox(width: 6),
                Text(
                  o[1] as String,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? Brand.royalBlue
                        : (isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBankAccountsCard(bool isDark) {
    if (_loadingBanks) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (_bankAccounts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark
              ? Brand.darkCardElevated
              : Brand.royalBlueSurface.withAlpha(180),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Brand.royalBlue.withAlpha(40)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                color: Brand.royalBlue, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Please contact us for bank details before paying.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pay to one of these accounts',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        ..._bankAccounts.map((b) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Brand.royalBlue.withAlpha(36)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_balance_rounded,
                          color: Brand.royalBlue, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          b['bank_name']?.toString() ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Brand.darkTextPrimary
                                : Brand.royalBlueDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${b['account_name'] ?? ''}  •  ${b['account_number'] ?? ''}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                  ),
                  if ((b['branch'] ?? '').toString().isNotEmpty)
                    Text(
                      'Branch: ${b['branch']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                      ),
                    ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildReceiptsPicker(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _pickReceipts,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Brand.royalBlue.withAlpha(80),
                style: BorderStyle.solid,
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.add_photo_alternate_rounded,
                    color: Brand.royalBlue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _receipts.isEmpty
                        ? 'Add receipt photo(s)'
                        : 'Add more (${_receipts.length} selected)',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_receipts.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _receipts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final r = _receipts[i];
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        r.bytes,
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => setState(() => _receipts.removeAt(i)),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded,
                              size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _PickedReceipt {
  final String name;
  final Uint8List bytes;
  final String mimeType;
  const _PickedReceipt({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });
}
