// lib/widgets/common/chat_message_attachments.dart
//
// Reusable renderers for non-text chat messages (voice / document / location).
// Driven by ChatMessage-style data: message_type + attachments[] + metadata.
// Shared across the customer, engineer, EA and inquiry chat screens.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

/// Returns the appropriate attachment widget for a message, or null for plain
/// text / unknown types. [isMe] flips colours for own-message bubbles.
Widget? buildChatAttachment({
  required String messageType,
  required List<String> attachments,
  Map<String, dynamic>? metadata,
  required bool isMe,
  required Color accent,
}) {
  switch (messageType) {
    case 'voice':
      if (attachments.isEmpty) return null;
      final ms = (metadata?['duration_ms'] as num?)?.toInt();
      return ChatVoiceBubble(
          url: attachments.first, durationMs: ms, isMe: isMe, accent: accent);
    case 'document':
      if (attachments.isEmpty) return null;
      return ChatDocumentBubble(
        url: attachments.first,
        filename: metadata?['filename'] as String? ?? 'Document',
        size: (metadata?['size'] as num?)?.toInt(),
        isMe: isMe,
        accent: accent,
      );
    case 'location':
      final lat = (metadata?['lat'] as num?)?.toDouble();
      final lng = (metadata?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return ChatLocationBubble(
        lat: lat,
        lng: lng,
        label: metadata?['label'] as String?,
        isMe: isMe,
        accent: accent,
      );
    default:
      return null; // text / image handled by the existing renderers
  }
}

String _fmtDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString();
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

// ── Voice ─────────────────────────────────────────────────────
class ChatVoiceBubble extends StatefulWidget {
  final String url;
  final int? durationMs;
  final bool isMe;
  final Color accent;
  const ChatVoiceBubble({
    super.key,
    required this.url,
    required this.isMe,
    required this.accent,
    this.durationMs,
  });

  @override
  State<ChatVoiceBubble> createState() => _ChatVoiceBubbleState();
}

class _ChatVoiceBubbleState extends State<ChatVoiceBubble> {
  AudioPlayer? _player;
  bool _loading = false;
  bool _playing = false;
  Duration _pos = Duration.zero;
  Duration? _total;
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    if (widget.durationMs != null) {
      _total = Duration(milliseconds: widget.durationMs!);
    }
  }

  Future<void> _toggle() async {
    final p = _player ??= AudioPlayer();
    if (_player != null && _subs.isEmpty) {
      _subs.add(p.positionStream.listen((d) {
        if (mounted) setState(() => _pos = d);
      }));
      _subs.add(p.playerStateStream.listen((s) {
        if (!mounted) return;
        setState(() => _playing = s.playing);
        if (s.processingState == ProcessingState.completed) {
          p.seek(Duration.zero);
          p.pause();
          setState(() => _playing = false);
        }
      }));
    }
    try {
      if (_playing) {
        await p.pause();
      } else {
        if (p.audioSource == null) {
          setState(() => _loading = true);
          final dur = await p.setUrl(widget.url);
          if (mounted) setState(() => _total = dur ?? _total);
        }
        if (mounted) setState(() => _loading = false);
        await p.play();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.isMe ? Colors.white : widget.accent;
    final track = fg.withAlpha(60);
    final total = _total ?? const Duration(seconds: 1);
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (_pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _toggle,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(shape: BoxShape.circle, color: fg.withAlpha(38)),
            child: _loading
                ? Padding(
                    padding: const EdgeInsets.all(11),
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                : Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: fg, size: 22),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 130,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: track,
                  valueColor: AlwaysStoppedAnimation(fg),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Icon(Icons.mic_rounded, size: 12, color: fg.withAlpha(180)),
                const SizedBox(width: 3),
                Text(
                  _playing || _pos > Duration.zero
                      ? _fmtDuration(_pos)
                      : _fmtDuration(total),
                  style: TextStyle(
                      fontSize: 11, color: fg.withAlpha(200), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

// ── Document ──────────────────────────────────────────────────
class ChatDocumentBubble extends StatelessWidget {
  final String url;
  final String filename;
  final int? size;
  final bool isMe;
  final Color accent;
  const ChatDocumentBubble({
    super.key,
    required this.url,
    required this.filename,
    required this.isMe,
    required this.accent,
    this.size,
  });

  IconData get _icon {
    final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart_rounded;
      case 'zip':
      case 'rar':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  String _human(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final fg = isMe ? Colors.white : accent;
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: fg.withAlpha(38), borderRadius: BorderRadius.circular(10)),
            child: Icon(_icon, color: fg, size: 22),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
                const SizedBox(height: 2),
                Text(
                  size != null ? '${_human(size!)} · Tap to open' : 'Tap to open',
                  style: TextStyle(fontSize: 11, color: fg.withAlpha(180)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Location ──────────────────────────────────────────────────
class ChatLocationBubble extends StatelessWidget {
  final double lat;
  final double lng;
  final String? label;
  final bool isMe;
  final Color accent;
  const ChatLocationBubble({
    super.key,
    required this.lat,
    required this.lng,
    required this.isMe,
    required this.accent,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isMe ? Colors.white : accent;
    return GestureDetector(
      onTap: () => launchUrl(
        Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
        mode: LaunchMode.externalApplication,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: fg.withAlpha(38), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.location_on_rounded, color: fg, size: 22),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label?.isNotEmpty == true ? label! : 'Shared location',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
                const SizedBox(height: 2),
                Text('Tap to open in Maps',
                    style: TextStyle(fontSize: 11, color: fg.withAlpha(180))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
