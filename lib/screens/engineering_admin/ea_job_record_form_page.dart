// ═══════════════════════════════════════════════════════════════
// FILE: lib/screens/engineering_admin/ea_job_record_form_page.dart
// Engineering Admin Portal — Screen 10: Job Record Form
// Create or edit a job record. Supports engineer picker,
// ticket picker, job type, date, duration, notes, outcome.
// Returns true on Navigator.pop if record was saved.
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';
import '../../widgets/ds/ds_widgets.dart';

const Color _eaAccent = Color(0xFF16A34A);

class EaJobRecordFormPage extends StatefulWidget {
  // For edit mode — pass the existing record map
  final Map<String, dynamic>? existingRecord;

  // For create mode with pre-selected engineer (from detail page)
  final String? preselectedEngineerId;
  final String? preselectedEngineerName;

  const EaJobRecordFormPage({
    super.key,
    this.existingRecord,
    this.preselectedEngineerId,
    this.preselectedEngineerName,
  });

  @override
  State<EaJobRecordFormPage> createState() => _EaJobRecordFormPageState();
}

class _EaJobRecordFormPageState extends State<EaJobRecordFormPage> {
  final _formKey = GlobalKey<FormState>();

  // Form state
  String? _engineerId;
  String? _engineerName;
  String? _ticketId;
  String? _ticketDisplay; // "#TKT-0001 — Title"
  String _jobType = 'repair';
  DateTime _jobDate = DateTime.now();
  double? _durationHours;
  String _status = 'completed';
  String _location = '';
  String _notes = '';
  String _outcome = '';

  // Pickers data
  List<Map<String, dynamic>> _engineers = [];
  List<Map<String, dynamic>> _tickets = [];
  bool _loadingEngineers = true;
  bool _loadingTickets = false;

  // Controllers
  final _durationCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _outcomeCtrl = TextEditingController();

  bool _saving = false;
  bool get _isEdit => widget.existingRecord != null;

  static const _jobTypes = [
    ('repair', 'Repair'),
    ('installation', 'Installation'),
    ('maintenance', 'Maintenance'),
    ('inspection', 'Inspection'),
    ('warranty', 'Warranty Visit'),
  ];

  static const _statuses = [
    ('pending', 'Pending'),
    ('in_progress', 'In Progress'),
    ('completed', 'Completed'),
    ('cancelled', 'Cancelled'),
  ];

  @override
  void initState() {
    super.initState();
    _prefill();
    _loadEngineers();
  }

  @override
  void dispose() {
    _durationCtrl.dispose();
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    _outcomeCtrl.dispose();
    super.dispose();
  }

  // ── Prefill for edit mode ─────────────────────────────────────

  void _prefill() {
    final r = widget.existingRecord;
    if (r != null) {
      final eng = r['engineer'] as Map<String, dynamic>?;
      final ticket = r['ticket'] as Map<String, dynamic>?;

      _engineerId = r['engineer_id'] as String?;
      _engineerName = eng?['full_name'] as String?;
      _ticketId = r['ticket_id'] as String?;
      if (ticket != null) {
        _ticketDisplay =
            '#${ticket['ticket_number'] ?? ''} — ${ticket['subject'] ?? ''}';
      }
      _jobType = r['job_type'] as String? ?? 'repair';
      _status = r['status'] as String? ?? 'completed';
      final dateStr = r['job_date'] as String?;
      if (dateStr != null) {
        try {
          _jobDate = DateTime.parse(dateStr);
        } catch (_) {}
      }
      _durationHours = (r['duration_hours'] as num?)?.toDouble();
      if (_durationHours != null) {
        _durationCtrl.text = _durationHours!.toStringAsFixed(1);
      }
      _location = r['location'] as String? ?? '';
      _locationCtrl.text = _location;
      _notes = r['notes'] as String? ?? '';
      _notesCtrl.text = _notes;
      _outcome = r['outcome'] as String? ?? '';
      _outcomeCtrl.text = _outcome;
    } else {
      // Create mode with pre-selected engineer
      _engineerId = widget.preselectedEngineerId;
      _engineerName = widget.preselectedEngineerName;
    }
  }

