import 'package:erefill/core/constants.dart';
import 'package:erefill/core/theme/app_colors.dart';
import 'package:erefill/core/widgets/shadcn_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

export 'package:erefill/core/widgets/shadcn_widgets.dart';
export 'package:shadcn_flutter/shadcn_flutter.dart' show LucideIcons;

TextStyle adminScreenTitleStyle(BuildContext context) =>
    AppUi.screenTitle.copyWith(color: AppUi.textPrimaryOf(context));

TextStyle adminSectionTitleStyle(BuildContext context) =>
    AppUi.sectionTitle.copyWith(color: AppUi.textPrimaryOf(context));

TextStyle adminBodyTextStyle(BuildContext context) =>
    AppUi.bodyText.copyWith(color: AppUi.textSecondaryOf(context));

TextStyle adminCaptionTextStyle(BuildContext context) =>
    AppUi.captionText.copyWith(color: AppUi.textSecondaryOf(context));

Color adminMutedTextColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? const Color(0xFFB8C9CE) : AppUi.textMuted;
}

Color adminSemanticErrorColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFFF7B83)
      : AppUi.error;
}

Color adminDestructiveButtonColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFFCA5A5)
      : AppUi.error;
}

Color adminDestructiveButtonForeground(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? AppUi.darkPageBg
      : Colors.white;
}

Color adminStatusColor(BuildContext context, String status) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final s = status.toLowerCase().replaceAll(' ', '_');
  return switch (s) {
    'delivered' || 'completed' || 'open' || 'processed' =>
      isDark ? const Color(0xFF10B981) : AppColors.statusDelivered,
    'out_for_delivery' || 'on_the_way' || 'in_transit' =>
      isDark ? const Color(0xFFFB923C) : AppColors.statusOutForDelivery,
    'preparing' || 'in_preparation' =>
      isDark ? const Color(0xFFA78BFA) : AppColors.statusPreparing,
    'accepted' =>
      isDark ? const Color(0xFF60A5FA) : AppColors.statusAccepted,
    'pending' || 'pending_verification' || 'busy' || 'processing' =>
      isDark ? const Color(0xFFFBBF24) : AppColors.statusPending,
    'cancelled' || 'failed' || 'rejected' || 'suspended' || 'maintenance' =>
      isDark ? const Color(0xFFF87171) : AppColors.statusCancelled,
    _ => isDark ? AppUi.accentCyan : AppUi.bluePrimary,
  };
}

/// Advanced desktop & tablet layout primitives for eRefill Admin console.

class AdminGlassCard extends StatelessWidget {
  const AdminGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.accent,
    this.expand = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? accent;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(padding: padding, child: child);

    if (accent != null) {
      content = Stack(
        children: [
          Positioned(
            left: 0,
            top: 14,
            bottom: 14,
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          content,
        ],
      );
    }

    return Container(
      width: expand ? double.infinity : null,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: AppUi.surfaceOf(context),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppUi.borderOf(context)),
        ),
        child: onTap != null
            ? InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(16),
                child: content,
              )
            : content,
      ),
    );
  }
}

class AdminSectionHeader extends StatelessWidget {
  const AdminSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final titleContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: adminScreenTitleStyle(context)),
        if (subtitle != null) ...[
          AppUi.vGapXs,
          Text(subtitle!, style: adminBodyTextStyle(context)),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleContent,
              if (trailing != null) ...[AppUi.vGapSm, trailing!],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: titleContent),
            trailing ?? const SizedBox.shrink(),
          ],
        );
      },
    );
  }
}

