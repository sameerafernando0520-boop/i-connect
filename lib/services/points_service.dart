import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';
import '../utils/app_logger.dart';

/// Centralized fire-and-forget point awarding.
/// All methods swallow errors — points should NEVER block UI.
class PointsService {
  PointsService._();

  // ── Award to current logged-in user ──

  static void award(
    String activityType,
    int points,
    String description, [
    String? referenceId,
    String? referenceType,
  ]) {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;
    awardTo(userId, activityType, points, description, referenceId, referenceType);
  }

  // ── Award to a specific user (admin → customer) ──

  static void awardTo(
    String userId,
    String activityType,
    int points,
    String description, [
    String? referenceId,
    String? referenceType,
  ]) {
    SupabaseConfig.client
        .rpc('award_points', params: {
          'p_user_id': userId,
          'p_activity_type': activityType,
          'p_base_points': points,
          'p_description': description,
          'p_reference_id': referenceId,
          'p_reference_type': referenceType,
        })
        .then((_) => AppLogger.info('PointsService', '+$points pts ($activityType) → $userId'))
        .catchError((e) => AppLogger.warn('PointsService', 'Award failed ($activityType)', error: e));
  }

  // ── One-time award (SharedPreferences guard for current user) ──

  static Future<void> awardOnce(
    String activityType,
    int points,
    String description,
  ) async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;

      final prefs = await SharedPreferences.getInstance();
      final key = 'pts_${userId}_$activityType';
      if (prefs.getBool(key) == true) return;

      awardTo(userId, activityType, points, description);
      await prefs.setBool(key, true);
    } catch (e) {
      AppLogger.warn('PointsService', 'awardOnce failed ($activityType)', error: e);
    }
  }

  // ── Article read with 5/day limit ──

  static Future<void> articleRead(String articleId) async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;

      final prefs = await SharedPreferences.getInstance();
      // H8: use UTC date so the "5 reads per day" window is identical for
      // every user regardless of local timezone and so users can't bypass
      // the limit by hopping timezones or travelling across the dateline.
      final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final countKey = 'pts_${userId}_reads_$today';
      final artKey = 'pts_${userId}_art_$articleId';

      // Already read this article today
      if (prefs.getBool(artKey) == true) return;

      // Daily limit reached
      final count = prefs.getInt(countKey) ?? 0;
      if (count >= 5) return;

      awardTo(userId, 'article_read', 10, 'Read knowledge base article',
          articleId, 'article');

      await prefs.setInt(countKey, count + 1);
      await prefs.setBool(artKey, true);
    } catch (e) {
      AppLogger.warn('PointsService', 'articleRead failed', error: e);
    }
  }

  // ── Qualify referral on purchase (fire-and-forget) ──

  static void qualifyReferral(
    String customerId,
    double purchaseAmount,
    String machineCategory, [
    String? ticketId,
  ]) {
    SupabaseConfig.client
        .rpc('qualify_referral', params: {
          'p_referred_id': customerId,
          'p_ticket_id': ticketId,
          'p_purchase_amount': purchaseAmount,
          'p_machine_category': machineCategory,
        })
        .then((_) => AppLogger.info('PointsService', 'Referral qualified'))
        .catchError((e) => AppLogger.warn('PointsService', 'Referral qualification skipped', error: e));
  }

  // ── Check if first machine for customer ──

  static Future<int> _machineCount(String customerId) async {
    try {
      final data = await SupabaseConfig.client
          .from('customer_machines')
          .select('id')
          .eq('user_id', customerId);
      return (data as List).length;
    } catch (_) {
      return 999; // Assume not first on error
    }
  }

  /// Award machine purchase points (500 first, 300 subsequent)
  /// + qualify referral
  static Future<void> machinePurchase({
    required String customerId,
    required String machineId,
    required double amount,
    required String category,
    String? ticketId,
  }) async {
    try {
      final count = await _machineCount(customerId);
      // count includes the one just registered
      final points = count <= 1 ? 500 : 300;
      final desc = count <= 1 ? 'First machine purchase!' : 'Machine purchased';

      awardTo(customerId, 'machine_purchase', points, desc, machineId, 'machine');

      // Also qualify referral
      qualifyReferral(customerId, amount, category, ticketId);
    } catch (e) {
      AppLogger.warn('PointsService', 'machinePurchase failed', error: e);
    }
  }
}