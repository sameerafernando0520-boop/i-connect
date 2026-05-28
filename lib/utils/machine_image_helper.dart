// lib/utils/machine_image_helper.dart
//
// Centralised image extraction for machine_catalog rows.
//
// machine_catalog rows can carry their primary image in any of three
// fields depending on which admin tool inserted them:
//   - image_url    (string, modern primary)
//   - product_images[0] (array, legacy admin uploads)
//   - images[0]    (array, very early imports)
//
// Each call site that renders a machine card was duplicating the same
// fallback chain. This helper consolidates it so adding a new image
// source (or fixing a bug in the extraction) only happens here.

class MachineImageHelper {
  MachineImageHelper._();

  /// Returns the first non-empty image URL from a machine row, trying
  /// `image_url` → `product_images[0]` → `images[0]`. Returns null if
  /// no usable URL is present.
  static String? primaryImage(Map<String, dynamic> machine) {
    final iu = machine['image_url'];
    if (iu is String && iu.trim().isNotEmpty) return iu;

    final pi = machine['product_images'];
    if (pi is List && pi.isNotEmpty) {
      final first = pi.first;
      if (first is String && first.trim().isNotEmpty) return first;
    }

    final im = machine['images'];
    if (im is List && im.isNotEmpty) {
      final first = im.first;
      if (first is String && first.trim().isNotEmpty) return first;
    }

    return null;
  }

  /// Returns every available image URL across `image_url`,
  /// `product_images`, and `images`, deduplicated and order-preserved
  /// (image_url first, then product_images entries, then images
  /// entries). Useful for galleries.
  static List<String> allImages(Map<String, dynamic> machine) {
    final result = <String>{};

    final iu = machine['image_url'];
    if (iu is String && iu.trim().isNotEmpty) result.add(iu);

    for (final key in const ['product_images', 'images']) {
      final arr = machine[key];
      if (arr is List) {
        for (final v in arr) {
          if (v is String && v.trim().isNotEmpty) result.add(v);
        }
      }
    }

    return result.toList();
  }
}
