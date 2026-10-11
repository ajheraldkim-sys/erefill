import 'package:flutter/material.dart';

import 'constants.dart';

class WaterTypeInfo {
  final String name;
  final String shortName;
  final String tagline;
  final String description;
  final String badge;
  final List<String> benefits;
  final IconData icon;
  final Color color;

  const WaterTypeInfo({
    required this.name,
    required this.shortName,
    required this.tagline,
    required this.description,
    required this.badge,
    required this.benefits,
    required this.icon,
    required this.color,
  });
}

class WaterTypes {
  static const purified = WaterTypeInfo(
    name: 'Purified Water',
    shortName: 'Purified',
    tagline: 'Ultra-clean, every drop',
    description:
        'Reverse-osmosis filtered for a pure, neutral taste — no impurities, no aftertaste.',
    badge: 'Ultra Clean',
    benefits: ['RO filtered', 'Neutral taste', 'Family safe'],
    icon: Icons.water_drop_rounded,
    color: AppUi.bluePrimary,
  );

  static const mineral = WaterTypeInfo(
    name: 'Mineral Water',
    shortName: 'Mineral',
    tagline: 'Refreshingly natural',
    description:
        'Filtered spring water enriched with calcium and magnesium for a crisp, refreshing taste.',
    badge: 'Natural Minerals',
    benefits: ['Natural minerals', 'Crisp taste', 'Daily hydration'],
    icon: Icons.spa_rounded,
    color: AppUi.accentGreen,
  );

  static const alkaline = WaterTypeInfo(
    name: 'Alkaline Water',
    shortName: 'Alkaline',
    tagline: 'Smooth & balanced',
    description:
        'Ionized to pH 8.0–9.0 for a smoother taste and lower acidity.',
    badge: 'pH Balanced',
    benefits: ['Higher pH', 'Smooth taste', 'Low acidity'],
    icon: Icons.science_rounded,
    color: AppUi.accentCyan,
  );

  static const all = [purified, mineral, alkaline];

  static WaterTypeInfo byName(String? value) {
    final normalized = (value ?? '').toLowerCase();
    return all.firstWhere(
      (type) =>
          normalized.contains(type.shortName.toLowerCase()) ||
          normalized.contains(type.name.toLowerCase()),
      orElse: () => purified,
    );
  }
}
