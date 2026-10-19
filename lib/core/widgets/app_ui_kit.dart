import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants.dart';
import '../theme/app_colors.dart';
import '../utils/money.dart';

export '../theme/app_colors.dart' show StatusTone, StatusToneStyle;
export '../utils/money.dart';

/// Layout breakpoints shared by the mobile apps and the admin console.
class AppBreakpoints {
  static const double compact = 600;
  static const double expanded = 1024;
  static const double contentMaxWidth = 1200;
  static const double formMaxWidth = 640;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compact;
  static bool isExpanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= expanded;
}

/// Centers [child] and caps its width so content stays readable on tablets
/// and desktop instead of stretching edge to edge.
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = AppBreakpoints.contentMaxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Compact pill for any non-order status (payments, accounts, stations,
/// payouts). Pair with [StatusToneStyle.paymentTone] / `accountTone`.
/// Order statuses use `OrderStatusBadge`, which shares the same geometry.
class AppStatusPill extends StatelessWidget {
  final String label;
  final StatusTone tone;
  final IconData? icon;

  const AppStatusPill({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
  });

  /// Pill for a raw payment status string, e.g. `paid`, `failed`.
  factory AppStatusPill.payment(String? status, {Key? key}) => AppStatusPill(
    key: key,
    label: _humanize(status, fallback: 'Unknown'),
    tone: StatusToneStyle.paymentTone(status),
  );

  /// Pill for a raw account / station / rider state, e.g. `active`.
  factory AppStatusPill.account(String? status, {Key? key}) => AppStatusPill(
    key: key,
    label: _humanize(status, fallback: 'Unknown'),
    tone: StatusToneStyle.accountTone(status),
  );

  static String _humanize(String? raw, {required String fallback}) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return fallback;
    final words = s.replaceAll('_', ' ').toLowerCase();
    return words[0].toUpperCase() + words.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final style = StatusToneStyle.of(tone, isDark: AppUi.isDark(context));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: AppUi.fullRadius,
        border: Border.all(color: style.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: style.foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: style.foreground,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Error state with a clear message and a retry action. Use wherever a
/// request can fail so the user is never left with a blank screen.
class AppErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final IconData icon;

  const AppErrorState({
    super.key,
    this.title = 'Something went wrong',
    this.message = 'Check your connection and try again.',
    this.onRetry,
    this.retryLabel = 'Try again',
    this.icon = Icons.error_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrolls instead of overflowing when placed in a short area.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppUi.spacingXl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: StatusToneStyle.of(
                    StatusTone.danger,
                    isDark: AppUi.isDark(context),
                  ).background,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: AppUi.isDark(context) ? AppUi.errorFgDark : AppUi.error,
                  size: 28,
                ),
              ),
              const SizedBox(height: AppUi.spacingLg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppUi.spacingSm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: AppUi.spacingLg),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(retryLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Minus / value / plus stepper with 48 dp targets.
///
/// When the value is at [min] and [onRemove] is provided, the minus button
/// becomes a remove action so customers can drop a line item in one tap.
class QuantitySelector extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final VoidCallback? onRemove;
  final int min;
  final int? max;
  final String itemLabel;
  final bool compact;

  const QuantitySelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.onRemove,
    this.min = 1,
    this.max,
    this.itemLabel = 'item',
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final atMin = value <= min;
    final atMax = max != null && value >= max!;
    final showRemove = atMin && onRemove != null;
    final size = compact ? 40.0 : AppUi.kMinTouchTarget;

    Widget button({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onTap,
      Color? color,
    }) {
      return SizedBox(
        width: size,
        height: size,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            minimumSize: Size(size, size),
            foregroundColor: color ?? AppUi.textPrimaryOf(context),
          ),
          icon: Icon(icon, size: 18),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: AppUi.controlRadius,
        border: Border.all(color: AppUi.borderOf(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            icon: showRemove ? Icons.delete_outline_rounded : Icons.remove_rounded,
            tooltip: showRemove ? 'Remove $itemLabel' : 'Decrease quantity',
            color: showRemove ? AppUi.error : null,
            onTap: showRemove
                ? onRemove
                : (atMin ? null : () => onChanged(value - 1)),
          ),
          Semantics(
            label: 'Quantity',
            value: '$value',
            liveRegion: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 28),
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppUi.textPrimaryOf(context),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          button(
            icon: Icons.add_rounded,
            tooltip: 'Increase quantity',
            onTap: atMax ? null : () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

/// One line in a [PriceBreakdown].
class PriceLine {
  final String label;

  /// Amount in pesos. Null renders [placeholder] (e.g. "Calculated at checkout").
  final num? amount;
  final String? placeholder;
  final String? note;
  final bool isDiscount;

  const PriceLine({
    required this.label,
    this.amount,
    this.placeholder,
    this.note,
    this.isDiscount = false,
  });
}

/// Subtotal → fees → total summary used by cart, checkout and order detail
/// so customers always see the same price structure.
class PriceBreakdown extends StatelessWidget {
  final List<PriceLine> lines;
  final String totalLabel;
  final num total;
  final String? footnote;
  final String? title;

  const PriceBreakdown({
    super.key,
    required this.lines,
    required this.total,
    this.totalLabel = 'Total',
    this.footnote,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = AppUi.textSecondaryOf(context);
    final primary = AppUi.textPrimaryOf(context);
    const tabular = [FontFeature.tabularFigures()];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(title!, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUi.spacingMd),
        ],
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: AppUi.spacingSm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.label,
                        style: TextStyle(fontSize: 14, color: secondary),
                      ),
                      if (line.note != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            line.note!,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppUi.isDark(context)
                                  ? AppUi.darkTextMuted
                                  : AppUi.textMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppUi.spacingMd),
                Text(
                  line.amount == null
                      ? (line.placeholder ?? '—')
                      : '${line.isDiscount ? '−' : ''}${formatPeso(line.amount!.abs())}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: line.isDiscount
                        ? (AppUi.isDark(context)
                              ? AppUi.successFgDark
                              : AppColors.uiSuccess)
                        : (line.amount == null ? secondary : primary),
                    fontFeatures: tabular,
                  ),
                ),
              ],
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppUi.spacingXs),
          child: Divider(height: 1),
        ),
        const SizedBox(height: AppUi.spacingSm),
        Row(
          children: [
            Expanded(
              child: Text(
                totalLabel,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: primary,
                ),
              ),
            ),
            Text(
              formatPeso(total),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: primary,
                fontFeatures: tabular,
              ),
            ),
          ],
        ),
        if (footnote != null) ...[
          const SizedBox(height: AppUi.spacingSm),
          Text(
            footnote!,
            style: TextStyle(fontSize: 12, color: secondary, height: 1.4),
          ),
        ],
      ],
    );
  }
}

/// Bordered surface with the standard card padding. Prefer this over
/// hand-rolled `Container(decoration: …)` cards.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  const AppCard({
    super.key,
    required this.child,
    this.padding = AppUi.cardPadding,
    this.onTap,
    this.color,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = AppUi.cardDecorationOf(
      context,
      color: color,
      borderColor: borderColor,
    );
    final content = Padding(padding: padding, child: child);
    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: content);
    }
    return Material(
      color: decoration.color,
      shape: RoundedRectangleBorder(
        borderRadius: AppUi.cardRadius,
        side: BorderSide(color: borderColor ?? AppUi.borderOf(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// Standard confirmation dialog. Returns `true` only when the user confirms.
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: AppUi.error,
                  foregroundColor: Colors.white,
                )
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
