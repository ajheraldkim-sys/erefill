/// Owner station profile reads that tolerate optional columns on remote Supabase.
abstract final class StationQueryHelpers {
  /// Columns safe to request on owner profiles across schema versions.
  static const ownerStationFields =
      'id, station_name, full_name, town, barangay, complete_address, '
      'average_rating, is_open, station_photo_url, primary_water_type, '
      'price_per_gallon, latitude, longitude, lat, lng';

  static Map<String, dynamic> withAvailability(Map<String, dynamic> row) {
    final isOpen = (row['is_open'] as bool?) ?? true;
    return {
      ...row,
      'station_availability':
          row['station_availability']?.toString() ??
          (isOpen ? 'open' : 'closed'),
    };
  }

  static List<Map<String, dynamic>> withAvailabilityAll(
    Iterable<Map<String, dynamic>> rows,
  ) {
    return rows.map((row) => withAvailability(row)).toList();
  }
}
