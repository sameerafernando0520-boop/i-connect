// lib/utils/upload_validator.dart
//
// L7: Centralized upload-validation helper.
//
// Why this file exists before the attachment feature ships:
// The audit flagged that no existing code validates file size or MIME type on
// uploads. Rather than scatter bespoke checks when chat/ticket attachments
// finally land, this module defines the contract up front — size caps,
// allowed MIME types, magic-number sniffing, and a single `validate()`
// entry point every future upload call site can funnel through.
//
// Usage:
//   final result = UploadValidator.validate(
//     bytes: fileBytes,
//     filename: pickedFile.name,
//     mimeTypeHint: pickedFile.mimeType,
//     category: UploadCategory.chatAttachment,
//   );
//   if (!result.ok) {
//     _snack(result.error!, isError: true);
//     return;
//   }

import 'dart:typed_data';

/// Categories let us tune size caps and allow-lists per upload site without
/// littering magic numbers at the call site.
enum UploadCategory {
  /// Profile photos — strict: images only, small.
  profilePhoto,

  /// Generic in-chat attachments (tickets, inquiries, support).
  chatAttachment,

  /// Machine/invoice documents (admin-facing PDF + image).
  document,
}

/// Result of a validation pass. `ok == true` means the bytes can be uploaded;
/// otherwise `error` carries a human-readable reason to show via SnackBar.
class UploadValidationResult {
  final bool ok;
  final String? error;
  final String? detectedMime;

  const UploadValidationResult._(this.ok, this.error, this.detectedMime);

  const UploadValidationResult.success(String detectedMime)
      : this._(true, null, detectedMime);

  const UploadValidationResult.failure(String error)
      : this._(false, error, null);
}

class UploadValidator {
  UploadValidator._();

  // ─── Size caps (bytes) ─────────────────────────────────────
  // Chosen to fit well within Supabase free-tier object limits and keep
  // bandwidth usage sane on mobile.
  static const int _kb = 1024;
  static const int _mb = 1024 * _kb;

  static int _maxSizeFor(UploadCategory cat) {
    switch (cat) {
      case UploadCategory.profilePhoto:
        return 2 * _mb; // 2 MB
      case UploadCategory.chatAttachment:
        return 10 * _mb; // 10 MB
      case UploadCategory.document:
        return 20 * _mb; // 20 MB
    }
  }

  // ─── Allowed MIME types ───────────────────────────────────
  static const Set<String> _imageMimes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic', // iOS camera default
    'image/heif',
  };

  static const Set<String> _documentMimes = {
    'application/pdf',
    'image/jpeg',
    'image/png',
  };

  static Set<String> _allowedFor(UploadCategory cat) {
    switch (cat) {
      case UploadCategory.profilePhoto:
        return _imageMimes;
      case UploadCategory.chatAttachment:
        return {..._imageMimes, ..._documentMimes};
      case UploadCategory.document:
        return _documentMimes;
    }
  }

  // ─── Magic-number sniffers ────────────────────────────────
  // Filename extension and MIME hint from the picker can both be spoofed;
  // sniff the first few bytes as a trust anchor.
  static String? _sniff(Uint8List bytes) {
    if (bytes.length < 12) return null;

    // PNG:  89 50 4E 47 0D 0A 1A 0A
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    // PDF:  25 50 44 46  ("%PDF")
    if (bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return 'application/pdf';
    }
    // WEBP: "RIFF....WEBP"
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    // HEIC / HEIF: bytes 4..11 contain "ftypheic"/"ftypheix"/"ftyphevc" etc.
    // Check for "ftyp" at offset 4 and an HEIC brand at offset 8.
    if (bytes[4] == 0x66 && // f
        bytes[5] == 0x74 && // t
        bytes[6] == 0x79 && // y
        bytes[7] == 0x70) {
      final brand = String.fromCharCodes(bytes.sublist(8, 12));
      if (brand.startsWith('hei') || brand == 'mif1' || brand == 'msf1') {
        return 'image/heic';
      }
    }

    return null;
  }

  /// Validate bytes against the given category. Pass `mimeTypeHint` when the
  /// picker already reports one — it's used as a fallback only if magic-number
  /// sniffing returns nothing (some formats like SVG don't have a clean
  /// binary signature).
  static UploadValidationResult validate({
    required Uint8List bytes,
    required String filename,
    String? mimeTypeHint,
    required UploadCategory category,
  }) {
    // Empty file — reject early so we don't waste a round-trip.
    if (bytes.isEmpty) {
      return const UploadValidationResult.failure('File is empty.');
    }

    // Size cap.
    final cap = _maxSizeFor(category);
    if (bytes.length > cap) {
      final capMb = (cap / _mb).toStringAsFixed(0);
      return UploadValidationResult.failure(
          'File exceeds $capMb MB limit for this upload type.');
    }

    // Prefer sniffed MIME over hint (hints are spoofable, magic numbers are
    // what actually controls how the file renders downstream).
    final sniffed = _sniff(bytes);
    final effective = sniffed ?? mimeTypeHint?.toLowerCase();

    if (effective == null) {
      return UploadValidationResult.failure(
          'Could not determine file type for "$filename".');
    }

    final allowed = _allowedFor(category);
    if (!allowed.contains(effective)) {
      return UploadValidationResult.failure(
          'File type "$effective" is not allowed here.');
    }

    // If the hint disagrees with the sniffed bytes, the file was renamed or
    // tampered with — refuse rather than silently letting a PHP file be
    // uploaded as "image/png".
    if (sniffed != null &&
        mimeTypeHint != null &&
        mimeTypeHint.toLowerCase() != sniffed) {
      return UploadValidationResult.failure(
          'File contents do not match its declared type.');
    }

    return UploadValidationResult.success(effective);
  }
}