class AdminKpiTile extends StatelessWidget {
  const AdminKpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.delta,
    this.compact = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? delta;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AdminGlassCard(
      padding: EdgeInsets.all(compact ? 16 : 20),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(compact ? 10 : 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: color, size: compact ? 20 : 24),
          ),
          AppUi.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: compact ? 22 : 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppUi.textSecondaryOf(context),
                  ),
                ),
                if (delta != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      delta!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-height workspace for data-heavy admin pages (tables, split views).
class AdminWorkspaceLayout extends StatelessWidget {
  const AdminWorkspaceLayout({
    super.key,
    this.header,
    this.toolbar,
    this.metrics,
    required this.body,
    this.sidePanel,
    this.sideWidth = 360,
    this.onRefresh,
  });

  final Widget? header;
  final Widget? toolbar;
  final Widget? metrics;
  final Widget body;
  final Widget? sidePanel;
  final double sideWidth;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1050;
        final horizontalPadding = compact ? 16.0 : 28.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                AppUi.pageBgOf(context),
                AppUi.pageBgOf(context),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  20,
                  horizontalPadding,
                  0,
                ),
                child: header ?? const SizedBox.shrink(),
              ),
              if (toolbar != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    16,
                    horizontalPadding,
                    0,
                  ),
                  child: toolbar,
                ),
              if (metrics != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    16,
                    horizontalPadding,
                    0,
                  ),
                  child: metrics,
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    16,
                    horizontalPadding,
                    compact ? 16 : 24,
                  ),
                  child: sidePanel == null
                      ? body
                      : compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 3, child: body),
                            AppUi.vGapMd,
                            Expanded(flex: 2, child: sidePanel!),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: body),
                            AppUi.hGapMd,
                            SizedBox(width: sideWidth, child: sidePanel),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Scrollable page for dashboards and forms.
class AdminPageScaffold extends StatelessWidget {
  const AdminPageScaffold({
    super.key,
    required this.child,
    this.header,
    this.actions,
    this.onRefresh,
  });

  final Widget child;
  final Widget? header;
  final List<Widget>? actions;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final horizontalPadding = compact ? 16.0 : 28.0;
        final heading = header ?? const SizedBox.shrink();
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                AppUi.pageBgOf(context),
              ],
            ),
          ),
          child: RefreshIndicator(
            onRefresh: onRefresh ?? () async {},
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    24,
                    horizontalPadding,
                    8,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              heading,
                              if (actions != null && actions!.isNotEmpty) ...[
                                AppUi.vGapSm,
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: actions!,
                                ),
                              ],
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: heading),
                              ...?actions,
                            ],
                          ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    8,
                    horizontalPadding,
                    32,
                  ),
                  sliver: SliverToBoxAdapter(child: child),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class AdminToolbar extends StatelessWidget {
  const AdminToolbar({
    super.key,
    this.searchController,
    this.searchHint = 'Search…',
    this.onSearch,
    this.filters = const [],
    this.actions = const [],
    this.onRefresh,
  });

  final TextEditingController? searchController;
  final String searchHint;
  final VoidCallback? onSearch;
  final List<Widget> filters;
  final List<Widget> actions;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return AdminGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          return Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              if (searchController != null)
                SizedBox(
                  width: compact
                      ? constraints.maxWidth
                      : (constraints.maxWidth * 0.38).clamp(260, 420),
                  child: TextField(
                    controller: searchController,
                    decoration: AppUi.fieldDecorationOf(
                      context,
                      searchHint,
                      prefixIcon: const Icon(Icons.search_rounded),
                    ).copyWith(isDense: true),
                    onSubmitted: (_) => onSearch?.call(),
                  ),
                ),
              ...filters,
              ...actions,
              if (onRefresh != null)
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
          );
        },
      ),
    );
  }
}

class AdminDataPanel extends StatelessWidget {
  const AdminDataPanel({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.emptyMessage,
    this.isEmpty = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final String? emptyMessage;
  final bool isEmpty;

  @override
  Widget build(BuildContext context) {
    return AdminGlassCard(
      expand: true,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AppUi.cardPadding,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: adminSectionTitleStyle(context)),
                      if (subtitle != null)
                        Text(subtitle!, style: adminCaptionTextStyle(context)),
                    ],
                  ),
                ),
                trailing ?? const SizedBox.shrink(),
              ],
            ),
          ),
          Divider(height: 1, color: AppUi.dividerOf(context)),
          Expanded(
            child: isEmpty
                ? AdminEmptyState(message: emptyMessage ?? 'No records found')
                : child,
          ),
        ],
      ),
    );
  }
}

class AdminDetailPanel extends StatelessWidget {
  const AdminDetailPanel({
    super.key,
    required this.title,
    required this.onClose,
    required this.children,
    this.actions,
  });

  final String title;
  final VoidCallback onClose;
  final List<Widget> children;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return AdminGlassCard(
      expand: true,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: AppUi.cardPadding,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: adminSectionTitleStyle(context)),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: AppUi.cardPaddingLoose,
              children: children,
            ),
          ),
          if (actions != null && actions!.isNotEmpty)
            Padding(
              padding: AppUi.cardPadding,
              child: Row(children: actions!),
            ),
        ],
      ),
    );
  }
}

