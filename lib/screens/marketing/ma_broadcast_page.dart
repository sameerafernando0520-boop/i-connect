// lib/screens/marketing/ma_broadcast_page.dart
// P6 — Broadcast Notifications: compose + send to all / by role

import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../utils/time_utils.dart';
import '../../widgets/ds/ds_widgets.dart';

const Color _bcColor = AdminColors.error;

class MaBroadcastPage extends StatefulWidget {
  const MaBroadcastPage({super.key});

  @override
  State<MaBroadcastPage> createState() => _MaBroadcastPageState();
}

class _MaBroadcastPageState extends State<MaBroadcastPage> {
  List<Map<String, dynamic>> _history = [];
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final res = await SupabaseConfig.client
          .from('notifications')
          .select('id, title, message, created_at, type, metadata')
          .eq('type', 'broadcast')
          .order('created_at', ascending: false)
          .limit(30);
      if (!mounted) return;
      setState(() {
        _history = List<Map<String, dynamic>>.from(res);
        _loadingHistory = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
    }
  }

  Future<void> _openCompose() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ComposeSheet(),
    );
    if (sent == true && mounted) {
      _loadHistory();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Row(children: [
          Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Text('Broadcast sent!', style: TextStyle(fontWeight: FontWeight.w600)),
        ]),
        backgroundColor: AdminColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: DsPageHeader(
        title: 'Broadcast',
        accent: HeroAccent.violet,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadHistory),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Compose Banner ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: InkWell(
              onTap: _openCompose,
              borderRadius: BorderRadius.circular(Brand.r(18)),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AdminColors.error, StatusColors.danger],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(Brand.r(18)),
                  boxShadow: [
                    BoxShadow(color: _bcColor.withAlpha(60), blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.campaign_rounded, color: Colors.white, size: 32),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Send Broadcast',
                            style: TextStyle(color: Colors.white, fontSize: 17,
                                fontWeight: FontWeight.w800)),
                        SizedBox(height: 2),
                        Text('Reach all customers instantly',
                            style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ]),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 16),
                  ],
                ),
              ),
            ),
          ),
          // ── History Label ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Text('RECENT BROADCASTS',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight)),
          ),
          // ── History List ──
          Expanded(
            child: _loadingHistory
                ? const Center(child: CircularProgressIndicator(color: _bcColor))
                : RefreshIndicator(
                    onRefresh: _loadHistory, color: _bcColor,
                    child: _history.isEmpty
                        ? ListView(children: [
                            const SizedBox(height: 60),
                            Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Container(
                                width: 72, height: 72,
                                decoration: BoxDecoration(
                                  color: _bcColor.withAlpha(20),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.history_rounded, size: 36, color: _bcColor),
                              ),
                              const SizedBox(height: 20),
                              Text('No broadcasts yet',
                                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                                      color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
                              const SizedBox(height: 8),
                              Text('Your sent broadcasts will appear here.',
                                  style: TextStyle(fontSize: 13, color: AdminColors.textHint(context))),
                            ])),
                          ])
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                            itemCount: _history.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, i) => _buildHistoryCard(_history[i], isDark),
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCompose,
        icon: const Icon(Icons.send_rounded),
        label: const Text('Compose', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: _bcColor, foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> n, bool isDark) {
    final createdAt = n['created_at'] as String?;
    final meta = n['metadata'] as Map<String, dynamic>?;
    final audience = meta?['audience'] as String? ?? 'all';

    return Container(
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(14)),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 16, offset: const Offset(0, 2)),
          BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 6, offset: const Offset(0, 1)),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _bcColor.withAlpha(isDark ? 30 : 15),
              borderRadius: BorderRadius.circular(Brand.r(10)),
            ),
            child: const Icon(Icons.campaign_rounded, size: 18, color: _bcColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n['title'] ?? 'Broadcast',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
              if ((n['message'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(n['message'].toString(),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AdminColors.textHint(context))),
              ],
              const SizedBox(height: 4),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _bcColor.withAlpha(15),
                    borderRadius: BorderRadius.circular(Brand.r(6)),
                  ),
                  child: Text('To: $audience',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                          color: _bcColor)),
                ),
                const Spacer(),
                if (createdAt != null)
                  Text(TimeUtils.formatDateShort(DateTime.tryParse(createdAt) ?? DateTime.now()),
                      style: TextStyle(fontSize: 11, color: AdminColors.textHint(context))),
              ]),
            ]),
          ),
        ],
      ),
    );
  }
}

// ─── Compose Sheet ─────────────────────────────────────────────────────────────

class _ComposeSheet extends StatefulWidget {
  const _ComposeSheet();

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final _titleCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  String _audience = 'all';
  bool _sending = false;

  final _audiences = [
    {'value': 'all', 'label': 'All Users'},
    {'value': 'customer', 'label': 'Customers Only'},
    {'value': 'engineer', 'label': 'Engineers Only'},
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_titleCtrl.text.trim().isEmpty || _msgCtrl.text.trim().isEmpty) return;
    setState(() => _sending = true);

    try {
      // Fetch user IDs based on audience
      List<String> userIds = [];

      if (_audience == 'all') {
        final res = await SupabaseConfig.client
            .from('users')
            .select('id')
            .inFilter('role', ['customer', 'engineer']);
        userIds = (res as List).map((u) => u['id'] as String).toList();
      } else {
        final res = await SupabaseConfig.client
            .from('users')
            .select('id')
            .eq('role', _audience);
        userIds = (res as List).map((u) => u['id'] as String).toList();
      }

      // Insert one notification record per user
      if (userIds.isNotEmpty) {
        final records = userIds.map((uid) => {
          'user_id': uid,
          'type': 'broadcast',
          'title': _titleCtrl.text.trim(),
          'message': _msgCtrl.text.trim(),
          'is_read': false,
          'metadata': {'audience': _audience, 'sent_by': SupabaseConfig.client.auth.currentUser?.id},
        }).toList();

        await SupabaseConfig.client.from('notifications').insert(records);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString(), style: const TextStyle(color: Colors.white)),
        backgroundColor: AdminColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Brand.r(28))),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPad),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Center(child: Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: isDark ? Brand.darkBorderLight : Brand.borderLight,
            borderRadius: BorderRadius.circular(Brand.r(2)),
          ),
        )),
        const SizedBox(height: 16),
        Row(children: [
          const Icon(Icons.campaign_rounded, color: _bcColor, size: 22),
          const SizedBox(width: 8),
          Text('Compose Broadcast',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
        ]),
        const SizedBox(height: 20),
        // Audience selector
        Text('AUDIENCE',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight)),
        const SizedBox(height: 8),
        Row(
          children: _audiences.map((a) {
            final selected = _audience == a['value'];
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => setState(() => _audience = a['value']!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? _bcColor : (isDark ? Brand.darkCardElevated : Brand.scaffoldLight),
                      borderRadius: BorderRadius.circular(Brand.r(12)),
                      border: Border.all(color: selected ? _bcColor : (isDark ? Brand.darkBorder : Brand.borderLight)),
                    ),
                    child: Text(a['label']!,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : AdminColors.textHint(context))),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _titleCtrl,
          decoration: InputDecoration(
            labelText: 'Title *',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
            filled: true,
            fillColor: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _msgCtrl,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Message *',
            alignLabelWithHint: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
            filled: true,
            fillColor: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded),
            label: Text(_sending ? 'Sending…' : 'Send Broadcast',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _bcColor, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(14))),
            ),
          ),
        ),
      ]),
    );
  }
}
