import 'package:flutter/material.dart';

/// Opacity Utilities
/// Provides safe opacity/alpha conversion methods for colors.

extension OpacityExtension on Color {
  /// Convert a [Color] with opacity value (0.0 - 1.0) to use withAlpha() instead.
  /// This properly converts opacity percentages to alpha channel (0-255).
  ///
  /// Example:
  /// ```dart
  /// // Old (inefficient):
  /// Color myColor = Colors.blue.withAlpha(((0.5) * 255).toInt());
  ///
  /// // New (efficient):
  /// Color myColor = Colors.blue.withAlpha((0.5 * 255).toInt());
  /// ```
  Color withOpacityToAlpha(double opacity) {
    assert(opacity >= 0.0 && opacity <= 1.0, 'Opacity must be between 0 and 1');
    return withAlpha((opacity * 255).toInt());
  }

  /// Convenience method - returns with specific alpha value (0-255).
  Color withAlphaPercent(int alphaPercent) {
    assert(alphaPercent >= 0 && alphaPercent <= 100,
        'Alpha percent must be between 0 and 100');
    return withAlpha((alphaPercent / 100 * 255).toInt());
  }
}
