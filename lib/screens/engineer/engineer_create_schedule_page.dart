import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/supabase_config.dart';
import '../../utils/string_utils.dart';

const Color _engAccent = Color(0xFF00B4D8);


class EngineerCreateSchedulePage extends StatefulWidget {
  const EngineerCreateSchedulePage({super.key});

  @override
  State<EngineerCreateSchedulePage> createState() =>
      _EngineerCreateSchedulePageState();
}

class _EngineerCreateSchedulePageState
    extends State<EngineerCreateSchedulePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  Map<String, dynamic>? _selectedCustomer;
  Map<String, dynamic>? _selectedMachine;

  String _scheduleType = 'preventive';
  DateTime _scheduledDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _scheduledTime = const TimeOfDay(hour: 9, minute: 0);
  int _duration = 60;
  bool _saving = false;

  static const _scheduleTypes = [
    ('preventive', 'Preventive Maintenance', Icons.build_circle_outlined),
    ('repair', 'Repair', Icons.handyman),
    ('inspection', 'Inspection', Icons.search),
    ('installation', 'Installation', Icons.precision_manufacturing),
    ('warranty_visit', 'Warranty Visit', Icons.verified_user),
  ];

  static const _durations = [30, 60, 90, 120, 180, 240];

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

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Save ──

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomer == null) {
      _showSnack('Please select a customer', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final userId = SupabaseConfig.client.auth.currentUser!.id;
      final timeStr =
          '${_scheduledTime.hour.toString().padLeft(2, '0')}:${_scheduledTime.minute.toString().padLeft(2, '0')}:00';

      // v24: Engineer-created schedules start as 'pending_approval' and are
      // NOT visible to the customer until an admin / engineering admin
      // approves the schedule.  Status flips to 'scheduled' on approval and
      // notifications fan out to the customer + the engineer.
      final inserted = await SupabaseConfig.client
          .from('service_schedules')
          .insert({
            'customer_id': _selectedCustomer!['id'],
            'engineer_id': userId,
            'customer_machine_id': _selectedMachine?['id'],
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
            'engineer_notes':
                _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
            'status': 'pending_approval',
            'created_by': userId,
          })
          .select('id, title')
          .single();

      // Best-effort notification to every admin + engineering admin so they
      // can review the request quickly.
      try {
        final reviewers = await SupabaseConfig.client
            .from('users')
            .select('id')
            .inFilter('role', ['admin', 'super_admin', 'engineering_admin']);
        final now = DateTime.now().toUtc().toIso8601String();
        final rows = (reviewers as List).map((r) => {
              'user_id': r['id'],
              'title': 'Schedule needs approval',
              'body':
                  'An engineer proposed: ${inserted['title'] ?? 'a service schedule'}',
              'type': 'system',
              'is_read': false,
              'created_at': now,
              'metadata': {
                'type': 'schedule_approval',
                'schedule_id': inserted['id'],
              },
            }).toList();
        if (rows.isNotEmpty) {
          await SupabaseConfig.client.from('notifications').insert(rows);
        }
      } catch (_) {
        // Non-fatal: the row is in pending_approval state and will surface in
        // the EA pending-approval list regardless.
      }

      if (!mounted) return;
      _showSnack('Schedule submitted for approval');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to create schedule: $e', isError: true);
      setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle,
              color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg)),
        ]),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isError ? StatusColors.danger : StatusColors.success,
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
          accent: HeroAccent.cyan,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : TextButton(
                      onPressed: _save,
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
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
              _buildTypeChips(isDark),
              const SizedBox(height: 20),

              // ── Customer ──
              _sectionLabel('Customer *', isDark),
              const SizedBox(height: 6),
              _buildSelectorTile(
                isDark: isDark,
                icon: Icons.person_outline,
                label:
                    _selectedCustomer?['full_name'] ?? 'Select Customer',
                subtitle: _selectedCustomer?['company_name'],
                isSelected: _selectedCustomer != null,
                onTap: _showCustomerPicker,
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
                          ? () => _showSnack('Select a customer first',
                              isError: true)
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
                        foregroundColor: StatusColors.danger,
                        backgroundColor: StatusColors.danger.withAlpha(20),
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

              // ── Engineer Notes ──
              _sectionLabel('Notes (Internal)', isDark),
              const SizedBox(height: 6),
              _buildTextField(
                _notesCtrl,
                'Your internal notes...',
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
          color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
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
        color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
          fontSize: 14,
        ),
        filled: true,
        fillColor: Brand.surface(isDark),
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
          borderSide: const BorderSide(color: _engAccent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.r(12)),
          borderSide: BorderSide(color: StatusColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.r(12)),
          borderSide: BorderSide(color: StatusColors.danger, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  // ── Schedule Type Chips ──

  Widget _buildTypeChips(bool isDark) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _scheduleTypes.map((t) {
        final selected = _scheduleType == t.$1;
        final color = _typeColor(t.$1);
        return ChoiceChip(
          avatar: Icon(t.$3, size: 16,
              color: selected ? Colors.white : color),
          label: Text(t.$2),
          selected: selected,
          onSelected: (_) => setState(() => _scheduleType = t.$1),
          selectedColor: color,
          backgroundColor: Brand.surface(isDark),
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected
                ? Colors.white
                : (isDark ? Brand.darkTextSecondary : Brand.subtleLight),
          ),
          side: BorderSide(
            color: selected
                ? color
                : (isDark ? Brand.darkBorder : Brand.borderLight),
          ),
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
        );
      }).toList(),
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
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(12)),
          border: Border.all(
            color: isSelected
                ? _engAccent.withAlpha(128)
                : (isDark ? Brand.darkBorder : Brand.borderLight),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? _engAccent
                  : (isDark ? Brand.darkTextTertiary : Brand.subtleLight),
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
                              : Brand.royalBlueDark)
                          : (isDark
                              ? Brand.darkTextTertiary
                              : Brand.subtleLight),
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
                            : Brand.subtleLight,
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
              color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
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
                seedColor: _engAccent,
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
          color: Brand.surface(isDark),
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
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_scheduledDate.day}/${_scheduledDate.month}/${_scheduledDate.year}',
                style: TextStyle(
                  fontSize: 14,
                  color:
                      isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
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
                seedColor: _engAccent,
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
          color: Brand.surface(isDark),
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
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _scheduledTime.format(context),
                style: TextStyle(
                  fontSize: 14,
                  color:
                      isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
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
          selectedColor: _engAccent,
          backgroundColor: Brand.surface(isDark),
          labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected
                ? Colors.white
                : (isDark ? Brand.darkTextSecondary : Brand.subtleLight),
          ),
          side: BorderSide(
            color: selected
                ? _engAccent
                : (isDark ? Brand.darkBorder : Brand.borderLight),
          ),
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
        );
      }).toList(),
    );
  }

  String _machineName(Map<String, dynamic> machine) {
    final catalog = machine['catalog'] as Map<String, dynamic>?;
    return catalog?['machine_name'] as String? ?? 'Machine';
  }

  // ── Customer Picker ──

  Future<void> _showCustomerPicker() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => const _CustomerPickerSheet(),
    );
    if (!mounted || result == null) return;
    setState(() {
      _selectedCustomer = Map<String, dynamic>.from(result);
      _selectedMachine = null;
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
      builder: (sheetCtx) => _MachinePickerSheet(customerId: customerId),
    );
    if (!mounted || result == null) return;
    setState(() => _selectedMachine = Map<String, dynamic>.from(result));
  }
}