  // ── Load engineers ────────────────────────────────────────────

  Future<void> _loadEngineers() async {
    try {
      final data = await SupabaseConfig.client
          .from('users')
          .select('id, full_name, employee_id, assigned_zone')
          .eq('role', 'engineer')
          .filter('date_terminated', 'is', null)
          .order('full_name');

      if (!mounted) return;
      setState(() {
        _engineers = (data as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loadingEngineers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingEngineers = false);
    }
  }

  // ── Load open tickets (for ticket picker) ─────────────────────

  Future<void> _loadTickets() async {
    setState(() => _loadingTickets = true);
    try {
      final data = await SupabaseConfig.client
          .from('service_tickets')
          .select('id, ticket_number, subject, status')
          .inFilter('status', ['open', 'assigned', 'in_progress'])
          .order('created_at', ascending: false)
          .limit(100);

      if (!mounted) return;
      setState(() {
        _tickets = (data as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loadingTickets = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTickets = false);
    }
  }

  // ── Pickers ───────────────────────────────────────────────────

  void _pickEngineer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? Brand.darkCard : Colors.white;
    final textPrimary = isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B);
    final textSecondary = isDark ? Brand.darkTextSecondary : const Color(0xFF64748B);
    final borderColor = isDark ? Brand.darkBorder : Brand.borderLight;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (_, ctrl) => Container(
          decoration: BoxDecoration(
            color: cardBg,
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
                  color: borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Select Engineer',
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loadingEngineers
                    ? const Center(
                        child: CircularProgressIndicator(color: _eaAccent))
                    : ListView.builder(
                        controller: ctrl,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _engineers.length,
                        itemBuilder: (_, i) {
                          final e = _engineers[i];
                          final name = e['full_name'] as String? ?? '';
                          final empId = e['employee_id'] as String? ?? '';
                          final zone = e['assigned_zone'] as String? ?? '';
                          final selected = e['id'] == _engineerId;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  _eaAccent.withAlpha(isDark ? 30 : 20),
                              child: Text(
                                name.isNotEmpty
                                    ? name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: _eaAccent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            title: Text(name,
                                style: TextStyle(
                                    color: selected ? _eaAccent : textPrimary,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500)),
                            subtitle: Text(
                              '$empId · Zone $zone',
                              style: TextStyle(
                                  color: textSecondary, fontSize: 12),
                            ),
                            trailing: selected
                                ? const Icon(Icons.check_rounded,
                                    color: _eaAccent)
                                : null,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            onTap: () {
                              setState(() {
                                _engineerId = e['id'] as String;
                                _engineerName = name;
                              });
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _pickTicket() {
    if (_tickets.isEmpty && !_loadingTickets) _loadTickets();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? Brand.darkCard : Colors.white;
    final textPrimary = isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B);
    final textSecondary = isDark ? Brand.darkTextSecondary : const Color(0xFF64748B);
    final borderColor = isDark ? Brand.darkBorder : Brand.borderLight;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (_, ctrl) => StatefulBuilder(
          builder: (__, setInner) => Container(
            decoration: BoxDecoration(
              color: cardBg,
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
                    color: borderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Link Ticket (optional)',
                            style: TextStyle(
                                color: textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                      ),
                      if (_ticketId != null)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _ticketId = null;
                              _ticketDisplay = null;
                            });
                            Navigator.pop(context);
                          },
                          child: const Text('Clear',
                              style: TextStyle(color: Color(0xFFEF4444))),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _loadingTickets
                      ? const Center(
                          child: CircularProgressIndicator(color: _eaAccent))
                      : _tickets.isEmpty
                          ? Center(
                              child: Text('No open tickets',
                                  style: TextStyle(color: textSecondary)))
                          : ListView.builder(
                              controller: ctrl,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _tickets.length,
                              itemBuilder: (_, i) {
                                final t = _tickets[i];
                                final num = t['ticket_number'] as String? ?? '';
                                final title = t['subject'] as String? ?? '';
                                final selected = t['id'] == _ticketId;
                                return ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Brand.royalBlue.withAlpha(20),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.confirmation_number_outlined,
                                      size: 16,
                                      color: Brand.royalBlue,
                                    ),
                                  ),
                                  title: Text(
                                    '#$num · $title',
                                    style: TextStyle(
                                        color: selected
                                            ? _eaAccent
                                            : textPrimary,
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        fontSize: 13),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: selected
                                      ? const Icon(Icons.check_rounded,
                                          color: _eaAccent)
                                      : null,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                  onTap: () {
                                    setState(() {
                                      _ticketId = t['id'] as String;
                                      _ticketDisplay = '#$num — $title';
                                    });
                                    Navigator.pop(context);
                                  },
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _jobDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => _jobDate = picked);
  }

  // ── Save ──────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_engineerId == null) {
      _showSnack('Please select an engineer.');
      return;
    }

    setState(() => _saving = true);

    final dateStr =
        '${_jobDate.year}-${_jobDate.month.toString().padLeft(2, '0')}-${_jobDate.day.toString().padLeft(2, '0')}';

    final payload = <String, dynamic>{
      'engineer_id': _engineerId,
      'ticket_id': _ticketId,
      'job_type': _jobType,
      'job_date': dateStr,
      'status': _status,
      'duration_hours': _durationHours,
      'location': _locationCtrl.text.trim().isEmpty
          ? null
          : _locationCtrl.text.trim(),
      'notes': _notesCtrl.text.trim().isEmpty
          ? null
          : _notesCtrl.text.trim(),
      'outcome': _outcomeCtrl.text.trim().isEmpty
          ? null
          : _outcomeCtrl.text.trim(),
    };

    try {
      if (_isEdit) {
        await SupabaseConfig.client
            .from('job_records')
            .update(payload)
            .eq('id', widget.existingRecord!['id'] as String);
      } else {
        await SupabaseConfig.client.from('job_records').insert(payload);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showSnack('Error: ${e.toString()}');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = Brand.canvas(isDark);
    final textPrimary = isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B);
    final textSecondary = isDark ? Brand.darkTextSecondary : const Color(0xFF64748B);
    final borderColor = isDark ? Brand.darkBorder : Brand.borderLight;
    final inputFill = isDark ? Brand.darkCardElevated : Brand.scaffoldLight;

    final months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    return Scaffold(
      backgroundColor: bg,
      appBar: DsPageHeader(
        title: _isEdit ? 'Edit Job Record' : 'New Job Record',
        accent: HeroAccent.emerald,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Engineer picker ────────────────────────────────────
            _sectionLabel('Engineer *', textSecondary),
            _pickerTile(
              label: _engineerName ?? 'Select engineer',
              isEmpty: _engineerName == null,
              icon: Icons.person_rounded,
              isDark: isDark,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              borderColor: borderColor,
              onTap: _pickEngineer,
            ),
            const SizedBox(height: 16),

            // ── Ticket picker ──────────────────────────────────────
            _sectionLabel('Linked Ticket (optional)', textSecondary),
            _pickerTile(
              label: _ticketDisplay ?? 'Link to a ticket',
              isEmpty: _ticketDisplay == null,
              icon: Icons.confirmation_number_outlined,
              isDark: isDark,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              borderColor: borderColor,
              onTap: _pickTicket,
            ),
            const SizedBox(height: 16),

            // ── Job type ───────────────────────────────────────────
            _sectionLabel('Job Type', textSecondary),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _jobTypes.map((t) {
                final sel = _jobType == t.$1;
                return GestureDetector(
                  onTap: () => setState(() => _jobType = t.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? _eaAccent.withAlpha(25) : inputFill,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: sel ? _eaAccent : borderColor,
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      t.$2,
                      style: TextStyle(
                        color: sel ? _eaAccent : textSecondary,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // ── Status ─────────────────────────────────────────────
            _sectionLabel('Status', textSecondary),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _statuses.map((s) {
                final sel = _status == s.$1;
                final col = _statusColor(s.$1);
                return GestureDetector(
                  onTap: () => setState(() => _status = s.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? col.withAlpha(25) : inputFill,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: sel ? col : borderColor,
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      s.$2,
                      style: TextStyle(
                        color: sel ? col : textSecondary,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // ── Date picker ────────────────────────────────────────
            _sectionLabel('Job Date', textSecondary),
            _pickerTile(
              label:
                  '${_jobDate.day} ${months[_jobDate.month]} ${_jobDate.year}',
              isEmpty: false,
              icon: Icons.calendar_today_rounded,
              isDark: isDark,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              borderColor: borderColor,
              onTap: _pickDate,
            ),
            const SizedBox(height: 16),

            // ── Duration ───────────────────────────────────────────
            _sectionLabel('Duration (hours)', textSecondary),
            TextFormField(
              controller: _durationCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: textPrimary, fontSize: 14),
              decoration: _inputDeco(
                hint: 'e.g. 2.5',
                isDark: isDark,
                textSecondary: textSecondary,
              ),
              onChanged: (v) {
                _durationHours = double.tryParse(v);
              },
            ),
            const SizedBox(height: 16),

            // ── Location ───────────────────────────────────────────
            _sectionLabel('Location (optional)', textSecondary),
            TextFormField(
              controller: _locationCtrl,
              style: TextStyle(color: textPrimary, fontSize: 14),
              decoration: _inputDeco(
                hint: 'e.g. Colombo 03, Site B',
                isDark: isDark,
                textSecondary: textSecondary,
              ),
            ),
            const SizedBox(height: 16),

            // ── Notes ──────────────────────────────────────────────
            _sectionLabel('Notes (optional)', textSecondary),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              style: TextStyle(color: textPrimary, fontSize: 14),
              decoration: _inputDeco(
                hint: 'Internal notes about this job…',
                isDark: isDark,
                textSecondary: textSecondary,
              ),
            ),
            const SizedBox(height: 16),

            // ── Outcome ────────────────────────────────────────────
            _sectionLabel('Outcome / Findings (optional)', textSecondary),
            TextFormField(
              controller: _outcomeCtrl,
              maxLines: 3,
              style: TextStyle(color: textPrimary, fontSize: 14),
              decoration: _inputDeco(
                hint: 'What was found or done…',
                isDark: isDark,
                textSecondary: textSecondary,
              ),
            ),
            const SizedBox(height: 16),

            const SizedBox(height: 32),

            // ── Save button ────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _eaAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        _isEdit ? 'Save Changes' : 'Create Job Record',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Widget helpers ────────────────────────────────────────────

  Widget _sectionLabel(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _pickerTile({
    required String label,
    required bool isEmpty,
    required IconData icon,
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    final inputFill = isDark ? Brand.darkCardElevated : Brand.scaffoldLight;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: inputFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isEmpty ? textSecondary : _eaAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isEmpty ? textSecondary : textPrimary,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: textSecondary),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco({
    required String hint,
    required bool isDark,
    required Color textSecondary,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: textSecondary, fontSize: 14),
      filled: true,
      fillColor: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Brand.darkBorder : Brand.borderLight,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _eaAccent, width: 1.5),
      ),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'in_progress':
        return const Color(0xFF3B82F6);
      case 'completed':
        return const Color(0xFF10B981);
      case 'cancelled':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF94A3B8);
    }
  }
}
