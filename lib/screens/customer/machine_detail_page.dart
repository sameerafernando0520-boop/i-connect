// ============================================================
// FILE: lib/screens/customer/machine_detail_page.dart
// FIXED v18 — Removed AppTheme, _B class; uses Brand + Theme.of
// ============================================================

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../l10n/s.dart';
import '../../utils/machine_image_helper.dart';
import 'ticket_detail_page.dart';
import 'my_machines_page.dart';

// ── Colors not in Brand (machine detail specific) ────────────
const _dNavy = Color(0xFF0D1B3E);
const _dNavySurf = Color(0xFF132044);

// ── Custom Icons ─────────────────────────────────────────────
class _LaserIcon extends StatelessWidget {
  final Color color;
  final double size;
  const _LaserIcon({this.color = Brand.royalBlue, this.size = 20});
  @override
  Widget build(BuildContext context) => SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LaserP(color: color)));
}

class _LaserP extends CustomPainter {
  final Color color;
  const _LaserP({required this.color});
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final w = s.width, h = s.height;
    c.drawPath(
        Path()
          ..moveTo(w * .05, h * .08)
          ..lineTo(w * .95, h * .08)
          ..lineTo(w * .85, h * .22)
          ..lineTo(w * .15, h * .22)
          ..close(),
        p);
    c.drawPath(
        Path()
          ..moveTo(w * .30, h * .25)
          ..lineTo(w * .70, h * .25)
          ..lineTo(w * .62, h * .36)
          ..lineTo(w * .38, h * .36)
          ..close(),
        p);
    c.drawRect(Rect.fromLTWH(w * .40, h * .37, w * .20, h * .13), p);
    c.drawRect(Rect.fromLTWH(w * .465, h * .50, w * .07, h * .20), p);
    c.drawRect(Rect.fromLTWH(w * .05, h * .76, w * .38, h * .16), p);
    c.drawRect(Rect.fromLTWH(w * .57, h * .76, w * .38, h * .16), p);
  }

  @override
  bool shouldRepaint(_LaserP o) => o.color != color;
}

class _CncIcon extends StatelessWidget {
  final Color color;
  final double size;
  const _CncIcon({this.color = Brand.royalBlue, this.size = 20});
  @override
  Widget build(BuildContext context) => SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CncP(color: color)));
}

class _CncP extends CustomPainter {
  final Color color;
  const _CncP({required this.color});
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final w = s.width, h = s.height;
    final cx = w * .38, cy = h * .54, oR = w * .30, iR = w * .19, hR = w * .07;
    const t = 8;
    final gP = Path();
    for (int i = 0; i < t; i++) {
      final a1 = (2 * math.pi / t) * i - math.pi / 2;
      final a2 = a1 + (2 * math.pi / t) * .4;
      final a3 = a2 + (2 * math.pi / t) * .2;
      final a4 = a1 + (2 * math.pi / t);
      if (i == 0) {
        gP.moveTo(cx + oR * math.cos(a1), cy + oR * math.sin(a1));
      } else {
        gP.lineTo(cx + oR * math.cos(a1), cy + oR * math.sin(a1));
      }
      gP
        ..lineTo(cx + oR * math.cos(a2), cy + oR * math.sin(a2))
        ..lineTo(cx + iR * math.cos(a3), cy + iR * math.sin(a3))
        ..lineTo(cx + iR * math.cos(a4), cy + iR * math.sin(a4));
    }
    gP.close();
    c.drawPath(
        Path.combine(
            PathOperation.difference,
            gP,
            Path()
              ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: hR))),
        p);
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * .62, h * .06, w * .32, h * .20),
            const Radius.circular(3)),
        p);
    c.drawPath(
        Path()
          ..moveTo(w * .62, h * .28)
          ..lineTo(w * .94, h * .28)
          ..lineTo(w * .89, h * .46)
          ..lineTo(w * .67, h * .46)
          ..close(),
        p);
    c.drawPath(
        Path()
          ..moveTo(w * .69, h * .47)
          ..lineTo(w * .87, h * .47)
          ..lineTo(w * .78, h * .64)
          ..close(),
        p);
  }

  @override
  bool shouldRepaint(_CncP o) => o.color != color;
}

// ══════════════════════════════════════════════════════════════
class MachineDetailPage extends StatefulWidget {
  final Map<String, dynamic> machine;
  const MachineDetailPage({super.key, required this.machine});
  @override
  State<MachineDetailPage> createState() => _MachineDetailPageState();
}

class _MachineDetailPageState extends State<MachineDetailPage> {
  bool _isInquiryLoading = false;
  bool _isOrderLoading = false;
  int _currentImageIndex = 0;
  bool _specsExpanded = true;
  bool _featuresExpanded = true;
  bool _applicationsExpanded = false;

  bool _isSaved = false;
  bool _isOwned = false;
  int _existingInquiryCount = 0;
  List<Map<String, dynamic>> _relatedMachines = [];

  final PageController _imagePageController = PageController();

  // ── Application image slideshow ──
  late final PageController _appImgController;
  Timer? _appImgTimer;
  int _currentAppImg = 0;
  List<Map<String, dynamic>> _appsWithImages = []; // [{name, image_url}]

  @override
  void initState() {
    super.initState();
    _appImgController = PageController();
    _initAppImages();
    _loadUserSpecificData();
    _loadRelatedMachines();
    _trackView();
  }

