// Progressive/tiered data loading helper.
// Enables dashboards to show critical data immediately while loading details
// in background tiers.

import 'package:flutter/foundation.dart';

typedef DataLoader<T> = Future<T> Function();

/// Manages tiered data loading with callbacks for each tier.
/// Tier 1: Critical data (shown immediately)
/// Tier 2: Important data (shown after Tier 1 completes)
/// Tier 3: Nice-to-have data (loaded in background)
class TieredDataLoader {
  /// Load data in three tiers with callbacks for each.
  ///
  /// Example:
  /// ```dart
  /// await TieredDataLoader.load(
  ///   tier1: [() => _repo.getName(), () => _repo.getStats()],
  ///   tier2: [() => _repo.getPhoto()],
  ///   tier3: [() => _repo.getEscalations()],
  ///   onTier1Complete: (results) => setState(() { ... }),
  ///   onTier2Complete: (results) => setState(() { ... }),
  ///   onTier3Complete: (results) => setState(() { ... }),
  /// );
  /// ```
  static Future<List<dynamic>> load({
    required List<DataLoader<dynamic>> tier1,
    required List<DataLoader<dynamic>> tier2,
    required List<DataLoader<dynamic>> tier3,
    required void Function(List<dynamic>) onTier1Complete,
    required void Function(List<dynamic>) onTier2Complete,
    required void Function(List<dynamic>) onTier3Complete,
    Duration tier2Delay = const Duration(milliseconds: 500),
  }) async {
    final allResults = <dynamic>[];

    try {
      // ── Tier 1: Load immediately ──
      final tier1Results = await Future.wait(tier1.map((loader) => loader()));
      allResults.addAll(tier1Results);
      onTier1Complete(tier1Results);

      // ── Tier 2: Load after a small delay (prevents UI jank) ──
      await Future.delayed(tier2Delay);
      final tier2Results = await Future.wait(tier2.map((loader) => loader()));
      allResults.addAll(tier2Results);
      onTier2Complete(tier2Results);

      // ── Tier 3: Load in background (fire-and-forget) ──
      Future.wait(tier3.map((loader) => loader())).then((tier3Results) {
        allResults.addAll(tier3Results);
        onTier3Complete(tier3Results);
      }).catchError((Object e) {
        // Tier 3 failures are non-fatal.
        debugPrint('⚠️ Tier 3 data load failed: $e');
      });

      return allResults;
    } catch (e) {
      debugPrint('❌ Data loading failed: $e');
      rethrow;
    }
  }

  /// Streamed variant: emits partial results for each tier as it completes.
  static Stream<TierResult<T>> loadStream<T>({
    required List<DataLoader<T>> tier1,
    required List<DataLoader<T>> tier2,
    required List<DataLoader<T>> tier3,
    Duration tier2Delay = const Duration(milliseconds: 500),
  }) async* {
    // Tier 1
    final tier1Results = await Future.wait(tier1.map((loader) => loader()));
    yield TierResult<T>(tier: 1, data: tier1Results);

    // Tier 2
    await Future.delayed(tier2Delay);
    final tier2Results = await Future.wait(tier2.map((loader) => loader()));
    yield TierResult<T>(tier: 2, data: tier2Results);

    // Tier 3
    final tier3Results = await Future.wait(tier3.map((loader) => loader()));
    yield TierResult<T>(tier: 3, data: tier3Results, isComplete: true);
  }
}

/// Result from a tier in tiered loading.
class TierResult<T> {
  final int tier;
  final List<T> data;
  final bool isComplete;

  TierResult({
    required this.tier,
    required this.data,
    this.isComplete = false,
  });
}
