import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../constants.dart';
import '../water_types.dart';
import 'app_cached_image.dart';
import 'press_bounce.dart';
import 'refill_status_widgets.dart';

import 'package:erefill/core/utils/money.dart';
/// Full-width search field for finding nearby water stations.
class RefillSearchBar extends StatelessWidget {
  final String hint;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final bool readOnly;

  const RefillSearchBar({
    super.key,
    this.hint = 'Search nearby water stations',
    this.onTap,
    this.onChanged,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    if (onTap != null || readOnly) {
      return Material(
        color: AppUi.surfaceOf(context),
        borderRadius: AppUi.pillRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppUi.pillRadius,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: AppUi.pillRadius,
              border: Border.all(color: AppUi.borderOf(context)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: AppUi.textSecondaryOf(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hint,
                    style: AppUi.captionText.copyWith(
                      fontSize: 13,
                      color: AppUi.textSecondaryOf(context),
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppUi.textSecondaryOf(context),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return TextField(
      onChanged: onChanged,
      decoration: AppUi.fieldDecorationOf(
        context,
        hint,
        prefixIcon: Icon(
          Icons.search_rounded,
          color: AppUi.textSecondaryOf(context),
        ),
      ),
    );
  }
}

/// Horizontal filter chips for water types.
class WaterTypeFilterChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;
  final bool includeAll;

  const WaterTypeFilterChips({
    super.key,
    required this.selected,
    required this.onSelected,
    this.includeAll = true,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      if (includeAll) 'all',
      ...WaterTypes.all.map((t) => t.shortName),
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppUi.spacingSm),
        itemBuilder: (context, index) {
          final value = options[index];
          final isSelected = selected == value;
          final label = value == 'all'
              ? 'All water types'
              : WaterTypes.byName(value).shortName;

          return ChoiceChip(
            label: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            selected: isSelected,
            onSelected: (_) => onSelected(value),
            selectedColor: AppUi.bluePrimary,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : AppUi.textSecondaryOf(context),
            ),
          );
        },
      ),
    );
  }
}

/// Station card for list and grid views.
class StationCard extends StatelessWidget {
  final Map<String, dynamic> station;
  final VoidCallback? onTap;
  final bool compact;
  final bool showFavorite;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;
  final String? distanceLabel;

  const StationCard({
    super.key,
    required this.station,
    this.onTap,
    this.compact = false,
    this.showFavorite = false,
    this.isFavorite = false,
    this.onFavoriteToggle,
    this.distanceLabel,
  });

  String get _name {
    final stationName = station['station_name']?.toString().trim();
    if (stationName != null && stationName.isNotEmpty) return stationName;
    return station['full_name']?.toString() ?? 'Water Station';
  }

  @override
  Widget build(BuildContext context) {
    if (compact) return _buildGridCard(context);
    return _buildListCard(context);
  }

  Widget _buildGridCard(BuildContext context) {
    final barangay = station['barangay']?.toString() ?? '';
    final town = station['town']?.toString() ?? '';
    final location = [barangay, town].where((part) => part.isNotEmpty).join(', ');
    final rating = (station['average_rating'] as num?)?.toDouble() ?? 0.0;
    final price = (station['price_per_gallon'] as num?)?.toDouble();
    final availability =
        station['station_availability']?.toString() ??
        ((station['is_open'] as bool? ?? true) ? 'open' : 'closed');
    final photoUrl = station['station_photo_url']?.toString();

    final bool isClosed = availability.toLowerCase() == 'closed';

    return Opacity(
      opacity: isClosed ? 0.65 : 1.0,
      child: Material(
        color: AppUi.surfaceOf(context),
        borderRadius: AppUi.cardRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppUi.cardRadius,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppUi.cardRadius,
              border: Border.all(color: AppUi.borderOf(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppUi.brandSoftOf(context),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppUi.radiusCard),
                        ),
                      ),
                      child: AppCachedImage(
                        imageUrl: photoUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 480,
                        memCacheHeight: 480,
                        placeholder: _placeholderIcon(),
                        errorWidget: _placeholderIcon(),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: StationAvailabilityBadge(availability: availability),
                    ),
                    if (showFavorite)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Material(
                          color: Colors.white.withValues(alpha: 0.92),
                          shape: const CircleBorder(),
                          child: InkWell(
                            onTap: onFavoriteToggle,
                            customBorder: const CircleBorder(),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                isFavorite
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 18,
                                color: isFavorite
                                    ? AppUi.error
                                    : AppUi.textSecondaryOf(context),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppUi.sectionTitle.copyWith(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          Icons.verified_rounded,
                          size: 13,
                          color: AppUi.brandOf(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      location.isEmpty ? 'Location unavailable' : location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppUi.captionText.copyWith(
                        color: AppUi.textSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 14, color: AppColors.uiWarning),
                        const SizedBox(width: 3),
                        Text(
                          rating > 0 ? rating.toStringAsFixed(1) : 'New',
                          style: AppUi.captionText.copyWith(
                            color: AppUi.textSecondaryOf(context),
                          ),
                        ),
                        if (price != null && price > 0) ...[
                          const Spacer(),
                          Text(
                            '₱${_formatPrice(price)}/gal',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              color: AppUi.brandOf(context),
                            ),
                          ),
                        ] else ...[
                          const Spacer(),
                          Text(
                            'Price not listed',
                            style: AppUi.captionText.copyWith(
                              color: AppUi.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildListCard(BuildContext context) {
    final barangay = station['barangay']?.toString() ?? '';
    final town = station['town']?.toString() ?? '';
    final location = [barangay, town].where((s) => s.isNotEmpty).join(', ');
    final rating = (station['average_rating'] as num?)?.toDouble() ?? 0.0;
    final reviewCount = (station['review_count'] as num?)?.toInt() ?? 0;
    final price = (station['price_per_gallon'] as num?)?.toDouble();
    final availability =
        station['station_availability']?.toString() ??
        ((station['is_open'] as bool? ?? true) ? 'open' : 'closed');
    final photoUrl = station['station_photo_url']?.toString();
    final bool isClosed = availability.toLowerCase() == 'closed';

    return Opacity(
      opacity: isClosed ? 0.65 : 1.0,
      child: Material(
        color: AppUi.surfaceOf(context),
        borderRadius: AppUi.cardRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppUi.cardRadius,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: AppUi.cardDecorationOf(context),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppUi.radiusControl),
                child: SizedBox(
                  width: 68,
                  height: 68,
                  child: AppCachedImage(
                    imageUrl: photoUrl,
                    width: 68,
                    height: 68,
                    fit: BoxFit.cover,
                    memCacheWidth: 180,
                    memCacheHeight: 180,
                    fallbackIcon: Icons.water_drop_rounded,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppUi.sectionTitle,
                          ),
                        ),
                        if (showFavorite)
                          IconButton(
                            tooltip: isFavorite
                                ? 'Remove favorite'
                                : 'Add favorite',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: 36,
                              height: 36,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: onFavoriteToggle,
                            icon: Icon(
                              isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 20,
                              color: isFavorite
                                  ? AppUi.error
                                  : AppUi.textSecondaryOf(context),
                            ),
                          ),
                      ],
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppUi.captionText.copyWith(
                          color: AppUi.textSecondaryOf(context),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StationAvailabilityBadge(availability: availability),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: AppUi.bluePrimary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppUi.radiusSm),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_rounded,
                                size: 12,
                                color: AppUi.brandOf(context),
                              ),
                              SizedBox(width: 3),
                              Text(
                                'Sanitary Verified',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0369A1),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _StationCardMeta(
                          icon: Icons.star_rounded,
                          label: reviewCount > 0
                              ? '${rating.toStringAsFixed(1)} · $reviewCount reviews'
                              : 'New station',
                          iconColor: AppColors.uiWarning,
                        ),
                        if (distanceLabel != null &&
                            distanceLabel!.isNotEmpty)
                          _StationCardMeta(
                            icon: Icons.near_me_outlined,
                            label: distanceLabel!,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      price != null && price > 0
                          ? '₱${_formatPrice(price)} / gallon'
                          : 'Price not listed',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: price != null && price > 0
                                ? AppUi.brandOf(context)
                                : AppUi.textSecondaryOf(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
              if (!showFavorite)
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppUi.textSecondaryOf(context),
                ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  String _formatPrice(double price) {
    return price % 1 == 0
        ? price.toStringAsFixed(0)
        : price.toStringAsFixed(2);
  }

  Widget _placeholderIcon() {
    return Container(
      color: AppUi.blueSoft,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.water_drop_rounded,
                size: 28,
                color: AppUi.bluePrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Water Station',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppUi.bluePrimary,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationCardMeta extends StatelessWidget {
  const _StationCardMeta({
    required this.icon,
    required this.label,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: iconColor ?? AppUi.textSecondaryOf(context),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: AppUi.captionText.copyWith(
            color: AppUi.textSecondaryOf(context),
          ),
        ),
      ],
    );
  }
}

/// Small badge for station open/closed/busy/maintenance status.
class StationAvailabilityBadge extends StatelessWidget {
  final String availability;

  const StationAvailabilityBadge({super.key, required this.availability});

  @override
  Widget build(BuildContext context) {
    final normalized = availability.toLowerCase();
    late Color bg;
    late Color fg;
    late String label;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (normalized) {
      case 'open':
        bg = isDark ? const Color(0xFF153B31) : AppUi.successBg;
        fg = isDark ? const Color(0xFF7DE0B3) : AppUi.successFg;
        label = 'Open';
      case 'busy':
        bg = isDark ? const Color(0xFF3D321E) : AppUi.warningBg;
        fg = isDark ? const Color(0xFFFFD27A) : AppUi.warningFg;
        label = 'Busy';
      case 'maintenance':
        bg = isDark ? const Color(0xFF3D321E) : AppUi.warningBg;
        fg = isDark ? const Color(0xFFFFD27A) : AppUi.warningFg;
        label = 'Maintenance';
      case 'closed':
      default:
        bg = isDark ? AppUi.darkSurfaceRaised : const Color(0xFFF3F4F6);
        fg = AppUi.textSecondaryOf(context);
        label = 'Closed';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppUi.radiusSm),
        border: Border.all(color: fg.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            normalized == 'open'
                ? Icons.check_circle_rounded
                : (normalized == 'busy'
                    ? Icons.access_time_rounded
                    : Icons.circle),
            size: 9,
            color: fg,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// One-tap reorder from home.
class QuickOrderCard extends StatelessWidget {
  const QuickOrderCard({
    super.key,
    required this.stationName,
    required this.subtitle,
    required this.onTap,
  });

  final String stationName;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppUi.bluePrimary,
      borderRadius: AppUi.cardRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppUi.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppUi.radiusCard),
                ),
                child: const Icon(
                  Icons.flash_on_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick order',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stationName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Summary stat card for owner and rider dashboards.
/// Supports optional [trend] sparkline data and [delta] percentage chip.
class DashboardStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  /// Optional 7-point sparkline data (oldest → newest). When provided,
  /// a mini LineChart is rendered at the bottom of the card.
  final List<double>? trend;

  /// Optional delta string, e.g. '+12%' or '-3%'. Shown as a chip above
  /// the label when [trend] is non-null.
  final String? delta;

  const DashboardStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.onTap,
    this.trend,
    this.delta,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppUi.bluePrimary;
    final hasTrend = trend != null && trend!.length >= 2;
    final isPositive = delta?.startsWith('+') ?? true;

    return RepaintBoundary(
      child: PressBounce(
        onTap: onTap,
        pressedScale: 0.985,
        child: Container(
          decoration: AppUi.cardDecorationOf(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top accent stripe
              Container(
                height: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent, accent.withValues(alpha: 0.35)],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppUi.radiusCard),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppUi.radiusControl),
                          ),
                          child: Icon(icon, size: 18, color: accent),
                        ),
                        if (hasTrend && delta != null) ...[
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isPositive
                                  ? AppUi.accentGreen.withValues(alpha: 0.12)
                                  : AppUi.error.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(AppUi.radiusFull),
                            ),
                            child: Text(
                              delta!,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isPositive
                                    ? AppUi.accentGreen
                                    : AppUi.error,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.0, 0.2),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Text(
                        value,
                        key: ValueKey(value),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppUi.textPrimaryOf(context),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(label, style: AppUi.captionText),
                    if (hasTrend) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 30,
                        child: _SparklineChart(data: trend!, color: accent),
                      ),
                      const SizedBox(height: 6),
                    ] else
                      const SizedBox(height: 14),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Minimal sparkline LineChart using fl_chart.
class _SparklineChart extends StatelessWidget {
  final List<double> data;
  final Color color;

  const _SparklineChart({required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    if (data.length < 2) return const SizedBox.shrink();

    final spots = data.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value);
    }).toList();

    final minY = data.reduce((a, b) => a < b ? a : b);
    final maxY = data.reduce((a, b) => a > b ? a : b);
    final yPad = (maxY - minY) == 0 ? 1.0 : (maxY - minY) * 0.2;

    return LineChart(
      LineChartData(
        minY: minY - yPad,
        maxY: maxY + yPad,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: color,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.22),
                  color.withValues(alpha: 0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Active order summary card for customer home.
class ActiveOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final String statusLabel;
  final VoidCallback? onTap;

  const ActiveOrderCard({
    super.key,
    required this.order,
    this.statusLabel = 'Active order',
    this.onTap,
  });

  int _currentStage(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'out_for_delivery':
      case 'delivering':
        return 2;
      case 'preparing':
      case 'ready':
      case 'ready_for_pickup':
      case 'assigned_to_rider':
      case 'rider_assigned':
        return 1;
      default:
        return 0; // pending, accepted
    }
  }

  @override
  Widget build(BuildContext context) {
    final stationName =
        (order['profiles'] as Map<String, dynamic>?)?['station_name'] ??
        order['station_name']?.toString() ??
        'Water station';
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final status = order['status']?.toString();
    final paymentMethod =
        (order['payment_method'] ?? 'cod').toString().toLowerCase();
    final paymentStatus =
        (order['payment_status'] ?? 'pending').toString().toLowerCase();
    final isOnline = {'gcash', 'maya', 'card'}.contains(paymentMethod);
    final isPaid = paymentStatus == 'success' || paymentStatus == 'paid';
    final stage = _currentStage(status);

    final statusColor = OrderStatusColors.getColor(status);

    return Material(
      color: AppUi.surfaceOf(context),
      borderRadius: AppUi.cardRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppUi.cardRadius,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: AppUi.cardDecorationOf(context, elevated: true),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Live status dot, station name, and total
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      stationName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatPeso(total, whole: true),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Status Badge and Action Prompt
              Row(
                children: [
                  OrderStatusBadge(status: status, showIcon: true),
                  const Spacer(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Track order',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: statusColor,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 3-step progress track
              Row(
                children: [
                  _buildStageStep(
                    context,
                    label: 'Placed',
                    isDone: stage >= 0,
                    isActive: stage == 0,
                    statusColor: statusColor,
                  ),
                  _buildStageLine(context, isDone: stage >= 1, statusColor: statusColor),
                  _buildStageStep(
                    context,
                    label: 'Preparing',
                    isDone: stage >= 1,
                    isActive: stage == 1,
                    statusColor: statusColor,
                  ),
                  _buildStageLine(context, isDone: stage >= 2, statusColor: statusColor),
                  _buildStageStep(
                    context,
                    label: 'On the Way',
                    isDone: stage >= 2,
                    isActive: stage == 2,
                    statusColor: statusColor,
                  ),
                ],
              ),

              if (isOnline && !isPaid) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.uiWarningBg,
                    borderRadius: BorderRadius.circular(AppUi.radiusControl),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.payment_rounded, size: 14, color: AppColors.uiWarning),
                      SizedBox(width: 6),
                      Text(
                        'Awaiting online payment',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.uiWarning,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStageStep(
    BuildContext context, {
    required String label,
    required bool isDone,
    required bool isActive,
    required Color statusColor,
  }) {
    final color = isDone ? statusColor : AppUi.borderOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: isDone ? statusColor : AppUi.surfaceRaisedOf(context),
            shape: BoxShape.circle,
            border: Border.all(
              color: color,
              width: isActive ? 2 : 1,
            ),
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                : Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppUi.textSecondaryOf(context).withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isDone ? FontWeight.w700 : FontWeight.w500,
            color: isDone ? AppUi.textPrimaryOf(context) : AppUi.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildStageLine(BuildContext context, {required bool isDone, required Color statusColor}) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 14),
        color: isDone ? statusColor : AppUi.borderOf(context),
      ),
    );
  }
}

/// Water-focused empty state presets.
class RefillEmptyStates {
  static const noStations = (
    icon: Icons.water_drop_outlined,
    title: 'No water stations nearby',
    message: 'We could not find refill stations in your area yet. Try updating your location or check back later.',
  );

  static const noOrders = (
    icon: Icons.receipt_long_outlined,
    title: 'No refill orders yet',
    message: 'Browse nearby water stations and place your first water refill order.',
  );

  static const noDeliveries = (
    icon: Icons.local_shipping_outlined,
    title: 'No deliveries assigned',
    message: 'New delivery tasks from your station will appear here.',
  );

  static const noMessages = (
    icon: Icons.chat_bubble_outline_rounded,
    title: 'No conversations',
    message: 'Messages with customers, riders, or support will show up here.',
  );

  static const noWaterPricing = (
    icon: Icons.water_drop_outlined,
    title: 'No water prices set',
    message: 'Add prices for Purified, Mineral, and Alkaline water so customers can order refills.',
  );
}
