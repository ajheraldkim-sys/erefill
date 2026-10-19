import 'package:flutter/material.dart';
import '../constants.dart';
import 'skeleton.dart';

/// Primary button. Material's built-in ink response provides clear, cheap tap
/// feedback without rebuilding the button for every pointer event.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isLoading;
  final bool isEnabled;
  final double? width;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.isEnabled = true,
    this.width,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? double.infinity,
      child: _buildButton(),
    );
  }

  Widget _buildButton() {
    final onPressed = isEnabled && !isLoading
        ? this.onPressed
        : null;

    if (isLoading) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              isEnabled ? Colors.white : Colors.grey,
            ),
          ),
        ),
        label: Text(label),
      );
    }

    final icon = this.icon;
    if (icon != null) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      );
    }

    return ElevatedButton(onPressed: onPressed, child: Text(label));
  }
}

/// Secondary Button
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isEnabled;
  final double? width;
  final IconData? icon;

  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isEnabled = true,
    this.width,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return SizedBox(
      width: width ?? double.infinity,
      child: icon != null
          ? OutlinedButton.icon(
              onPressed: isEnabled ? onPressed : null,
              icon: Icon(icon),
              label: Text(label),
            )
          : OutlinedButton(
              onPressed: isEnabled ? onPressed : null,
              child: Text(label),
            ),
    );
  }
}

/// Text Button
class TextLinkButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color? color;
  final TextDecoration? decoration;

  const TextLinkButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          color: color ?? AppUi.bluePrimary,
          decoration: decoration,
        ),
      ),
    );
  }
}

/// Custom Card Widget
class CustomCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final BoxDecoration? decoration;
  final bool elevated;

  const CustomCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.decoration,
    this.elevated = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding ?? AppUi.cardPadding,
      margin: margin,
      decoration:
          decoration ?? AppUi.cardDecorationOf(context, elevated: elevated),
      child: child,
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppUi.cardRadius,
          child: content,
        ),
      );
    }

    return content;
  }
}

/// Section Header
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onViewAll;
  final EdgeInsetsGeometry? padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onViewAll,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          padding ??
          const EdgeInsets.symmetric(
            horizontal: AppUi.screenPadding,
            vertical: AppUi.spacingMd,
          ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              if (subtitle != null) AppUi.vGapXs,
              if (subtitle != null)
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          if (onViewAll != null)
            TextButton(onPressed: onViewAll, child: const Text('View All')),
        ],
      ),
    );
  }
}

/// Empty State Widget
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String? actionLabel;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppUi.spacing2xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: AppUi.textSecondary),
            AppUi.vGapLg,
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            AppUi.vGapSm,
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              AppUi.vGapXl,
              PrimaryButton(
                label: actionLabel ?? 'Retry',
                onPressed: onRetry!,
                width: 140,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Loading State Widget
class LoadingState extends StatelessWidget {
  final String? message;

  const LoadingState({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return const SkeletonList(itemCount: 6);
  }
}

/// Info Card
class InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color? iconColor;
  final Color? backgroundColor;

  const InfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.iconColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      decoration: BoxDecoration(
        color: backgroundColor ?? AppUi.blueSoft,
        borderRadius: AppUi.radiusLg,
        border: Border.all(color: AppUi.blueBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 32, color: iconColor ?? AppUi.bluePrimary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(description, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge Widget
class AppBadge extends StatelessWidget {
  final String label;
  final Color? backgroundColor;
  final Color? textColor;
  final IconData? icon;

  const AppBadge({
    super.key,
    required this.label,
    this.backgroundColor,
    this.textColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppUi.blueSoft,
        borderRadius: AppUi.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                icon,
                size: 12,
                color: textColor ?? AppUi.bluePrimary,
              ),
            ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor ?? AppUi.bluePrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Divider with Text
class DividerWithText extends StatelessWidget {
  final String text;
  final double height;

  const DividerWithText({super.key, required this.text, this.height = 16});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(text, style: Theme.of(context).textTheme.labelSmall),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}
