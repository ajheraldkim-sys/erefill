import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/theme/app_colors.dart';
export 'package:shadcn_flutter/shadcn_flutter.dart' show LucideIcons;

bool _hasShadcnTheme(BuildContext context) {
  try {
    return context.getElementForInheritedWidgetOfExactType<shadcn.Theme>() != null;
  } catch (_) {
    return false;
  }
}

/// Unified Shadcn Primary Button with loading state and optional icon.
class ShadcnPrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget? child;
  final String? text;
  final IconData? icon;
  final bool isLoading;
  final double? width;
  final double height;
  final bool enabled;

  const ShadcnPrimaryButton({
    super.key,
    this.onPressed,
    this.child,
    this.text,
    this.icon,
    this.isLoading = false,
    this.width,
    this.height = 48,
    this.enabled = true,
  }) : assert(child != null || text != null, 'Either child or text must be provided');

  @override
  Widget build(BuildContext context) {
    final effectiveChild = isLoading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: shadcn.CircularProgressIndicator(),
          )
        : FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                ],
                if (child != null)
                  child!
                else
                  Text(
                    text!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          );

    final handlePress = enabled && !isLoading && onPressed != null
        ? () {
            HapticFeedback.lightImpact();
            onPressed!();
          }
        : null;

    final hasShadcn = _hasShadcnTheme(context);
    if (!hasShadcn) {
      final mBtn = material.FilledButton(
        style: material.FilledButton.styleFrom(
          backgroundColor: AppUi.bluePrimary,
          foregroundColor: material.Colors.white,
          shape: material.RoundedRectangleBorder(
            borderRadius: material.BorderRadius.circular(AppUi.radiusControl),
          ),
          padding: const material.EdgeInsets.symmetric(horizontal: 16),
        ),
        onPressed: handlePress,
        child: effectiveChild,
      );
      if (width != null) {
        return SizedBox(width: width, height: height, child: mBtn);
      }
      return SizedBox(height: height, child: mBtn);
    }

    final btn = shadcn.PrimaryButton(
      onPressed: handlePress,
      child: effectiveChild,
    );

    if (width != null) {
      return SizedBox(width: width, height: height, child: btn);
    }
    return SizedBox(height: height, child: btn);
  }
}

/// Unified Shadcn Outline Button with optional icon.
class ShadcnOutlineButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget? child;
  final String? text;
  final IconData? icon;
  final double? width;
  final double height;
  final bool enabled;

  const ShadcnOutlineButton({
    super.key,
    this.onPressed,
    this.child,
    this.text,
    this.icon,
    this.width,
    this.height = 48,
    this.enabled = true,
  }) : assert(
         child != null || text != null,
         'Either child or text must be provided',
       );

  @override
  Widget build(BuildContext context) {
    final effectiveChild = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: 8),
          ],
          if (child != null)
            child!
          else
            Text(
              text!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
        ],
      ),
    );

    final handlePress = enabled && onPressed != null
        ? () {
            HapticFeedback.lightImpact();
            onPressed!();
          }
        : null;

    final hasShadcn = _hasShadcnTheme(context);
    if (!hasShadcn) {
      final mBtn = material.OutlinedButton(
        style: material.OutlinedButton.styleFrom(
          foregroundColor: AppUi.brandOf(context),
          side: const material.BorderSide(color: AppUi.borderLight),
          shape: material.RoundedRectangleBorder(borderRadius: material.BorderRadius.circular(AppUi.radiusControl)),
          padding: const material.EdgeInsets.symmetric(horizontal: 16),
        ),
        onPressed: handlePress,
        child: effectiveChild,
      );
      if (width != null) return SizedBox(width: width, height: height, child: mBtn);
      return SizedBox(height: height, child: mBtn);
    }

    final btn = shadcn.OutlineButton(
      onPressed: handlePress,
      child: effectiveChild,
    );

    if (width != null) {
      return SizedBox(width: width, height: height, child: btn);
    }
    return SizedBox(height: height, child: btn);
  }
}