// ══════════════════════════════════════════════════════════════
// Customer Picker Bottom Sheet
// ══════════════════════════════════════════════════════════════

class _CustomerPickerSheet extends StatefulWidget {
  const _CustomerPickerSheet();

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
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
          .select('id, full_name, phone_number, profile_photo, company_name')
          .eq('role', 'customer')
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
        color: Brand.surface(isDark),
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
                borderRadius: BorderRadius.circular(Brand.r(2)),
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
                    'Select Customer',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : Brand.royalBlueDark,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  style: IconButton.styleFrom(
                    foregroundColor:
                        isDark ? Brand.darkTextSecondary : Brand.subtleLight,
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
                color:
                    isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              ),
              decoration: InputDecoration(
                hintText: 'Search by name, company or phone...',
                hintStyle: TextStyle(
                  color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                  fontSize: 14,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 20,
                  color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                ),
                filled: true,
                fillColor:
                    isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
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

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: _engAccent.withAlpha(26),
        child: Text(
          StringUtils.getInitials(name),
          style: const TextStyle(
            color: _engAccent,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
          color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
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
                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
              ),
            ),
          if (phone.isNotEmpty)
            Text(
              phone,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
              ),
            ),
        ],
      ),
      trailing: Icon(
        Icons.chevron_right,
        size: 18,
        color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
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
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCardElevated : Brand.borderLight,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity, height: 16,
                    decoration: BoxDecoration(
                      color: isDark ? Brand.darkCardElevated : Brand.borderLight,
                      borderRadius: BorderRadius.circular(Brand.r(8)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 140, height: 12,
                    decoration: BoxDecoration(
                      color: isDark ? Brand.darkCardElevated : Brand.borderLight,
                      borderRadius: BorderRadius.circular(Brand.r(8)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isDark) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search_outlined,
                size: 48,
                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
            const SizedBox(height: 12),
            Text(
              _searchCtrl.text.isEmpty
                  ? 'No customers found'
                  : 'No results for "${_searchCtrl.text}"',
              style: TextStyle(
                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
              ),
            ),
          ],
        ),
      );

  Widget _buildError(bool isDark) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: StatusColors.danger),
            const SizedBox(height: 12),
            Text(
              'Failed to load customers',
              style: TextStyle(
                color:
                    isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style:
                  TextButton.styleFrom(foregroundColor: _engAccent),
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
        color: Brand.surface(isDark),
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
                borderRadius: BorderRadius.circular(Brand.r(2)),
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
                          : Brand.royalBlueDark,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  style: IconButton.styleFrom(
                    foregroundColor:
                        isDark ? Brand.darkTextSecondary : Brand.subtleLight,
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

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
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
      ),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
          color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
        ),
      ),
      subtitle: Text(
        [if (model.isNotEmpty) model, if (serial.isNotEmpty) 'S/N: $serial']
            .join(' · '),
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        size: 18,
        color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
      ),
      onTap: () => Navigator.pop(context, m),
    );
  }

  Widget _buildShimmer(bool isDark) {
    return ListView.builder(
      itemCount: 4,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCardElevated : Brand.borderLight,
                borderRadius: BorderRadius.circular(Brand.r(10)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity, height: 16,
                    decoration: BoxDecoration(
                      color: isDark ? Brand.darkCardElevated : Brand.borderLight,
                      borderRadius: BorderRadius.circular(Brand.r(8)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 140, height: 12,
                    decoration: BoxDecoration(
                      color: isDark ? Brand.darkCardElevated : Brand.borderLight,
                      borderRadius: BorderRadius.circular(Brand.r(8)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isDark) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.precision_manufacturing_outlined,
                size: 48,
                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
            const SizedBox(height: 12),
            Text(
              'No machines found for this customer',
              style: TextStyle(
                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
              ),
            ),
          ],
        ),
      );

  Widget _buildError(bool isDark) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: StatusColors.danger),
            const SizedBox(height: 12),
            Text(
              'Failed to load machines',
              style: TextStyle(
                color:
                    isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style:
                  TextButton.styleFrom(foregroundColor: _engAccent),
            ),
          ],
        ),
      );
}
