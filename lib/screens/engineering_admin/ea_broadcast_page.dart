// lib/screens/engineering_admin/ea_broadcast_page.dart
// v24 — Engineering Admin Broadcast Composer
//
// Allows EA to send push notifications to:
//   • All engineers
//   • Engineers by specialization
//   • A single engineer (picker)
//   • The customer attached to a service ticket (passed in as a constructor arg)
//
// Writes notifications rows + invokes the `send-push` Edge Function.
// Schema-truth columns used:  users.role, users.specializations TEXT[],
// notifications.title/body/type/metadata/is_read/created_at.

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';
import '../../widgets/ds/ds_widgets.dart';

const Color _eaAccent = Brand.lightGreenDark;

enum _BroadcastAudience {
  allEngineers,
  bySpecialization,
  singleEngineer,
}

class EaBroadcastPage extends StatefulWidget {
  /// Optional — when the page is opened from a ticket context, the EA can
  /// also target "this ticket's customer".
  final String? prefilledCustomerId;
  final String? prefilledCustomerName;

  const EaBroadcastPage({
    super.key,
    this.prefilledCustomerId,
    this.prefilledCustomerName,
  });

  @override
  State<EaBroadcastPage> createState() => _EaBroadcastPageState();
}

class _EaBroadcastPageState extends State<EaBroadcastPage> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl  = TextEditingController();

  _BroadcastAudience _audience = _BroadcastAudience.allEngineers;
  String? _specialization;
  Map<String, dynamic>? _selectedEngineer;
  bool _includeCustomer = false;

  List<Map<String, dynamic>> _engineers = [];
  List<String> _specializations = [];
  int _recipientCount = 0;
  bool _loadingMeta = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  // ── Load engineers + specializations ──────────────────────────────────
  Future<void> _loadMeta() async {
    try {
      final rows = await SupabaseConfig.client
          .from('users')
          .select('id, full_name, profile_photo, specializations, employee_id')
          .eq('role', 'engineer')
          .filter('date_terminated', 'is', null)
          .order('full_name');

      final list = (rows as List).cast<Map<String, dynamic>>();
      final specs = <String>{};
      for (final e in list) {
        final raw = e['specializations'];
        if (raw is List) {
          for (final s in raw) {
            if (s is String && s.isNotEmpty) specs.add(s);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _engineers = list;
        _specializations = specs.toList()..sort();
        _loadingMeta = false;
      });
      await _refreshCount();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMeta = false);
    }
  }

  // ── Recipient count ───────────────────────────────────────────────────
  Future<void> _refreshCount() async {
    int count = 0;
    switch (_audience) {
      case _BroadcastAudience.allEngineers:
        count = _engineers.length;
        break;
      case _BroadcastAudience.bySpecialization:
        if (_specialization == null) {
          count = 0;
        } else {
          count = _engineers.where((e) {
            final raw = e['specializations'];
            return raw is List && raw.contains(_specialization);
          }).length;
        }
        break;
      case _BroadcastAudience.singleEngineer:
        count = _selectedEngineer == null ? 0 : 1;
        break;
    }
    if (_includeCustomer && widget.prefilledCustomerId != null) count++;
    if (!mounted) return;
    setState(() => _recipientCount = count);
  }

  // ── Resolve target user IDs ───────────────────────────────────────────
  List<String> _resolveTargetIds() {
    final ids = <String>{};
    switch (_audience) {
      case _BroadcastAudience.allEngineers:
        ids.addAll(_engineers.map((e) => e['id'] as String));
        break;
      case _BroadcastAudience.bySpecialization:
        if (_specialization != null) {
          for (final e in _engineers) {
            final raw = e['specializations'];
            if (raw is List && raw.contains(_specialization)) {
              ids.add(e['id'] as String);
            }
          }
        }
        break;
      case _BroadcastAudience.singleEngineer:
        if (_selectedEngineer != null) {
          ids.add(_selectedEngineer!['id'] as String);
        }
        break;
    }
    if (_includeCustomer && widget.prefilledCustomerId != null) {
      ids.add(widget.prefilledCustomerId!);
    }
    return ids.toList();
  }

  // ── Send broadcast ────────────────────────────────────────────────────
  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final body  = _bodyCtrl.text.trim();
    if (title.isEmpty) { _snack('Please enter a title', isError: true); return; }
    if (body.isEmpty)  { _snack('Please enter a message', isError: true); return; }

    final ids = _resolveTargetIds();
    if (ids.isEmpty) {
      _snack('No recipients selected', isError: true);
      return;
    }

    final confirmed = await _confirmDialog(ids.length);
    if (!confirmed) return;
    if (!mounted) return;

    setState(() => _sending = true);
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final rows = ids
          .map((uid) => {
                'user_id': uid,
                'title': title,
                'body': body,
                'type': 'broadcast',
                'is_read': false,
                'created_at': now,
                'metadata': {
                  'source': 'engineering_admin_broadcast',
                  'audience': _audience.name,
                },
              })
          .toList();

      // Batch insert (Postgres handles up to ~1000; chunk to be safe)
      for (var i = 0; i < rows.length; i += 100) {
        final chunk = rows.sublist(i, (i + 100) > rows.length ? rows.length : i + 100);
        await SupabaseConfig.client.from('notifications').insert(chunk);
      }

      // Fire-and-forget FCM push via Edge Function.
      try {
        await SupabaseConfig.client.functions.invoke('send-push', body: {
          'title': title,
          'body': body,
          'user_ids': ids,
        });
      } catch (_) {
        // Notification rows still inserted — push is best-effort.
      }

      if (!mounted) return;
      _snack('Broadcast sent to ${ids.length} recipient${ids.length == 1 ? '' : 's'}');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _snack('Send failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<bool> _confirmDialog(int count) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: isDark ? Brand.darkCard : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(20))),
            title: Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: _eaAccent.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send_rounded, color: _eaAccent, size: 18),
              ),
              const SizedBox(width: 10),
              const Text('Send broadcast?', style: TextStyle(fontSize: 17)),
            ]),
            content: Text(
              'This will deliver a push notification to $count recipient${count == 1 ? '' : 's'} and cannot be undone.',
              style: TextStyle(fontSize: 13, color: AdminColors.textSub(context)),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: _eaAccent),
                child: const Text('Send'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? StatusColors.danger : _eaAccent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: DsPageHeader(
        title: 'New Broadcast',
        accent: HeroAccent.emerald,
      ),
      body: _loadingMeta
          ? const Center(child: CircularProgressIndicator(color: _eaAccent))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              children: [
                _audienceCard(isDark),
                const SizedBox(height: 16),
                _messageCard(isDark),
                const SizedBox(height: 20),
                _recipientPill(isDark),
              ],
            ),
      bottomNavigationBar: _buildSendBar(isDark),
    );
  }

  // ── Audience card ─────────────────────────────────────────────────────
  Widget _audienceCard(bool isDark) {
    return _section(
      isDark: isDark,
      title: 'Audience',
      icon: Icons.groups_rounded,
      child: RadioGroup<_BroadcastAudience>(
        groupValue: _audience,
        onChanged: (v) {
          if (v == null) return;
          setState(() => _audience = v);
          _refreshCount();
        },
        child: Column(
          children: [
          _audienceTile(
            isDark: isDark,
            value: _BroadcastAudience.allEngineers,
            icon: Icons.engineering_rounded,
            label: 'All Engineers',
            sub: '${_engineers.length} engineer${_engineers.length == 1 ? '' : 's'}',
          ),
          _audienceTile(
            isDark: isDark,
            value: _BroadcastAudience.bySpecialization,
            icon: Icons.workspace_premium_rounded,
            label: 'By Specialization',
            sub: _specializations.isEmpty
                ? 'No specializations defined yet'
                : '${_specializations.length} specializations available',
          ),
          if (_audience == _BroadcastAudience.bySpecialization &&
              _specializations.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Wrap(
                spacing: 8, runSpacing: 8,
                children: _specializations.map((s) {
                  final selected = s == _specialization;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _specialization = s);
                      _refreshCount();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: selected
                            ? _eaAccent
                            : (isDark ? Brand.darkCardElevated : Brand.slateLight),
                        borderRadius: BorderRadius.circular(Brand.r(999)),
                        border: Border.all(
                          color: selected
                              ? _eaAccent
                              : (isDark ? Brand.darkBorder : Brand.borderLight),
                        ),
                      ),
                      child: Text(s,
                          style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600,
                            color: selected
                                ? Colors.white
                                : (isDark ? Brand.darkTextPrimary : Brand.darkSurface),
                          )),
                    ),
                  );
                }).toList(),
              ),
            ),
          _audienceTile(
            isDark: isDark,
            value: _BroadcastAudience.singleEngineer,
            icon: Icons.person_rounded,
            label: 'One Engineer',
            sub: _selectedEngineer == null
                ? 'Tap to choose an engineer'
                : _selectedEngineer!['full_name'] ?? 'Engineer',
            trailingTap: _pickEngineer,
          ),
          if (widget.prefilledCustomerId != null) ...[
            const Divider(height: 24),
            CheckboxListTile(
              value: _includeCustomer,
              onChanged: (v) {
                setState(() => _includeCustomer = v ?? false);
                _refreshCount();
              },
              activeColor: _eaAccent,
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 6),
              title: Text('Also notify customer',
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: isDark ? Brand.darkTextPrimary : AdminColors.textPrimary,
                  )),
              subtitle: Text(widget.prefilledCustomerName ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    color: AdminColors.textSub(context),
                  )),
            ),
          ],
          ],
        ),
      ),
    );
  }

  Widget _audienceTile({
    required bool isDark,
    required _BroadcastAudience value,
    required IconData icon,
    required String label,
    required String sub,
    VoidCallback? trailingTap,
  }) {
    final selected = _audience == value;
    return InkWell(
      borderRadius: BorderRadius.circular(Brand.r(12)),
      onTap: () {
        setState(() => _audience = value);
        _refreshCount();
        if (value == _BroadcastAudience.singleEngineer && trailingTap != null) {
          trailingTap();
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? _eaAccent.withAlpha(isDark ? 35 : 18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Brand.r(12)),
          border: Border.all(
            color: selected
                ? _eaAccent
                : (isDark ? Brand.darkBorder : Brand.borderLight),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _eaAccent.withAlpha(isDark ? 50 : 30),
              borderRadius: BorderRadius.circular(Brand.r(10)),
            ),
            child: Icon(icon, color: _eaAccent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: isDark ? Brand.darkTextPrimary : AdminColors.textPrimary,
                    )),
                const SizedBox(height: 2),
                Text(sub,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: AdminColors.textSub(context),
                    )),
              ],
            ),
          ),
          Radio<_BroadcastAudience>(
            value: value,
            activeColor: _eaAccent,
          ),
        ]),
      ),
    );
  }

  Future<void> _pickEngineer() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: isDark ? Brand.darkCard : Colors.white,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Brand.r(28))),
      ),
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withAlpha(80),
                borderRadius: BorderRadius.circular(Brand.r(2)),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                const Icon(Icons.person_search_rounded, color: _eaAccent),
                const SizedBox(width: 10),
                Text('Choose Engineer',
                    style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700,
                      color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    )),
              ]),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _engineers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (_, i) {
                  final e = _engineers[i];
                  final photo = e['profile_photo'] as String?;
                  final name = e['full_name'] as String? ?? 'Engineer';
                  final empId = e['employee_id'] as String? ?? '';
                  return ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(10))),
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: _eaAccent.withAlpha(30),
                      backgroundImage: photo != null && photo.isNotEmpty
                          ? CachedNetworkImageProvider(photo)
                          : null,
                      child: photo == null || photo.isEmpty
                          ? const Icon(Icons.engineering_rounded, color: _eaAccent, size: 20)
                          : null,
                    ),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(empId.isEmpty ? '' : 'ID: $empId',
                        style: TextStyle(color: AdminColors.textSub(context), fontSize: 11)),
                    onTap: () => Navigator.pop(sheetCtx, e),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) {
      setState(() => _selectedEngineer = picked);
      _refreshCount();
    }
  }

  // ── Message card ──────────────────────────────────────────────────────
  Widget _messageCard(bool isDark) {
    final txtColor = isDark ? Brand.darkTextPrimary : AdminColors.textPrimary;
    final hintColor = AdminColors.textHint(context);

    return _section(
      isDark: isDark,
      title: 'Message',
      icon: Icons.chat_bubble_rounded,
      child: Column(children: [
        TextField(
          controller: _titleCtrl,
          maxLength: 60,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: txtColor),
          decoration: InputDecoration(
            hintText: 'Title',
            hintStyle: TextStyle(color: hintColor),
            counterStyle: TextStyle(fontSize: 11, color: hintColor),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _bodyCtrl,
          maxLines: 4,
          maxLength: 240,
          style: TextStyle(fontSize: 13, color: txtColor),
          decoration: InputDecoration(
            hintText: 'Write your message…',
            hintStyle: TextStyle(color: hintColor),
            counterStyle: TextStyle(fontSize: 11, color: hintColor),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
          ),
        ),
      ]),
    );
  }

  Widget _recipientPill(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _eaAccent.withAlpha(isDark ? 35 : 18),
        borderRadius: BorderRadius.circular(Brand.r(12)),
        border: Border.all(color: _eaAccent.withAlpha(80)),
      ),
      child: Row(children: [
        const Icon(Icons.people_alt_rounded, color: _eaAccent, size: 16),
        const SizedBox(width: 8),
        Text(
          '$_recipientCount recipient${_recipientCount == 1 ? '' : 's'} will receive this',
          style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: _eaAccent,
          ),
        ),
      ]),
    );
  }

  Widget _section({
    required bool isDark,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(Brand.r(20)),
        border: Border.all(
          color: isDark ? Brand.darkBorder : Brand.borderLight,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(6),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: _eaAccent),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : AdminColors.textPrimary,
                )),
          ]),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildSendBar(bool isDark) {
    final enabled = !_sending && _recipientCount > 0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: enabled ? _send : null,
            style: FilledButton.styleFrom(
              backgroundColor: _eaAccent,
              disabledBackgroundColor: _eaAccent.withAlpha(110),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(16))),
            ),
            icon: _sending
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                : const Icon(Icons.send_rounded, color: Colors.white),
            label: Text(
              _sending ? 'Sending…' : 'Send broadcast',
              style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
