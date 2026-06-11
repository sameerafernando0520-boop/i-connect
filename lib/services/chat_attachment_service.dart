// lib/services/chat_attachment_service.dart
//
// Shared helper for chat attachments (image / document / voice / location).
// Centralises Supabase Storage uploads (bucket: chat-attachments) and the
// platform pickers so the customer / engineer / EA / inquiry chat screens
// don't each re-implement pick → upload.

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../config/supabase_config.dart';
import '../utils/app_logger.dart';

/// A document chosen by the user (file + display name + byte size).
class PickedDoc {
  final File file;
  final String name;
  final int size;
  PickedDoc(this.file, this.name, this.size);
}

class ChatAttachmentService {
  ChatAttachmentService._();

  static final _client = SupabaseConfig.client;
  static const String bucket = 'chat-attachments';

  // ── Uploads ───────────────────────────────────────────────
  /// Upload raw [bytes] under `<ticketId>/<ts>_<uid>.<ext>`; returns public URL.
  static Future<String> uploadBytes({
    required String ticketId,
    required Uint8List bytes,
    required String ext,
    String? contentType,
  }) async {
    final uid = _client.auth.currentUser?.id ?? 'anon';
    final path =
        '$ticketId/${DateTime.now().millisecondsSinceEpoch}_$uid.$ext';
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return _client.storage.from(bucket).getPublicUrl(path);
  }

  /// Upload a [file] from disk; returns public URL.
  static Future<String> uploadFile({
    required String ticketId,
    required File file,
    String? contentType,
  }) async {
    final ext = file.path.contains('.') ? file.path.split('.').last : 'bin';
    final bytes = await file.readAsBytes();
    return uploadBytes(
      ticketId: ticketId,
      bytes: bytes,
      ext: ext,
      contentType: contentType,
    );
  }

  // ── Pickers ───────────────────────────────────────────────
  static Future<File?> pickImage({bool camera = false}) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 80,
    );
    return x == null ? null : File(x.path);
  }

  static Future<PickedDoc?> pickDocument() async {
    final res = await FilePicker.pickFiles(type: FileType.any);
    if (res == null || res.files.isEmpty) return null;
    final f = res.files.first;
    if (f.path == null) return null;
    return PickedDoc(File(f.path!), f.name, f.size);
  }

  /// Current GPS position, requesting permission as needed. Null if unavailable.
  static Future<Position?> currentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition();
    } catch (e) {
      AppLogger.warn('ChatAttachment', 'location failed', error: e);
      return null;
    }
  }

  /// Human-readable file size, e.g. "1.4 MB".
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
