import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../utils/string_utils.dart';
import '../../widgets/ds/ds_widgets.dart';

class CreateSchedulePage extends StatefulWidget {
  final String? prefilledCustomerId;
  final String? prefilledCustomerName;
  final String? prefilledTicketId;
  final String? prefilledMachineId;

  const CreateSchedulePage({
    super.key,
    this.prefilledCustomerId,
    this.prefilledCustomerName,
    this.prefilledTicketId,
    this.prefilledMachineId,
  });

  @override
  State<CreateSchedulePage> createState() => _CreateSchedulePageState();
}

class _CreateSchedulePageState extends State<CreateSchedulePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _customerNotesCtrl = TextEditingController();
  final _adminNotesCtrl = TextEditingController();

  Map<String, dynamic>? _selectedCustomer;
  Map<String, dynamic>? _selectedEngineer;
  Map<String, dynamic>? _selectedMachine;

  String _scheduleType = 'preventive';
  DateTime _scheduledDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _scheduledTime = const TimeOfDay(hour: 9, minute: 0);
  int _duration = 60;
  bool _isRecurring = false;
  String _recurrenceRule = 'monthly';
  bool _saving = false;

  static const _scheduleTypes = [
    ('preventive', 'Preventive Maintenance'),
    ('repair', 'Repair'),
    ('inspection', 'Inspection'),
    ('installation', 'Installation'),
    ('warranty_visit', 'Warranty Visit'),
  ];

  static const _durations = [30, 60, 90, 120, 180, 240];

  static const _recurrenceRules = [
    ('monthly', 'Monthly'),
    ('quarterly', 'Quarterly'),
    ('biannual', 'Every 6 Months'),
    ('annual', 'Annually'),
  ];

  // ── Color map for schedule types ──
  static Color _typeColor(String type) {
    switch (type) {
      case 'preventive':
        return const Color(0xFF3B82F6);
      case 'repair':
        return const Color(0xFFEF4444);
      case 'inspection':
        return const Color(0xFF14B8A6);
      case 'installation':
        return const Color(0xFF8B5CF6);
      case 'warranty_visit':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF6B7280);
    }
  }

  // ── Lifecycle ──

  @override
  void initState() {
    super.initState();
    if (widget.prefilledCustomerId != null) {
      _loadPrefilledCustomer();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _customerNotesCtrl.dispose();
    _adminNotesCtrl.dispose();
    super.dispose();
  }

  // ── Prefill ──

  Future<void> _loadPrefilledCustomer() async {
    try {
      final data = await SupabaseConfig.client
          .from('users')
          .select('id, full_name, phone_number, profile_photo, company_name')
          .eq('id', widget.prefilledCustomerId!)
          .maybeSingle();
      if (!mounted || data == null) return;
      setState(() => _selectedCustomer = Map<String, dynamic>.from(data));

      // Also prefill machine if provided
      if (widget.prefilledMachineId != null) {
        _loadPrefilledMachine(widget.prefilledMachineId!);
      }
    } catch (_) {}
  }

  Future<void> _loadPrefilledMachine(String machineId) async {
    try {
      final data = await SupabaseConfig.client
          .from('customer_machines')
          .select('''
            id, serial_number, status,
            catalog:machine_catalog!catalog_machine_id(
              machine_name, model_number, image_url
            )
          ''')
          .eq('id', machineId)
          .maybeSingle();
      if (!mounted || data == null) return;
      setState(() => _selectedMachine = Map<String, dynamic>.from(data));
    } catch (_) {}
  }

  // ── Save ──

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomer == null) {
      _showError('Please select a customer');
      return;
    }

    setState(() => _saving = true);
    try {
      final userId = SupabaseConfig.client.auth.currentUser!.id;
      final timeStr =
          '${_scheduledTime.hour.toString().padLeft(2, '0')}:${_scheduledTime.minute.toString().padLeft(2, '0')}:00';

      await SupabaseConfig.client.from('service_schedules').insert({
        'customer_id': _selectedCustomer!['id'],
        'engineer_id': _selectedEngineer?['id'],
        'customer_machine_id': _selectedMachine?['id'],
        'ticket_id': widget.prefilledTicketId,
        'schedule_type': _scheduleType,
        'title': _titleCtrl.text.trim(),
        'description':
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'scheduled_date': _fmtDate(_scheduledDate),
        'scheduled_time': timeStr,
        'estimated_duration': _duration,
        'service_location': _locationCtrl.text.trim().isEmpty
            ? null
            : _locationCtrl.text.trim(),
        'is_recurring': _isRecurring,
        'recurrence_rule': _isRecurring ? _recurrenceRule : null,
        'customer_notes': _customerNotesCtrl.text.trim().isEmpty
            ? null
            : _customerNotesCtrl.text.trim(),
        'admin_notes': _adminNotesCtrl.text.trim().isEmpty
            ? null
            : _adminNotesCtrl.text.trim(),
        'status': 'scheduled',
        'created_by': userId,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(children: [
            Icon(Icons.check_circle, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Schedule created successfully'),
          ]),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AdminColors.success,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to create schedule: $e');
      setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg)),
        ]),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AdminColors.error,
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _machineName(Map<String, dynamic> machine) {
    final catalog = machine['catalog'] as Map<String, dynamic>?;
    return catalog?['machine_name'] as String? ?? 'Machine';
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Brand.canvas(isDark),
        appBar: DsPageHeader(
          title: 'Create Schedule',
          accent: HeroAccent.navy,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: _saving ? null : _save,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: _saving
                        ? null
                        : const LinearGradient(
                            colors: [
                              Brand.royalBlueDark,
                              Brand.royalBlueLight
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    color: _saving ? Brand.royalBlue : null,
                    borderRadius: BorderRadius.circular(Brand.r(10)),
                    boxShadow: isDark || _saving
                        ? null
                        : [
                            BoxShadow(
                              color: Brand.royalBlue.withAlpha(76),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Title ──
              _sectionLabel('Title *', isDark),
              const SizedBox(height: 6),
              _buildTextField(
                _titleCtrl,
                'e.g. Quarterly Maintenance',
                isDark,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 20),

              // ── Schedule Type ──
              _sectionLabel('Schedule Type', isDark),
              const SizedBox(height: 6),
              _buildTypeDropdown(isDark),
              const SizedBox(height: 20),

              // ── Customer ──
              _sectionLabel('Customer *', isDark),
              const SizedBox(height: 6),
              _buildSelectorTile(
                isDark: isDark,
                icon: Icons.person_outline,
                label: _selectedCustomer?['full_name'] ?? 'Select Customer',
                subtitle: _selectedCustomer?['company_name'],
                isSelected: _selectedCustomer != null,
                onTap: () => _showPersonPicker(
                  title: 'Select Customer',
                  role: 'customer',
                ),
              ),
              const SizedBox(height: 16),

              // ── Engineer ──
              _sectionLabel('Engineer (Optional)', isDark),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _buildSelectorTile(
                      isDark: isDark,
                      icon: Icons.engineering_outlined,
                      label: _selectedEngineer?['full_name'] ??
                          'Select Engineer',
                      isSelected: _selectedEngineer != null,
                      onTap: () => _showPersonPicker(
                        title: 'Select Engineer',
                        role: 'engineer',
                      ),
                    ),
                  ),
                  if (_selectedEngineer != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () =>
                          setState(() => _selectedEngineer = null),
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Clear engineer',
                      style: IconButton.styleFrom(
                        foregroundColor: AdminColors.error,
                        backgroundColor: AdminColors.error.withAlpha(20),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // ── Machine ──
              _sectionLabel('Machine (Optional)', isDark),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _buildSelectorTile(
                      isDark: isDark,
                      icon: Icons.precision_manufacturing_outlined,
                      label: _selectedMachine != null
                          ? '${_machineName(_selectedMachine!)} · '
                              '${_selectedMachine!['serial_number'] ?? ''}'
                          : _selectedCustomer == null
                              ? 'Select a customer first'
                              : 'Select Machine',
                      isSelected: _selectedMachine != null,
                      onTap: _selectedCustomer == null
                          ? () => _showError('Select a customer first')
                          : _showMachinePicker,
                    ),
                  ),
                  if (_selectedMachine != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () =>
                          setState(() => _selectedMachine = null),
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Clear machine',
                      style: IconButton.styleFrom(
                        foregroundColor: AdminColors.error,
                        backgroundColor: AdminColors.error.withAlpha(20),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),

              // ── Date & Time ──
              _sectionLabel('Date & Time', isDark),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _buildDateTile(isDark)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTimeTile(isDark)),
                ],
              ),
              const SizedBox(height: 20),

              // ── Duration ──
              _sectionLabel('Estimated Duration', isDark),
              const SizedBox(height: 6),
              _buildDurationChips(isDark),
              const SizedBox(height: 20),

              // ── Location ──
              _sectionLabel('Service Location', isDark),
              const SizedBox(height: 6),
              _buildTextField(
                _locationCtrl,
                'Enter service location address',
                isDark,
              ),
              const SizedBox(height: 20),

              // ── Recurring ──
              _buildRecurringSection(isDark),
              const SizedBox(height: 20),

              // ── Description ──
              _sectionLabel('Description', isDark),
              const SizedBox(height: 6),
              _buildTextField(
                _descCtrl,
                'Describe the service work to be done...',
                isDark,
                maxLines: 3,
              ),
              const SizedBox(height: 20),

              // ── Notes ──
              _sectionLabel('Admin Notes (Internal)', isDark),
              const SizedBox(height: 6),
              _buildTextField(
                _adminNotesCtrl,
                'Internal notes not visible to customer...',
                isDark,
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              _sectionLabel('Customer Notes', isDark),
              const SizedBox(height: 6),
              _buildTextField(
                _customerNotesCtrl,
                'Notes visible to customer...',
                isDark,
                maxLines: 2,
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ── Section Label ──

  Widget _sectionLabel(String text, bool isDark) => Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark
              ? Brand.darkTextSecondary
              : AdminColors.textSub(context),
        ),
      );

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
        color: isDark ? Brand.darkTextPrimary : AdminColors.text(context),
        fontSize: 14,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark
              ? Brand.darkTextTertiary
              : AdminColors.textHint(context),
          fontSize: 14,
        ),
        filled: true,
        fillColor: isDark ? Brand.darkCardElevated : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.r(12)),
          borderSide: BorderSide(
            color: isDark ? Brand.darkBorder : Brand.borderLight,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.r(12)),
          borderSide: BorderSide(
            color: isDark ? Brand.darkBorder : Brand.borderLight,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.r(12)),
          borderSide: const BorderSide(color: Brand.royalBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.r(12)),
          borderSide: const BorderSide(color: AdminColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.r(12)),
          borderSide: const BorderSide(color: AdminColors.error, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  // ── Schedule Type Dropdown ──

  Widget _buildTypeDropdown(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCardElevated : Colors.white,
        borderRadius: BorderRadius.circular(Brand.r(12)),
        border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _scheduleType,
          isExpanded: true,
          dropdownColor: isDark ? Brand.darkCardElevated : Colors.white,
          style: TextStyle(
            color: isDark ? Brand.darkTextPrimary : AdminColors.text(context),
            fontSize: 14,
          ),
          items: _scheduleTypes.map((t) {
            return DropdownMenuItem(
              value: t.$1,
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _typeColor(t.$1),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(t.$2),
                ],
              ),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) setState(() => _scheduleType = v);
          },
        ),
      ),
    );
  }

  // ── Selector Tile ──

  Widget _buildSelectorTile({
    required bool isDark,
    required IconData icon,
    required String label,
    String? subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Brand.r(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCardElevated : Colors.white,
          borderRadius: BorderRadius.circular(Brand.r(12)),
          border: Border.all(
            color: isSelected
                ? Brand.royalBlue.withAlpha(128)
                : (isDark ? Brand.darkBorder : Brand.borderLight),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? Brand.royalBlue
                  : (isDark
                      ? Brand.darkTextTertiary
                      : AdminColors.textHint(context)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w500 : FontWeight.w400,
                      color: isSelected
                          ? (isDark
                              ? Brand.darkTextPrimary
                              : AdminColors.text(context))
                          : (isDark
                              ? Brand.darkTextTertiary
                              : AdminColors.textHint(context)),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Brand.darkTextTertiary
                            : AdminColors.textHint(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: isDark
                  ? Brand.darkTextTertiary
                  : AdminColors.textHint(context),
            ),
          ],
        ),
      ),
    );
  }

  // ── Date Tile ──

  Widget _buildDateTile(bool isDark) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _scheduledDate,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Brand.royalBlue,
                brightness: isDark ? Brightness.dark : Brightness.light,
              ),
            ),
            child: child!,
          ),
        );
        if (!mounted) return;
        if (picked != null) setState(() => _scheduledDate = picked);
      },
      borderRadius: BorderRadius.circular(Brand.r(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCardElevated : Colors.white,
          borderRadius: BorderRadius.circular(Brand.r(12)),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today,
              size: 18,
              color: isDark
                  ? Brand.darkTextSecondary
                  : AdminColors.textSub(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_scheduledDate.day}/${_scheduledDate.month}/${_scheduledDate.year}',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? Brand.darkTextPrimary
                      : AdminColors.text(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Time Tile ──

  Widget _buildTimeTile(bool isDark) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: _scheduledTime,
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Brand.royalBlue,
                brightness: isDark ? Brightness.dark : Brightness.light,
              ),
            ),
            child: child!,
          ),
        );
        if (!mounted) return;
        if (picked != null) setState(() => _scheduledTime = picked);
      },
      borderRadius: BorderRadius.circular(Brand.r(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCardElevated : Colors.white,
          borderRadius: BorderRadius.circular(Brand.r(12)),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              Icons.access_time,
              size: 18,
              color: isDark
                  ? Brand.darkTextSecondary
                  : AdminColors.textSub(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _scheduledTime.format(context),
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? Brand.darkTextPrimary
                      : AdminColors.text(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Duration Chips ──

  Widget _buildDurationChips(bool isDark) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _durations.map((d) {
        final selected = _duration == d;
        final hours = d ~/ 60;
        final mins = d % 60;
        final label = hours > 0
            ? (mins > 0 ? '${hours}h ${mins}m' : '${hours}h')
            : '${mins}m';
        return ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => setState(() => _duration = d),
          selectedColor: Brand.royalBlue,
          backgroundColor: isDark ? Brand.darkCardElevated : Colors.white,
          labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected
                ? Colors.white
                : (isDark
                    ? Brand.darkTextSecondary
                    : AdminColors.textSub(context)),
          ),
          side: BorderSide(
            color: selected
                ? Brand.royalBlue
                : (isDark ? Brand.darkBorder : Brand.borderLight),
          ),
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
        );
      }).toList(),
    );
  }

  // ── Recurring Section ──

  Widget _buildRecurringSection(bool isDark) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCardElevated : Colors.white,
        borderRadius: BorderRadius.circular(Brand.r(12)),
        border: Border.all(
          color: _isRecurring
              ? Brand.royalBlue.withAlpha(128)
              : (isDark ? Brand.darkBorder : Brand.borderLight),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.repeat,
                size: 20,
                color: _isRecurring
                    ? Brand.royalBlue
                    : (isDark
                        ? Brand.darkTextSecondary
                        : AdminColors.textSub(context)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recurring Schedule',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : AdminColors.text(context),
                      ),
                    ),
                    if (_isRecurring)
                      Text(
                        'Automatic follow-up schedules will be created',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Brand.darkTextTertiary
                              : AdminColors.textHint(context),
                        ),
                      ),
                  ],
                ),
              ),
              Switch(
                value: _isRecurring,
                onChanged: (v) => setState(() => _isRecurring = v),
                activeThumbColor: Brand.royalBlue,
              ),
            ],
          ),
          if (_isRecurring) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _recurrenceRule,
              onChanged: (v) {
                if (v != null) setState(() => _recurrenceRule = v);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_recurrenceRules.length, (i) {
                  final rule = _recurrenceRules[i];
                  return RadioListTile<String>(
                    value: rule.$1,
                    title: Text(
                      rule.$2,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : AdminColors.text(context),
                      ),
                    ),
                    activeColor: Brand.royalBlue,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  );
                }),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Person Picker ──

  Future<void> _showPersonPicker({
    required String title,
    required String role,
  }) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) =>
          _PersonPickerSheet(title: title, role: role),
    );
    if (!mounted || result == null) return;

    setState(() {
      if (role == 'customer') {
        _selectedCustomer = Map<String, dynamic>.from(result);
        _selectedMachine = null; // reset machine on customer change
      } else {
        _selectedEngineer = Map<String, dynamic>.from(result);
      }
    });
  }

  // ── Machine Picker ──

  Future<void> _showMachinePicker() async {
    final customerId = _selectedCustomer?['id'] as String?;
    if (customerId == null) return;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) =>
          _MachinePickerSheet(customerId: customerId),
    );
    if (!mounted || result == null) return;
    setState(() => _selectedMachine = Map<String, dynamic>.from(result));
  }
}