/// Unified Shadcn Destructive Button for actions like Delete Account / Cancel Order.
class ShadcnDestructiveButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget? child;
  final String? text;
  final IconData? icon;
  final double? width;
  final double height;
  final bool isLoading;

  const ShadcnDestructiveButton({
    super.key,
    this.onPressed,
    this.child,
    this.text,
    this.icon,
    this.width,
    this.height = 48,
    this.isLoading = false,
  }) : assert(child != null || text != null, 'Either child or text must be provided');

  @override
  Widget build(BuildContext context) {
    final effectiveChild = isLoading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: shadcn.CircularProgressIndicator(),
          )
        : FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                ],
                if (child != null)
                  child!
                else
                  Text(
                    text!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          );

    final handlePress = !isLoading && onPressed != null
        ? () {
            HapticFeedback.mediumImpact();
            onPressed!();
          }
        : null;

    final hasShadcn = _hasShadcnTheme(context);
    if (!hasShadcn) {
      final mBtn = material.FilledButton(
        style: material.FilledButton.styleFrom(
          backgroundColor: AppColors.uiError,
          foregroundColor: material.Colors.white,
          shape: material.RoundedRectangleBorder(
            borderRadius: material.BorderRadius.circular(AppUi.radiusControl),
          ),
          padding: const material.EdgeInsets.symmetric(horizontal: 16),
        ),
        onPressed: handlePress,
        child: effectiveChild,
      );
      if (width != null) {
        return SizedBox(width: width, height: height, child: mBtn);
      }
      return SizedBox(height: height, child: mBtn);
    }

    final btn = shadcn.DestructiveButton(
      onPressed: handlePress,
      child: effectiveChild,
    );

    if (width != null) {
      return SizedBox(width: width, height: height, child: btn);
    }
    return SizedBox(height: height, child: btn);
  }
}

/// Unified Shadcn Ghost Button for minimal, subtle actions.
class ShadcnGhostButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget? child;
  final String? text;
  final IconData? icon;

  const ShadcnGhostButton({
    super.key,
    this.onPressed,
    this.child,
    this.text,
    this.icon,
  }) : assert(
         child != null || text != null,
         'Either child or text must be provided',
       );

  @override
  Widget build(BuildContext context) {
    final content = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: 8),
          ],
          if (child != null)
            child!
          else
            Text(
              text!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
        ],
      ),
    );

    final hasShadcn = _hasShadcnTheme(context);
    if (!hasShadcn) {
      return material.TextButton(
        onPressed: onPressed,
        child: content,
      );
    }

    return shadcn.GhostButton(
      onPressed: onPressed,
      child: content,
    );
  }
}

/// Unified Shadcn Card surface with flat 1px subtle border.
class ShadcnCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  const ShadcnCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardWidget = shadcn.Card(
      theme: shadcn.CardTheme(padding: padding),
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: cardWidget,
      );
    }

    return cardWidget;
  }
}

/// Status / Tag Badges following Shadcn badge patterns.
enum ShadcnBadgeVariant { primary, secondary, outline, destructive, success, warning }

class ShadcnBadge extends StatelessWidget {
  final String label;
  final ShadcnBadgeVariant variant;
  final IconData? icon;

  const ShadcnBadge({
    super.key,
    required this.label,
    this.variant = ShadcnBadgeVariant.primary,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );

    switch (variant) {
      case ShadcnBadgeVariant.primary:
        return shadcn.PrimaryBadge(child: content);
      case ShadcnBadgeVariant.secondary:
        return shadcn.SecondaryBadge(child: content);
      case ShadcnBadgeVariant.destructive:
        return shadcn.DestructiveBadge(child: content);
      case ShadcnBadgeVariant.outline:
        return shadcn.OutlineBadge(child: content);
      case ShadcnBadgeVariant.success:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.uiSuccess.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppUi.radiusSm),
            border: Border.all(color: AppColors.uiSuccess.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 12, color: AppColors.uiSuccess),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.uiSuccess,
                  ),
                ),
              ),
            ],
          ),
        );
      case ShadcnBadgeVariant.warning:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.uiWarning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppUi.radiusSm),
            border: Border.all(color: AppColors.uiWarning.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 12, color: AppColors.uiWarning),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.uiWarning,
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }
}