  void _initAppImages() {
    final raw = (widget.machine['application_images'] as List?) ?? [];
    final imageMap = <String, String>{};
    for (final img in raw) {
      if (img is Map) {
        final name = img['name']?.toString() ?? '';
        final url = img['image_url']?.toString() ?? '';
        if (name.isNotEmpty && url.isNotEmpty) imageMap[name] = url;
      }
    }
    final apps = (widget.machine['applications'] as List?) ?? [];
    _appsWithImages = apps
        .where((a) => imageMap.containsKey(a.toString()))
        .map<Map<String, dynamic>>(
            (a) => {'name': a.toString(), 'image_url': imageMap[a.toString()]!})
        .toList();

    if (_appsWithImages.length > 1) {
      _appImgTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted) return;
        final next = (_currentAppImg + 1) % _appsWithImages.length;
        setState(() => _currentAppImg = next);
        if (_appImgController.hasClients) {
          _appImgController.animateToPage(
            next,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _appImgTimer?.cancel();
    _appImgController.dispose();
    _imagePageController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  //  DATA
  // ═══════════════════════════════════════════════════════════

  Future<void> _loadUserSpecificData() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;
    final machineId = widget.machine['id'];
    try {
      final results = await Future.wait<dynamic>([
        SupabaseConfig.client
            .from('saved_machines')
            .select('id')
            .eq('user_id', userId)
            .eq('catalog_machine_id', machineId)
            .maybeSingle(),
        SupabaseConfig.client
            .from('customer_machines')
            .select('id')
            .eq('user_id', userId)
            .eq('catalog_machine_id', machineId)
            .limit(1),
        SupabaseConfig.client
            .from('service_tickets')
            .select('id')
            .eq('user_id', userId)
            .eq('catalog_machine_id', machineId)
            .eq('is_deleted', false)
            // Closed-state set per spec: resolved/closed/completed/cancelled.
            .inFilter('ticket_type', ['inquiry', 'order']).not(
                'status', 'in', '("resolved","closed","completed","cancelled")'),
      ]);
      if (!mounted) return;
      setState(() {
        _isSaved = results[0] != null;
        _isOwned = (results[1] as List).isNotEmpty;
        _existingInquiryCount = (results[2] as List).length;
      });
    } catch (_) {}
  }

  Future<void> _loadRelatedMachines() async {
    try {
      final machineId = widget.machine['id'];
      List<Map<String, dynamic>> rows;
      try {
        final r = await SupabaseConfig.client.rpc('get_related_machines',
            params: {'p_machine_id': machineId, 'p_limit': 4});
        rows = List<Map<String, dynamic>>.from(r);
      } catch (_) {
        final category = widget.machine['category'];
        final r = await SupabaseConfig.client
            .from('machine_catalog')
            .select(
                'id, machine_name, model_number, brand, category, sub_category, image_url, product_images, images')
            .eq('is_active', true)
            .eq('category', category)
            .neq('id', machineId)
            .limit(4);
        rows = List<Map<String, dynamic>>.from(r);
      }
      // Normalize: each row exposes `product_image` for the card to render.
      // The RPC now applies the canonical fallback chain
      // (image_url → product_images[1] → images[1]); for the table-fallback
      // path below, MachineImageHelper recomputes it client-side. Prefer the
      // RPC's value when present, then fall through to the helper to catch
      // edge cases (e.g. legacy rows where only `images` is populated).
      _relatedMachines = rows.map((m) {
        final fromRpc = (m['product_image'] as String?)?.trim();
        final resolved = (fromRpc != null && fromRpc.isNotEmpty)
            ? fromRpc
            : MachineImageHelper.primaryImage(m);
        return {...m, 'product_image': resolved};
      }).toList();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _trackView() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await SupabaseConfig.client.from('recently_viewed_machines').upsert({
        'user_id': userId,
        'catalog_machine_id': widget.machine['id'],
        'viewed_at': DateTime.now().toIso8601String()
      }, onConflict: 'user_id,catalog_machine_id');
    } catch (_) {}
  }

  Future<void> _toggleSaved() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;
    final was = _isSaved;
    setState(() => _isSaved = !_isSaved);
    HapticFeedback.lightImpact();
    try {
      if (was) {
        await SupabaseConfig.client
            .from('saved_machines')
            .delete()
            .eq('user_id', userId)
            .eq('catalog_machine_id', widget.machine['id']);
      } else {
        await SupabaseConfig.client.from('saved_machines').insert(
            {'user_id': userId, 'catalog_machine_id': widget.machine['id']});
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(was ? 'Removed from saved' : 'Saved to wishlist'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    } catch (_) {
      if (mounted) setState(() => _isSaved = was);
    }
  }

  Future<bool?> _confirmInquiryDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final machineName =
        widget.machine['machine_name']?.toString() ?? 'this machine';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? Brand.darkCard : Brand.cardLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Brand.royalBlue.withAlpha(26),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.help_outline_rounded,
                  color: Brand.royalBlue, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Send Inquiry?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Text(
          'A new inquiry will be created for $machineName. Our team '
          'will get back to you with details and pricing.',
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Brand.royalBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text(
              'Send Inquiry',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createInquiry() async {
    final confirmed = await _confirmInquiryDialog();
    if (confirmed != true) return;
    setState(() => _isInquiryLoading = true);
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');
      String ticketId, ticketNumber;
      try {
        final r =
            await SupabaseConfig.client.rpc('create_catalog_ticket', params: {
          'p_user_id': userId,
          'p_catalog_machine_id': widget.machine['id'],
          'p_ticket_type': 'inquiry'
        });
        final rm = r as Map<String, dynamic>;
        if (rm['success'] != true) throw Exception(rm['error'] ?? 'Failed');
        ticketId = rm['ticket_id'];
        ticketNumber = rm['ticket_number'];
      } catch (_) {
        final fb = await _createTicketFallback(userId, 'inquiry');
        ticketId = fb['id'];
        ticketNumber = fb['ticket_number'];
      }
      if (!mounted) return;
      setState(() {
        _isInquiryLoading = false;
        _existingInquiryCount++;
      });
      _showTicketSuccessDialog(
          type: 'Inquiry', ticketNumber: ticketNumber, ticketId: ticketId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isInquiryLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _showOrderForm() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final qc = TextEditingController(text: '1');
    final ac = TextEditingController();
    final rc = TextEditingController();
    final result = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) => Container(
            decoration: BoxDecoration(
                color: isDark ? Brand.darkCard : Brand.cardLight,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28))),
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                          child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white12
                                      : Brand.subtleLight.withAlpha(77),
                                  borderRadius: BorderRadius.circular(2)))),
                      const SizedBox(height: 24),
                      Row(children: [
                        Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                                color: Brand.lightGreen
                                    .withAlpha(isDark ? 31 : 20),
                                borderRadius: BorderRadius.circular(14)),
                            child: const Icon(Icons.shopping_cart_rounded,
                                color: Brand.lightGreen, size: 22)),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(S.of(context)!.catalogPlaceOrder,
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Colors.white
                                          : Brand.royalBlueDark)),
                              Text(widget.machine['machine_name'] ?? '',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Brand.darkTextSecondary
                                          : Brand.subtleLight),
                                  overflow: TextOverflow.ellipsis),
                            ])),
                      ]),
                      const SizedBox(height: 24),
                      _formLabel('Quantity', isDark),
                      const SizedBox(height: 8),
                      _formField(qc, 'Enter quantity', isDark,
                          keyboardType: TextInputType.number),
                      const SizedBox(height: 16),
                      _formLabel('Delivery Address', isDark),
                      const SizedBox(height: 8),
                      _formField(ac, 'Enter delivery address', isDark,
                          maxLines: 2),
                      const SizedBox(height: 16),
                      _formLabel('Additional Requirements', isDark),
                      const SizedBox(height: 8),
                      _formField(
                          rc, 'Any special requirements? (optional)', isDark,
                          maxLines: 3),
                      const SizedBox(height: 24),
                      Material(
                          color: Colors.transparent,
                          child: InkWell(
                              onTap: () => Navigator.pop(sheetCtx, {
                                    'quantity': int.tryParse(qc.text) ?? 1,
                                    'address': ac.text.trim(),
                                    'requirements': rc.text.trim()
                                  }),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                  width: double.infinity,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  decoration: BoxDecoration(
                                      gradient: const LinearGradient(colors: [
                                        Brand.lightGreen,
                                        Brand.lightGreenBright
                                      ]),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                            color:
                                                Brand.lightGreen.withAlpha(89),
                                            blurRadius: 14,
                                            offset: const Offset(0, 5))
                                      ]),
                                  child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.send_rounded,
                                            color: Colors.white, size: 20),
                                        SizedBox(width: 8),
                                        Text(S.of(context)!.machineSubmitOrder,
                                            style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white)),
                                      ])))),
                      const SizedBox(height: 8),
                    ]))));

    if (result == null) return;
    await _submitOrder(result);
  }

  Future<void> _submitOrder(Map<String, dynamic> od) async {
    setState(() => _isOrderLoading = true);
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');
      String ticketId, ticketNumber;
      try {
        final r =
            await SupabaseConfig.client.rpc('create_catalog_ticket', params: {
          'p_user_id': userId,
          'p_catalog_machine_id': widget.machine['id'],
          'p_ticket_type': 'order',
          'p_quantity': od['quantity'] ?? 1,
          'p_delivery_address': od['address'],
          'p_additional_requirements': od['requirements']
        });
        final rm = r as Map<String, dynamic>;
        if (rm['success'] != true) throw Exception(rm['error'] ?? 'Failed');
        ticketId = rm['ticket_id'];
        ticketNumber = rm['ticket_number'];
      } catch (_) {
        final fb = await _createTicketFallback(userId, 'order',
            quantity: od['quantity'],
            address: od['address'],
            requirements: od['requirements']);
        ticketId = fb['id'];
        ticketNumber = fb['ticket_number'];
      }
      if (!mounted) return;
      setState(() {
        _isOrderLoading = false;
        _existingInquiryCount++;
      });
      _showTicketSuccessDialog(
          type: 'Order', ticketNumber: ticketNumber, ticketId: ticketId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isOrderLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));
    }
  }

  Future<Map<String, dynamic>> _createTicketFallback(String userId, String type,
      {int? quantity, String? address, String? requirements}) async {
    final prefix = type == 'order' ? 'ORD' : 'INQ';
    final tn =
        '$prefix-${DateTime.now().toString().substring(2, 10).replaceAll('-', '')}-${(DateTime.now().millisecondsSinceEpoch % 1000).toString().padLeft(3, '0')}';
    final r = await SupabaseConfig.client
        .from('service_tickets')
        .insert({
          'user_id': userId,
          'ticket_number': tn,
          'ticket_type': type,
          'catalog_machine_id': widget.machine['id'],
          'subject':
              '${type == 'order' ? 'Order' : 'Inquiry'}: ${widget.machine['machine_name']}',
          'description':
              'Customer interested in ${widget.machine['machine_name']} (${widget.machine['model_number']})',
          'category': type == 'order' ? 'Purchase Order' : 'Sales Inquiry',
          'priority': type == 'order' ? 'high' : 'medium',
          'status': 'open',
          'sales_stage': 'new',
          'quantity': quantity ?? 1,
          'delivery_address': address,
          'additional_requirements': requirements,
        })
        .select()
        .single();
    try {
      await SupabaseConfig.client.from('chat_messages').insert({
        'ticket_id': r['id'],
        'sender_id': null,
        'sender_type': 'system',
        'message':
            '${type == 'order' ? '🛒 Order' : '📋 Inquiry'} created for: ${widget.machine['machine_name']}\nModel: ${widget.machine['model_number']}${quantity != null && quantity > 1 ? '\nQuantity: $quantity' : ''}'
      });
    } catch (_) {}
    return r;
  }

  void _showTicketSuccessDialog(
      {required String type,
      required String ticketNumber,
      required String ticketId}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => PopScope(
            canPop: false,
            child: Dialog(
                backgroundColor: isDark ? Brand.darkCard : Brand.cardLight,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28)),
                child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.elasticOut,
                          builder: (_, v, c) =>
                              Transform.scale(scale: v, child: c),
                          child: Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [
                                    Brand.lightGreen.withAlpha(38),
                                    Brand.lightGreenBright.withAlpha(26)
                                  ]),
                                  borderRadius: BorderRadius.circular(24)),
                              child: const Icon(Icons.check_circle_rounded,
                                  color: Brand.lightGreen, size: 42))),
                      const SizedBox(height: 22),
                      Text('$type Sent!',
                          style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w600,
                              color:
                                  isDark ? Colors.white : Brand.royalBlueDark)),
                      const SizedBox(height: 10),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                              color:
                                  Brand.royalBlue.withAlpha(isDark ? 31 : 15),
                              borderRadius: BorderRadius.circular(10)),
                          child: Text(ticketNumber,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Brand.royalBlueGlow
                                      : Brand.royalBlue,
                                  letterSpacing: 0.5))),
                      const SizedBox(height: 14),
                      Text(S.of(context)!.machineReviewNote,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight,
                              height: 1.5)),
                      const SizedBox(height: 24),
                      SizedBox(
                          width: double.infinity,
                          child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                  onTap: () {
                                    Navigator.pop(dialogCtx);
                                    Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => TicketDetailPage(
                                                ticketId: ticketId)));
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 15),
                                      decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                              colors: [
                                                Brand.royalBlue,
                                                Brand.royalBlueLight
                                              ]),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          boxShadow: [
                                            BoxShadow(
                                                color: Brand.royalBlue
                                                    .withAlpha(89),
                                                blurRadius: 14,
                                                offset: const Offset(0, 5))
                                          ]),
                                      child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.chat_rounded,
                                                color: Colors.white, size: 18),
                                            SizedBox(width: 8),
                                            Text(S.of(context)!.machineOpenChat,
                                                style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 15,
                                                    color: Colors.white))
                                          ]))))),
                      const SizedBox(height: 10),
                      GestureDetector(
                          onTap: () => Navigator.pop(dialogCtx),
                          child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(S.of(context)!.machineContinueBrowsing,
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: isDark
                                          ? Brand.darkTextSecondary
                                          : Brand.subtleLight,
                                      fontWeight: FontWeight.w600)))),
                    ])))));
  }

  // ═══════════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════════

  List<String> _getImages() {
    final m = widget.machine;
    final pi = m['product_images'];
    if (pi is List && pi.isNotEmpty) {
      return pi.map((e) => e.toString()).toList();
    }
    if (m['images'] is List && (m['images'] as List).isNotEmpty) {
      return (m['images'] as List).map((e) => e.toString()).toList();
    }
    if (m['image_url'] != null && m['image_url'].toString().isNotEmpty) {
      return [m['image_url'].toString()];
    }
    return [];
  }

  String _formatKey(String key) =>
      key.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');

  Widget _catIcon(String? cat, Color color, double size) {
    switch (cat) {
      case 'Laser Cutters':
        return _LaserIcon(color: color, size: size);
      case 'CNC Routers':
        return _CncIcon(color: color, size: size);
      case 'Digital Printers':
        return Icon(Icons.print_rounded, color: color, size: size);
      case 'Finishing Equipment':
        return Icon(Icons.construction_rounded, color: color, size: size);
      default:
        return Icon(Icons.inventory_2_rounded, color: color, size: size);
    }
  }

  Color _catAccent(String? cat) {
    switch (cat) {
      case 'Digital Printers':
        return Brand.royalBlue;
      case 'CNC Routers':
        return const Color(0xFFE65100);
      case 'Laser Cutters':
        return const Color(0xFF6A1B9A);
      case 'Finishing Equipment':
        return Brand.lightGreen;
      default:
        return Brand.royalBlueLight;
    }
  }

  Map<String, Map<String, String>> _getQuickSpecs() {
    final s = widget.machine['specifications'] as Map<String, dynamic>? ?? {};
    switch (widget.machine['category'] as String? ?? '') {
      case 'Digital Printers':
        return {
          'Size': {
            'icon': 'straighten',
            'value':
                s['print_width'] as String? ?? s['print_area'] as String? ?? '-'
          },
          'Speed': {'icon': 'speed', 'value': s['speed'] as String? ?? '-'},
          'Heads': {
            'icon': 'settings',
            'value': s['print_heads'] as String? ?? '-'
          }
        };
      case 'CNC Routers':
        return {
          'Area': {
            'icon': 'straighten',
            'value': s['working_area'] as String? ?? '-'
          },
          'Spindle': {
            'icon': 'settings',
            'value': s['spindle'] as String? ?? '-'
          },
          'Speed': {'icon': 'speed', 'value': s['speed'] as String? ?? '-'}
        };
      case 'Laser Cutters':
        return {
          'Area': {
            'icon': 'straighten',
            'value': s['working_area'] as String? ?? '-'
          },
          'Laser': {
            'icon': 'settings',
            'value': s['laser_type'] as String? ?? '-'
          },
          'Power': {'icon': 'bolt', 'value': s['power'] as String? ?? '-'}
        };
      case 'Finishing Equipment':
        return {
          'Width': {
            'icon': 'straighten',
            'value': s['working_width'] as String? ??
                s['welding_width'] as String? ??
                '-'
          },
          'Speed': {'icon': 'speed', 'value': s['speed'] as String? ?? '-'},
          'Type': {'icon': 'settings', 'value': s['features'] as String? ?? '-'}
        };
      default:
        return {
          'Spec 1': {
            'icon': 'settings',
            'value': s.isNotEmpty ? s.values.first.toString() : '-'
          }
        };
    }
  }

  IconData _specIcon(String n) {
    switch (n) {
      case 'straighten':
        return Icons.straighten_rounded;
      case 'speed':
        return Icons.speed_rounded;
      case 'bolt':
        return Icons.bolt_rounded;
      default:
        return Icons.settings_rounded;
    }
  }

  // ── NEED HELP CHOOSING → call routing ─────────────────────
  // Tries to dial the customer's assigned connector first; if none is
  // assigned (or the connector has no phone on file) we fall back to the
  // company main number from company_info. As a final safety we keep the
  // legacy fixed number so the button is never dead even before
  // company_info is populated.
  Future<void> _callNeedHelp() async {
    String? phone;
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId != null) {
        // Resolve connector_id → connector.phone_number in one round-trip.
        final row = await SupabaseConfig.client
            .from('users')
            .select(
                'connector_id, connector:users!connector_id(phone_number)')
            .eq('id', userId)
            .maybeSingle();
        final c = row?['connector'];
        if (c is Map) {
          final p = (c['phone_number'] as String?)?.trim();
          if (p != null && p.isNotEmpty) phone = p;
        }
      }
    } catch (e) {
      debugPrint('Connector phone lookup failed: $e');
    }

    if (phone == null || phone.isEmpty) {
      // Fallback: company main phone.
      try {
        final ci = await SupabaseConfig.client
            .from('company_info')
            .select('phone')
            .limit(1)
            .maybeSingle();
        final p = (ci?['phone'] as String?)?.trim();
        if (p != null && p.isNotEmpty) phone = p;
      } catch (e) {
        debugPrint('company_info phone lookup failed: $e');
      }
    }

    // Final hard fallback to the legacy number so the button is never dead.
    phone ??= '0777244882';

    await _launchUrl('tel:$phone');
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  void _shareProduct() {
    final m = widget.machine;
    Clipboard.setData(ClipboardData(
        text:
            'Check out ${m['machine_name']} by ${m['brand']}\nModel: ${m['model_number']}\nCategory: ${m['category']}\n\nLearn more at https://www.ifrontiers.lk'));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Product info copied!'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    }
  }

  Widget _formLabel(String t, bool isDark) => Text(t,
      style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : Brand.royalBlueDark));

  Widget _formField(TextEditingController c, String hint, bool isDark,
      {int maxLines = 1, TextInputType? keyboardType}) {
    return TextField(
        controller: c,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white : Brand.royalBlueDark),
        decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                fontSize: 14),
            filled: true,
            fillColor:
                isDark ? Colors.white.withAlpha(10) : Brand.royalBlueSurface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                    color: isDark ? Brand.darkBorderLight : Brand.borderLight)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                    color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                    width: 1.5)),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14))));
  }

  // ═══════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final machine = widget.machine;
    final specs = machine['specifications'] as Map<String, dynamic>?;
    final features = machine['features'] as List<dynamic>?;
    final applications = machine['applications'] as List<dynamic>?;
    final brochureUrl = machine['brochure_url'] as String?;
    final videoUrl = machine['video_url'] as String?;
    final subCategory = machine['sub_category'] as String?;
    final images = _getImages();
    final accent = _catAccent(machine['category']);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: isDark ? Brand.darkBg : Brand.scaffoldLight,
        body:
            CustomScrollView(physics: const BouncingScrollPhysics(), slivers: [
          // ── IMAGE HEADER ───────────────────────────────
          SliverAppBar(
            expandedHeight: 360,
            pinned: true,
            stretch: true,
            backgroundColor: isDark ? _dNavy : Brand.royalBlueDark,
            elevation: 0,
            leading: Padding(
                padding: const EdgeInsets.all(8),
                child: _appBarBtn(Icons.arrow_back_ios_new_rounded,
                    () => Navigator.pop(context))),
            actions: [
              Padding(
                  padding: const EdgeInsets.all(4),
                  child: _appBarBtn(
                      _isSaved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      _toggleSaved,
                      bg: _isSaved ? Brand.royalBlue : null)),
              Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 8, 4),
                  child: _appBarBtn(Icons.share_rounded, _shareProduct)),
            ],
            flexibleSpace: FlexibleSpaceBar(
                background: _buildImageGallery(images, isDark)),
          ),

          // ── CONTENT ────────────────────────────────────
          SliverToBoxAdapter(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                if (_isOwned) _ownedBadge(isDark),
                if (_existingInquiryCount > 0) _inquiryNotice(isDark),
                _infoCard(machine, subCategory, accent, isDark),
                _quickSpecs(isDark),
                if ((brochureUrl != null && brochureUrl.isNotEmpty) ||
                    (videoUrl != null && videoUrl.isNotEmpty))
                  _resourcesRow(brochureUrl, videoUrl, isDark),
                if (specs != null && specs.isNotEmpty)
                  _specsCard(specs, isDark),
                if (features != null && features.isNotEmpty)
                  _featuresCard(features, accent, isDark),
                if (applications != null && applications.isNotEmpty)
                  _appsCard(applications, accent, isDark),
                _priceCard(isDark),
                _contactCard(isDark),
                if (_relatedMachines.isNotEmpty) _related(isDark),
                const SizedBox(height: 120),
              ])),
        ]),
        bottomNavigationBar: _bottomActions(isDark),
      ),
    );
  }

  Widget _appBarBtn(IconData icon, VoidCallback onTap, {Color? bg}) {
    return GestureDetector(
        onTap: onTap,
        child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: bg ?? Colors.black.withAlpha(71),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withAlpha(20))),
            child: Icon(icon, color: Colors.white, size: 18)));
  }

  // ── IMAGE GALLERY ──────────────────────────────────────────
  Widget _buildImageGallery(List<String> images, bool isDark) {
    if (images.isEmpty) {
      return Container(
          color: isDark ? _dNavy : Brand.royalBlueSurface,
          child: _imgPlaceholder(widget.machine['category'], isDark));
    }

    return Stack(fit: StackFit.expand, children: [
      PageView.builder(
          controller: _imagePageController,
          itemCount: images.length,
          onPageChanged: (i) => setState(() => _currentImageIndex = i),
          itemBuilder: (_, i) => GestureDetector(
              onTap: () => _showFullScreen(images, i),
              child: CachedNetworkImage(
                  imageUrl: images[i],
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Center(
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: Brand.royalBlue, strokeWidth: 2.5))),
                  errorWidget: (_, __, ___) =>
                      _imgPlaceholder(widget.machine['category'], isDark)))),
      // Gradient
      Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 120,
          child: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                Colors.transparent,
                Colors.black.withAlpha(128)
              ])))),
      // Dots
      if (images.length > 1)
        Positioned(
            bottom: 22,
            left: 0,
            right: 0,
            child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                    images.length,
                    (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: _currentImageIndex == i ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: _currentImageIndex == i
                                ? Brand.lightGreenBright
                                : Colors.white.withAlpha(102),
                            boxShadow: _currentImageIndex == i
                                ? [
                                    BoxShadow(
                                        color: Brand.lightGreen.withAlpha(102),
                                        blurRadius: 6)
                                  ]
                                : null))))),
      // Counter
      if (images.length > 1)
        Positioned(
            top: 85,
            right: 16,
            child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.black.withAlpha(115),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withAlpha(26))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.photo_library_rounded,
                      color: Colors.white, size: 14),
                  const SizedBox(width: 6),
                  Text('${_currentImageIndex + 1}/${images.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700))
                ]))),
    ]);
  }

  void _showFullScreen(List<String> images, int idx) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => _FullScreenGallery(
                images: images,
                initialIndex: idx,
                machineName: widget.machine['machine_name'] ?? '')));
  }

  Widget _imgPlaceholder(String? cat, bool isDark) {
    return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
              color: isDark ? _dNavy.withAlpha(128) : Brand.royalBlueSurface,
              borderRadius: BorderRadius.circular(24)),
          child: Center(
              child: _catIcon(
                  cat,
                  isDark
                      ? Brand.royalBlueGlow.withAlpha(77)
                      : Brand.royalBlue.withAlpha(51),
                  36))),
      const SizedBox(height: 12),
      Text(S.of(context)!.machineNoImage,
          style: TextStyle(
              fontSize: 13,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight)),
    ]));
  }

  // ── OWNED BADGE ────────────────────────────────────────────
  Widget _ownedBadge(bool isDark) {
    return Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Brand.lightGreen.withAlpha(isDark ? 20 : 13),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Brand.lightGreen.withAlpha(51))),
        child: Row(children: [
          Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Brand.lightGreen, Brand.lightGreenBright]),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.check_circle,
                  color: Colors.white, size: 18)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(S.of(context)!.machineYouOwn,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Brand.lightGreen))),
          Material(
              color: Colors.transparent,
              child: InkWell(
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MyMachinesPage())),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: Brand.lightGreen.withAlpha(26),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Text('View',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Brand.lightGreen))))),
        ]));
  }

  // ── INQUIRY NOTICE ─────────────────────────────────────────
  Widget _inquiryNotice(bool isDark) {
    return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Brand.royalBlue.withAlpha(isDark ? 20 : 10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Brand.royalBlue.withAlpha(38))),
        child: Row(children: [
          Icon(Icons.info_outline_rounded,
              color: isDark ? Brand.royalBlueGlow : Brand.royalBlue, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(
                  'You have $_existingInquiryCount active inquiry/order for this machine',
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                      fontWeight: FontWeight.w500))),
        ]));
  }

  // ── INFO CARD ──────────────────────────────────────────────
  Widget _infoCard(
      Map<String, dynamic> m, String? subCat, Color accent, bool isDark) {
    return Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
            color: isDark ? Brand.darkCard : Brand.cardLight,
            borderRadius: BorderRadius.circular(24),
            border: isDark ? Border.all(color: Brand.darkBorder) : null,
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                        color: Brand.royalBlue.withAlpha(13),
                        blurRadius: 16,
                        offset: const Offset(0, 5))
                  ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            _badge(m['brand'] ?? 'iFrontiers', accent, isDark),
            _badge(m['category'] ?? '',
                isDark ? Brand.royalBlueGlow : Brand.royalBlue, isDark,
                filled: false),
            if (subCat != null && subCat.isNotEmpty)
              _badge(subCat,
                  isDark ? Brand.darkTextSecondary : Brand.subtleLight, isDark,
                  filled: false),
          ]),
          const SizedBox(height: 18),
          Text(m['machine_name'] ?? 'Unknown Machine',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Brand.royalBlueDark,
                  height: 1.15,
                  letterSpacing: -0.5)),
          const SizedBox(height: 10),
          Row(children: [
            Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                    color: isDark
                        ? Brand.royalBlue.withAlpha(26)
                        : Brand.royalBlueSurface,
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.tag_rounded,
                    size: 14,
                    color: isDark ? Brand.royalBlueGlow : Brand.royalBlue)),
            const SizedBox(width: 8),
            Text('Model: ${m['model_number'] ?? 'N/A'}',
                style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    fontWeight: FontWeight.w600)),
          ]),
          if (m['description'] != null) ...[
            const SizedBox(height: 18),
            Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withAlpha(8)
                        : Brand.royalBlueSurface.withAlpha(102),
                    borderRadius: BorderRadius.circular(14)),
                child: Text(m['description'],
                    style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                        height: 1.6)))
          ],
        ]));
  }

  Widget _badge(String text, Color c, bool isDark, {bool filled = true}) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color:
                c.withAlpha(filled ? (isDark ? 38 : 20) : (isDark ? 15 : 10)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.withAlpha(31))),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: c,
                letterSpacing: 0.3)));
  }

  // ── QUICK SPECS ────────────────────────────────────────────
  Widget _quickSpecs(bool isDark) {
    final qs = _getQuickSpecs();
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Row(
            children: qs.entries
                .map((e) => Expanded(
                    child: Container(
                        margin: EdgeInsets.only(
                            right: e.key != qs.keys.last ? 10 : 0),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: isDark ? Brand.darkCard : Brand.cardLight,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                                color: isDark
                                    ? Brand.darkBorder
                                    : Brand.borderLight),
                            boxShadow: isDark
                                ? null
                                : [
                                    BoxShadow(
                                        color: Brand.royalBlue.withAlpha(10),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3))
                                  ]),
                        child: Column(children: [
                          Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                  color: isDark
                                      ? Brand.royalBlue.withAlpha(26)
                                      : Brand.royalBlueSurface,
                                  borderRadius: BorderRadius.circular(11)),
                              child: Icon(
                                  _specIcon(e.value['icon'] ?? 'settings'),
                                  color: isDark
                                      ? Brand.royalBlueGlow
                                      : Brand.royalBlue,
                                  size: 18)),
                          const SizedBox(height: 8),
                          Text(e.key,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Brand.darkTextSecondary
                                      : Brand.subtleLight,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Text(
                              (e.value['value'] ?? '-').length > 14
                                  ? '${(e.value['value'] ?? '-').substring(0, 14)}...'
                                  : e.value['value'] ?? '-',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Colors.white
                                      : Brand.royalBlueDark)),
                        ]))))
                .toList()));
  }

  // ── RESOURCES ROW ──────────────────────────────────────────
  Widget _resourcesRow(String? brochure, String? video, bool isDark) {
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Row(children: [
          if (brochure != null && brochure.isNotEmpty)
            Expanded(
                child: _resourceBtn(Icons.picture_as_pdf_rounded, 'Brochure',
                    Colors.red, isDark, () => _launchUrl(brochure))),
          if (brochure != null &&
              brochure.isNotEmpty &&
              video != null &&
              video.isNotEmpty)
            const SizedBox(width: 10),
          if (video != null && video.isNotEmpty)
            Expanded(
                child: _resourceBtn(Icons.play_circle_rounded, 'Watch Demo',
                    Brand.royalBlueLight, isDark, () => _launchUrl(video))),
        ]));
  }

  Widget _resourceBtn(
      IconData icon, String label, Color c, bool isDark, VoidCallback onTap) {
    return Material(
        color: Colors.transparent,
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                    color: c.withAlpha(isDark ? 20 : 13),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.withAlpha(38))),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, color: c, size: 20),
                  const SizedBox(width: 8),
                  Text(label,
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700, color: c))
                ]))));
  }

  // ── SPECIFICATIONS ─────────────────────────────────────────
  Widget _specsCard(Map<String, dynamic> specs, bool isDark) {
    return _expandable('Specifications', Icons.tune_rounded, _specsExpanded,
        () => setState(() => _specsExpanded = !_specsExpanded), isDark,
        child: Column(
            children: specs.entries.toList().asMap().entries.map((e) {
          final isEven = e.key % 2 == 0;
          return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                  color: isEven
                      ? (isDark
                          ? Colors.white.withAlpha(5)
                          : Brand.royalBlueSurface.withAlpha(77))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10)),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 5, right: 12),
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Brand.lightGreen, Brand.lightGreenBright]),
                        borderRadius: BorderRadius.circular(3))),
                Expanded(
                    flex: 2,
                    child: Text(_formatKey(e.value.key),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color:
                                isDark ? Colors.white : Brand.royalBlueDark))),
                Expanded(
                    flex: 3,
                    child: Text('${e.value.value}',
                        style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight))),
              ]));
        }).toList()));
  }

  // ── FEATURES ───────────────────────────────────────────────
  Widget _featuresCard(List<dynamic> features, Color accent, bool isDark) {
    return _expandable('Key Features', Icons.stars_rounded, _featuresExpanded,
        () => setState(() => _featuresExpanded = !_featuresExpanded), isDark,
        child: Column(
            children: features.asMap().entries.map((e) {
          return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                        color: accent.withAlpha(isDark ? 31 : 20),
                        borderRadius: BorderRadius.circular(8)),
                    child: Center(
                        child: Text('${e.key + 1}',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: accent)))),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(e.value.toString(),
                          style: TextStyle(
                              fontSize: 13,
                              color:
                                  isDark ? Colors.white : Brand.royalBlueDark,
                              fontWeight: FontWeight.w500,
                              height: 1.4)),
                      if (e.key < features.length - 1)
                        Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Divider(
                                color: isDark
                                    ? Brand.darkBorder
                                    : Brand.borderLight,
                                height: 1)),
                    ])),
              ]));
        }).toList()));
  }

  // ── APPLICATIONS ───────────────────────────────────────────
  Widget _appsCard(List<dynamic> apps, Color accent, bool isDark) {
    return _expandable(
      'Applications',
      Icons.apps_rounded,
      _applicationsExpanded,
      () => setState(() => _applicationsExpanded = !_applicationsExpanded),
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Image slideshow (shown only when at least one app has an image) ──
          if (_appsWithImages.isNotEmpty) ...[
            SizedBox(
              height: 180,
              child: PageView.builder(
                controller: _appImgController,
                itemCount: _appsWithImages.length,
                onPageChanged: (i) => setState(() => _currentAppImg = i),
                itemBuilder: (ctx, i) {
                  final name = _appsWithImages[i]['name'] as String;
                  final url = _appsWithImages[i]['image_url'] as String;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: isDark
                                  ? Brand.darkCardElevated
                                  : Brand.royalBlueSurface,
                              child: const Center(
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: isDark
                                  ? Brand.darkCardElevated
                                  : Brand.royalBlueSurface,
                              child: Icon(Icons.broken_image_rounded,
                                  color: Brand.subtleLight),
                            ),
                          ),
                          // Gradient + label overlay
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withAlpha(179),
                                  ],
                                ),
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
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
            // Page indicator dots
            if (_appsWithImages.length > 1) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_appsWithImages.length, (i) {
                  final active = i == _currentAppImg;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active
                          ? accent
                          : Brand.subtleLight.withAlpha(128),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ],
            const SizedBox(height: 14),
          ],
          // ── All apps as text chips ──
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: apps
                .map((a) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                        color: isDark
                            ? Brand.darkCardElevated
                            : Brand.royalBlueSurface.withAlpha(128),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: isDark
                                ? Brand.darkBorderLight
                                : Brand.borderLight)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                              gradient: LinearGradient(colors: [
                                Brand.lightGreen,
                                Brand.lightGreenBright
                              ]),
                              shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(a.toString(),
                          style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white : Brand.royalBlueDark,
                              fontWeight: FontWeight.w600)),
                    ])))
                .toList(),
          ),
        ],
      ),
    );
  }

  // ── EXPANDABLE ─────────────────────────────────────────────
  Widget _expandable(String title, IconData icon, bool expanded,
      VoidCallback onToggle, bool isDark,
      {required Widget child}) {
    return Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        decoration: BoxDecoration(
            color: isDark ? Brand.darkCard : Brand.cardLight,
            borderRadius: BorderRadius.circular(22),
            border: isDark ? Border.all(color: Brand.darkBorder) : null,
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                        color: Brand.royalBlue.withAlpha(10),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ]),
        child: Column(children: [
          Material(
              color: Colors.transparent,
              child: InkWell(
                  onTap: onToggle,
                  borderRadius: BorderRadius.circular(22),
                  child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(children: [
                        Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                                color: isDark
                                    ? Brand.royalBlue.withAlpha(26)
                                    : Brand.royalBlueSurface,
                                borderRadius: BorderRadius.circular(12)),
                            child: Icon(icon,
                                color: isDark
                                    ? Brand.royalBlueGlow
                                    : Brand.royalBlue,
                                size: 20)),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Text(title,
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white
                                        : Brand.royalBlueDark))),
                        AnimatedRotation(
                            turns: expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 300),
                            child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withAlpha(10)
                                        : Brand.royalBlueSurface.withAlpha(128),
                                    borderRadius: BorderRadius.circular(8)),
                                child: Icon(Icons.keyboard_arrow_down_rounded,
                                    color: isDark
                                        ? Colors.white54
                                        : Brand.subtleLight,
                                    size: 22))),
                      ])))),
          AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              crossFadeState: expanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  child: child),
              secondChild: const SizedBox(width: double.infinity)),
        ]));
  }

  // ── PRICE CARD ─────────────────────────────────────────────
  Widget _priceCard(bool isDark) {
    return Material(
        color: Colors.transparent,
        child: InkWell(
            onTap: _isInquiryLoading ? null : _createInquiry,
            borderRadius: BorderRadius.circular(22),
            child: Container(
                margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: isDark
                            ? [_dNavy, _dNavySurf]
                            : [
                                Brand.royalBlueDark.withAlpha(10),
                                Brand.lightGreen.withAlpha(15)
                              ]),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                        color: isDark
                            ? Brand.royalBlueLight.withAlpha(38)
                            : Brand.lightGreen.withAlpha(51),
                        width: 1.5)),
                child: Row(children: [
                  Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            Brand.lightGreen.withAlpha(38),
                            Brand.lightGreenBright.withAlpha(26)
                          ]),
                          borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.request_quote_rounded,
                          color: Brand.lightGreen, size: 24)),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(S.of(context)!.catalogPriceOnRequest,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Colors.white
                                    : Brand.royalBlueDark)),
                        const SizedBox(height: 4),
                        Text(S.of(context)!.machineQuoteHint,
                            style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight)),
                      ])),
                  Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                          color: Brand.lightGreen.withAlpha(26),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.arrow_forward_ios_rounded,
                          color: Brand.lightGreen, size: 14)),
                ]))));
  }

  // ── CONTACT CARD ───────────────────────────────────────────
  Widget _contactCard(bool isDark) {
    return Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: isDark ? Brand.darkCard : Brand.cardLight,
            borderRadius: BorderRadius.circular(22),
            border: isDark ? Border.all(color: Brand.darkBorder) : null),
        child: Row(children: [
          Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                  color: isDark
                      ? Brand.royalBlue.withAlpha(26)
                      : Brand.royalBlueSurface,
                  borderRadius: BorderRadius.circular(16)),
              child: Icon(Icons.headset_mic_rounded,
                  color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                  size: 24)),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(S.of(context)!.machineNeedHelp,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Brand.royalBlueDark)),
                const SizedBox(height: 4),
                Text(S.of(context)!.machineExpertsGuide,
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight)),
              ])),
          Material(
              color: Colors.transparent,
              child: InkWell(
                  onTap: _callNeedHelp,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Brand.royalBlue, Brand.royalBlueLight]),
                          borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        const Icon(Icons.phone, color: Colors.white, size: 14),
                        const SizedBox(width: 6),
                        Text(S.of(context)!.machineCall,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700))
                      ])))),
        ]));
  }

  // ── RELATED MACHINES ───────────────────────────────────────
  Widget _related(bool isDark) {
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Brand.royalBlue, Brand.royalBlueGlow],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Text(S.of(context)!.catalogRelatedMachines,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Brand.royalBlueDark,
                    letterSpacing: -0.3)),
          ]),
          const SizedBox(height: 14),
          SizedBox(
              height: 170,
              child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _relatedMachines.length,
                  itemBuilder: (_, i) {
                    final r = _relatedMachines[i];
                    // Use pre-computed product_image set by MachineImageHelper
                    // (canonical fallback: image_url → product_images[0] → images[0])
                    final img = r['product_image'] as String?;
                    return GestureDetector(
                        onTap: () async {
                          try {
                            final full = await SupabaseConfig.client
                                .from('machine_catalog')
                                .select()
                                .eq('id', r['id'])
                                .single();
                            if (!mounted) return;
                            Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        MachineDetailPage(machine: full)));
                          } catch (_) {
                            if (!mounted) return;
                            Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        MachineDetailPage(machine: r)));
                          }
                        },
                        child: Container(
                            width: 150,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                                color:
                                    isDark ? Brand.darkCard : Brand.cardLight,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                    color: isDark
                                        ? Brand.darkBorder
                                        : Brand.borderLight),
                                boxShadow: isDark
                                    ? null
                                    : [
                                        BoxShadow(
                                            color:
                                                Brand.royalBlue.withAlpha(10),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3))
                                      ]),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                      height: 85,
                                      decoration: BoxDecoration(
                                          color: isDark
                                              ? _dNavy.withAlpha(102)
                                              : Brand.royalBlueSurface
                                                  .withAlpha(128),
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                  top: Radius.circular(18))),
                                      child: ClipRRect(
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                  top: Radius.circular(18)),
                                          child: img != null
                                              ? CachedNetworkImage(
                                                  imageUrl: img,
                                                  width: double.infinity,
                                                  fit: BoxFit.cover,
                                                  errorWidget: (_, __, ___) => Center(
                                                      child: _catIcon(
                                                          r['category'],
                                                          isDark
                                                              ? Brand.royalBlueGlow
                                                                  .withAlpha(77)
                                                              : Brand.royalBlue
                                                                  .withAlpha(51),
                                                          26)))
                                              : Center(child: _catIcon(r['category'], isDark ? Brand.royalBlueGlow.withAlpha(77) : Brand.royalBlue.withAlpha(51), 26)))),
                                  Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(r['brand'] ?? '',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: _catAccent(
                                                        r['category']))),
                                            const SizedBox(height: 4),
                                            Text(r['machine_name'] ?? '',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: -0.1,
                                                    color: isDark
                                                        ? Colors.white
                                                        : Brand.royalBlueDark,
                                                    height: 1.2)),
                                          ])),
                                ])));
                  })),
        ]));
  }

  // ── BOTTOM ACTIONS ─────────────────────────────────────────
  Widget _bottomActions(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28), topRight: Radius.circular(28)),
          border: Border(
              top: BorderSide(
                  color: isDark ? Brand.darkBorder : Brand.borderLight,
                  width: 1)),
          boxShadow: isDark ? null : [
            BoxShadow(
                color: Brand.royalBlue.withAlpha(15),
                blurRadius: 24,
                offset: const Offset(0, -6))
          ]),
      child: SafeArea(
          child: Row(children: [
        // Inquire
        Expanded(
            child: Material(
                color: Colors.transparent,
                child: InkWell(
                    onTap: _isInquiryLoading ? null : _createInquiry,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: isDark
                                  ? Brand.royalBlueLight
                                  : Brand.royalBlue,
                              width: 2)),
                      child: _isInquiryLoading
                          ? Center(
                              child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: isDark
                                          ? Brand.royalBlueGlow
                                          : Brand.royalBlue,
                                      strokeWidth: 2.5)))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                  Icon(Icons.chat_bubble_outline_rounded,
                                      color: isDark
                                          ? Brand.royalBlueGlow
                                          : Brand.royalBlue,
                                      size: 18),
                                  const SizedBox(width: 8),
                                  Text(S.of(context)!.machineInquire,
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? Brand.royalBlueGlow
                                              : Brand.royalBlue))
                                ]),
                    )))),
        const SizedBox(width: 12),
        // Order
        Expanded(
            child: Material(
                color: Colors.transparent,
                child: InkWell(
                    onTap: _isOrderLoading ? null : _showOrderForm,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [
                            Brand.lightGreen,
                            Brand.lightGreenBright
                          ]),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                                color: Brand.lightGreen.withAlpha(102),
                                blurRadius: 14,
                                offset: const Offset(0, 5))
                          ]),
                      child: _isOrderLoading
                          ? const Center(
                              child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5)))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                  const Icon(Icons.shopping_cart_rounded,
                                      color: Colors.white, size: 18),
                                  const SizedBox(width: 8),
                                  Text(S.of(context)!.catalogPlaceOrder,
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white))
                                ]),
                    )))),
      ])),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  FULL SCREEN GALLERY
// ══════════════════════════════════════════════════════════════
class _FullScreenGallery extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  final String machineName;
  const _FullScreenGallery(
      {required this.images,
      required this.initialIndex,
      required this.machineName});
  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late PageController _c;
  late int _i;
  @override
  void initState() {
    super.initState();
    _i = widget.initialIndex;
    _c = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            backgroundColor: Colors.black,
            elevation: 0,
            leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context)),
            title: Text('${_i + 1} / ${widget.images.length}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            centerTitle: true),
        body: PageView.builder(
            controller: _c,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (_, i) => InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                    child: CachedNetworkImage(
                        imageUrl: widget.images[i],
                        fit: BoxFit.contain,
                        placeholder: (_, __) => Center(
                            child: CircularProgressIndicator(
                                color: Brand.lightGreenBright)),
                        errorWidget: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image,
                                color: Colors.white38, size: 48)))))));
  }
}
