import 'package:flutter/material.dart';
import 'package:erefill/core/constants.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../providers/notification_provider.dart';
import '../routing/app_navigation.dart';
import '../theme/app_theme.dart';

enum ERefillHeaderType { standard, dashboard, search, orderDetail }

class ERefillHeader extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;
  final bool automaticallyImplyLeading;
  final ERefillHeaderType type;
  final Widget? statusBadge;
  final Widget? searchBar;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onProfileTap;
  final bool showNotifications;
  final bool showProfileAvatar;

  const ERefillHeader({
    super.key,
    this.title,
    this.titleWidget,
    this.subtitle,
    this.subtitleWidget,
    this.leading,
    this.actions,
    this.bottom,
    this.centerTitle = false,
    this.automaticallyImplyLeading = true,
    this.type = ERefillHeaderType.standard,
    this.statusBadge,
    this.searchBar,
    this.onNotificationTap,
    this.onProfileTap,
    this.showNotifications = true,
    this.showProfileAvatar = true,
  }) : assert(title != null || titleWidget != null);

  @override
  Size get preferredSize {
    double height = (subtitle == null && subtitleWidget == null)
        ? AppUi.headerHeight
        : AppUi.headerHeightWithSubtitle;
    if (type == ERefillHeaderType.dashboard) {
      height = AppUi.headerHeightWithSubtitle;
    }
    if (type == ERefillHeaderType.search) {
      height = (subtitle == null && subtitleWidget == null) ? 124 : 138;
    }
    return Size.fromHeight(height + (bottom?.preferredSize.height ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final effectiveLeading = leading ?? _buildLeading(context);
    final colorScheme = Theme.of(context).colorScheme;
    return AppBar(
      systemOverlayStyle: AppTheme.systemUiOverlayStyle(context, isHero: false),
      automaticallyImplyLeading: type == ERefillHeaderType.dashboard
          ? false
          : automaticallyImplyLeading,
      leading: effectiveLeading,
      actions: _buildActions(context),
      bottom: bottom,
      centerTitle: centerTitle,
      toolbarHeight: preferredSize.height - (bottom?.preferredSize.height ?? 0),
      backgroundColor: colorScheme.surface,
      foregroundColor: AppUi.textPrimaryOf(context),
      surfaceTintColor: colorScheme.surface,
      elevation: 0,
      titleSpacing: _titleSpacing(effectiveLeading),
      shape: Border(bottom: BorderSide(color: AppUi.borderOf(context))),
      title: _buildTitle(context),
    );
  }

  double _titleSpacing(Widget? effectiveLeading) {
    if (type == ERefillHeaderType.dashboard) return 20;
    return effectiveLeading == null ? 20 : 0;
  }

  Widget? _buildLeading(BuildContext context) {
    if (type == ERefillHeaderType.dashboard) {
      return null; // Dashboard uses custom layout in title
    }

    if (context.canPop() && automaticallyImplyLeading) {
      return IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => context.popRoute(),
      );
    }
    return null;
  }

  List<Widget> _buildActions(BuildContext context) {
    if (type == ERefillHeaderType.dashboard) {
      return [
        if (showNotifications) _buildNotificationBell(context),
        ...?actions,
        if (showProfileAvatar) _buildAvatar(context),
        const SizedBox(width: 12),
      ];
    }

    return [...?actions, const SizedBox(width: 8)];
  }

  Widget _buildTitle(BuildContext context) {
    if (type == ERefillHeaderType.dashboard) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (titleWidget != null)
            titleWidget!
          else
            Text(
              title ?? '',
              style: AppUi.headerTitleStyle.copyWith(
                color: AppUi.textPrimaryOf(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (subtitleWidget != null) ...[
            const SizedBox(height: 3),
            subtitleWidget!,
          ] else if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: AppUi.headerSubtitleStyle.copyWith(
                color: AppUi.textSecondaryOf(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      );
    }

    if (type == ERefillHeaderType.orderDetail) {
      return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (titleWidget != null)
                  titleWidget!
                else
                  Text(
                    title ?? '',
                    style: AppUi.headerTitleStyle.copyWith(
                      color: AppUi.textPrimaryOf(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (subtitleWidget != null) ...[
                  const SizedBox(height: 2),
                  subtitleWidget!,
                ] else if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppUi.headerSubtitleStyle.copyWith(
                      color: AppUi.textSecondaryOf(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          ?statusBadge,
          const SizedBox(width: 12),
        ],
      );
    }

    if (type == ERefillHeaderType.search) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (titleWidget != null)
            titleWidget!
          else
            Text(
              title ?? '',
              style: AppUi.headerTitleStyle.copyWith(
                color: AppUi.textPrimaryOf(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (subtitleWidget != null) ...[
            const SizedBox(height: 3),
            subtitleWidget!,
          ] else if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: AppUi.headerSubtitleStyle.copyWith(
                color: AppUi.textSecondaryOf(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (searchBar != null) ...[const SizedBox(height: 8), searchBar!],
        ],
      );
    }

    // Standard Header
    return Column(
      crossAxisAlignment: centerTitle
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (titleWidget != null)
          titleWidget!
        else
          Text(
            title ?? '',
            style: AppUi.headerTitleStyle.copyWith(
              color: AppUi.textPrimaryOf(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        if (subtitleWidget != null) ...[
          const SizedBox(height: 2),
          subtitleWidget!,
        ] else if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: AppUi.headerSubtitleStyle.copyWith(
              color: AppUi.textSecondaryOf(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _buildAvatar(BuildContext context) {
    return Selector<UserProvider, String>(
      selector: (_, p) {
        final user = p.user;
        final name = user?.firstName ?? user?.fullName ?? 'U';
        return name.isNotEmpty ? name[0].toUpperCase() : 'U';
      },
      builder: (context, initial, _) {
        return GestureDetector(
          onTap: onProfileTap,
          child: Container(
            width: 34,
            height: 34,
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              color: AppUi.brandSoftOf(context),
              shape: BoxShape.circle,
              border: Border.all(color: AppUi.blueBorder, width: 1),
            ),
            child: Center(
              child: Text(
                initial,
                style: TextStyle(
                  color: AppUi.brandOf(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNotificationBell(BuildContext context) {
    return Selector<NotificationProvider, int>(
      selector: (_, p) => p.unreadCount,
      builder: (context, count, _) {
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              onPressed: onNotificationTap,
              icon: Icon(
                Icons.notifications_none_rounded,
                color: AppUi.textPrimaryOf(context),
                size: 24,
              ),
            ),
            if (count > 0)
              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: AppUi.error,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Center(
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
