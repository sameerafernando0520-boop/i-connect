// lib/providers/permissions_provider.dart
//
// Caches the logged-in marketing_admin's permission record.
// Drives dynamic navigation and feature visibility throughout the marketer portal.

import 'package:flutter/foundation.dart';
import '../config/supabase_config.dart';

class PermissionsProvider extends ChangeNotifier {
  Map<String, bool>? _perms;
  bool _isLoading = false;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Returns true if permissions have been loaded
  bool get isLoaded => _perms != null;

  // ── 9 permission getters ────────────────────────────────────────────────────
  bool get canViewCustomers    => _perms?['customers']        ?? false;
  bool get canViewReferral     => _perms?['referral_program'] ?? false;
  bool get canViewTiers        => _perms?['loyalty_tiers']    ?? false;
  bool get canManageBanners    => _perms?['banners']          ?? false;
  bool get canManageKnowledge  => _perms?['knowledge_base']   ?? false;
  bool get canBroadcast        => _perms?['broadcast']        ?? false;
  bool get canViewAnalytics    => _perms?['analytics']        ?? false;
  bool get canViewCatalog      => _perms?['machine_catalog']  ?? false;
  bool get canViewPoints       => _perms?['point_activities'] ?? false;

  /// Returns a flat map of all permissions (for display / debugging)
  Map<String, bool> get all => Map.unmodifiable(_perms ?? {});

  /// Count of enabled permissions
  int get enabledCount => _perms?.values.where((v) => v).length ?? 0;

  // ── Load ────────────────────────────────────────────────────────────────────
  Future<void> load() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) {
      clear();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await SupabaseConfig.client
          .from('marketer_permissions')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (res != null) {
        _perms = {
          'customers':        (res['customers']        as bool?) ?? false,
          'referral_program': (res['referral_program'] as bool?) ?? false,
          'loyalty_tiers':    (res['loyalty_tiers']    as bool?) ?? false,
          'banners':          (res['banners']           as bool?) ?? false,
          'knowledge_base':   (res['knowledge_base']   as bool?) ?? false,
          'broadcast':        (res['broadcast']         as bool?) ?? false,
          'analytics':        (res['analytics']         as bool?) ?? false,
          'machine_catalog':  (res['machine_catalog']   as bool?) ?? false,
          'point_activities': (res['point_activities']  as bool?) ?? false,
        };
      } else {
        // Row not found — default everything to false
        _perms = {
          'customers': false,
          'referral_program': false,
          'loyalty_tiers': false,
          'banners': false,
          'knowledge_base': false,
          'broadcast': false,
          'analytics': false,
          'machine_catalog': false,
          'point_activities': false,
        };
      }
      _error = null;
    } catch (e) {
      _error = e.toString();
      debugPrint('⚠️ PermissionsProvider.load failed: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Clear ───────────────────────────────────────────────────────────────────
  void clear() {
    _perms = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  // ── Check by key ────────────────────────────────────────────────────────────
  bool check(String key) => _perms?[key] ?? false;
}
