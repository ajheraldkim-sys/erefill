import 'package:flutter/material.dart';

/// Centralized, single source of truth for all brand, semantic status,
/// UI state, and neutral surface colors across the eRefill application.
class AppColors {
  // ── 1. BRAND COLORS (Primary brand identity & actions) ──────────
  static const Color brandPrimary = Color(0xFF0F71C3);
  static const Color brandPrimaryDark = Color(0xFF0C5BA0);
  static const Color brandSecondary = Color(0xFF087E8B);
  static const Color brandSoft = Color(0xFFE8F3FC);
  static const Color brandBorder = Color(0xFFBAD7F2);
  static const Color brandPale = Color(0xFFF1F7FD);
  static const Color deepNavy = Color(0xFF10283B);
  static const Color accentCyan = Color(0xFF42C2C8);

  // ── 2. GLOBAL SEMANTIC STATUS PALETTE ───────────────────────────
  // Strictly defined for order lifecycles across Customer, Owner, Rider & Admin.
  static const Color statusPending = Color(0xFFE58A16);        // Premium Amber
  static const Color statusConfirmed = Color(0xFF2563EB);      // Royal Blue (accepted)
  static const Color statusPreparing = Color(0xFF7C3AED);      // Rich Violet
  static const Color statusReady = Color(0xFF0F766E);          // Deep Teal (ready for delivery/pickup)
  static const Color statusOutForDelivery = Color(0xFF4338CA); // Indigo
  static const Color statusCompleted = Color(0xFF16803D);      // Emerald Green (delivered)
  static const Color statusCancelled = Color(0xFFDC2626);      // Premium Red
  static const Color statusRejected = Color(0xFF991B1B);       // Deep Crimson
  static const Color statusNeutral = Color(0xFF64748B);        // Slate fallback

  // ── 3. UI STATE COLORS (System feedback, separate from order status)
  static const Color uiSuccess = Color(0xFF16A34A);
  static const Color uiSuccessBg = Color(0xFFDCFCE7);
  static const Color uiWarning = Color(0xFFD97706);
  static const Color uiWarningBg = Color(0xFFFEF3C7);
  static const Color uiError = Color(0xFFDC2626);
  static const Color uiErrorBg = Color(0xFFFEE2E2);
  static const Color uiInfo = Color(0xFF2563EB);
  static const Color uiInfoBg = Color(0xFFEFF6FF);

  // ── 4. NEUTRAL & SURFACE COLORS ─────────────────────────────────
  static const Color surfaceLight = Colors.white;
  static const Color surfaceDark = Color(0xFF121D21);
  static const Color surfaceDarkRaised = Color(0xFF1B2A2F);
  static const Color pageBgLight = Color(0xFFF5F7F8);
  static const Color pageBgDark = Color(0xFF0B1215);

  static const Color textPrimaryLight = Color(0xFF17252A);
  static const Color textSecondaryLight = Color(0xFF64777D);
  static const Color textMutedLight = Color(0xFF829398);
  static const Color textDisabledLight = Color(0xFFC9D1DD);

  static const Color textPrimaryDark = Color(0xFFF1F5F9);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color textMutedDark = Color(0xFF64748B);

  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color borderDark = Color(0xFF1E293B);
  static const Color dividerLight = Color(0xFFE2E8F0);
  static const Color dividerDark = Color(0xFF1E293B);
}

/// Centralized mapping between order statuses and their exact semantic colors,
/// normalized status identifiers, user-facing labels, and standard icons.
class OrderStatusColors {
  // ── Canonical Static Constants ─────────────────────────────────
  static const Color pending = AppColors.statusPending;
  static const Color confirmed = AppColors.statusConfirmed;
  static const Color preparing = AppColors.statusPreparing;
  static const Color readyForDelivery = AppColors.statusReady;
  static const Color outForDelivery = AppColors.statusOutForDelivery;
  static const Color completed = AppColors.statusCompleted;
  static const Color cancelled = AppColors.statusCancelled;
  static const Color rejected = AppColors.statusRejected;

  /// Normalizes any input status string to a standard canonical key.
  static String normalize(String? rawStatus) {
    final s = (rawStatus ?? 'pending').trim().toLowerCase().replaceAll('-', '_');
    if (s == 'confirmed') return 'accepted';
    if (s == 'completed') return 'delivered';
    if (s == 'canceled') return 'cancelled';
    if (s == 'in_prep') return 'preparing';
    if (s == 'ready_for_delivery') return 'ready_for_pickup';
    if (s == 'dispatched' || s == 'delivering' || s == 'assigned_to_rider' || s == 'rider_assigned') {
      return 'out_for_delivery';
    }
    return s;
  }