// ══════════════════════════════════════════════════════════════
// Person Picker Bottom Sheet
// ══════════════════════════════════════════════════════════════

class _PersonPickerSheet extends StatefulWidget {
  final String title;
  final String role;
  const _PersonPickerSheet({required this.title, required this.role});

  @override
  State<_PersonPickerSheet> createState() => _PersonPickerSheetState();
}

class _PersonPickerSheetState extends State<_PersonPickerSheet> {
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  bool _hasError = false;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final data = await SupabaseConfig.client
          .from('users')
          .select(
            'id, full_name, phone_number, profile_photo, company_name',
          )
          .eq('role', widget.role)
          .order('full_name');
      if (!mounted) return;
      setState(() {
        _all = List<Map<String, dynamic>>.from(data);
        _filtered = List<Map<String, dynamic>>.from(_all);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  void _search(String q) {
    final query = q.toLowerCase().trim();
    setState(() {
      _filtered = query.isEmpty
          ? List<Map<String, dynamic>>.from(_all)
          : _all.where((p) {
              final name = (p['full_name'] ?? '').toString().toLowerCase();
              final company =
                  (p['company_name'] ?? '').toString().toLowerCase();
              final phone =
                  (p['phone_number'] ?? '').toString().toLowerCase();
              return name.contains(query) ||
                  company.contains(query) ||
                  phone.contains(query);
            }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : AdminColors.text(context),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  style: IconButton.styleFrom(
                    foregroundColor: isDark
                        ? Brand.darkTextSecondary
                        : AdminColors.textSub(context),
                  ),
                ),
              ],
            ),
          ),

          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _search,
              style: TextStyle(
                color: isDark
                    ? Brand.darkTextPrimary
                    : AdminColors.text(context),
              ),
              decoration: InputDecoration(
                hintText: 'Search by name, company or phone...',
                hintStyle: TextStyle(
                  color: isDark
                      ? Brand.darkTextTertiary
                      : AdminColors.textHint(context),
                  fontSize: 14,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 20,
                  color: isDark
                      ? Brand.darkTextTertiary
                      : AdminColors.textHint(context),
                ),
                filled: true,
                fillColor: isDark
                    ? Brand.darkCardElevated
                    : Brand.scaffoldLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Brand.r(12)),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Content
          Expanded(
            child: _loading
                ? _buildShimmer(isDark)
                : _hasError
                    ? _buildError(isDark)
                    : _filtered.isEmpty
                        ? _buildEmpty(isDark)
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 16),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) =>
                                _buildPersonTile(_filtered[i], isDark),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonTile(Map<String, dynamic> person, bool isDark) {
    final name = person['full_name'] as String? ?? 'Unknown';
    final company = person['company_name'] as String? ?? '';
    final phone = person['phone_number'] as String? ?? '';
    final photo = person['profile_photo'] as String?;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: Brand.royalBlue.withAlpha(26),
        backgroundImage: photo != null && photo.isNotEmpty
            ? CachedNetworkImageProvider(photo)
            : null,
        child: (photo == null || photo.isEmpty)
            ? Text(
                StringUtils.getInitials(name),
                style: const TextStyle(
                  color: Brand.royalBlue,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              )
            : null,
      ),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
          color: isDark ? Brand.darkTextPrimary : AdminColors.text(context),
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (company.isNotEmpty)
            Text(
              company,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? Brand.darkTextTertiary
                    : AdminColors.textHint(context),
              ),
            ),
          if (phone.isNotEmpty)
            Text(
              phone,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? Brand.darkTextTertiary
                    : AdminColors.textHint(context),
              ),
            ),
        ],
      ),
      trailing: Icon(
        Icons.chevron_right,
        size: 18,
        color:
            isDark ? Brand.darkTextTertiary : AdminColors.textHint(context),
      ),
      onTap: () => Navigator.pop(context, person),
    );
  }

  Widget _buildShimmer(bool isDark) {
    return ListView.builder(
      itemCount: 6,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _shimmerBox(44, 44, isDark, radius: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _shimmerBox(16, double.infinity, isDark),
                  const SizedBox(height: 6),
                  _shimmerBox(12, 140, isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shimmerBox(double h, double w, bool isDark, {double radius = 8}) =>
      Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCardElevated : Brand.borderLight,
          borderRadius: BorderRadius.circular(radius),
        ),
      );

  Widget _buildEmpty(bool isDark) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_search_outlined,
              size: 48,
              color: isDark
                  ? Brand.darkTextTertiary
                  : AdminColors.textHint(context),
            ),
            const SizedBox(height: 12),
            Text(
              _searchCtrl.text.isEmpty
                  ? 'No ${widget.role}s found'
                  : 'No results for "${_searchCtrl.text}"',
              style: TextStyle(
                color: isDark
                    ? Brand.darkTextTertiary
                    : AdminColors.textHint(context),
              ),
            ),
          ],
        ),
      );

  Widget _buildError(bool isDark) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AdminColors.error),
            const SizedBox(height: 12),
            Text(
              'Failed to load ${widget.role}s',
              style: TextStyle(
                color: isDark
                    ? Brand.darkTextSecondary
                    : AdminColors.textSub(context),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: TextButton.styleFrom(
                foregroundColor: Brand.royalBlue,
              ),
            ),
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════
// Machine Picker Bottom Sheet
// ══════════════════════════════════════════════════════════════

class _MachinePickerSheet extends StatefulWidget {
  final String customerId;
  const _MachinePickerSheet({required this.customerId});

  @override
  State<_MachinePickerSheet> createState() => _MachinePickerSheetState();
}

class _MachinePickerSheetState extends State<_MachinePickerSheet> {
  List<Map<String, dynamic>> _machines = [];
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final data = await SupabaseConfig.client
          .from('customer_machines')
          .select('''
            id, serial_number, status,
            catalog:machine_catalog!catalog_machine_id(
              machine_name, model_number, image_url
            )
          ''')
          .eq('user_id', widget.customerId)
          .eq('status', 'active')
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _machines = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.58,
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Select Machine',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : AdminColors.text(context),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  style: IconButton.styleFrom(
                    foregroundColor: isDark
                        ? Brand.darkTextSecondary
                        : AdminColors.textSub(context),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _loading
                ? _buildShimmer(isDark)
                : _hasError
                    ? _buildError(isDark)
                    : _machines.isEmpty
                        ? _buildEmpty(isDark)
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 16),
                            itemCount: _machines.length,
                            itemBuilder: (_, i) =>
                                _buildMachineTile(_machines[i], isDark),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildMachineTile(Map<String, dynamic> m, bool isDark) {
    final catalog = m['catalog'] as Map<String, dynamic>?;
    final name = catalog?['machine_name'] as String? ?? 'Machine';
    final model = catalog?['model_number'] as String? ?? '';
    final serial = m['serial_number'] as String? ?? '';
    final imageUrl = catalog?['image_url'] as String?;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(Brand.r(10)),
        child: imageUrl != null && imageUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _machineIconBox(),
              )
            : _machineIconBox(),
      ),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
          color: isDark ? Brand.darkTextPrimary : AdminColors.text(context),
        ),
      ),
      subtitle: Text(
        [if (model.isNotEmpty) model, if (serial.isNotEmpty) 'S/N: $serial']
            .join(' · '),
        style: TextStyle(
          fontSize: 12,
          color: isDark
              ? Brand.darkTextTertiary
              : AdminColors.textHint(context),
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        size: 18,
        color:
            isDark ? Brand.darkTextTertiary : AdminColors.textHint(context),
      ),
      onTap: () => Navigator.pop(context, m),
    );
  }

  Widget _machineIconBox() => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF8B5CF6).withAlpha(26),
          borderRadius: BorderRadius.circular(Brand.r(10)),
        ),
        child: const Icon(
          Icons.precision_manufacturing,
          size: 24,
          color: Color(0xFF8B5CF6),
        ),
      );

  Widget _buildShimmer(bool isDark) {
    return ListView.builder(
      itemCount: 4,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _shimmerBox(48, 48, isDark, radius: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _shimmerBox(16, double.infinity, isDark),
                  const SizedBox(height: 6),
                  _shimmerBox(12, 160, isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shimmerBox(double h, double w, bool isDark, {double radius = 8}) =>
      Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCardElevated : Brand.borderLight,
          borderRadius: BorderRadius.circular(radius),
        ),
      );

  Widget _buildEmpty(bool isDark) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.precision_manufacturing_outlined,
              size: 48,
              color: isDark
                  ? Brand.darkTextTertiary
                  : AdminColors.textHint(context),
            ),
            const SizedBox(height: 12),
            Text(
              'No active machines registered',
              style: TextStyle(
                color: isDark
                    ? Brand.darkTextTertiary
                    : AdminColors.textHint(context),
              ),
            ),
          ],
        ),
      );

  Widget _buildError(bool isDark) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AdminColors.error),
            const SizedBox(height: 12),
            Text(
              'Failed to load machines',
              style: TextStyle(
                color: isDark
                    ? Brand.darkTextSecondary
                    : AdminColors.textSub(context),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: TextButton.styleFrom(
                foregroundColor: Brand.royalBlue,
              ),
            ),
          ],
        ),
      );
}