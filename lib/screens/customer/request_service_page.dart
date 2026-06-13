import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';

class RequestServicePage extends StatefulWidget {
  const RequestServicePage({super.key});

  @override
  State<RequestServicePage> createState() => _RequestServicePageState();
}

class _RequestServicePageState extends State<RequestServicePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _scheduleType = 'repair';
  DateTime _preferredDate = DateTime.now().add(const Duration(days: 2));
  TimeOfDay _preferredTime = const TimeOfDay(hour: 9, minute: 0);
  Map<String, dynamic>? _selectedMachine;
  List<Map<String, dynamic>> _machines = [];
  bool _loadingMachines = true;
  bool _saving = false;

  static const _scheduleTypes = [
    ('repair', 'Repair', Icons.handyman, Color(0xFFEF4444)),
    (
      'preventive',
      'Preventive Maintenance',
      Icons.build_circle_outlined,
      Color(0xFF3B82F6)
    ),
    ('inspection', 'Inspection', Icons.search, Color(0xFF14B8A6)),
    (
      'installation',
      'Installation',
      Icons.precision_manufacturing,
      Color(0xFF8B5CF6)
    ),
    (
      'warranty_visit',
      'Warranty Visit',
      Icons.verified_user,
      Color(0xFFF59E0B)
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadMachines();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMachines() async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;

      final data = await SupabaseConfig.client
          .from('customer_machines')
          .select('''
            id, serial_number, status, installation_address,
            catalog:machine_catalog!catalog_machine_id(machine_name, model_number, image_url)
          ''')
          .eq('user_id', userId)
          .eq('status', 'active')
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _machines = List<Map<String, dynamic>>.from(data);
        _loadingMachines = false;
      });
    } catch (e) {
      debugPrint('Load machines error: $e');
      if (mounted) setState(() => _loadingMachines = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final userId = SupabaseConfig.client.auth.currentUser!.id;
      final timeStr =
          '${_preferredTime.hour.toString().padLeft(2, '0')}:${_preferredTime.minute.toString().padLeft(2, '0')}:00';
      final dateStr =
          '${_preferredDate.year}-${_preferredDate.month.toString().padLeft(2, '0')}-${_preferredDate.day.toString().padLeft(2, '0')}';

      // Auto-fill location from machine if not provided
      String? location =
          _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim();
      if (location == null && _selectedMachine != null) {
        location = _selectedMachine!['installation_address'] as String?;
      }

      await SupabaseConfig.client.from('service_schedules').insert({
        'customer_id': userId,
        'customer_machine_id': _selectedMachine?['id'],
        'schedule_type': _scheduleType,
        'title': _titleCtrl.text.trim(),
        'description':
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'scheduled_date': dateStr,
        'scheduled_time': timeStr,
        'service_location': location,
        'customer_notes':
            _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'status': 'requested',
        'created_by': userId,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Service request submitted!'),
          ]),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Brand.lightGreenDark,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Failed to submit: $e')),
          ]),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _saving = false);
    }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: AppBar(
        title: const Text('Request Service'),
        backgroundColor: isDark ? Brand.darkCard : Colors.white,
        foregroundColor: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Info Banner ──
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Brand.royalBlue.withAlpha(isDark ? 25 : 15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Brand.royalBlue.withAlpha(51)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 18,
                      color: isDark ? Brand.royalBlueGlow : Brand.royalBlue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Submit your preferred date and time. Our team will confirm and assign an engineer.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.royalBlueDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Service Type ──
            _sectionLabel('What do you need? *', isDark),
            const SizedBox(height: 10),
            _buildTypeSelector(isDark),
            const SizedBox(height: 24),

            // ── Title ──
            _sectionLabel('Title *', isDark),
            const SizedBox(height: 8),
            _buildTextField(
              _titleCtrl,
              'e.g. Machine not starting',
              isDark,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter a title'
                  : null,
            ),
            const SizedBox(height: 24),

            // ── Machine ──
            _sectionLabel('Select Machine (Optional)', isDark),
            const SizedBox(height: 8),
            _buildMachineSelector(isDark),
            const SizedBox(height: 24),

            // ── Preferred Date & Time ──
            _sectionLabel('Preferred Date & Time *', isDark),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildDateTile(isDark)),
                const SizedBox(width: 12),
                Expanded(child: _buildTimeTile(isDark)),
              ],
            ),
            const SizedBox(height: 24),

            // ── Location ──
            _sectionLabel('Service Location', isDark),
            const SizedBox(height: 8),
            _buildTextField(
              _locationCtrl,
              'Address for the service visit',
              isDark,
            ),
            if (_selectedMachine != null &&
                (_selectedMachine!['installation_address'] as String?)
                        ?.isNotEmpty ==
                    true)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: GestureDetector(
                  onTap: () {
                    _locationCtrl.text =
                        _selectedMachine!['installation_address'] as String;
                  },
                  child: Row(
                    children: [
                      Icon(Icons.my_location,
                          size: 14,
                          color:
                              isDark ? Brand.royalBlueGlow : Brand.royalBlue),
                      const SizedBox(width: 6),
                      Text(
                        'Use machine installation address',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),

            // ── Description ──
            _sectionLabel('Description', isDark),
            const SizedBox(height: 8),
            _buildTextField(
              _descCtrl,
              'Describe the issue or service needed...',
              isDark,
              maxLines: 4,
            ),
            const SizedBox(height: 24),

            // ── Notes ──
            _sectionLabel('Additional Notes', isDark),
            const SizedBox(height: 8),
            _buildTextField(
              _notesCtrl,
              'Any special requirements or access instructions...',
              isDark,
              maxLines: 2,
            ),
            const SizedBox(height: 32),

            // ── Submit Button ──
            GestureDetector(
              onTap: _saving ? null : _submit,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 52,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: _saving
                      ? null
                      : const LinearGradient(
                          colors: [Brand.royalBlueDark, Brand.royalBlueLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  color: _saving
                      ? (isDark ? Brand.darkBorderLight : Brand.borderLight)
                      : null,
                  borderRadius: BorderRadius.circular(14),
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_saving)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      else
                        const Icon(Icons.send_rounded,
                            size: 20, color: Colors.white),
                      const SizedBox(width: 10),
                      Text(
                        _saving ? 'Submitting...' : 'Submit Request',
                        style: const TextStyle(
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
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── Section Label ──

  Widget _sectionLabel(String text, bool isDark) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? Brand.darkTextSecondary : Brand.royalBlueDark,
      ),
    );
  }

  // ── Text Field ──

  Widget _buildTextField(
    TextEditingController ctrl,
    String hint,
    bool isDark, {
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      validator: validator,
      style: TextStyle(
        color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
        ),
        filled: true,
        fillColor: isDark ? Brand.darkCardElevated : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? Brand.darkBorder : Brand.borderLight,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? Brand.darkBorder : Brand.borderLight,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Brand.royalBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  // ── Type Selector ──

  Widget _buildTypeSelector(bool isDark) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _scheduleTypes.map((t) {
        final selected = _scheduleType == t.$1;
        return GestureDetector(
          onTap: () => setState(() => _scheduleType = t.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? t.$4.withAlpha(isDark ? 38 : 26)
                  : (isDark ? Brand.darkCard : Colors.white),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? t.$4
                    : (isDark ? Brand.darkBorder : Brand.borderLight),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(t.$3,
                    size: 18,
                    color: selected
                        ? t.$4
                        : (isDark
                            ? Brand.darkTextTertiary
                            : Brand.subtleLight)),
                const SizedBox(width: 8),
                Text(
                  t.$2,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? t.$4
                        : (isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Machine Selector ──

  Widget _buildMachineSelector(bool isDark) {
    if (_loadingMachines) {
      return Container(
        height: 56,
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_machines.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline,
                size: 18,
                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No registered machines. You can still request service.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _machines.map((m) {
        final catalog = m['catalog'] as Map<String, dynamic>?;
        final name = catalog?['machine_name'] as String? ?? 'Machine';
        final model = catalog?['model_number'] as String? ?? '';
        final serial = m['serial_number'] as String? ?? '';
        final selected = _selectedMachine?['id'] == m['id'];

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => setState(() {
              _selectedMachine = selected ? null : m;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selected
                    ? Brand.royalBlue.withAlpha(isDark ? 25 : 15)
                    : (isDark ? Brand.darkCard : Colors.white),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? Brand.royalBlue
                      : (isDark ? Brand.darkBorder : Brand.borderLight),
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Brand.royalBlue.withAlpha(isDark ? 38 : 26),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.precision_manufacturing,
                      size: 20,
                      color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Brand.darkTextPrimary
                                : Brand.royalBlueDark,
                          ),
                        ),
                        Text(
                          '$model · S/N: $serial',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Brand.darkTextTertiary
                                : Brand.subtleLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check_circle,
                        size: 22, color: Brand.royalBlue),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Date Tile ──

  Widget _buildDateTile(bool isDark) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _preferredDate,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 90)),
        );
        if (picked != null && mounted) {
          setState(() => _preferredDate = picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today,
                size: 18,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${_preferredDate.day}/${_preferredDate.month}/${_preferredDate.year}',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down,
                size: 20,
                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
          ],
        ),
      ),
    );
  }

  // ── Time Tile ──

  Widget _buildTimeTile(bool isDark) {
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: _preferredTime,
        );
        if (picked != null && mounted) {
          setState(() => _preferredTime = picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        ),
        child: Row(
          children: [
            Icon(Icons.access_time,
                size: 18,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _preferredTime.format(context),
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down,
                size: 20,
                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
          ],
        ),
      ),
    );
  }
}
