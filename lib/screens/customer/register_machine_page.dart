// ============================================================
// FILE: lib/screens/customer/register_machine_page.dart
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../l10n/s.dart';

class RegisterMachinePage extends StatefulWidget {
  final Map<String, dynamic>? preselectedMachine;

  const RegisterMachinePage({super.key, this.preselectedMachine});

  @override
  State<RegisterMachinePage> createState() => _RegisterMachinePageState();
}

class _RegisterMachinePageState extends State<RegisterMachinePage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isCheckingDuplicate = false;
  int _currentStep = 0;
  final int _totalSteps = 3;

  // Controllers
  final _serialNumberController = TextEditingController();
  final _installationAddressController = TextEditingController();
  final _notesController = TextEditingController();
  final _nicknameController = TextEditingController();

  // Dates
  DateTime? _purchaseDate;
  DateTime? _warrantyEndDate;
  String _warrantyType = 'standard';

  // Machine selection
  String? _selectedMachineId;
  Map<String, dynamic>? _selectedMachineData;
  String _selectedCategory = 'All';

  // Machine catalog
  List<Map<String, dynamic>> _availableMachines = [];
  List<Map<String, dynamic>> _filteredMachines = [];
  bool _loadingMachines = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  // Photos
  final List<File> _installationPhotos = [];
  File? _purchaseProof;
  final _imagePicker = ImagePicker();

  // Validation
  String? _duplicateWarning;
  bool _serialValidated = false;

  // ── Connector (marketer / admin) the customer assigns at registration.
  // Stored on users.connector_id (per-customer), so registering a second
  // machine doesn't overwrite the first machine's connector — instead it
  // updates the customer's single connector.
  String? _connectorId;
  Map<String, dynamic>? _connectorData;
  List<Map<String, dynamic>> _availableConnectors = [];
  bool _loadingConnectors = false;

  // Animation
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  final List<String> _machineCategories = [
    'All',
    'Digital Printers',
    'CNC Routers',
    'Laser Cutters',
    'Finishing Equipment',
  ];

  final List<Map<String, dynamic>> _warrantyTypes = [
    {
      'value': 'standard',
      'label': 'Standard Warranty',
      'icon': Icons.verified_user_rounded,
      'color': Brand.lightGreen,
      'desc': 'Manufacturer default warranty',
    },
    {
      'value': 'extended',
      'label': 'Extended Warranty',
      'icon': Icons.security_rounded,
      'color': const Color(0xFF2196F3),
      'desc': 'Additional coverage purchased',
    },
    {
      'value': 'none',
      'label': 'No Warranty',
      'icon': Icons.remove_circle_outline_rounded,
      'color': const Color(0xFF9E9E9E),
      'desc': 'Warranty expired or not applicable',
    },
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );

    _loadAvailableMachines();
    _loadAvailableConnectors();
    _loadCurrentConnector();

    if (widget.preselectedMachine != null) {
      _selectedMachineId = widget.preselectedMachine!['id'];
      _selectedMachineData = widget.preselectedMachine;
      _currentStep = 1;
    }
  }

  @override
  void dispose() {
    _serialNumberController.dispose();
    _installationAddressController.dispose();
    _notesController.dispose();
    _nicknameController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _animController.dispose();
    super.dispose();
  }

  // ─── DATA LOADING ──────────────────────────────────────────

  Future<void> _loadAvailableMachines() async {
    try {
      final data = await SupabaseConfig.client
          .from('machine_catalog')
          .select(
              'id, machine_name, model_number, brand, category, sub_category, image_url, images, description')
          .eq('is_active', true)
          .order('category')
          .order('machine_name');

      if (!mounted) return;
      setState(() {
        _availableMachines = List<Map<String, dynamic>>.from(data);
        _filteredMachines = _availableMachines;
        _loadingMachines = false;
      });
      _animController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMachines = false);
      _animController.forward();
      _showSnackBar('Failed to load machines: $e', isError: true);
    }
  }

  // ─── CONNECTORS ────────────────────────────────────────────
  // The Connector picker lists every active marketer + admin in the system.
  // The customer picks who should contact them; their selection writes to
  // users.connector_id so admin/customer-detail/Need-Help-Choosing call
  // routing all stay in sync.
  Future<void> _loadAvailableConnectors() async {
    setState(() => _loadingConnectors = true);
    try {
      final data = await SupabaseConfig.client
          .from('users')
          .select('id, full_name, role, phone_number, profile_photo, company_name')
          .inFilter('role', const ['marketing_admin', 'admin', 'super_admin'])
          .or('is_active.is.null,is_active.eq.true')
          .order('full_name');
      if (!mounted) return;
      setState(() {
        _availableConnectors = List<Map<String, dynamic>>.from(data as List);
        _loadingConnectors = false;
      });
    } catch (e) {
      debugPrint('Failed to load connectors: $e');
      if (!mounted) return;
      setState(() => _loadingConnectors = false);
    }
  }

  Future<void> _loadCurrentConnector() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final row = await SupabaseConfig.client
          .from('users')
          .select(
              'connector_id, connector:users!connector_id(id, full_name, role, phone_number, profile_photo)')
          .eq('id', userId)
          .maybeSingle();
      if (!mounted || row == null) return;
      final cid = row['connector_id'] as String?;
      final c = row['connector'];
      if (cid != null && c is Map) {
        setState(() {
          _connectorId = cid;
          _connectorData = Map<String, dynamic>.from(c);
        });
      }
    } catch (e) {
      debugPrint('Failed to load current connector: $e');
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredMachines = _availableMachines.where((m) {
        final matchesCategory =
            _selectedCategory == 'All' || m['category'] == _selectedCategory;
        final query = _searchQuery.toLowerCase();
        final matchesSearch = query.isEmpty ||
            (m['machine_name'] ?? '')
                .toString()
                .toLowerCase()
                .contains(query) ||
            (m['brand'] ?? '').toString().toLowerCase().contains(query) ||
            (m['model_number'] ?? '')
                .toString()
                .toLowerCase()
                .contains(query) ||
            (m['sub_category'] ?? '').toString().toLowerCase().contains(query);
        return matchesCategory && matchesSearch;
      }).toList();
    });
  }

  int _getCategoryCount(String category) {
    if (category == 'All') return _availableMachines.length;
    return _availableMachines.where((m) => m['category'] == category).length;
  }

  // ─── DUPLICATE CHECK ───────────────────────────────────────

  Future<void> _checkDuplicate() async {
    final serial = _serialNumberController.text.trim();
    if (serial.isEmpty || _selectedMachineId == null) return;

    setState(() {
      _isCheckingDuplicate = true;
      _duplicateWarning = null;
    });

    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;

      // NOTE: check_duplicate_machine RPC may not exist — graceful fallback
      final result =
          await SupabaseConfig.client.rpc('check_duplicate_machine', params: {
        'p_serial_number': serial,
        'p_catalog_machine_id': _selectedMachineId,
        'p_user_id': userId,
      });

      if (!mounted) return;
      final data = result as Map<String, dynamic>;
      setState(() {
        _isCheckingDuplicate = false;
        if (data['duplicate'] == true) {
          _duplicateWarning = data['message'];
          _serialValidated = false;
        } else {
          _duplicateWarning = null;
          _serialValidated = true;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingDuplicate = false;
        _serialValidated = true; // Allow registration even if check fails
      });
    }
  }

  // ─── IMAGE PICKING ─────────────────────────────────────────

  Future<void> _pickInstallationPhoto() async {
    if (_installationPhotos.length >= 4) {
      _showSnackBar('Maximum 4 photos allowed');
      return;
    }

    final source = await _showImageSourceDialog();
    if (source == null) return;

    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
      );

      if (picked != null && mounted) {
        setState(() => _installationPhotos.add(File(picked.path)));
      }
    } catch (e) {
      _showSnackBar('Failed to pick image', isError: true);
    }
  }

  Future<void> _pickPurchaseProof() async {
    final source = await _showImageSourceDialog();
    if (source == null) return;

    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
      );

      if (picked != null && mounted) {
        setState(() => _purchaseProof = File(picked.path));
      }
    } catch (e) {
      _showSnackBar('Failed to pick image', isError: true);
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Brand.surface(isDark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkBorder : Brand.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Select Photo Source',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildImageSourceOption(
                    icon: Icons.camera_alt_rounded,
                    label: S.of(context)!.ticketCamera,
                    color: const Color(0xFF2196F3),
                    onTap: () => Navigator.pop(sheetCtx, ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildImageSourceOption(
                    icon: Icons.photo_library_rounded,
                    label: S.of(context)!.ticketGallery,
                    color: const Color(0xFF4CAF50),
                    onTap: () => Navigator.pop(sheetCtx, ImageSource.gallery),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSourceOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: color.withAlpha(((0.08) * 255).toInt()),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(((0.2) * 255).toInt())),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  Future<List<String>> _uploadPhotos() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return [];

    List<String> urls = [];

    for (int i = 0; i < _installationPhotos.length; i++) {
      try {
        final file = _installationPhotos[i];
        final ext = file.path.split('.').last;
        final path =
            'machines/$userId/${DateTime.now().millisecondsSinceEpoch}_$i.$ext';

        await SupabaseConfig.client.storage
            .from('machine-photos')
            .upload(path, file);

        final url = SupabaseConfig.client.storage
            .from('machine-photos')
            .getPublicUrl(path);
        urls.add(url);
      } catch (e) {
        debugPrint('Failed to upload photo $i: $e');
      }
    }

    return urls;
  }

  Future<String?> _uploadPurchaseProof() async {
    if (_purchaseProof == null) return null;
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      final ext = _purchaseProof!.path.split('.').last;
      final path =
          'proofs/$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';

      await SupabaseConfig.client.storage
          .from('machine-photos')
          .upload(path, _purchaseProof!);

      return SupabaseConfig.client.storage
          .from('machine-photos')
          .getPublicUrl(path);
    } catch (e) {
      debugPrint('Failed to upload purchase proof: $e');
      return null;
    }
  }

  // ─── DATE PICKER ───────────────────────────────────────────

  Future<void> _selectDate(BuildContext context,
      {required bool isPurchase}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isPurchase
          ? (_purchaseDate ?? DateTime.now())
          : (_warrantyEndDate ?? DateTime.now().add(const Duration(days: 365))),
      firstDate: DateTime(2000),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? ColorScheme.dark(
                    primary: Brand.darkIconActive,
                    onPrimary: const Color(0xFF1A1F36),
                    surface: Brand.darkCard,
                    onSurface: Brand.darkTextPrimary,
                  )
                : const ColorScheme.light(
                    primary: Brand.royalBlueDark,
                    onPrimary: Colors.white,
                    onSurface: Brand.royalBlueDark,
                  ), dialogTheme: DialogThemeData(backgroundColor: Brand.surface(isDark)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isPurchase) {
          _purchaseDate = picked;
          if (_warrantyEndDate == null && _warrantyType != 'none') {
            _warrantyEndDate = picked.add(const Duration(days: 365));
          }
        } else {
          _warrantyEndDate = picked;
        }
      });
    }
  }

  // ─── REGISTRATION ──────────────────────────────────────────

  Future<void> _registerMachine() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedMachineId == null) {
      _showSnackBar('Please select a machine model', isError: true);
      setState(() => _currentStep = 0);
      return;
    }

    if (_purchaseDate == null) {
      _showSnackBar('Please select a purchase date', isError: true);
      return;
    }

    if (_duplicateWarning != null) {
      _showSnackBar(_duplicateWarning!, isError: true);
      return;
    }

    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();

    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      final uploadResults = await Future.wait<dynamic>([
        _uploadPhotos(),
        _uploadPurchaseProof(),
      ]);

      if (!mounted) return;

      final photoUrls = uploadResults[0] as List<String>;
      final proofUrl = uploadResults[1] as String?;

      String? machineId;
      String? machineName;

      // NOTE: register_customer_machine RPC may not exist — fallback below
      try {
        final result = await SupabaseConfig.client
            .rpc('register_customer_machine', params: {
          'p_user_id': userId,
          'p_catalog_machine_id': _selectedMachineId,
          'p_serial_number': _serialNumberController.text.trim(),
          'p_installation_address':
              _installationAddressController.text.trim().isEmpty
                  ? null
                  : _installationAddressController.text.trim(),
          'p_purchase_date': _formatDateForDb(_purchaseDate),
          'p_warranty_end_date':
              _warrantyType != 'none' && _warrantyEndDate != null
                  ? _formatDateForDb(_warrantyEndDate)
                  : null,
          'p_warranty_type': _warrantyType,
          'p_machine_nickname': _nicknameController.text.trim().isEmpty
              ? null
              : _nicknameController.text.trim(),
          'p_notes': _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          'p_installation_photos': photoUrls.isEmpty ? null : photoUrls,
          'p_purchase_proof_url': proofUrl,
        });

        if (!mounted) return;
        final data = result as Map<String, dynamic>;
        if (data['success'] != true) {
          throw Exception(data['error'] ?? 'Registration failed');
        }
        machineId = data['machine_id'];
        machineName = data['machine_name'];
      } catch (rpcError) {
        debugPrint('RPC failed, using fallback: $rpcError');

        final insertResult = await SupabaseConfig.client
            .from('customer_machines')
            .insert({
              'user_id': userId,
              'catalog_machine_id': _selectedMachineId,
              'serial_number': _serialNumberController.text.trim(),
              'installation_address':
                  _installationAddressController.text.trim().isEmpty
                      ? null
                      : _installationAddressController.text.trim(),
              'purchase_date': _formatDateForDb(_purchaseDate),
              'warranty_end_date':
                  _warrantyType != 'none' && _warrantyEndDate != null
                      ? _formatDateForDb(_warrantyEndDate)
                      : null,
              'status': 'active',
            })
            .select()
            .single();

        if (!mounted) return;

        machineId = insertResult['id'];
        machineName = _selectedMachineData?['machine_name'];

        try {
          await SupabaseConfig.client.from('notifications').insert({
            'user_id': userId,
            'title': '🎉 Machine Registered!',
            'body':
                '${machineName ?? 'Your machine'} has been registered successfully.',
            'type': 'machine_registered',
            'related_id': machineId,
          });
        } catch (_) {}
      }

      // Persist chosen connector (if any) onto the customer's users row.
      // We do this AFTER the machine is created so a failed registration
      // doesn't silently change the customer's connector.
      if (_connectorId != null) {
        try {
          await SupabaseConfig.client.from('users').update({
            'connector_id': _connectorId,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', userId);
        } catch (e) {
          debugPrint('Failed to save connector_id: $e');
        }
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
      HapticFeedback.heavyImpact();
      _showSuccessDialog(machineName ??
          _selectedMachineData?['machine_name'] ??
          'Your machine');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar(
          'Registration failed: ${e.toString().replaceAll('Exception: ', '')}',
          isError: true);
    }
  }

  // ─── HELPERS ───────────────────────────────────────────────

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatDateForDb(DateTime? date) {
    if (date == null) return '';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String? _getMachineImageUrl(Map<String, dynamic> machine) {
    if (machine['images'] != null && (machine['images'] as List).isNotEmpty) {
      return (machine['images'] as List)[0]?.toString();
    }
    if (machine['image_url'] != null &&
        machine['image_url'].toString().isNotEmpty) {
      return machine['image_url'].toString();
    }
    return null;
  }

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
        return Icons.settings_suggest_rounded;
    }
  }

  Color _getCategoryColor(String? category) {
    switch (category) {
      case 'Digital Printers':
        return const Color(0xFF2196F3);
      case 'CNC Routers':
        return const Color(0xFFFF9800);
      case 'Laser Cutters':
        return const Color(0xFFE91E63);
      case 'Finishing Equipment':
        return const Color(0xFF4CAF50);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.info_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red : Brand.lightGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  double get _progressValue {
    double base = (_currentStep / _totalSteps);
    if (_currentStep == 1) {
      int filled = 0;
      if (_serialNumberController.text.isNotEmpty) filled++;
      if (_purchaseDate != null) filled++;
      if (_installationAddressController.text.isNotEmpty) filled++;
      base += (filled / 3) * (1 / _totalSteps);
    }
    return base.clamp(0.0, 1.0);
  }

  bool get _canProceedStep1 => _selectedMachineId != null;

  bool get _canProceedStep2 =>
      _serialNumberController.text.trim().isNotEmpty &&
      _purchaseDate != null &&
      _duplicateWarning == null;

  // ─── EXIT CONFIRMATION ─────────────────────────────────────

  void _showExitConfirmation() {
    if (_selectedMachineId == null && _serialNumberController.text.isEmpty) {
      Navigator.pop(context);
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Brand.surface(isDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(((isDark ? 0.15 : 0.1) * 255).toInt()),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.warning_rounded,
                    color: Colors.orange.shade400, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                'Discard Registration?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your progress will be lost.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(dialogCtx),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color:
                                isDark ? Brand.darkBorder : Brand.borderLight,
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            'Keep Editing',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(dialogCtx);
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(S.of(context)!.registerDiscard,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ),
                      ),
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

  // ─── SUCCESS DIALOG ────────────────────────────────────────

  void _showSuccessDialog(String machineName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Brand.surface(isDark),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) =>
                      Transform.scale(scale: value, child: child),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color:
                          (isDark ? Brand.lightGreenBright : Brand.lightGreen)
                              .withAlpha(((0.12) * 255).toInt()),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(Icons.check_circle_rounded,
                        color:
                            isDark ? Brand.lightGreenBright : Brand.lightGreen,
                        size: 48),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Machine Registered!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$machineName\nhas been registered successfully.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (isDark ? Brand.darkIconActive : Brand.royalBlue)
                        .withAlpha(((0.06) * 255).toInt()),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color:
                              isDark ? Brand.darkIconActive : Brand.royalBlue,
                          size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'You can now create support tickets and track service for this machine.',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(dialogCtx);
                      Navigator.pop(context, true);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [
                                  Brand.darkIconActive,
                                  Brand.darkIconActive.withAlpha(((0.8) * 255).toInt()),
                                ]
                              : [
                                  Brand.royalBlueDark,
                                  Brand.royalBlue,
                                ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: (isDark
                                    ? Brand.darkIconActive
                                    : Brand.royalBlueDark)
                                .withAlpha(((0.3) * 255).toInt()),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'View My Machines',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color:
                                isDark ? const Color(0xFF1A1F36) : Colors.white,
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

  // ─── BUILD ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(isDark),
            if (!_loadingMachines) ...[
              _buildProgressBar(isDark),
              _buildStepIndicator(isDark),
            ],
            Expanded(
              child: _loadingMachines
                  ? _buildLoadingState(isDark)
                  : FadeTransition(
                      opacity: _fadeAnimation,
                      child: _buildFormContent(isDark),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── TOP BAR ───────────────────────────────────────────────

  Widget _buildTopBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 8, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: _showExitConfirmation,
            child: Container(
              width: 44,
              height: 44,
              margin: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                color: Brand.surface(isDark),
                borderRadius: BorderRadius.circular(12),
                border: isDark ? Border.all(color: Brand.darkBorder) : null,
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
              child: Icon(Icons.close_rounded,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  size: 22),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Register Machine',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                ),
                Text(
                  _currentStep == 0
                      ? 'Step 1: Choose your machine'
                      : _currentStep == 1
                          ? 'Step 2: Machine details'
                          : 'Step 3: Review & confirm',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                ),
              ],
            ),
          ),
          if (_currentStep > 0)
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _currentStep--);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color:
                      isDark ? Brand.darkCardElevated : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: isDark ? Border.all(color: Brand.darkBorder) : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_rounded,
                        size: 16,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight),
                    const SizedBox(width: 4),
                    Text(
                      'Back',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── PROGRESS BAR ─────────────────────────────────────────

  Widget _buildProgressBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: _progressValue),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          builder: (context, value, _) => LinearProgressIndicator(
            value: value,
            minHeight: 4,
            backgroundColor: isDark ? Brand.darkBorder : Brand.borderLight,
            valueColor: AlwaysStoppedAnimation<Color>(
                isDark ? Brand.darkIconActive : Brand.royalBlue),
          ),
        ),
      ),
    );
  }

  // ─── STEP INDICATOR ────────────────────────────────────────

  Widget _buildStepIndicator(bool isDark) {
    final steps = ['Select', 'Details', 'Review'];
    final accent = isDark ? Brand.darkIconActive : Brand.royalBlue;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: List.generate(steps.length, (index) {
          final isActive = _currentStep >= index;
          final isCurrent = _currentStep == index;
          final isCompleted = _currentStep > index;

          return Expanded(
            child: Row(
              children: [
                if (index > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: isActive
                          ? accent
                          : (isDark ? Brand.darkBorder : Brand.borderLight),
                    ),
                  ),
                GestureDetector(
                  onTap: index < _currentStep
                      ? () => setState(() => _currentStep = index)
                      : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: isActive
                              ? accent
                              : (isDark
                                  ? Brand.darkCardElevated
                                  : const Color(0xFFF1F5F9)),
                          shape: BoxShape.circle,
                          border: !isActive
                              ? Border.all(
                                  color: isDark
                                      ? Brand.darkBorder
                                      : Brand.borderLight)
                              : null,
                          boxShadow: isCurrent
                              ? [
                                  BoxShadow(
                                    color: accent.withAlpha(((0.3) * 255).toInt()),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : [],
                        ),
                        child: Center(
                          child: isCompleted
                              ? Icon(Icons.check_rounded,
                                  size: 14,
                                  color: isDark
                                      ? const Color(0xFF1A1F36)
                                      : Colors.white)
                              : Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isActive
                                        ? (isDark
                                            ? const Color(0xFF1A1F36)
                                            : Colors.white)
                                        : (isDark
                                            ? Brand.darkTextSecondary
                                            : Brand.subtleLight),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        steps[index],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              isCurrent ? FontWeight.bold : FontWeight.w500,
                          color: isCurrent
                              ? (isDark
                                  ? Brand.darkTextPrimary
                                  : Brand.royalBlueDark)
                              : (isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
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
                      : _buildStep3(isDark),
            ),
          ),
          _buildBottomActions(isDark),
        ],
      ),
    );
  }

  // ─── STEP 1: SELECT MACHINE ────────────────────────────────

  Widget _buildStep1(bool isDark) {
    final accent = isDark ? Brand.darkIconActive : Brand.royalBlue;

    return Column(
      key: const ValueKey('step1'),
      children: [
        // Search
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius: BorderRadius.circular(14),
            border: isDark ? Border.all(color: Brand.darkBorder) : null,
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Brand.royalBlue.withAlpha(10),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: (value) {
              _searchQuery = value;
              _applyFilters();
            },
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            ),
            cursorColor: accent,
            decoration: InputDecoration(
              hintText: S.of(context)!.registerSearchHint,
              hintStyle: TextStyle(
                color: (isDark ? Brand.darkTextSecondary : Brand.subtleLight)
                    .withAlpha(((0.6) * 255).toInt()),
                fontSize: 13,
              ),
              prefixIcon: Icon(Icons.search_rounded,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  size: 22),
              suffixIcon: _searchQuery.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        _searchQuery = '';
                        _applyFilters();
                      },
                      child: Icon(Icons.close_rounded,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight,
                          size: 20),
                    )
                  : null,
              enabledBorder: InputBorder.none,
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                      width: 1.5)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),

        // Category chips
        Container(
          height: 48,
          margin: const EdgeInsets.only(top: 10),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: _machineCategories.length,
            itemBuilder: (context, index) {
              final cat = _machineCategories[index];
              final isSelected = _selectedCategory == cat;
              final count = _getCategoryCount(cat);

              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _selectedCategory = cat;
                  _applyFilters();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark ? Brand.darkIconActive : Brand.royalBlueDark)
                        : (Brand.surface(isDark)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? (isDark
                              ? Brand.darkIconActive
                              : Brand.royalBlueDark)
                          : (isDark ? Brand.darkBorder : Brand.borderLight),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        cat == 'All' ? 'All' : cat.split(' ').first,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? (isDark
                                  ? const Color(0xFF1A1F36)
                                  : Colors.white)
                              : (isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withAlpha(((0.2) * 255).toInt())
                              : (isDark
                                  ? Brand.darkCardElevated
                                  : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? (isDark
                                    ? const Color(0xFF1A1F36)
                                    : Colors.white)
                                : (isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // Results count
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
          child: Row(
            children: [
              Text(
                '${_filteredMachines.length} machines',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (_selectedMachineId != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(((0.1) * 255).toInt()),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 14, color: accent),
                      const SizedBox(width: 4),
                      Text(
                        '1 selected',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // Machine list
        Expanded(
          child: _filteredMachines.isEmpty
              ? _buildEmptySearchState(isDark)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: _filteredMachines.length,
                  itemBuilder: (context, index) =>
                      _buildMachineSelectCard(_filteredMachines[index], isDark),
                ),
        ),
      ],
    );
  }

  Widget _buildMachineSelectCard(Map<String, dynamic> machine, bool isDark) {
    final accent = isDark ? Brand.darkIconActive : Brand.royalBlue;
    final isSelected = _selectedMachineId == machine['id'];
    final imageUrl = _getMachineImageUrl(machine);
    final categoryColor = _getCategoryColor(machine['category']);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedMachineId = machine['id'];
          _selectedMachineData = machine;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? Brand.darkIconActive.withAlpha(((0.08) * 255).toInt())
                  : Brand.royalBlueDark.withAlpha(((0.04) * 255).toInt()))
              : (Brand.surface(isDark)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? (isDark ? Brand.darkIconActive : Brand.royalBlueDark)
                : (isDark ? Brand.darkBorder : Brand.borderLight),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: (isDark ? Brand.darkIconActive : Brand.royalBlueDark)
                        .withAlpha(((0.12) * 255).toInt()),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Brand.royalBlue.withAlpha(10),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
        ),
        child: Row(
          children: [
            // Image
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: isSelected
                    ? categoryColor.withAlpha(((0.1) * 255).toInt())
                    : (isDark
                        ? Brand.darkCardElevated
                        : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        width: 58,
                        height: 58,
                        placeholder: (_, __) => Icon(
                            _getCategoryIcon(machine['category']),
                            size: 26,
                            color: categoryColor),
                        errorWidget: (_, __, ___) => Icon(
                            _getCategoryIcon(machine['category']),
                            size: 26,
                            color: categoryColor),
                      ),
                    )
                  : Icon(_getCategoryIcon(machine['category']),
                      size: 26, color: categoryColor),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    machine['machine_name'] ?? 'Unknown',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? (isDark
                              ? Brand.darkIconActive
                              : Brand.royalBlueDark)
                          : (isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withAlpha(((isDark ? 0.15 : 0.1) * 255).toInt()),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          machine['brand'] ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          machine['model_number'] ?? '',
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
                  if (machine['sub_category'] != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      machine['sub_category'],
                      style: TextStyle(
                        fontSize: 11,
                        color: (isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight)
                            .withAlpha(((0.7) * 255).toInt()),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Check
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: isSelected ? accent : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? accent
                      : (isDark ? Brand.darkBorder : Brand.borderLight),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Icon(Icons.check_rounded,
                      size: 16,
                      color: isDark ? const Color(0xFF1A1F36) : Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySearchState(bool isDark) {
    final accent = isDark ? Brand.darkIconActive : Brand.royalBlue;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded,
              size: 52,
              color: (isDark ? Brand.darkTextSecondary : Brand.subtleLight)
                  .withAlpha(((0.3) * 255).toInt())),
          const SizedBox(height: 14),
          Text(
            'No machines found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different search or category',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () {
              _searchController.clear();
              _searchQuery = '';
              _selectedCategory = 'All';
              _applyFilters();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: accent.withAlpha(((0.1) * 255).toInt()),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Clear Filters',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── STEP 2: DETAILS ───────────────────────────────────────

  Widget _buildStep2(bool isDark) {
    final imageUrl = _selectedMachineData != null
        ? _getMachineImageUrl(_selectedMachineData!)
        : null;

    return SingleChildScrollView(
      key: const ValueKey('step2'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSelectedMachineHeader(imageUrl, isDark),
          const SizedBox(height: 20),
          _buildSectionLabel('Machine Nickname', Icons.label_rounded, isDark,
              isOptional: true),
          const SizedBox(height: 8),
          _buildInputField(
            controller: _nicknameController,
            hint: 'E.g., "Main Printer", "Workshop CNC"',
            icon: Icons.edit_rounded,
            isDark: isDark,
          ),
          const SizedBox(height: 18),
          _buildSectionLabel('Serial Number', Icons.qr_code_2_rounded, isDark),
          const SizedBox(height: 8),
          _buildSerialNumberField(isDark),
          const SizedBox(height: 18),
          _buildSectionLabel(
              'Installation Address', Icons.location_on_rounded, isDark),
          const SizedBox(height: 8),
          _buildInputField(
            controller: _installationAddressController,
            hint: 'E.g., Production Floor, Building B, Room 5',
            icon: Icons.place_rounded,
            isDark: isDark,
            validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 18),
          _buildSectionLabel(
              'Purchase Date', Icons.calendar_today_rounded, isDark),
          const SizedBox(height: 8),
          _buildDatePicker(
            date: _purchaseDate,
            placeholder: S.of(context)!.registerSelectPurchaseDate,
            icon: Icons.event_rounded,
            onTap: () => _selectDate(context, isPurchase: true),
            isRequired: true,
            isDark: isDark,
          ),
          const SizedBox(height: 18),
          _buildSectionLabel('Warranty Type', Icons.shield_rounded, isDark),
          const SizedBox(height: 8),
          _buildWarrantyTypeSelector(isDark),
          const SizedBox(height: 14),
          if (_warrantyType != 'none') ...[
            _buildSectionLabel(
                'Warranty End Date', Icons.verified_user_rounded, isDark,
                isOptional: true),
            const SizedBox(height: 8),
            _buildDatePicker(
              date: _warrantyEndDate,
              placeholder: S.of(context)!.registerSelectWarrantyDate,
              icon: Icons.event_available_rounded,
              onTap: () => _selectDate(context, isPurchase: false),
              isDark: isDark,
            ),
            const SizedBox(height: 18),
          ],
          _buildSectionLabel('Connector', Icons.support_agent_rounded, isDark),
          const SizedBox(height: 8),
          _buildConnectorPicker(isDark),
          const SizedBox(height: 18),
          _buildSectionLabel('Notes', Icons.notes_rounded, isDark,
              isOptional: true),
          const SizedBox(height: 8),
          _buildInputField(
            controller: _notesController,
            hint: 'Any additional details about the machine...',
            icon: Icons.edit_note_rounded,
            maxLines: 3,
            isDark: isDark,
          ),
          const SizedBox(height: 18),
          _buildSectionLabel(
              'Installation Photos', Icons.camera_alt_rounded, isDark,
              isOptional: true),
          const SizedBox(height: 8),
          _buildPhotoGrid(isDark),
          const SizedBox(height: 18),
          _buildSectionLabel(
              'Purchase Proof', Icons.receipt_long_rounded, isDark,
              isOptional: true),
          const SizedBox(height: 8),
          _buildPurchaseProofPicker(isDark),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSelectedMachineHeader(String? imageUrl, bool isDark) {
    final accent = isDark ? Brand.darkIconActive : Brand.royalBlue;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withAlpha(((0.2) * 255).toInt())),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(10),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCardElevated : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: imageUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      width: 52,
                      height: 52,
                      placeholder: (_, __) => Icon(
                          _getCategoryIcon(_selectedMachineData?['category']),
                          size: 24,
                          color: accent),
                      errorWidget: (_, __, ___) => Icon(
                          _getCategoryIcon(_selectedMachineData?['category']),
                          size: 24,
                          color: accent),
                    ),
                  )
                : Icon(_getCategoryIcon(_selectedMachineData?['category']),
                    size: 24, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedMachineData?['machine_name'] ?? 'Selected Machine',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_selectedMachineData?['brand'] ?? ''} · ${_selectedMachineData?['model_number'] ?? ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _currentStep = 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color:
                    isDark ? Brand.darkCardElevated : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: isDark ? Border.all(color: Brand.darkBorder) : null,
              ),
              child: Text(
                'Change',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSerialNumberField(bool isDark) {
    final accent = isDark ? Brand.darkIconActive : Brand.royalBlue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _duplicateWarning != null
                  ? Colors.red.withAlpha(((0.5) * 255).toInt())
                  : _serialValidated
                      ? accent.withAlpha(((0.3) * 255).toInt())
                      : (isDark ? Brand.darkBorder : Brand.borderLight),
              width: 1.5,
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Brand.royalBlue.withAlpha(8),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: TextFormField(
            controller: _serialNumberController,
            validator: (v) => v == null || v.trim().isEmpty
                ? 'Serial number is required'
                : null,
            onChanged: (_) {
              setState(() {
                _duplicateWarning = null;
                _serialValidated = false;
              });
            },
            onFieldSubmitted: (_) => _checkDuplicate(),
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
            textCapitalization: TextCapitalization.characters,
            cursorColor: accent,
            decoration: InputDecoration(
              hintText: S.of(context)!.machineSerialHint,
              hintStyle: TextStyle(
                color: (isDark ? Brand.darkTextSecondary : Brand.subtleLight)
                    .withAlpha(((0.6) * 255).toInt()),
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
              prefixIcon: Icon(Icons.tag_rounded,
                  color: isDark ? Brand.darkIconActive : Brand.royalBlueDark,
                  size: 20),
              suffixIcon: _isCheckingDuplicate
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: accent),
                      ),
                    )
                  : _serialValidated
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: Icon(Icons.check_circle_rounded,
                              color: Brand.lightGreen, size: 20),
                        )
                      : _serialNumberController.text.isNotEmpty
                          ? GestureDetector(
                              onTap: _checkDuplicate,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Icon(
                                  Icons.verified_rounded,
                                  color: isDark
                                      ? Brand.darkTextSecondary
                                      : Brand.subtleLight,
                                  size: 20,
                                ),
                              ),
                            )
                          : null,
              enabledBorder: InputBorder.none,
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                      width: 1.5)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        if (_duplicateWarning != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(((0.06) * 255).toInt()),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withAlpha(((0.2) * 255).toInt())),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_rounded,
                    color: Colors.red.shade400, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _duplicateWarning!,
                    style: TextStyle(fontSize: 12, color: Colors.red.shade600),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (!_serialValidated &&
            _serialNumberController.text.isNotEmpty &&
            _duplicateWarning == null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Tap ✓ to verify serial number',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWarrantyTypeSelector(bool isDark) {
    return Row(
      children: _warrantyTypes.map((wt) {
        final isSelected = _warrantyType == wt['value'];
        final color = wt['color'] as Color;

        return Expanded(
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _warrantyType = wt['value'] as String;
                if (_warrantyType == 'none') {
                  _warrantyEndDate = null;
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: EdgeInsets.only(right: wt != _warrantyTypes.last ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withAlpha(((0.1) * 255).toInt())
                    : (Brand.surface(isDark)),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? color
                      : (isDark ? Brand.darkBorder : Brand.borderLight),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(wt['icon'] as IconData,
                      color: isSelected
                          ? color
                          : (isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight),
                      size: 22),
                  const SizedBox(height: 6),
                  Text(
                    (wt['label'] as String).split(' ').first,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected
                          ? color
                          : (isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── CONNECTOR PICKER ──────────────────────────────────────
  // Tap to open a bottom sheet listing every marketer + admin. The choice
  // is stored on users.connector_id at submit time (see _registerMachine).
  Widget _buildConnectorPicker(bool isDark) {
    final accent = isDark ? Brand.darkIconActive : Brand.royalBlue;
    final selected = _connectorData;
    final hasSelection = _connectorId != null && selected != null;

    return GestureDetector(
      onTap: _openConnectorSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasSelection
                ? accent.withAlpha(115)
                : (isDark ? Brand.darkBorder : Brand.borderLight),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withAlpha(31),
                borderRadius: BorderRadius.circular(11),
              ),
              child: hasSelection &&
                      (selected['profile_photo'] as String?)?.isNotEmpty == true
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: CachedNetworkImage(
                        imageUrl: selected['profile_photo'] as String,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Icon(
                            Icons.support_agent_rounded,
                            size: 20,
                            color: accent),
                        errorWidget: (_, __, ___) => Icon(
                            Icons.support_agent_rounded,
                            size: 20,
                            color: accent),
                      ),
                    )
                  : Icon(Icons.support_agent_rounded,
                      size: 20, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasSelection
                        ? (selected['full_name'] as String? ?? 'Connector')
                        : S.of(context)!.registerChooseConnector,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: hasSelection
                          ? (isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark)
                          : (isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasSelection
                        ? _formatConnectorRole(
                            selected['role'] as String? ?? '')
                        : S.of(context)!.registerConnectorDesc,
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight),
          ],
        ),
      ),
    );
  }

  String _formatConnectorRole(String role) {
    switch (role) {
      case 'marketing_admin':
        return 'Marketer';
      case 'admin':
      case 'super_admin':
        return 'Admin';
      default:
        return role.isEmpty ? '' : role[0].toUpperCase() + role.substring(1);
    }
  }

  void _openConnectorSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollCtrl) => Container(
            decoration: BoxDecoration(
              color: Brand.surface(isDark),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Brand.darkBorder
                        : Colors.grey.withAlpha(77),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(24, 4, 24, 12),
                  child: Row(
                    children: [
                      Icon(Icons.support_agent_rounded,
                          color: isDark
                              ? Brand.darkIconActive
                              : Brand.royalBlue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Choose Your Connector',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Brand.darkTextPrimary
                                  : Brand.royalBlueDark),
                        ),
                      ),
                      if (_connectorId != null)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _connectorId = null;
                              _connectorData = null;
                            });
                            Navigator.pop(sheetCtx);
                          },
                          child: Text(S.of(context)!.commonClear),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Your connector is the person who will reach out about your machine and answer questions.',
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _loadingConnectors
                      ? const Center(
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : _availableConnectors.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  'No marketers or admins are available yet.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: isDark
                                          ? Brand.darkTextSecondary
                                          : Brand.subtleLight),
                                ),
                              ),
                            )
                          : ListView.separated(
                              controller: scrollCtrl,
                              padding: const EdgeInsets.fromLTRB(
                                  16, 8, 16, 24),
                              itemCount: _availableConnectors.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final c = _availableConnectors[i];
                                final selected = c['id'] == _connectorId;
                                final photo =
                                    c['profile_photo'] as String?;
                                return InkWell(
                                  borderRadius:
                                      BorderRadius.circular(14),
                                  onTap: () {
                                    setState(() {
                                      _connectorId = c['id'] as String;
                                      _connectorData =
                                          Map<String, dynamic>.from(c);
                                    });
                                    Navigator.pop(sheetCtx);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? (isDark
                                                  ? Brand.darkIconActive
                                                  : Brand.royalBlue)
                                              .withAlpha(31)
                                          : (isDark
                                              ? Brand.darkCardElevated
                                              : Brand.scaffoldLight),
                                      borderRadius:
                                          BorderRadius.circular(14),
                                      border: Border.all(
                                        color: selected
                                            ? (isDark
                                                ? Brand.darkIconActive
                                                : Brand.royalBlue)
                                            : (isDark
                                                ? Brand.darkBorder
                                                : Brand.borderLight),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: (isDark
                                                    ? Brand.darkIconActive
                                                    : Brand.royalBlue)
                                                .withAlpha(31),
                                            borderRadius:
                                                BorderRadius.circular(11),
                                          ),
                                          child: photo != null &&
                                                  photo.isNotEmpty
                                              ? ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          11),
                                                  child:
                                                      CachedNetworkImage(
                                                    imageUrl: photo,
                                                    fit: BoxFit.cover,
                                                    placeholder: (_, __) =>
                                                        Icon(
                                                      Icons.person_rounded,
                                                      color: isDark
                                                          ? Brand
                                                              .darkIconActive
                                                          : Brand
                                                              .royalBlue,
                                                    ),
                                                    errorWidget:
                                                        (_, __, ___) => Icon(
                                                      Icons.person_rounded,
                                                      color: isDark
                                                          ? Brand
                                                              .darkIconActive
                                                          : Brand
                                                              .royalBlue,
                                                    ),
                                                  ),
                                                )
                                              : Icon(
                                                  Icons.person_rounded,
                                                  color: isDark
                                                      ? Brand.darkIconActive
                                                      : Brand.royalBlue,
                                                ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                (c['full_name'] as String?) ??
                                                    'Connector',
                                                style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.w700,
                                                  fontSize: 14,
                                                  color: isDark
                                                      ? Brand
                                                          .darkTextPrimary
                                                      : Brand
                                                          .royalBlueDark,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _formatConnectorRole(
                                                    (c['role'] as String?) ??
                                                        ''),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isDark
                                                      ? Brand
                                                          .darkTextSecondary
                                                      : Brand.subtleLight,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (selected)
                                          Icon(Icons.check_circle_rounded,
                                              color: isDark
                                                  ? Brand.darkIconActive
                                                  : Brand.royalBlue),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPhotoGrid(bool isDark) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ..._installationPhotos.asMap().entries.map((entry) {
          return Stack(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: isDark ? Border.all(color: Brand.darkBorder) : null,
                  image: DecorationImage(
                      image: FileImage(entry.value), fit: BoxFit.cover),
                ),
              ),
              Positioned(
                top: -4,
                right: -4,
                child: GestureDetector(
                  onTap: () =>
                      setState(() => _installationPhotos.removeAt(entry.key)),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Brand.surface(isDark),
                          width: 2),
                    ),
                    child: const Icon(Icons.close_rounded,
                        size: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        }),
        if (_installationPhotos.length < 4)
          GestureDetector(
            onTap: _pickInstallationPhoto,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color:
                    isDark ? Brand.darkCardElevated : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: isDark ? Border.all(color: Brand.darkBorder) : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_rounded,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      size: 22),
                  const SizedBox(height: 4),
                  Text(
                    '${_installationPhotos.length}/4',
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPurchaseProofPicker(bool isDark) {
    final accent = isDark ? Brand.darkIconActive : Brand.royalBlue;

    if (_purchaseProof != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withAlpha(((0.3) * 255).toInt())),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                image: DecorationImage(
                    image: FileImage(_purchaseProof!), fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Purchase proof attached',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    ),
                  ),
                  Text(
                    'Invoice or receipt photo',
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _purchaseProof = null),
              child: Icon(Icons.close_rounded,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  size: 22),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _pickPurchaseProof,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCardElevated : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
           border: isDark
           ? Border.all(color: Brand.darkBorder) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.upload_file_rounded,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                size: 22),
            const SizedBox(width: 10),
            Text(
              'Upload invoice or receipt',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── STEP 3: REVIEW ────────────────────────────────────────

  Widget _buildStep3(bool isDark) {
    final accent = isDark ? Brand.darkIconActive : Brand.royalBlue;

    return SingleChildScrollView(
      key: const ValueKey('step3'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: accent.withAlpha(((0.06) * 255).toInt()),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withAlpha(((0.15) * 255).toInt())),
            ),
            child: Row(
              children: [
                Icon(Icons.fact_check_rounded, color: accent, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Review Registration',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark,
                        ),
                      ),
                      Text(
                        'Please verify all details before submitting',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildReviewSection(
            'Machine',
            Icons.precision_manufacturing_rounded,
            [
              _buildReviewItem('Name',
                  _selectedMachineData?['machine_name'] ?? 'N/A', isDark),
              _buildReviewItem(
                  'Brand', _selectedMachineData?['brand'] ?? 'N/A', isDark),
              _buildReviewItem('Model',
                  _selectedMachineData?['model_number'] ?? 'N/A', isDark),
              _buildReviewItem('Category',
                  _selectedMachineData?['category'] ?? 'N/A', isDark),
            ],
            isDark,
          ),
          const SizedBox(height: 12),
          _buildReviewSection(
            'Details',
            Icons.assignment_rounded,
            [
              if (_nicknameController.text.isNotEmpty)
                _buildReviewItem('Nickname', _nicknameController.text, isDark),
              _buildReviewItem(
                  'Serial Number', _serialNumberController.text, isDark),
              _buildReviewItem(
                'Installation',
                _installationAddressController.text.isEmpty
                    ? 'Not specified'
                    : _installationAddressController.text,
                isDark,
              ),
              _buildReviewItem(
                  'Purchase Date', _formatDate(_purchaseDate), isDark),
              _buildReviewItem(
                'Warranty',
                _warrantyType == 'none'
                    ? 'No warranty'
                    : '${_warrantyType.substring(0, 1).toUpperCase()}${_warrantyType.substring(1)} - ${_formatDate(_warrantyEndDate)}',
                isDark,
              ),
              if (_connectorData != null)
                _buildReviewItem(
                  'Connector',
                  '${_connectorData!['full_name'] ?? '—'} (${_formatConnectorRole((_connectorData!['role'] as String?) ?? '')})',
                  isDark,
                ),
              if (_notesController.text.isNotEmpty)
                _buildReviewItem('Notes', _notesController.text, isDark),
            ],
            isDark,
          ),
          const SizedBox(height: 12),
          if (_installationPhotos.isNotEmpty || _purchaseProof != null)
            _buildReviewSection(
              'Attachments',
              Icons.attach_file_rounded,
              [
                if (_installationPhotos.isNotEmpty)
                  _buildReviewItem(
                    'Photos',
                    '${_installationPhotos.length} installation photo(s)',
                    isDark,
                  ),
                if (_purchaseProof != null)
                  _buildReviewItem(
                      'Purchase Proof', 'Invoice/receipt attached', isDark),
              ],
              isDark,
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? Brand.darkIconActive.withAlpha(((0.08) * 255).toInt())
                  : Brand.royalBlueDark.withAlpha(((0.04) * 255).toInt()),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? Brand.darkIconActive.withAlpha(((0.15) * 255).toInt())
                    : Brand.royalBlueDark.withAlpha(((0.1) * 255).toInt()),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: isDark ? Brand.darkIconActive : Brand.royalBlueDark,
                    size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'After registration, you\'ll be able to create support tickets, track warranty, and get service reminders for this machine.',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewSection(
      String title, IconData icon, List<Widget> items, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(16),
         border: isDark
         ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(10),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Brand.darkCardElevated
                        : Brand.royalBlueSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon,
                      color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                      size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                ),
              ],
            ),
          ),
          Divider(
              color: isDark ? Brand.darkBorder : Brand.borderLight, height: 1),
          ...items,
        ],
      ),
    );
  }

  Widget _buildReviewItem(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
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
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── SHARED WIDGETS ────────────────────────────────────────

  Widget _buildSectionLabel(String label, IconData icon, bool isDark,
      {bool isOptional = false}) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isDark
                ? Brand.darkIconActive.withAlpha(((0.12) * 255).toInt())
                : Brand.royalBlueDark.withAlpha(((0.08) * 255).toInt()),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon,
              color: isDark ? Brand.darkIconActive : Brand.royalBlueDark,
              size: 15),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
          ),
        ),
        if (!isOptional)
          const Text(' *',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFFE53935),
              )),
        if (isOptional)
          Text(
            ' (Optional)',
            style: TextStyle(
              fontSize: 11,
              color: (isDark ? Brand.darkTextSecondary : Brand.subtleLight)
                  .withAlpha(((0.7) * 255).toInt()),
            ),
          ),
      ],
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool isDark,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(14),
        border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(8),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        validator: validator,
        style: TextStyle(
          fontSize: 14,
          color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
        ),
        cursorColor: isDark ? Brand.darkIconActive : Brand.royalBlue,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: (isDark ? Brand.darkTextSecondary : Brand.subtleLight)
                .withAlpha(((0.6) * 255).toInt()),
            fontSize: 13,
          ),
          prefixIcon: Padding(
            padding: EdgeInsets.only(top: maxLines > 1 ? 14 : 0),
            child: Icon(icon,
                color: isDark ? Brand.darkIconActive : Brand.royalBlueDark,
                size: 20),
          ),
          enabledBorder: InputBorder.none,
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                  color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                  width: 1.5)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.red.shade400)),
          focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  BorderSide(color: Colors.red.shade400, width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildDatePicker({
    required DateTime? date,
    required String placeholder,
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
    bool isRequired = false,
  }) {
    final accent = isDark ? Brand.darkIconActive : Brand.royalBlue;
    final hasDate = date != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasDate
                ? accent.withAlpha(((0.3) * 255).toInt())
                : (isDark ? Brand.darkBorder : Brand.borderLight),
            width: 1.5,
          ),
          boxShadow: isDark ? null : [
            BoxShadow(
              color: Brand.royalBlue.withAlpha(8),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: hasDate
                    ? accent.withAlpha(((isDark ? 0.15 : 0.1) * 255).toInt())
                    : (isDark
                        ? Brand.darkCardElevated
                        : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: hasDate
                      ? accent
                      : (isDark ? Brand.darkTextSecondary : Brand.subtleLight),
                  size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasDate ? _formatDate(date) : placeholder,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: hasDate ? FontWeight.w600 : FontWeight.normal,
                  color: hasDate
                      ? (isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)
                      : (isDark ? Brand.darkTextSecondary : Brand.subtleLight)
                          .withAlpha(((0.6) * 255).toInt()),
                ),
              ),
            ),
            if (hasDate)
              GestureDetector(
                onTap: () => setState(() {
                  if (isRequired) {
                    _purchaseDate = null;
                  } else {
                    _warrantyEndDate = null;
                  }
                }),
                child: Icon(Icons.close_rounded,
                    size: 18,
                    color:
                        isDark ? Brand.darkTextSecondary : Brand.subtleLight),
              )
            else
              Icon(Icons.calendar_month_rounded,
                  size: 18,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight),
          ],
        ),
      ),
    );
  }

  // ─── BOTTOM ACTIONS ────────────────────────────────────────

  Widget _buildBottomActions(bool isDark) {


    String buttonLabel;
    bool canProceed;
    VoidCallback? onTap;

    switch (_currentStep) {
      case 0:
        buttonLabel = _selectedMachineId != null
            ? 'Continue with ${_selectedMachineData?['machine_name']?.toString().split(' ').take(3).join(' ') ?? 'Machine'}'
            : S.of(context)!.registerSelectMachine;
        canProceed = _canProceedStep1;
        onTap = canProceed ? () => setState(() => _currentStep = 1) : null;
        break;
      case 1:
        buttonLabel = 'Review Registration';
        canProceed = _canProceedStep2;
        onTap = canProceed ? () => setState(() => _currentStep = 2) : null;
        break;
      case 2:
        buttonLabel = 'Register Machine';
        canProceed = true;
        onTap = _isLoading ? null : _registerMachine;
        break;
      default:
        buttonLabel = 'Next';
        canProceed = false;
        onTap = null;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        border: Border(
          top: BorderSide(
            color: isDark ? Brand.darkBorder : Brand.borderLight,
            width: 1,
          ),
        ),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(15),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_currentStep > 0) ...[
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _currentStep--);
                },
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    border: isDark
                        ? Border.all(color: Brand.darkBorder)
                        : null,
                    borderRadius: BorderRadius.circular(14),
                    color: Brand.surface(isDark),
                  ),
                  child: Icon(Icons.arrow_back_rounded,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                      size: 22),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (onTap != null) {
                    HapticFeedback.mediumImpact();
                    onTap();
                  } else if (!canProceed) {
                    if (_currentStep == 0) {
                      _showSnackBar('Please select a machine', isError: true);
                    }
                    if (_currentStep == 1) {
                      _showSnackBar('Please fill required fields',
                          isError: true);
                    }
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: canProceed
                        ? LinearGradient(
                            colors: _currentStep == 2
                                ? [
                                    isDark
                                        ? Brand.lightGreenBright
                                        : Brand.lightGreen,
                                    (isDark
                                            ? Brand.lightGreenBright
                                            : Brand.lightGreen)
                                        .withAlpha(((0.85) * 255).toInt()),
                                  ]
                                : isDark
                                    ? [
                                        Brand.darkIconActive,
                                        Brand.darkIconActive.withAlpha(((0.8) * 255).toInt()),
                                      ]
                                    : [
                                        Brand.royalBlueDark,
                                        Brand.royalBlue,
                                      ],
                          )
                        : null,
                    color: canProceed
                        ? null
                        : (isDark ? Brand.darkTextSecondary : Brand.subtleLight)
                            .withAlpha(((0.2) * 255).toInt()),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: canProceed
                        ? [
                            BoxShadow(
                              color: (_currentStep == 2
                                      ? (isDark
                                          ? Brand.lightGreenBright
                                          : Brand.lightGreen)
                                      : (isDark
                                          ? Brand.darkIconActive
                                          : Brand.royalBlueDark))
                                  .withAlpha(((0.3) * 255).toInt()),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [],
                  ),
                  child: _isLoading
                      ? Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: isDark
                                  ? const Color(0xFF1A1F36)
                                  : Colors.white,
                              strokeWidth: 2.5,
                            ),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_currentStep == 2) ...[
                              Icon(
                                Icons.check_circle_rounded,
                                color: canProceed
                                    ? (isDark
                                        ? const Color(0xFF1A1F36)
                                        : Colors.white)
                                    : (isDark
                                        ? Brand.darkTextSecondary
                                        : Brand.subtleLight),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Text(
                                buttonLabel,
                                style: TextStyle(
                                  color: canProceed
                                      ? (isDark
                                          ? const Color(0xFF1A1F36)
                                          : Colors.white)
                                      : (isDark
                                          ? Brand.darkTextSecondary
                                          : Brand.subtleLight),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_currentStep < 2) ...[
                              const SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward_rounded,
                                color: canProceed
                                    ? (isDark
                                        ? const Color(0xFF1A1F36)
                                        : Colors.white)
                                    : (isDark
                                        ? Brand.darkTextSecondary
                                        : Brand.subtleLight),
                                size: 20,
                              ),
                            ],
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── LOADING STATE ─────────────────────────────────────────

  Widget _buildLoadingState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                  strokeWidth: 3,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading machine catalog...',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            ),
          ),
        ],
      ),
    );
  }
}
