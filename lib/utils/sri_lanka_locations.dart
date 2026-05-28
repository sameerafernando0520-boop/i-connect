// lib/utils/sri_lanka_locations.dart
//
// Static reference data for Sri Lanka's 9 provinces and the 25 districts
// nested under them. Used by:
//   - Customer profile (province + district selection)
//   - Admin customers_management_page (group/sort by province or district)
//   - Admin customer_detail_page (display)
//
// Source: Government of Sri Lanka administrative divisions.

class SriLankaLocations {
  SriLankaLocations._();

  /// Mapping from province → list of districts.
  /// Province names are the canonical English form stored in the DB.
  static const Map<String, List<String>> provinceDistricts = {
    'Western': ['Colombo', 'Gampaha', 'Kalutara'],
    'Central': ['Kandy', 'Matale', 'Nuwara Eliya'],
    'Southern': ['Galle', 'Matara', 'Hambantota'],
    'Northern': ['Jaffna', 'Kilinochchi', 'Mannar', 'Vavuniya', 'Mullaitivu'],
    'Eastern': ['Trincomalee', 'Batticaloa', 'Ampara'],
    'North Western': ['Kurunegala', 'Puttalam'],
    'North Central': ['Anuradhapura', 'Polonnaruwa'],
    'Uva': ['Badulla', 'Monaragala'],
    'Sabaragamuwa': ['Ratnapura', 'Kegalle'],
  };

  /// All 9 provinces, in the canonical display order.
  static List<String> get provinces => provinceDistricts.keys.toList();

  /// All 25 districts, flat list (useful for full-list sort views).
  static List<String> get allDistricts =>
      provinceDistricts.values.expand((d) => d).toList();

  /// Districts for a given province. Returns empty list if province is null
  /// or unrecognised — callers can safely use the result in a dropdown.
  static List<String> districtsOf(String? province) {
    if (province == null) return const [];
    return provinceDistricts[province] ?? const [];
  }

  /// Reverse lookup: which province does this district belong to?
  /// Returns null if district not recognised. Useful when admin sorts by
  /// district and we want to show the province context.
  static String? provinceOf(String? district) {
    if (district == null) return null;
    for (final entry in provinceDistricts.entries) {
      if (entry.value.contains(district)) return entry.key;
    }
    return null;
  }
}
