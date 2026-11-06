import 'package:erefill/core/water_types.dart';

/// Mirrors the rows seeded by supabase/scripts/single_water_product_catalog.sql.
const testPurified = WaterTypeInfo(
  id: '00000000-0000-0000-0000-000000000001',
  name: 'Purified Water',
  shortName: 'Purified',
  tagline: 'Ultra-clean, every drop',
  description: 'Reverse-osmosis filtered for a pure, neutral taste.',
  badge: 'Ultra Clean',
  benefits: ['RO filtered', 'Neutral taste', 'Family safe'],
  iconKey: 'water_drop',
  sortOrder: 10,
);

const testMineral = WaterTypeInfo(
  id: '00000000-0000-0000-0000-000000000002',
  name: 'Mineral Water',
  shortName: 'Mineral',
  tagline: 'Refreshingly natural',
  description: 'Filtered spring water enriched with calcium and magnesium.',
  badge: 'Natural Minerals',
  benefits: ['Natural minerals', 'Crisp taste', 'Daily hydration'],
  iconKey: 'spa',
  sortOrder: 20,
);

const testAlkaline = WaterTypeInfo(
  id: '00000000-0000-0000-0000-000000000003',
  name: 'Alkaline Water',
  shortName: 'Alkaline',
  tagline: 'Smooth & balanced',
  description: 'Ionized to pH 8.0–9.0 for a smoother taste.',
  badge: 'pH Balanced',
  benefits: ['Higher pH', 'Smooth taste', 'Low acidity'],
  iconKey: 'science',
  sortOrder: 30,
);

const testWaterTypes = [testPurified, testMineral, testAlkaline];

void seedTestWaterTypes() {
  // ignore: invalid_use_of_visible_for_testing_member
  WaterTypes.setCatalog(testWaterTypes);
}