class AdminDetailRow extends StatelessWidget {
  const AdminDetailRow(this.label, this.value, {super.key, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final valueText = Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: AppUi.textPrimaryOf(context),
            ),
          );
          if (constraints.maxWidth < 340) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: adminCaptionTextStyle(context)),
                const SizedBox(height: 3),
                valueText,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(label, style: adminCaptionTextStyle(context)),
              ),
              Expanded(child: valueText),
            ],
          );
        },
      ),
    );
  }
}

class AdminFilterPillItem<T> {
  final T value;
  final String label;
  final IconData? icon;
  final int? count;

  const AdminFilterPillItem({
    required this.value,
    required this.label,
    this.icon,
    this.count,
  });
}

class AdminFilterPills<T> extends StatelessWidget {
  final List<AdminFilterPillItem<T>> items;
  final T selected;
  final ValueChanged<T> onSelected;

  const AdminFilterPills({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: items.map((item) {
          final isSelected = item.value == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: isSelected
                  ? AppUi.bluePrimary
                  : AppUi.surfaceOf(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
                side: BorderSide(
                  color: isSelected
                      ? AppUi.bluePrimary
                      : AppUi.borderOf(context),
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onSelected(item.value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.icon != null) ...[
                        Icon(
                          item.icon,
                          size: 14,
                          color: isSelected ? Colors.white : AppUi.textSecondaryOf(context),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                          color: isSelected ? Colors.white : AppUi.textPrimaryOf(context),
                        ),
                      ),
                      if (item.count != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.22)
                                : Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${item.count}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isSelected ? Colors.white : AppUi.textSecondaryOf(context),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class AdminBadge extends StatelessWidget {
  const AdminBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final backgroundAlpha =
        Theme.of(context).brightness == Brightness.dark ? 0.16 : 0.1;
    final borderAlpha =
        Theme.of(context).brightness == Brightness.dark ? 0.36 : 0.26;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: backgroundAlpha),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: borderAlpha)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminEmptyState extends StatelessWidget {
  const AdminEmptyState({
    super.key,
    required this.message,
    this.subtitle,
    this.icon,
    this.action,
  });

  final String message;
  final String? subtitle;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon ?? LucideIcons.inbox,
                size: 36,
                color: adminMutedTextColor(context),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppUi.textPrimaryOf(context),
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 13,
                  color: AppUi.textSecondaryOf(context),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class AdminLoadingState extends StatelessWidget {
  const AdminLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class AdminErrorState extends StatelessWidget {
  const AdminErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AdminGlassCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: adminSemanticErrorColor(context).withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.circleAlert,
                  color: adminSemanticErrorColor(context),
                  size: 32,
                ),
              ),
              AppUi.vGapMd,
              Text(
                'Something went wrong',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppUi.textSecondaryOf(context)),
              ),
              AppUi.vGapLg,
              ShadcnPrimaryButton(
                onPressed: onRetry,
                icon: LucideIcons.refreshCw,
                text: 'Retry',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminMetricStrip extends StatelessWidget {
  const AdminMetricStrip({super.key, required this.items});

  final List<AdminMetricItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: items
          .map(
            (item) => AdminGlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.icon, size: 18, color: item.color),
                  AppUi.hGapSm,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.value, style: adminSectionTitleStyle(context)),
                      Text(item.label, style: adminCaptionTextStyle(context)),
                    ],
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class AdminMetricItem {
  const AdminMetricItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class AdminKpiGrid extends StatelessWidget {
  const AdminKpiGrid({super.key, required this.children, this.minWidth = 240});

  final List<Widget> children;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = (c.maxWidth / minWidth).floor().clamp(1, 4);
        final w = (c.maxWidth - (cols - 1) * 16) / cols;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: children
              .map((child) => SizedBox(width: w, child: child))
              .toList(),
        );
      },
    );
  }
}

num safeNum(dynamic value, {num fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value;
  if (value is String) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9.-]'), '').trim();
    if (cleaned.isEmpty || cleaned == '-' || cleaned == '.') {
      return fallback;
    }
    return num.tryParse(cleaned) ?? fallback;
  }
  return num.tryParse(value.toString()) ?? fallback;
}

double safeDouble(dynamic value, {double fallback = 0}) {
  return safeNum(value, fallback: fallback).toDouble();
}

int safeInt(dynamic value, {int fallback = 0}) {
  return safeNum(value, fallback: fallback).toInt();
}

String formatPeso(dynamic value) {
  return '₱${safeDouble(value).toStringAsFixed(2)}';
}

String adminFormatDateTime(dynamic raw) {
  if (raw == null) return '—';
  final dt = DateTime.tryParse(raw.toString());
  if (dt == null) return raw.toString();
  return DateFormat('MMM d, yyyy · HH:mm').format(dt.toLocal());
}

/// Unified Admin Form Text Field matching the mobile app's AuthTextField and field decoration.
class AdminTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final String? hint;
  final String? initialValue;
  final IconData? icon;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool enabled;
  final bool readOnly;
  final VoidCallback? onTap;
  final bool obscureText;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;

  const AdminTextField({
    super.key,
    this.controller,
    required this.label,
    this.hint,
    this.initialValue,
    this.icon,
    this.prefixIcon,
    this.suffixIcon,
    this.enabled = true,
    this.readOnly = false,
    this.onTap,
    this.obscureText = false,
    this.maxLines = 1,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.textInputAction,
    this.autofillHints,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: initialValue,
      enabled: enabled,
      readOnly: readOnly,
      onTap: onTap,
      obscureText: obscureText,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 14.5,
        color: AppUi.textPrimaryOf(context),
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        floatingLabelStyle: const TextStyle(
          color: AppUi.bluePrimary,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
        labelStyle: TextStyle(
          color: AppUi.textSecondaryOf(context),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: TextStyle(
          color: adminMutedTextColor(context),
          fontSize: 13.5,
        ),
        filled: true,
        fillColor: AppUi.surfaceOf(context),
        prefixIcon: prefixIcon ??
            (icon != null
                ? Icon(icon, size: 18, color: AppUi.textSecondaryOf(context))
                : null),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppUi.borderOf(context), width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppUi.borderOf(context), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppUi.bluePrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: adminSemanticErrorColor(context),
            width: 1.2,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: adminSemanticErrorColor(context),
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
    );
  }
}

/// Unified Admin Dropdown Form Field matching AdminTextField styling.
class AdminDropdownFormField<T> extends StatelessWidget {
  final T? value;
  final String label;
  final String? hint;
  final IconData? icon;
  final Widget? prefixIcon;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?)? validator;
  final bool enabled;

  const AdminDropdownFormField({
    super.key,
    required this.label,
    required this.items,
    this.value,
    this.hint,
    this.icon,
    this.prefixIcon,
    this.onChanged,
    this.validator,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: enabled ? onChanged : null,
      validator: validator,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 14.5,
        color: AppUi.textPrimaryOf(context),
      ),
      icon: const Icon(LucideIcons.chevronDown, size: 16),
      dropdownColor: AppUi.surfaceOf(context),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        floatingLabelStyle: const TextStyle(
          color: AppUi.bluePrimary,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
        labelStyle: TextStyle(
          color: AppUi.textSecondaryOf(context),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: TextStyle(
          color: adminMutedTextColor(context),
          fontSize: 13.5,
        ),
        filled: true,
        fillColor: AppUi.surfaceOf(context),
        prefixIcon: prefixIcon ??
            (icon != null
                ? Icon(icon, size: 18, color: AppUi.textSecondaryOf(context))
                : null),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppUi.borderOf(context), width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppUi.borderOf(context), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppUi.bluePrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: adminSemanticErrorColor(context),
            width: 1.2,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: adminSemanticErrorColor(context),
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
    );
  }
}

/// Unified Admin Modal Dialog matching the mobile app's rounded sheet and modal styling.
class AdminModalDialog extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final double maxWidth;
  final double maxHeight;
  final Widget child;
  final List<Widget>? actions;
  final VoidCallback? onClose;

  const AdminModalDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.maxWidth = 480,
    this.maxHeight = 680,
    required this.child,
    this.actions,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final effectiveIconColor = iconColor ?? AppUi.bluePrimary;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 24,
        vertical: compact ? 12 : 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppUi.borderOf(context)),
      ),
      backgroundColor: AppUi.surfaceOf(context),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppUi.borderOf(context))),
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: effectiveIconColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 20, color: effectiveIconColor),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppUi.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(LucideIcons.x, size: 18),
                    onPressed: onClose ?? () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: child,
            ),
            if (actions != null && actions!.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: AppUi.borderOf(context))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Unified Admin Prompt Dialog matching the mobile app's styled modal and text field.
