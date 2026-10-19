import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../providers/notification_provider.dart';
import '../../theme/app_theme.dart';
import '../navigation/app_nav_leading.dart';

Color _heroTextColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? Colors.white
    : AppUi.textPrimary;

Color _heroSubtleTextColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? Colors.white.withValues(alpha: 0.85)
    : AppUi.textSecondary;

Color _heroIconSurfaceColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? Colors.white.withValues(alpha: 0.08)
    : Colors.black.withValues(alpha: 0.04);

Widget _wrapHeroOverlay(BuildContext context, Widget child) {
  return AnnotatedRegion<SystemUiOverlayStyle>(
    value: AppTheme.systemUiOverlayStyle(context, isHero: true),
    child: child,
  );
}

/// Packgeon-style hero header for customer dashboards.
class CustomerHeroHeader extends StatelessWidget {
  final String greeting;
  final String location;
  final Widget? searchBar;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onFavoritesTap;
  final VoidCallback? onLocationTap;
  final int notificationCount;
  final int favoritesCount;

  const CustomerHeroHeader({
    super.key,
    required this.greeting,
    required this.location,
    this.searchBar,
    this.onNotificationTap,
    this.onFavoritesTap,
    this.onLocationTap,
    this.notificationCount = 0,
    this.favoritesCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final onHero = _heroTextColor(context);
    final onHeroSoft = _heroSubtleTextColor(context);

    return _wrapHeroOverlay(
      context,
      Container(
        width: double.infinity,
        decoration: BoxDecoration(color: AppUi.heroColorOf(context)),
        padding: EdgeInsets.fromLTRB(
          AppUi.screenPadding,
          top + 8,
          AppUi.screenPadding,
          AppUi.spacingMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        greeting,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: onHero,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: onLocationTap,
                        borderRadius: BorderRadius.circular(AppUi.radiusControl),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                size: 14,
                                color: onHeroSoft,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  location,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: onHeroSoft,
                                  ),
                                ),
                              ),
                              if (onLocationTap != null) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                  color: onHeroSoft,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _HeroIconButton(
                  icon: Icons.notifications_none_rounded,
                  label: 'Notifications',
                  onTap: onNotificationTap,
                  badge: notificationCount,
                  color: onHero,
                ),
                const SizedBox(width: 8),
                _HeroIconButton(
                  icon: Icons.favorite_border_rounded,
                  label: 'Favorites',
                  onTap: onFavoritesTap,
                  badge: favoritesCount,
                  color: onHero,
                ),
              ],
            ),
            if (searchBar != null) ...[const SizedBox(height: 16), searchBar!],
          ],
        ),
      ),
    );
  }
}

class _HeroIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final int badge;
  final Color color;

  const _HeroIconButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.badge = 0,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: _heroIconSurfaceColor(context),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(icon, color: color, size: 22),
              ),
            ),
          ),
          if (badge > 0)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppUi.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  badge > 9 ? '9+' : '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Packgeon-style hero header for station owner dashboards.
class OwnerHeroHeader extends StatelessWidget {
  final String stationName;
  final String location;
  final String availability;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onChatTap;
  final int unreadChatCount;

  const OwnerHeroHeader({
    super.key,
    required this.stationName,
    required this.location,
    required this.availability,
    this.onNotificationTap,
    this.onChatTap,
    this.unreadChatCount = 0,
  });

