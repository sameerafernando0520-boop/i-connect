// lib/widgets/common/chat_attach_bar.dart
//
// Compose-side controls for chat attachments, reusable across the staff chat
// screens (engineer / admin / EA / inquiry):
//   • ChatAttachMenuButton  — "+" menu → Image / Camera / Document / Location
//   • ChatVoiceRecorderButton — hold-to-record voice note
// Both pick + upload via ChatAttachmentService, then hand the result back to
// the host screen via [onSend] so the screen owns the chat_messages insert.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../../config/brand_colors.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../services/chat_attachment_service.dart';

/// Called after an attachment has been uploaded; the host inserts the message.
typedef ChatSendAttachment = Future<void> Function({
  required String messageType,
  required List<String> attachments,
  Map<String, dynamic>? metadata,
});

// ── Attach "+" menu ───────────────────────────────────────────
class ChatAttachMenuButton extends StatefulWidget {
  final String ticketId;
  final ChatSendAttachment onSend;
  final Color accent;
  const ChatAttachMenuButton({
    super.key,
    required this.ticketId,
    required this.onSend,
    required this.accent,
  });

  @override
  State<ChatAttachMenuButton> createState() => _ChatAttachMenuButtonState();
}

class _ChatAttachMenuButtonState extends State<ChatAttachMenuButton> {
  bool _busy = false;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
    } catch (e) {
      _snack('Attachment failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _image({required bool camera}) => _run(() async {
        final f = await ChatAttachmentService.pickImage(camera: camera);
        if (f == null) return;
        final url = await ChatAttachmentService.uploadFile(
            ticketId: widget.ticketId, file: f, contentType: 'image/jpeg');
        await widget.onSend(messageType: 'image', attachments: [url]);
      });

  Future<void> _document() => _run(() async {
        final doc = await ChatAttachmentService.pickDocument();
        if (doc == null) return;
        final url = await ChatAttachmentService.uploadFile(
            ticketId: widget.ticketId, file: doc.file);
        await widget.onSend(
          messageType: 'document',
          attachments: [url],
          metadata: {'filename': doc.name, 'size': doc.size},
        );
      });

  Future<void> _location() => _run(() async {
        final pos = await ChatAttachmentService.currentLocation();
        if (pos == null) {
          _snack('Could not get location. Enable location & permissions.');
          return;
        }
        await widget.onSend(
          messageType: 'location',
          attachments: const [],
          metadata: {'lat': pos.latitude, 'lng': pos.longitude},
        );
      });

  void _openMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        Widget tile(IconData ic, String label, Color c, VoidCallback onTap) =>
            ListTile(
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: c.withAlpha(30),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(ic, color: c, size: 22),
              ),
              title: Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                onTap();
              },
            );
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 10),
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.withAlpha(80),
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 8),
              tile(Icons.image_rounded, 'Photo', const Color(0xFF8B5CF6),
                  () => _image(camera: false)),
              tile(Icons.camera_alt_rounded, 'Camera', const Color(0xFF06B6D4),
                  () => _image(camera: true)),
              tile(Icons.insert_drive_file_rounded, 'Document',
                  const Color(0xFFF59E0B), _document),
              tile(Icons.location_on_rounded, 'Location',
                  const Color(0xFFEF4444), _location),
              const SizedBox(height: 10),
            ]),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _busy ? null : _openMenu,
      icon: _busy
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: widget.accent))
          : Icon(Icons.add_circle_outline_rounded, color: widget.accent),
      tooltip: 'Attach',
    );
  }
}

// ── Voice recorder (hold to record) ───────────────────────────
class ChatVoiceRecorderButton extends StatefulWidget {
  final String ticketId;
  final ChatSendAttachment onSend;
  final Color accent;
  const ChatVoiceRecorderButton({
    super.key,
    required this.ticketId,
    required this.onSend,
    required this.accent,
  });

  @override
  State<ChatVoiceRecorderButton> createState() =>
      _ChatVoiceRecorderButtonState();
}

class _ChatVoiceRecorderButtonState extends State<ChatVoiceRecorderButton> {
  final _rec = AudioRecorder();
  bool _recording = false;
  bool _uploading = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  DateTime? _start;
  String? _path;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  Future<void> _startRec() async {
    try {
      if (!await _rec.hasPermission()) {
        _snack('Microphone permission denied');
        return;
      }
      final dir = await getTemporaryDirectory();
      final p =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: p);
      _path = p;
      _start = DateTime.now();
      setState(() {
        _recording = true;
        _elapsed = Duration.zero;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _start != null) {
          setState(() => _elapsed = DateTime.now().difference(_start!));
        }
      });
    } catch (e) {
      _snack('Recording failed: $e');
    }
  }

  Future<void> _stopRec({required bool send}) async {
    _timer?.cancel();
    final ms = _start == null
        ? 0
        : DateTime.now().difference(_start!).inMilliseconds;
    String? path;
    try {
      path = await _rec.stop();
    } catch (_) {}
    path ??= _path;
    setState(() => _recording = false);

    if (!send || path == null || ms < 800) {
      // too short or cancelled — discard
      return;
    }
    setState(() => _uploading = true);
    try {
      final url = await ChatAttachmentService.uploadFile(
          ticketId: widget.ticketId,
          file: File(path),
          contentType: 'audio/mp4');
      await widget.onSend(
        messageType: 'voice',
        attachments: [url],
        metadata: {'duration_ms': ms},
      );
    } catch (e) {
      _snack('Voice upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_uploading) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
            width: 20,
            height: 20,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: widget.accent)),
      );
    }
    return GestureDetector(
      onLongPressStart: (_) => _startRec(),
      onLongPressEnd: (_) => _stopRec(send: true),
      onLongPressCancel: () => _stopRec(send: false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: _recording
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.fiber_manual_record, color: StatusColors.danger, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${_elapsed.inMinutes}:${(_elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: StatusColors.danger),
                ),
              ])
            : Icon(Icons.mic_rounded, color: widget.accent),
      ),
    );
  }
}