Future<String?> showAdminPromptDialog(
  BuildContext context, {
  required String title,
  String? subtitle,
  IconData icon = LucideIcons.messageSquare,
  Color? iconColor,
  String label = 'Reason (optional)',
  String? hint,
  String? initialValue,
  int maxLines = 2,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
}) {
  final controller = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AdminModalDialog(
      title: title,
      subtitle: subtitle,
      icon: icon,
      iconColor: iconColor,
      maxWidth: 440,
      actions: [
        ShadcnOutlineButton(
          height: 38,
          text: cancelLabel,
          onPressed: () => Navigator.pop(ctx),
        ),
        const SizedBox(width: 8),
        ShadcnPrimaryButton(
          height: 38,
          text: confirmLabel,
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: AdminTextField(
          controller: controller,
          label: label,
          hint: hint,
          maxLines: maxLines,
        ),
      ),
    ),
  );
}

/// Unified Admin Confirmation Dialog matching the mobile app's styled modal.
Future<bool?> showAdminConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool isDestructive = false,
  IconData icon = LucideIcons.triangleAlert,
  Color? iconColor,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AdminModalDialog(
      title: title,
      icon: icon,
      iconColor: iconColor ?? (isDestructive ? AppUi.error : AppUi.bluePrimary),
      maxWidth: 440,
      actions: [
        ShadcnOutlineButton(
          height: 38,
          text: cancelLabel,
          onPressed: () => Navigator.pop(ctx, false),
        ),
        const SizedBox(width: 8),
        if (isDestructive)
          ShadcnDestructiveButton(
            height: 38,
            text: confirmLabel,
            onPressed: () => Navigator.pop(ctx, true),
          )
        else
          ShadcnPrimaryButton(
            height: 38,
            text: confirmLabel,
            onPressed: () => Navigator.pop(ctx, true),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          message,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppUi.textSecondaryOf(context),
          ),
        ),
      ),
    ),
  );
}