  String get _statusLabel => switch (availability) {
    'open' => 'Open for refills',
    'busy' => 'Busy — limited orders',
    'maintenance' => 'Under maintenance',
    _ => 'Closed today',
  };

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final titleColor = _heroTextColor(context);
    final subtitleColor = _heroSubtleTextColor(context);
    final pillColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.04);

    return _wrapHeroOverlay(
      context,
      Container(
        width: double.infinity,
        decoration: BoxDecoration(color: AppUi.heroColorOf(context)),
        padding: EdgeInsets.fromLTRB(
          AppUi.screenPadding,
          top + 8,
          AppUi.screenPadding,
          AppUi.spacingMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stationName,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.storefront_rounded,
                            size: 14,
                            color: subtitleColor,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: subtitleColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onChatTap != null) ...[
                  _HeroIconButton(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Messages',
                    onTap: onChatTap,
                    badge: unreadChatCount,
                    color: titleColor,
                  ),
                  const SizedBox(width: 8),
                ],
                _NotificationHeroButton(onTap: onNotificationTap),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: pillColor,
                borderRadius: AppUi.pillRadius,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: availability == 'open'
                          ? AppUi.accentGreen
                          : (Theme.of(context).brightness == Brightness.dark
                                ? Colors.white54
                                : AppUi.textSecondary),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _statusLabel,
                    style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hero header for rider dashboards.
class RiderHeroHeader extends StatelessWidget {
  final String greeting;
  final String subtitle;
  final VoidCallback? onNotificationTap;

  const RiderHeroHeader({
    super.key,
    required this.greeting,
    required this.subtitle,
    this.onNotificationTap,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final titleColor = _heroTextColor(context);
    final subtitleColor = _heroSubtleTextColor(context);

    return _wrapHeroOverlay(
      context,
      Container(
        width: double.infinity,
        decoration: BoxDecoration(color: AppUi.heroColorOf(context)),
        padding: EdgeInsets.fromLTRB(
          AppUi.screenPadding,
          top + 8,
          AppUi.screenPadding,
          AppUi.spacingMd,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greeting,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
            _NotificationHeroButton(onTap: onNotificationTap),
          ],
        ),
      ),
    );
  }
}

class _NotificationHeroButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _NotificationHeroButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    return Selector<NotificationProvider, int>(
      selector: (_, provider) => provider.unreadCount,
      builder: (context, unreadCount, _) => _HeroIconButton(
        icon: Icons.notifications_none_rounded,
        label: 'Notifications',
        onTap: onTap,
        badge: unreadCount,
        color: _heroTextColor(context),
      ),
    );
  }
}

/// Station discovery header with search.
class StationDiscoverHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? searchBar;
  final List<Widget>? actions;

  const StationDiscoverHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.searchBar,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final titleColor = _heroTextColor(context);
    final subtitleColor = _heroSubtleTextColor(context);
    return _wrapHeroOverlay(
      context,
      Container(
        width: double.infinity,
        decoration: BoxDecoration(color: AppUi.heroColorOf(context)),
        padding: EdgeInsets.fromLTRB(
          AppUi.screenPadding,
          top + 8,
          AppUi.screenPadding,
          AppUi.spacingLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (context.canPop()) ...[
                  const HeroBackButton(),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: subtitleColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ...?actions,
              ],
            ),
            if (searchBar != null) ...[const SizedBox(height: 14), searchBar!],
          ],
        ),
      ),
    );
  }
}

/// Reusable hero header for tab screens (orders, dispatch, account).
class TabScreenHeroHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? bottom;
  final Widget? leading;
  final List<Widget>? actions;

  const TabScreenHeroHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.bottom,
    this.leading,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final effectiveLeading =
        leading ?? (context.canPop() ? const HeroBackButton() : null);
    final titleColor = _heroTextColor(context);
    final subtitleColor = _heroSubtleTextColor(context);

    return _wrapHeroOverlay(
      context,
      Container(
        width: double.infinity,
        decoration: BoxDecoration(color: AppUi.heroColorOf(context)),
        padding: EdgeInsets.fromLTRB(
          AppUi.screenPadding,
          top + 8,
          AppUi.screenPadding,
          AppUi.spacingMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (effectiveLeading != null) ...[
                  effectiveLeading,
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: subtitleColor,
                        ),
                      ),
                    ],
                  ),
                ),
                ...?actions,
              ],
            ),
            if (bottom != null) ...[const SizedBox(height: 14), bottom!],
          ],
        ),
      ),
    );
  }
}

/// Promo banner for browse CTA.
class RefillPromoBanner extends StatelessWidget {
  final VoidCallback? onTap;

  const RefillPromoBanner({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(AppUi.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        child: Container(
          height: 120,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppUi.radiusCard),
            color: AppUi.bluePrimary,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Find water stations',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Browse nearby\nrefill stations',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.water_drop_rounded,
                size: 72,
                color: Colors.white.withValues(alpha: 0.25),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
