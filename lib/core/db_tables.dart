/// Supabase table / view names used by the app.
abstract final class DbTables {
  /// Station water refill options. Uses legacy `products` table; optional
  /// `water_options` view alias — see supabase/migrations/20260528_02_water_options_view.sql.
  static const waterOptions = 'products';
}