  /// Returns the canonical semantic color for the given order status.
  static Color getColor(String? rawStatus) {
    switch (normalize(rawStatus)) {
      case 'pending':
      case 'pending_sync':
        return AppColors.statusPending;
      case 'accepted':
        return AppColors.statusConfirmed;
      case 'preparing':
        return AppColors.statusPreparing;
      case 'ready':
      case 'ready_for_pickup':
        return AppColors.statusReady;
      case 'out_for_delivery':
        return AppColors.statusOutForDelivery;
      case 'delivered':
        return AppColors.statusCompleted;
      case 'cancelled':
        return AppColors.statusCancelled;
      case 'rejected':
        return AppColors.statusRejected;
      default:
        return AppColors.statusNeutral;
    }
  }

  /// Returns the human-readable standard label for the status.
  static String getLabel(String? rawStatus) {
    final s = (rawStatus ?? 'pending').trim().toLowerCase().replaceAll('-', '_');
    switch (s) {
      case 'pending_sync':
        return 'Queued Offline';
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'confirmed':
        return 'Confirmed';
      case 'preparing':
      case 'in_prep':
        return 'Preparing';
      case 'ready':
      case 'ready_for_pickup':
        return 'Ready for Pickup';
      case 'ready_for_delivery':
        return 'Ready for Delivery';
      case 'assigned_to_rider':
      case 'rider_assigned':
        return 'Assigned to Rider';
      case 'out_for_delivery':
      case 'delivering':
      case 'dispatched':
        return 'Out for Delivery';
      case 'delivered':
        return 'Delivered';
      case 'completed':
        return 'Completed';
      case 'cancelled':
      case 'canceled':
        return 'Cancelled';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Processing';
    }
  }

  /// Returns the standard icon representing the order status.
  static IconData getIcon(String? rawStatus) {
    final s = (rawStatus ?? 'pending').trim().toLowerCase().replaceAll('-', '_');
    switch (s) {
      case 'pending_sync':
        return Icons.cloud_upload_outlined;
      case 'pending':
        return Icons.schedule_rounded;
      case 'accepted':
      case 'confirmed':
        return Icons.thumb_up_alt_outlined;
      case 'preparing':
      case 'in_prep':
        return Icons.water_drop_rounded;
      case 'ready':
      case 'ready_for_pickup':
      case 'ready_for_delivery':
        return Icons.inventory_2_outlined;
      case 'assigned_to_rider':
      case 'rider_assigned':
        return Icons.person_pin_circle_outlined;
      case 'out_for_delivery':
      case 'delivering':
      case 'dispatched':
        return Icons.delivery_dining_rounded;
      case 'delivered':
      case 'completed':
        return Icons.check_circle_rounded;
      case 'cancelled':
      case 'canceled':
        return Icons.cancel_rounded;
      case 'rejected':
        return Icons.block_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }
}

/// Comprehensive, reusable resolution of background, foreground, badge,
/// border, and typography colors for any order status.
class OrderStatusStyle {
  /// The solid semantic status color (e.g. Amber #E58A16, Emerald #16803D).
  final Color primaryColor;

  /// Background color for full-color order cards.
  final Color cardBackground;

  /// Contrast-safe primary text color on full-color cards.
  final Color cardForeground;

  /// Contrast-safe secondary text color on full-color cards.
  final Color cardSecondaryText;

  /// Background for the compact status chip.
  final Color chipBackground;

  /// Text & icon color for the status chip.
  final Color chipForeground;

  /// Border for the status chip.
  final Color chipBorder;

  /// Subtle tint background for tables, compact badges, or neutral surfaces.
  final Color subtleBackground;

  /// Subtle border for outline elements.
  final Color subtleBorder;

  /// Representative icon for the status.
  final IconData icon;

  /// Canonical label for the status.
  final String label;

  const OrderStatusStyle({
    required this.primaryColor,
    required this.cardBackground,
    required this.cardForeground,
    required this.cardSecondaryText,
    required this.chipBackground,
    required this.chipForeground,
    required this.chipBorder,
    required this.subtleBackground,
    required this.subtleBorder,
    required this.icon,
    required this.label,
  });

  /// Alias for cardForeground representing the high-contrast title typography.
  Color get cardTitleText => cardForeground;

  /// Factory resolving the complete styling palette for any raw status string.
  factory OrderStatusStyle.resolve(String? rawStatus, {bool isDark = false}) {
    final color = OrderStatusColors.getColor(rawStatus);
    final label = OrderStatusColors.getLabel(rawStatus);
    final icon = OrderStatusColors.getIcon(rawStatus);

    return OrderStatusStyle(
      primaryColor: color,
      cardBackground: color,
      cardForeground: Colors.white,
      cardSecondaryText: Colors.white.withValues(alpha: 0.85),
      chipBackground: Colors.white.withValues(alpha: 0.22),
      chipForeground: Colors.white,
      chipBorder: Colors.white.withValues(alpha: 0.35),
      subtleBackground: color.withValues(alpha: isDark ? 0.18 : 0.09),
      subtleBorder: color.withValues(alpha: isDark ? 0.35 : 0.22),
      icon: icon,
      label: label,
    );
  }
}
