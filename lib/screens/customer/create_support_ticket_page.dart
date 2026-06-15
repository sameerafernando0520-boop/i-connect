// lib/screens/customer/create_support_ticket_page.dart

import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../services/points_service.dart';
import 'ticket_detail_page.dart';

class CreateSupportTicketPage extends StatefulWidget {
  final String? preselectedMachineId;
  final String? preselectedCategory;

  const CreateSupportTicketPage({
    super.key,
    this.preselectedMachineId,
    this.preselectedCategory,
  });

  @override
  State<CreateSupportTicketPage> createState() =>
      _CreateSupportTicketPageState();
}

class _CreateSupportTicketPageState extends State<CreateSupportTicketPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  int _currentStep = 0;

  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();

  String? _selectedMachineId;
  Map<String, dynamic>? _selectedMachineData;
  String? _selectedCategory;
  String _selectedPriority = 'medium';
  String _contactPreference = 'app';

  List<Map<String, dynamic>> _userMachines = [];
  List<Map<String, dynamic>> _existingOpenTickets = [];
  final List<XFile> _attachments = [];
  bool _loadingMachines = true;
  bool _hasError = false;
  bool _showExistingTicketWarning = false;

  Timer? _draftSaveTimer;
  bool _hasDraft = false;

  static const int _subjectMaxLength = 150;
  static const int _descriptionMaxLength = 2000;

  final List<Map<String, dynamic>> _categories = [
    {
      'value': 'Technical Issue',
      'icon': Icons.bug_report_rounded,
      'color': const Color(0xFFE53935),
      'desc': 'Software or hardware problems',
    },
    {
      'value': 'Maintenance Request',
      'icon': Icons.build_rounded,
      'color': const Color(0xFFFF9800),
      'desc': 'Scheduled or preventive service',
    },
    {
      'value': 'Parts Request',
      'icon': Icons.settings_rounded,
      'color': const Color(0xFF9C27B0),
      'desc': 'Spare parts or consumables',
    },
    {
      'value': 'Installation Support',
      'icon': Icons.handyman_rounded,
      'color': const Color(0xFF2196F3),
      'desc': 'Setup and configuration help',
    },
    {
      'value': 'Training Request',
      'icon': Icons.school_rounded,
      'color': const Color(0xFF4CAF50),
      'desc': 'Operator training needed',
    },
    {
      'value': 'Performance Issue',
      'icon': Icons.speed_rounded,
      'color': const Color(0xFFFF5722),
      'desc': 'Quality or speed problems',
    },
    {
      'value': 'Error/Fault',
      'icon': Icons.error_outline_rounded,
      'color': const Color(0xFFD32F2F),
      'desc': 'Error codes or machine faults',
    },
    {
      'value': 'Other',
      'icon': Icons.more_horiz_rounded,
      'color': const Color(0xFF607D8B),
      'desc': 'Something else',
    },
  ];

  final List<Map<String, dynamic>> _priorities = [
    {
      'value': 'low',
      'label': 'Low',
      'desc': 'Minor issue',
      'color': const Color(0xFF4CAF50),
      'icon': Icons.arrow_downward_rounded,
    },
    {
      'value': 'medium',
      'label': 'Medium',
      'desc': 'Normal issue',
      'color': const Color(0xFF2196F3),
      'icon': Icons.remove_rounded,
    },
    {
      'value': 'high',
      'label': 'High',
      'desc': 'Affecting work',
      'color': const Color(0xFFFF9800),
      'icon': Icons.arrow_upward_rounded,
    },
    {
      'value': 'urgent',
      'label': 'Urgent',
      'desc': 'Machine down',
      'color': const Color(0xFFE53935),
      'icon': Icons.priority_high_rounded,
    },
  ];

  final List<Map<String, dynamic>> _contactOptions = [
    {
      'value': 'app',
      'label': 'In-App Chat',
      'icon': Icons.chat_bubble_outline_rounded,
    },
    {
      'value': 'phone',
      'label': 'Phone Call',
      'icon': Icons.phone_outlined,
    },
    {
      'value': 'email',
      'label': 'Email',
      'icon': Icons.email_outlined,
    },
    {
      'value': 'whatsapp',
      'label': 'WhatsApp',
      'icon': Icons.message_outlined,
    },
  ];

  @override
  void initState() {
    super.initState();
    _selectedMachineId = widget.preselectedMachineId;
    _selectedCategory = widget.preselectedCategory;
    _loadUserMachines();
    _loadDraft();
    _subjectController.addListener(_scheduleDraftSave);
    _descriptionController.addListener(_scheduleDraftSave);
  }

  @override
  void dispose() {
    _subjectController.removeListener(_scheduleDraftSave);
    _descriptionController.removeListener(_scheduleDraftSave);
    _subjectController.dispose();
    _descriptionController.dispose();
    _scrollController.dispose();
    _draftSaveTimer?.cancel();
    super.dispose();
  }

  // ─── DATA LOADING ──────────────────────────────────────────
  Future<void> _loadUserMachines() async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      final data =
          await SupabaseConfig.client.from('customer_machines').select('''
            id,
            serial_number,
            status,
            purchase_date,
            warranty_end_date,
            catalog_machine_id,
            machine_catalog!inner(
              machine_name,
              brand,
              model_number,
              category,
              product_images
            )
          ''').eq('user_id', userId).order('purchase_date', ascending: false);

      if (!mounted) return;
      setState(() {
        _userMachines = List<Map<String, dynamic>>.from(data);
        _loadingMachines = false;
        _hasError = false;
      });

      if (_selectedMachineId != null) {
        final preselected = _userMachines.firstWhere(
          (m) => m['id'] == _selectedMachineId,
          orElse: () => <String, dynamic>{},
        );
        if (preselected.isNotEmpty) {
          _selectedMachineData = preselected;
          _checkExistingTickets();
        }
      }
    } catch (e) {
      debugPrint('Error loading machines: $e');
      if (!mounted) return;
      setState(() {
        _loadingMachines = false;
        _hasError = true;
      });
    }
  }

  // FIX #5/#11: Removed non-existent RPC, fixed .not() filter syntax
  Future<void> _checkExistingTickets() async {
    if (_selectedMachineId == null) {
      setState(() {
        _existingOpenTickets = [];
        _showExistingTicketWarning = false;
      });
      return;
    }

    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;

      final response = await SupabaseConfig.client
          .from('service_tickets')
          .select('id, ticket_number, subject, category, status, created_at')
          .eq('user_id', userId)
          .eq('customer_machine_id', _selectedMachineId!)
          .eq('ticket_type', 'support')
          // Closed/inactive states (per spec): resolved, closed, completed, cancelled.
          // Treat all of those as "not an existing open ticket" so the
          // duplicate-warning doesn't surface for tickets that were finished.
          .not('status', 'in', '(resolved,closed,completed,cancelled)')
          .order('created_at', ascending: false);

      _existingOpenTickets = List<Map<String, dynamic>>.from(response);

      if (!mounted) return;
      setState(() {
        _showExistingTicketWarning = _existingOpenTickets.isNotEmpty;
      });
    } catch (e) {
      debugPrint('Error checking existing tickets: $e');
    }
  }

  // ─── DRAFT MANAGEMENT ─────────────────────────────────────
  void _scheduleDraftSave() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(seconds: 3), _saveDraft);
  }

  Future<void> _saveDraft() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;

    if (_subjectController.text.isEmpty &&
        _descriptionController.text.isEmpty &&
        _selectedMachineId == null) {
      return;
    }

    try {
      await SupabaseConfig.client.from('ticket_drafts').upsert(
        {
          'user_id': userId,
          'ticket_type': 'support',
          'customer_machine_id': _selectedMachineId,
          'subject': _subjectController.text,
          'description': _descriptionController.text,
          'category': _selectedCategory,
          'priority': _selectedPriority,
          'draft_data': {
            'contact_preference': _contactPreference,
            'current_step': _currentStep,
          },
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,ticket_type',
      );
      if (mounted) {
        setState(() => _hasDraft = true);
      }
    } catch (e) {
      debugPrint('⚠️ Draft save skipped (table may not exist): $e');
    }
  }

  Future<void> _loadDraft() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;

    if (widget.preselectedMachineId != null) return;

    try {
      final response = await SupabaseConfig.client
          .from('ticket_drafts')
          .select('*')
          .eq('user_id', userId)
          .eq('ticket_type', 'support')
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          _hasDraft = true;
          if (response['subject'] != null) {
            _subjectController.text = response['subject'];
          }
          if (response['description'] != null) {
            _descriptionController.text = response['description'];
          }
          _selectedMachineId ??= response['customer_machine_id'];
          _selectedCategory ??= response['category'];
          _selectedPriority = response['priority'] ?? 'medium';

          final draftData = response['draft_data'] as Map<String, dynamic>?;
          if (draftData != null) {
            _contactPreference =
                draftData['contact_preference'] as String? ?? 'app';
          }
        });

        if (_subjectController.text.isNotEmpty ||
            _descriptionController.text.isNotEmpty) {
          _showDraftRestoredNotice();
        }
      }
    } catch (e) {
      debugPrint('⚠️ Draft load skipped: $e');
    }
  }

  Future<void> _deleteDraft() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await SupabaseConfig.client
          .from('ticket_drafts')
          .delete()
          .eq('user_id', userId)
          .eq('ticket_type', 'support');
    } catch (_) {}
  }

  void _showDraftRestoredNotice() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.restore, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Draft restored from previous session',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                setState(() {
                  _subjectController.clear();
                  _descriptionController.clear();
                  _selectedMachineId = null;
                  _selectedMachineData = null;
                  _selectedCategory = null;
                  _selectedPriority = 'medium';
                  _contactPreference = 'app';
                  _currentStep = 0;
                });
                _deleteDraft();
              },
              child: const Text(
                'CLEAR',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12),
              ),
            ),
          ],
        ),
        backgroundColor: Brand.royalBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(14))),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  // ─── ATTACHMENTS ───────────────────────────────────────────
  Future<void> _pickImage() async {
    if (_attachments.length >= 5) {
      _showError('Maximum 5 attachments allowed');
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Brand.surface(isDark),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Brand.r(24))),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                    borderRadius: BorderRadius.circular(Brand.r(2)),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Add Attachment',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildAttachmentOption(
                        Icons.camera_alt_rounded,
                        'Camera',
                        isDark,
                        () async {
                          Navigator.pop(sheetCtx);
                          final image = await _imagePicker.pickImage(
                            source: ImageSource.camera,
                            maxWidth: 1920,
                            maxHeight: 1080,
                            imageQuality: 80,
                          );
                          if (image != null && mounted) {
                            setState(() => _attachments.add(image));
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildAttachmentOption(
                        Icons.photo_library_rounded,
                        'Gallery',
                        isDark,
                        () async {
                          Navigator.pop(sheetCtx);
                          final images = await _imagePicker.pickMultiImage(
                            maxWidth: 1920,
                            maxHeight: 1080,
                            imageQuality: 80,
                          );
                          if (images.isNotEmpty && mounted) {
                            final remaining = 5 - _attachments.length;
                            setState(() {
                              _attachments.addAll(images.take(remaining));
                            });
                            if (images.length > remaining) {
                              _showError(
                                  'Only $remaining more attachment(s) allowed');
                            }
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildAttachmentOption(
                        Icons.videocam_rounded,
                        'Video',
                        isDark,
                        () async {
                          Navigator.pop(sheetCtx);
                          final video = await _imagePicker.pickVideo(
                            source: ImageSource.camera,
                            maxDuration: const Duration(seconds: 30),
                          );
                          if (video != null && mounted) {
                            setState(() => _attachments.add(video));
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttachmentOption(
    IconData icon,
    String label,
    bool isDark,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
          borderRadius: BorderRadius.circular(Brand.r(18)),
          border: Border.all(
              color: isDark ? Brand.darkBorderLight : Brand.borderLight),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<String>> _uploadAttachments(String ticketId) async {
    if (_attachments.isEmpty) return [];

    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return [];

    final List<String> uploadedUrls = [];

    for (int i = 0; i < _attachments.length; i++) {
      try {
        final file = _attachments[i];
        final ext = file.path.split('.').last.toLowerCase();
        final fileName =
            '$userId/$ticketId/attachment_${i + 1}_${DateTime.now().millisecondsSinceEpoch}.$ext';

        final bytes = await file.readAsBytes();

        await SupabaseConfig.client.storage
            .from('ticket-attachments')
            .uploadBinary(fileName, bytes);

        final url = SupabaseConfig.client.storage
            .from('ticket-attachments')
            .getPublicUrl(fileName);

        uploadedUrls.add(url);
      } catch (e) {
        debugPrint('Error uploading attachment $i: $e');
      }
    }

    return uploadedUrls;
  }

  // ─── TICKET CREATION ────────────────────────────────────────
  Future<void> _createTicket() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCategory == null) {
      _showError('Please select an issue category');
      setState(() => _currentStep = 0);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      // 1. Create ticket — trigger auto-generates ticket_number
      final result = await SupabaseConfig.client
          .from('service_tickets')
          .insert({
            'user_id': userId,
            'customer_machine_id': _selectedMachineId,
            'catalog_machine_id': _selectedMachineData?['catalog_machine_id'],
            'ticket_type': 'support',
            'subject': _subjectController.text.trim(),
            'description': _descriptionController.text.trim(),
            'category': _selectedCategory,
            'priority': _selectedPriority,
            'status': 'open',
            'metadata': {
              'contact_preference': _contactPreference,
            },
          })
          .select('id, ticket_number')
          .single();

      if (!mounted) return;

      final ticketId = result['id'] as String;
      final ticketNumber = result['ticket_number'] as String;

      // ── Award ticket creation points ──
      PointsService.award(
        'create_ticket',
        25,
        'Created support ticket',
        ticketId,
        'ticket',
      );

      // 2. Upload attachments (if any) — uses real ticket ID for path
      List<String> attachmentUrls = [];
      if (_attachments.isNotEmpty) {
        attachmentUrls = await _uploadAttachments(ticketId);
      }

      // 3. Create initial system chat message
      try {
        await SupabaseConfig.client.from('chat_messages').insert({
          'ticket_id': ticketId,
          'sender_id': null,
          'sender_type': 'system',
          'message':
              'Support ticket created: ${_subjectController.text.trim()}\n'
                  'Category: $_selectedCategory\n'
                  'Priority: ${_selectedPriority.toUpperCase()}',
          'attachments': attachmentUrls.isNotEmpty ? attachmentUrls : null,
          'is_internal': false,
        });
      } catch (_) {
        // Non-critical — ticket already created
      }

      // 4. Delete draft
      await _deleteDraft();

      if (!mounted) return;
      _showSuccessDialog(ticketNumber, ticketId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showError(
          'Error creating ticket: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(message,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
        backgroundColor: const Color(0xFFE53935),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(14))),
      ),
    );
  }

  void _showSuccessDialog(String ticketNumber, String ticketId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    setState(() => _isSubmitting = false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Brand.surface(isDark),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(26))),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.elasticOut,
                  builder: (_, value, child) {
                    return Transform.scale(scale: value, child: child);
                  },
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: Brand.lightGreen.withAlpha(((isDark ? 0.15 : 0.1) * 255).toInt()),
                      borderRadius: BorderRadius.circular(Brand.r(22)),
                      boxShadow: [
                        BoxShadow(
                          color: Brand.lightGreen.withAlpha(((0.2) * 255).toInt()),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.check_circle_rounded,
                        color: Brand.lightGreenBright, size: 42),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Ticket Created!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Brand.royalBlue.withAlpha(((0.12) * 255).toInt())
                        : Brand.royalBlueSurface,
                    borderRadius: BorderRadius.circular(Brand.r(10)),
                    border:
                        Border.all(color: Brand.royalBlue.withAlpha(((0.12) * 255).toInt())),
                  ),
                  child: Text(
                    ticketNumber,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Brand.royalBlueGlow : Brand.royalBlueDark,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Our support team will review your\nticket and respond within 24 hours.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 26),

                // Go to ticket chat
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(dialogCtx); // close dialog
                      if (!mounted) return;
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TicketDetailPage(ticketId: ticketId),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [Brand.royalBlue, Brand.royalBlueLight]
                              : [Brand.royalBlueDark, Brand.royalBlue],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(Brand.r(14)),
                        boxShadow: [
                          BoxShadow(
                            color: Brand.royalBlue.withAlpha(((0.35) * 255).toInt()),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_rounded,
                              color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Open Ticket Chat',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Done button
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(dialogCtx); // close dialog
                      if (!mounted) return;
                      Navigator.pop(context); // back to tickets list
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: isDark
                                ? Brand.darkBorderLight
                                : Brand.borderLight,
                            width: 1.5),
                        borderRadius: BorderRadius.circular(Brand.r(14)),
                      ),
                      child: Center(
                        child: Text(
                          'Back to Tickets',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── HELPERS ───────────────────────────────────────────────
  IconData _getCategoryIcon(String? category) {
    switch (category) {
      case 'Digital Printers':
        return Icons.print_rounded;
      case 'CNC Routers':
        return Icons.precision_manufacturing_rounded;
      case 'Laser Cutters':
        return Icons.content_cut_rounded;
      case 'Finishing Equipment':
        return Icons.construction_rounded;
      default:
        return Icons.settings_rounded;
    }
  }

  String? _getMachineImage(Map<String, dynamic>? catalog) {
    if (catalog == null) return null;
    final images = catalog['product_images'];
    if (images != null && images is List && images.isNotEmpty) {
      return images[0];
    }
    return null;
  }

  bool get _canProceedToStep2 => _selectedCategory != null;

  bool get _hasUnsavedData =>
      _subjectController.text.isNotEmpty ||
      _descriptionController.text.isNotEmpty ||
      _selectedMachineId != null ||
      _selectedCategory != null ||
      _attachments.isNotEmpty;

  Color _getPriorityColor(String priority) {
    for (var p in _priorities) {
      if (p['value'] == priority) return p['color'] as Color;
    }
    return Colors.grey;
  }

  // ─── BUILD ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Brand.darkCard)
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.white),
      child: PopScope(
        canPop: !_hasUnsavedData,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _hasUnsavedData) {
            _showExitConfirmation(isDark);
          }
        },
        child: Scaffold(
          backgroundColor: Brand.canvas(isDark),
          body: SafeArea(
            child: Column(
              children: [
                _buildTopBar(isDark),
                if (!_loadingMachines && !_hasError)
                  _buildStepIndicator(isDark),
                Expanded(
                  child: _loadingMachines
                      ? _buildLoadingState(isDark)
                      : _hasError
                          ? _buildErrorState(isDark)
                          : _buildFormContent(isDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── TOP BAR ───────────────────────────────────────────────
  Widget _buildTopBar(bool isDark) {
    return DsPageHeader(
      title: 'New Support Ticket',
      subtitle: _currentStep == 0
          ? 'Select machine & issue type'
          : _currentStep == 1
              ? 'Describe your issue'
              : 'Review & submit',
      onBack: () {
        if (_hasUnsavedData) {
          _showExitConfirmation(isDark);
        } else {
          Navigator.pop(context);
        }
      },
      actions: [
        if (_hasDraft)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Brand.lime.withAlpha(36),
              borderRadius: BorderRadius.circular(Brand.r(10)),
              border: Border.all(color: Brand.lime.withAlpha(120)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.save_outlined, color: Brand.lime, size: 12),
                SizedBox(width: 4),
                Text(
                  'Draft',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Brand.lime,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _showExitConfirmation(bool isDark) {
    showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Brand.surface(isDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(24))),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(((isDark ? 0.12 : 0.08) * 255).toInt()),
                  borderRadius: BorderRadius.circular(Brand.r(20)),
                ),
                child: Icon(Icons.warning_rounded,
                    color: Colors.orange.shade400, size: 30),
              ),
              const SizedBox(height: 18),
              Text('Leave Ticket?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    letterSpacing: -0.4,
                  )),
              const SizedBox(height: 8),
              Text(
                'Your progress will be saved as a draft.',
                style: TextStyle(
                    fontSize: 13,
                    color:
                        isDark ? Brand.darkTextSecondary : Brand.subtleLight),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(dialogCtx),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: isDark
                                  ? Brand.darkBorderLight
                                  : Brand.borderLight,
                              width: 1.5),
                          borderRadius: BorderRadius.circular(Brand.r(14)),
                        ),
                        child: Center(
                          child: Text('Keep Editing',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Brand.darkTextSecondary
                                      : Brand.subtleLight)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        await _saveDraft();
                        if (!dialogCtx.mounted) return;
                        Navigator.pop(dialogCtx);
                        if (!mounted) return;
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Brand.royalBlue, Brand.royalBlueLight],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(Brand.r(14)),
                          boxShadow: [
                            BoxShadow(
                                color: Brand.royalBlue.withAlpha(((0.35) * 255).toInt()),
                                blurRadius: 10,
                                offset: const Offset(0, 4)),
                          ],
                        ),
                        child: const Center(
                          child: Text('Save & Exit',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  await _deleteDraft();
                  if (!dialogCtx.mounted) return;
                  Navigator.pop(dialogCtx);
                  if (!mounted) return;
                  Navigator.pop(context);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Discard',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.red.shade400,
                      fontWeight: FontWeight.w700,
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

  // ─── STEP INDICATOR ────────────────────────────────────────
  Widget _buildStepIndicator(bool isDark) {
    final steps = ['Machine & Type', 'Details', 'Review'];

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (index) {
          if (index.isOdd) {
            return Expanded(
              child: Container(
                height: 2.5,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: _currentStep >= (index + 1) ~/ 2
                      ? Brand.royalBlue
                      : (isDark ? Brand.darkBorderLight : Brand.borderLight),
                  borderRadius: BorderRadius.circular(Brand.r(2)),
                ),
              ),
            );
          }

          final stepIndex = index ~/ 2;
          return _buildStep(stepIndex, steps[stepIndex], isDark);
        }),
      ),
    );
  }

  Widget _buildStep(int step, String label, bool isDark) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;
    final isCompleted = _currentStep > step;

    return GestureDetector(
      onTap: () {
        if (step < _currentStep) {
          setState(() => _currentStep = step);
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isActive
                  ? Brand.royalBlue
                  : (isDark ? Brand.darkCardElevated : Colors.white),
              shape: BoxShape.circle,
              border: !isActive
                  ? Border.all(
                      color: isDark ? Brand.darkBorderLight : Brand.borderLight)
                  : null,
              boxShadow: isCurrent
                  ? [
                      BoxShadow(
                        color: Brand.royalBlue.withAlpha(((0.35) * 255).toInt()),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : [],
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(Icons.check_rounded,
                      size: 16, color: Colors.white)
                  : Text(
                      '${step + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isActive
                            ? Colors.white
                            : (isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              color: isCurrent
                  ? (isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)
                  : (isDark ? Brand.darkTextSecondary : Brand.subtleLight),
            ),
          ),
        ],
      ),
    );
  }

  // ─── FORM CONTENT ──────────────────────────────────────────
  Widget _buildFormContent(bool isDark) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.05, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _currentStep == 0
                  ? _buildStep1(isDark)
                  : _currentStep == 1
                      ? _buildStep2(isDark)
                      : _buildStep3Review(isDark),
            ),
          ),
          _buildBottomActions(isDark),
        ],
      ),
    );
  }

  // ─── STEP 1: MACHINE & CATEGORY ────────────────────────────
  Widget _buildStep1(bool isDark) {
    return SingleChildScrollView(
      key: const ValueKey('step1'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? Brand.royalBlue.withAlpha(((0.08) * 255).toInt())
                  : Brand.royalBlueSurface,
              borderRadius: BorderRadius.circular(Brand.r(18)),
              border: Border.all(color: Brand.royalBlue.withAlpha(((0.12) * 255).toInt())),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Brand.royalBlue.withAlpha(((0.15) * 255).toInt())
                        : Brand.royalBlue.withAlpha(((0.08) * 255).toInt()),
                    borderRadius: BorderRadius.circular(Brand.r(12)),
                  ),
                  child: Icon(Icons.info_outline_rounded,
                      color: isDark ? Brand.royalBlueGlow : Brand.royalBlueDark,
                      size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Our support team typically responds within 24 hours. Attach photos to help us diagnose faster.',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Select Machine
          Row(
            children: [
              _buildSectionLabel('Select Machine',
                  Icons.precision_manufacturing_rounded, isDark,
                  required: false),
              const Spacer(),
              if (_userMachines.isNotEmpty)
                Text(
                  '(optional)',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (_userMachines.isEmpty)
            _buildNoMachinesInlineState(isDark)
          else
            ..._userMachines.map((machine) {
              final catalog =
                  machine['machine_catalog'] as Map<String, dynamic>?;
              final isSelected = _selectedMachineId == machine['id'];
              final machineImage = _getMachineImage(catalog);
              final isInService = machine['status'] == 'service';

              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (_selectedMachineId == machine['id']) {
                      _selectedMachineId = null;
                      _selectedMachineData = null;
                      _existingOpenTickets = [];
                      _showExistingTicketWarning = false;
                    } else {
                      _selectedMachineId = machine['id'];
                      _selectedMachineData = machine;
                      _checkExistingTickets();
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark
                            ? Brand.royalBlue.withAlpha(((0.08) * 255).toInt())
                            : Brand.royalBlueSurface)
                        : (Brand.surface(isDark)),
                    borderRadius: BorderRadius.circular(Brand.r(20)),
                    border: Border.all(
                      color: isSelected
                          ? (isDark ? Brand.royalBlueGlow : Brand.royalBlue)
                          : (isDark ? Brand.darkBorder : Brand.borderLight),
                      width: isSelected ? 2 : 1.5,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Brand.royalBlue
                                  .withAlpha(((isDark ? 0.2 : 0.12) * 255).toInt()),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : isDark
                            ? null
                            : [
                                BoxShadow(
                                    color: Brand.royalBlue.withAlpha(((0.04) * 255).toInt()),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3)),
                              ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDark
                                  ? Brand.royalBlue.withAlpha(((0.15) * 255).toInt())
                                  : Brand.royalBlue.withAlpha(((0.08) * 255).toInt()))
                              : (isDark
                                  ? Brand.darkCardElevated
                                  : Brand.royalBlueSurface),
                          borderRadius: BorderRadius.circular(Brand.r(14)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Brand.r(14)),
                          child: machineImage != null
                              ? CachedNetworkImage(
                                  imageUrl: machineImage,
                                  fit: BoxFit.cover,
                                  width: 50,
                                  height: 50,
                                  placeholder: (_, __) => Icon(
                                    _getCategoryIcon(catalog?['category']),
                                    size: 22,
                                    color: isDark
                                        ? Brand.royalBlueGlow
                                        : Brand.royalBlue,
                                  ),
                                  errorWidget: (_, __, ___) => Icon(
                                    _getCategoryIcon(catalog?['category']),
                                    size: 22,
                                    color: isDark
                                        ? Brand.royalBlueGlow
                                        : Brand.royalBlue,
                                  ),
                                )
                              : Icon(
                                  _getCategoryIcon(catalog?['category']),
                                  size: 22,
                                  color: isDark
                                      ? Brand.royalBlueGlow
                                      : Brand.royalBlue,
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              catalog?['machine_name'] ?? 'Unknown',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isSelected
                                    ? (isDark
                                        ? Brand.royalBlueGlow
                                        : Brand.royalBlueDark)
                                    : (isDark
                                        ? Brand.darkTextPrimary
                                        : Brand.royalBlueDark),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    '${catalog?['brand'] ?? ''} · S/N: ${machine['serial_number'] ?? 'N/A'}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? Brand.darkTextSecondary
                                          : Brand.subtleLight,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isInService) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.orange
                                          .withAlpha(((isDark ? 0.15 : 0.08) * 255).toInt()),
                                      borderRadius: BorderRadius.circular(Brand.r(10)),
                                      border: Border.all(
                                          color:
                                              Colors.orange.withAlpha(((0.15) * 255).toInt())),
                                    ),
                                    child: const Text(
                                      'IN SERVICE',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.orange,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color:
                              isSelected ? Brand.royalBlue : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? Brand.royalBlue
                                : (isDark
                                    ? Brand.darkBorderLight
                                    : Brand.borderLight),
                            width: 2,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                      color: Brand.royalBlue.withAlpha(((0.3) * 255).toInt()),
                                      blurRadius: 8)
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(Icons.check_rounded,
                                size: 14, color: Colors.white)
                            : null,
                      ),
                    ],
                  ),
                ),
              );
            }),

          // Existing ticket warning
          if (_showExistingTicketWarning) _buildExistingTicketWarning(isDark),

          const SizedBox(height: 24),

          // Issue Category
          _buildSectionLabel('Issue Category', Icons.label_rounded, isDark),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.4,
            children: _categories.map((cat) {
              final isSelected = _selectedCategory == cat['value'];
              final color = cat['color'] as Color;

              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedCategory = cat['value'] as String);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withAlpha(((isDark ? 0.12 : 0.08) * 255).toInt())
                        : (Brand.surface(isDark)),
                    borderRadius: BorderRadius.circular(Brand.r(16)),
                    border: Border.all(
                      color: isSelected
                          ? color
                          : (isDark ? Brand.darkBorder : Brand.borderLight),
                      width: isSelected ? 2 : 1.5,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                                color: color.withAlpha(((0.2) * 255).toInt()),
                                blurRadius: 10,
                                offset: const Offset(0, 3))
                          ]
                        : isDark
                            ? null
                            : [
                                BoxShadow(
                                    color: Brand.royalBlue.withAlpha(10),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2))
                              ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color.withAlpha(((isSelected ? 0.15 : 0.08) * 255).toInt()),
                          borderRadius: BorderRadius.circular(Brand.r(10)),
                        ),
                        child: Icon(cat['icon'] as IconData,
                            color: color, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              cat['value'] as String,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: isSelected
                                    ? color
                                    : (isDark
                                        ? Brand.darkTextPrimary
                                        : Brand.royalBlueDark),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              cat['desc'] as String,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Priority
          _buildSectionLabel('Priority Level', Icons.flag_rounded, isDark),
          const SizedBox(height: 12),
          Row(
            children: _priorities.map((priority) {
              final isSelected = _selectedPriority == priority['value'];
              final color = priority['color'] as Color;

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(
                        () => _selectedPriority = priority['value'] as String);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: EdgeInsets.only(
                        right: priority != _priorities.last ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withAlpha(((isDark ? 0.12 : 0.08) * 255).toInt())
                          : (Brand.surface(isDark)),
                      borderRadius: BorderRadius.circular(Brand.r(16)),
                      border: Border.all(
                        color: isSelected
                            ? color
                            : (isDark ? Brand.darkBorder : Brand.borderLight),
                        width: isSelected ? 2 : 1.5,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withAlpha(((0.2) * 255).toInt()),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : isDark
                              ? null
                              : [
                                  BoxShadow(
                                      color: Brand.royalBlue.withAlpha(10),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2))
                                ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: color.withAlpha(((isSelected ? 0.15 : 0.08) * 255).toInt()),
                            borderRadius: BorderRadius.circular(Brand.r(11)),
                          ),
                          child: Icon(
                            priority['icon'] as IconData,
                            color: color,
                            size: 16,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          priority['label'] as String,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w600,
                            color: isSelected
                                ? color
                                : (isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          priority['desc'] as String,
                          style: TextStyle(
                            fontSize: 11,
                            color: (isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight)
                                .withAlpha(((0.7) * 255).toInt()),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildExistingTicketWarning(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(((isDark ? 0.08 : 0.05) * 255).toInt()),
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: Border.all(color: Colors.orange.withAlpha(((0.18) * 255).toInt())),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(((0.15) * 255).toInt()),
                  borderRadius: BorderRadius.circular(Brand.r(10)),
                ),
                child: Icon(Icons.warning_amber_rounded,
                    color: Colors.orange.shade700, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You have ${_existingOpenTickets.length} open ticket${_existingOpenTickets.length > 1 ? 's' : ''} for this machine',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._existingOpenTickets.take(2).map((ticket) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 46),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TicketDetailPage(ticketId: ticket['id']),
                    ),
                  );
                },
                child: Row(
                  children: [
                    Text(
                      '${ticket['ticket_number']}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        ' - ${ticket['subject'] ?? ''}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.only(left: 46, top: 4),
            child: Text(
              'Consider updating an existing ticket instead.',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoMachinesInlineState(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(18)),
         border: isDark
         ? Border.all(color: Brand.darkBorder) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
              borderRadius: BorderRadius.circular(Brand.r(12)),
            ),
            child: Icon(Icons.info_outline,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'No machines registered. You can still create a general support ticket.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── STEP 2: DETAILS ───────────────────────────────────────
  Widget _buildStep2(bool isDark) {
    return SingleChildScrollView(
      key: const ValueKey('step2'),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subject
          _buildSectionLabel('Subject', Icons.title_rounded, isDark),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Brand.surface(isDark),
              borderRadius: BorderRadius.circular(Brand.r(18)),
              border: Border.all(
                  color: isDark ? Brand.darkBorder : Brand.borderLight,
                  width: 1.5),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                          color: Brand.royalBlue.withAlpha(((0.04) * 255).toInt()),
                          blurRadius: 10,
                          offset: const Offset(0, 3)),
                    ],
            ),
            child: Column(
              children: [
                TextFormField(
                  controller: _subjectController,
                  maxLength: _subjectMaxLength,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Subject is required'
                      : v.trim().length < 5
                          ? 'Subject too short (min 5 characters)'
                          : null,
                  style: TextStyle(
                      fontSize: 14,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                      fontWeight: FontWeight.w600),
                  cursorColor: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                  decoration: InputDecoration(
                    hintText: 'Brief description of the issue',
                    hintStyle: TextStyle(
                        color: (isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight)
                            .withAlpha(((0.6) * 255).toInt()),
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                    prefixIcon: Icon(Icons.edit_rounded,
                        color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                        size: 20),
                    enabledBorder: InputBorder.none,
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Brand.r(18)),
                        borderSide: BorderSide(
                            color: isDark
                                ? Brand.darkIconActive
                                : Brand.royalBlue,
                            width: 1.5)),
                    errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Brand.r(18)),
                        borderSide:
                            BorderSide(color: Colors.red.shade400)),
                    focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Brand.r(18)),
                        borderSide: BorderSide(
                            color: Colors.red.shade400, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    counterText: '',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 16, bottom: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${_subjectController.text.length}/$_subjectMaxLength',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _subjectController.text.length >
                                _subjectMaxLength * 0.9
                            ? Colors.orange
                            : (isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Description
          _buildSectionLabel('Description', Icons.description_rounded, isDark),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Brand.surface(isDark),
              borderRadius: BorderRadius.circular(Brand.r(18)),
              border: Border.all(
                  color: isDark ? Brand.darkBorder : Brand.borderLight,
                  width: 1.5),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                          color: Brand.royalBlue.withAlpha(((0.04) * 255).toInt()),
                          blurRadius: 10,
                          offset: const Offset(0, 3)),
                    ],
            ),
            child: Column(
              children: [
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 6,
                  maxLength: _descriptionMaxLength,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Description is required'
                      : v.trim().length < 10
                          ? 'Please provide more detail (min 10 characters)'
                          : null,
                  style: TextStyle(
                      fontSize: 14,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                      fontWeight: FontWeight.w500,
                      height: 1.5),
                  cursorColor: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                  decoration: InputDecoration(
                    hintText:
                        'Describe the issue in detail...\n\n• What happened?\n• When did it start?\n• Any error messages?',
                    hintStyle: TextStyle(
                        color: (isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight)
                            .withAlpha(((0.5) * 255).toInt()),
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                    enabledBorder: InputBorder.none,
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Brand.r(18)),
                        borderSide: BorderSide(
                            color: isDark
                                ? Brand.darkIconActive
                                : Brand.royalBlue,
                            width: 1.5)),
                    errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Brand.r(18)),
                        borderSide:
                            BorderSide(color: Colors.red.shade400)),
                    focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Brand.r(18)),
                        borderSide: BorderSide(
                            color: Colors.red.shade400, width: 1.5)),
                    contentPadding: const EdgeInsets.all(16),
                    counterText: '',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 16, bottom: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${_descriptionController.text.length}/$_descriptionMaxLength',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _descriptionController.text.length >
                                _descriptionMaxLength * 0.9
                            ? Colors.orange
                            : (isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Attachments section
          _buildSectionLabel('Attachments', Icons.attach_file_rounded, isDark,
              required: false),
          const SizedBox(height: 12),

          if (_attachments.isNotEmpty)
            Container(
              height: 94,
              margin: const EdgeInsets.only(bottom: 10),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _attachments.length + 1,
                itemBuilder: (context, index) {
                  if (index == _attachments.length) {
                    return _buildAddAttachmentButton(isDark);
                  }

                  final file = _attachments[index];
                  final isVideo = file.path.toLowerCase().endsWith('.mp4') ||
                      file.path.toLowerCase().endsWith('.mov');

                  return Container(
                    width: 94,
                    height: 94,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Brand.r(16)),
                      border: isDark ? Border.all(color: Brand.darkBorder) : null,
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(Brand.r(16)),
                          child: isVideo
                              ? Container(
                                  color: isDark
                                      ? Brand.darkCardElevated
                                      : Brand.royalBlueSurface,
                                  child: Center(
                                    child: Icon(Icons.videocam,
                                        color: isDark
                                            ? Brand.royalBlueGlow
                                            : Brand.royalBlue,
                                        size: 32),
                                  ),
                                )
                              : Image.file(
                                  File(file.path),
                                  width: 94,
                                  height: 94,
                                  fit: BoxFit.cover,
                                ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _attachments.removeAt(index));
                            },
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [
                                  Color(0xFFFF4757),
                                  Color(0xFFFF6B81)
                                ]),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color:
                                        isDark ? Brand.darkCard : Colors.white,
                                    width: 2),
                              ),
                              child: const Icon(Icons.close,
                                  size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            )
          else
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: BoxDecoration(
                  color: Brand.surface(isDark),
                  borderRadius: BorderRadius.circular(Brand.r(18)),
                  border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                              color: Brand.royalBlue.withAlpha(((0.04) * 255).toInt()),
                              blurRadius: 10,
                              offset: const Offset(0, 3)),
                        ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Brand.darkCardElevated
                            : Brand.royalBlueSurface,
                        borderRadius: BorderRadius.circular(Brand.r(16)),
                      ),
                      child: Icon(Icons.cloud_upload_outlined,
                          color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                          size: 26),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Tap to add photos or video',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.royalBlueDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Max 5 files · Photos & 30s videos',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 24),

          // Contact preference
          _buildSectionLabel(
              'How should we contact you?', Icons.contact_phone_rounded, isDark,
              required: false),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _contactOptions.map((option) {
              final isSelected = _contactPreference == option['value'];

              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(
                      () => _contactPreference = option['value'] as String);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark
                            ? Brand.royalBlue.withAlpha(((0.12) * 255).toInt())
                            : Brand.royalBlueSurface)
                        : (Brand.surface(isDark)),
                    borderRadius: BorderRadius.circular(Brand.r(14)),
                    border: Border.all(
                      color: isSelected
                          ? (isDark ? Brand.royalBlueGlow : Brand.royalBlue)
                          : (isDark ? Brand.darkBorder : Brand.borderLight),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        option['icon'] as IconData,
                        size: 16,
                        color: isSelected
                            ? (isDark ? Brand.royalBlueGlow : Brand.royalBlue)
                            : (isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        option['label'] as String,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? (isDark ? Brand.royalBlueGlow : Brand.royalBlue)
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
          ),
        ],
      ),
    );
  }

  Widget _buildAddAttachmentButton(bool isDark) {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        width: 94,
        height: 94,
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
          borderRadius: BorderRadius.circular(Brand.r(16)),
          border: Border.all(
              color: isDark ? Brand.darkBorderLight : Brand.borderLight),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded,
                color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                size: 24),
            const SizedBox(height: 4),
            Text(
              '${5 - _attachments.length} left',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── STEP 3: REVIEW ────────────────────────────────────────
  Widget _buildStep3Review(bool isDark) {
    final catalog =
        _selectedMachineData?['machine_catalog'] as Map<String, dynamic>?;

    return SingleChildScrollView(
      key: const ValueKey('step3'),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Review header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? Brand.lightGreen.withAlpha(((0.08) * 255).toInt())
                  : Brand.lightGreenSurface,
              borderRadius: BorderRadius.circular(Brand.r(18)),
              border: Border.all(color: Brand.lightGreen.withAlpha(((0.15) * 255).toInt())),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Brand.lightGreen.withAlpha(((0.15) * 255).toInt()),
                    borderRadius: BorderRadius.circular(Brand.r(12)),
                  ),
                  child: const Icon(Icons.preview_rounded,
                      color: Brand.lightGreenBright, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Please review your ticket details before submitting.',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Machine info
          if (_selectedMachineData != null) ...[
            _buildReviewSection('Machine', isDark, [
              _buildReviewRow(
                  'Name', catalog?['machine_name'] ?? 'Unknown', isDark),
              _buildReviewRow('Brand', catalog?['brand'] ?? 'N/A', isDark),
              _buildReviewRow('Serial',
                  _selectedMachineData?['serial_number'] ?? 'N/A', isDark),
            ]),
            const SizedBox(height: 14),
          ],

          // Issue details
          _buildReviewSection('Issue Details', isDark, [
            _buildReviewRow('Category', _selectedCategory ?? 'N/A', isDark),
            _buildReviewRow('Priority', _selectedPriority.toUpperCase(), isDark,
                valueColor: _getPriorityColor(_selectedPriority)),
            _buildReviewRow('Subject', _subjectController.text, isDark),
          ]),

          const SizedBox(height: 14),

          // Description
          _buildReviewSection('Description', isDark, [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _descriptionController.text,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ]),

          // Attachments
          if (_attachments.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildReviewSection(
                'Attachments (${_attachments.length})', isDark, [
              Container(
                height: 74,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _attachments.length,
                  itemBuilder: (context, index) {
                    return Container(
                      width: 74,
                      height: 74,
                      margin: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Brand.r(14)),
                        child: Image.file(
                          File(_attachments[index].path),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: isDark
                                ? Brand.darkCardElevated
                                : Brand.royalBlueSurface,
                            child: Icon(Icons.attach_file,
                                color: isDark
                                    ? Brand.royalBlueGlow
                                    : Brand.royalBlue),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ],

          // Contact preference
          const SizedBox(height: 14),
          _buildReviewSection('Contact Preference', isDark, [
            _buildReviewRow(
              'Method',
              _contactOptions.firstWhere(
                  (o) => o['value'] == _contactPreference,
                  orElse: () => {'label': 'In-App Chat'})['label'] as String,
              isDark,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildReviewSection(String title, bool isDark, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(18)),
         border: isDark
         ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Brand.royalBlue.withAlpha(((0.04) * 255).toInt()),
                    blurRadius: 10,
                    offset: const Offset(0, 3)),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _buildReviewRow(String label, String value, bool isDark,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: valueColor ??
                    (isDark ? Brand.darkTextPrimary : Brand.royalBlueDark),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── BOTTOM ACTIONS ────────────────────────────────────────
  Widget _buildBottomActions(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        border: Border(
          top: BorderSide(
              color: isDark ? Brand.darkBorder : Brand.borderLight, width: 1),
        ),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(15),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: _buildStepActions(isDark),
      ),
    );
  }

  Widget _buildStepActions(bool isDark) {
    switch (_currentStep) {
      case 0:
        return SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: () {
              if (_selectedCategory == null) {
                _showError('Please select an issue category');
                return;
              }
              setState(() => _currentStep = 1);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _canProceedToStep2
                      ? [Brand.royalBlueDark, Brand.royalBlue]
                      : [Colors.grey, Colors.grey.shade400],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(Brand.r(14)),
                boxShadow: _canProceedToStep2
                    ? [
                        BoxShadow(
                          color: Brand.royalBlue.withAlpha(((0.35) * 255).toInt()),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ]
                    : [],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Continue',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded,
                      color: Colors.white, size: 20),
                ],
              ),
            ),
          ),
        );

      case 1:
        return Row(
          children: [
            _backButton(isDark),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (_formKey.currentState!.validate()) {
                    setState(() => _currentStep = 2);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Brand.royalBlueDark, Brand.royalBlue],
                    ),
                    borderRadius: BorderRadius.circular(Brand.r(14)),
                    boxShadow: [
                      BoxShadow(
                          color: Brand.royalBlue.withAlpha(((0.35) * 255).toInt()),
                          blurRadius: 14,
                          offset: const Offset(0, 5)),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Review',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded,
                          color: Colors.white, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );

      case 2:
        return Row(
          children: [
            _backButton(isDark),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: _isSubmitting ? null : _createTicket,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Brand.lightGreenDark, Brand.lightGreen],
                    ),
                    borderRadius: BorderRadius.circular(Brand.r(14)),
                    boxShadow: [
                      BoxShadow(
                          color: Brand.lightGreen.withAlpha(((0.35) * 255).toInt()),
                          blurRadius: 14,
                          offset: const Offset(0, 5)),
                    ],
                  ),
                  child: _isSubmitting
                      ? const Center(
                          child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5)))
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.send_rounded,
                                color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text('Submit Ticket',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16)),
                          ],
                        ),
                ),
              ),
            ),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _backButton(bool isDark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _currentStep = _currentStep - 1),
        borderRadius: BorderRadius.circular(Brand.r(14)),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            border: Border.all(
                color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                width: 1.5),
            borderRadius: BorderRadius.circular(Brand.r(14)),
            color: Brand.surface(isDark),
          ),
          child: Icon(Icons.arrow_back_rounded,
              color: isDark ? Brand.darkTextSecondary : Brand.royalBlueDark,
              size: 22),
        ),
      ),
    );
  }

  // ─── SECTION LABEL ─────────────────────────────────────────
  Widget _buildSectionLabel(String label, IconData icon, bool isDark,
      {bool required = true}) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isDark
                ? Brand.royalBlue.withAlpha(((0.12) * 255).toInt())
                : Brand.royalBlueSurface,
            borderRadius: BorderRadius.circular(Brand.r(10)),
          ),
          child: Icon(icon,
              color: isDark ? Brand.royalBlueGlow : Brand.royalBlue, size: 16),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            letterSpacing: -0.2,
          ),
        ),
        if (required)
          const Text(' *',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE53935))),
      ],
    );
  }

  // ─── LOADING STATE ─────────────────────────────────────────
  Widget _buildLoadingState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: isDark
                  ? Brand.royalBlue.withAlpha(((0.1) * 255).toInt())
                  : Brand.royalBlueSurface,
              borderRadius: BorderRadius.circular(Brand.r(22)),
            ),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                  strokeWidth: 3,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Loading your machines...',
            style: TextStyle(
                fontSize: 14,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ─── ERROR STATE ───────────────────────────────────────────
  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(36),
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(24)),
           border: isDark
           ? Border.all(color: Brand.darkBorder) : null,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                      color: Brand.royalBlue.withAlpha(((0.04) * 255).toInt()),
                      blurRadius: 14,
                      offset: const Offset(0, 5)),
                ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(((isDark ? 0.12 : 0.08) * 255).toInt()),
                borderRadius: BorderRadius.circular(Brand.r(22)),
              ),
              child:
                  const Icon(Icons.error_outline, size: 38, color: Colors.red),
            ),
            const SizedBox(height: 22),
            Text(
              'Failed to Load',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Unable to load your machines.\nPlease check your connection.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 26),
            GestureDetector(
              onTap: () {
                setState(() {
                  _loadingMachines = true;
                  _hasError = false;
                });
                _loadUserMachines();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Brand.royalBlueDark, Brand.royalBlue],
                  ),
                  borderRadius: BorderRadius.circular(Brand.r(14)),
                  boxShadow: [
                    BoxShadow(
                        color: Brand.royalBlue.withAlpha(((0.35) * 255).toInt()),
                        blurRadius: 14,
                        offset: const Offset(0, 5)),
                  ],
                ),
                child: const Text('Try Again',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}