/// Super-visible Blue Manage Button for cards, tables, and sidebars.
class AdminManageButton extends StatelessWidget {
  const AdminManageButton({
    super.key,
    required this.onPressed,
    this.text = 'Manage',
    this.icon = LucideIcons.slidersHorizontal,
    this.height = 36,
    this.isLoading = false,
    this.compact = false,
  });

  final VoidCallback? onPressed;
  final String text;
  final IconData icon;
  final double height;
  final bool isLoading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const blueColor = Color(0xFF2563EB); // Vivid Tailwind Blue-600
    if (compact) {
      return Tooltip(
        message: text,
        child: SizedBox(
          height: height,
          width: height,
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: blueColor,
              foregroundColor: Colors.white,
              padding: EdgeInsets.zero,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(icon, size: 15, color: Colors.white),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: blueColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        child: isLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 15, color: Colors.white),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Colors.white,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Super-visible Red Suspend Button for cards, tables, and sidebars.
class AdminSuspendButton extends StatelessWidget {
  const AdminSuspendButton({
    super.key,
    required this.onPressed,
    this.text = 'Suspend',
    this.icon = LucideIcons.ban,
    this.height = 36,
    this.isLoading = false,
    this.compact = false,
  });

  final VoidCallback? onPressed;
  final String text;
  final IconData icon;
  final double height;
  final bool isLoading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const redColor = Color(0xFFDC2626); // Vivid Tailwind Red-600
    if (compact) {
      return Tooltip(
        message: text,
        child: SizedBox(
          height: height,
          width: height,
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: redColor,
              foregroundColor: Colors.white,
              padding: EdgeInsets.zero,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(icon, size: 15, color: Colors.white),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: redColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        child: isLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 15, color: Colors.white),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Colors.white,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Super-visible Green Activate / Unsuspend Button for cards, tables, and sidebars.
class AdminActivateButton extends StatelessWidget {
  const AdminActivateButton({
    super.key,
    required this.onPressed,
    this.text = 'Unsuspend',
    this.icon = LucideIcons.lockOpen,
    this.height = 36,
    this.isLoading = false,
    this.compact = false,
  });

  final VoidCallback? onPressed;
  final String text;
  final IconData icon;
  final double height;
  final bool isLoading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const greenColor = Color(0xFF059669); // Vivid Tailwind Emerald-600
    if (compact) {
      return Tooltip(
        message: text,
        child: SizedBox(
          height: height,
          width: height,
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: greenColor,
              foregroundColor: Colors.white,
              padding: EdgeInsets.zero,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(icon, size: 15, color: Colors.white),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: greenColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        child: isLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 15, color: Colors.white),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Colors.white,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

