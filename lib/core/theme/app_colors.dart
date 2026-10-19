import 'package:flutter/material.dart';

import '../constants.dart';

/// Centralized, single source of truth for all brand, semantic status,
/// UI state, and neutral surface colors across the eRefill application.
///
/// Raw values live in [AppUi]; this class names them by role.
class AppColors {
  // ── 1. BRAND COLORS (Primary brand identity & actions) ──────────
  static const Color brandPrimary = AppUi.bluePrimary;
  static const Color brandPrimaryDark = AppUi.bluePrimaryDark;
  static const Color brandSecondary = Color(0xFF4D777C);
  static const Color brandSoft = AppUi.blueSoft;
  static const Color brandBorder = AppUi.blueBorder;
  static const Color brandPale = AppUi.bluePale;
  static const Color deepNavy = AppUi.deepBlue;
  static const Color accentCyan = AppUi.accentCyan;

  // ── 2. GLOBAL SEMANTIC STATUS PALETTE ───────────────────────────
  // Strictly defined for order lifecycles across Customer, Owner, Rider & Admin.
  // Status colors support readable white foregrounds and text on white.
  static const Color statusPending = Color(0xFF925B28);
  static const Color statusConfirmed = Color(0xFF426F95);
  static const Color statusPreparing = Color(0xFF626C74);
  static const Color statusReady = Color(0xFF3F736D);
  static const Color statusOutForDelivery = Color(0xFF4B738A);
  static const Color statusCompleted = Color(0xFF4F775C);
  static const Color statusDelivered = statusCompleted;        // Direct semantic alias
  static const Color statusCancelled = Color(0xFF914646);
  static const Color statusRejected = Color(0xFF80434A);
  static const Color statusAccepted = statusConfirmed;        // Direct semantic alias
  static const Color statusNeutral = Color(0xFF64748B);        // Slate fallback

  // ── 3. UI STATE COLORS (System feedback, separate from order status)
  static const Color uiSuccess = AppUi.successFg;
  static const Color uiSuccessBg = AppUi.successBg;
  static const Color uiWarning = AppUi.warningFg;
  static const Color uiWarningBg = AppUi.warningBg;
  static const Color uiError = AppUi.error;
  static const Color uiErrorBg = AppUi.errorBg;
  static const Color uiInfo = AppUi.info;
  static const Color uiInfoBg = AppUi.infoBg;

  // ── 4. NEUTRAL & SURFACE COLORS ─────────────────────────────────
  static const Color surfaceLight = AppUi.surface;
  static const Color surfaceDark = AppUi.darkSurface;
  static const Color surfaceDarkRaised = AppUi.darkSurfaceRaised;
  static const Color pageBgLight = AppUi.pageBg;
  static const Color pageBgDark = AppUi.darkPageBg;

  static const Color textPrimaryLight = AppUi.textPrimary;
  static const Color textSecondaryLight = AppUi.textSecondary;
  static const Color textMutedLight = AppUi.textMuted;
  static const Color textDisabledLight = AppUi.textDisabled;

  static const Color textPrimaryDark = AppUi.darkTextPrimary;
  static const Color textSecondaryDark = AppUi.darkTextSecondary;
  static const Color textMutedDark = AppUi.darkTextMuted;

  static const Color borderLight = AppUi.borderLight;
  static const Color borderDark = AppUi.borderDark;
  static const Color dividerLight = AppUi.borderLight;
  static const Color dividerDark = AppUi.borderDark;
}

/// Semantic tone shared by every non-order status surface (payments,
/// accounts, stations, payouts, alerts) so a "success" looks identical in
/// the customer app, the owner tools, the rider app and the admin console.
enum StatusTone { neutral, info, success, warning, danger, progress }

/// Contrast-safe badge colors for a [StatusTone] (WCAG AA in both themes).
class StatusToneStyle {
  final Color background;
  final Color foreground;
  final Color border;

  const StatusToneStyle({
    required this.background,
    required this.foreground,
    required this.border,
  });

  factory StatusToneStyle.of(StatusTone tone, {bool isDark = false}) {
    switch (tone) {
      case StatusTone.success:
        return isDark
            ? const StatusToneStyle(
                background: Color(0xFF20352A),
                foreground: AppUi.successFgDark,
                border: Color(0xFF365745),
              )
            : const StatusToneStyle(
                background: AppUi.successBg,
                foreground: AppUi.successFg,
                border: AppUi.successBorder,
              );
      case StatusTone.warning:
        return isDark
            ? const StatusToneStyle(
                background: Color(0xFF3D3323),
                foreground: AppUi.warningFgDark,
                border: Color(0xFF665439),
              )
            : const StatusToneStyle(
                background: AppUi.warningBg,
                foreground: AppUi.warningFg,
                border: AppUi.warningBorder,
              );
      case StatusTone.danger:
        return isDark
            ? const StatusToneStyle(
                background: Color(0xFF3A2929),
                foreground: AppUi.errorFgDark,
                border: Color(0xFF684343),
              )
            : const StatusToneStyle(
                background: AppUi.errorBg,
                foreground: AppUi.errorFg,
                border: AppUi.errorBorder,
              );
      case StatusTone.info:
        return isDark
            ? const StatusToneStyle(
                background: Color(0xFF25313D),
                foreground: AppUi.infoFgDark,
                border: Color(0xFF3D5263),
              )
            : const StatusToneStyle(
                background: Color(0xFFDBE4EA),
                foreground: Color(0xFF3D638A),
                border: Color(0xFFBED0DD),
              );
      case StatusTone.progress:
        return isDark
            ? const StatusToneStyle(
                background: Color(0xFF25333D),
                foreground: Color(0xFFA8BECC),
                border: Color(0xFF405563),
              )
            : const StatusToneStyle(
                background: Color(0xFFE2EAF0),
                foreground: Color(0xFF3D627A),
                border: Color(0xFFC3D2DD),
              );
      case StatusTone.neutral:
        return isDark
            ? const StatusToneStyle(
                background: AppUi.darkSurfaceRaised,
                foreground: AppUi.darkTextSecondary,
                border: AppUi.borderDark,
              )
            : const StatusToneStyle(
                background: AppUi.lightSurfaceRaised,
                foreground: Color(0xFF334155),
                border: AppUi.borderLight,
              );
    }
  }

  /// Payment states (`paid`, `pending`, `failed`, `refunded`, …).
  static StatusTone paymentTone(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'paid':
      case 'success':
      case 'succeeded':
      case 'completed':
      case 'approved':
        return StatusTone.success;
      case 'pending':
      case 'unpaid':
      case 'awaiting_payment':
      case 'processing':
        return StatusTone.warning;
      case 'failed':
      case 'declined':
      case 'expired':
      case 'cancelled':
      case 'canceled':
      case 'rejected':
        return StatusTone.danger;
      case 'refunded':
      case 'partially_refunded':
        return StatusTone.info;
      default:
        return StatusTone.neutral;
    }
  }

  /// Account / station / rider lifecycle states.
  static StatusTone accountTone(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'active':
      case 'approved':
      case 'verified':
      case 'online':
      case 'open':
        return StatusTone.success;
      case 'pending':
      case 'pending_approval':
      case 'under_review':
      case 'busy':
        return StatusTone.warning;
      case 'suspended':
      case 'banned':
      case 'rejected':
      case 'blocked':
      case 'maintenance':
        return StatusTone.danger;
      default:
        return StatusTone.neutral;
    }
  }
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
      case 'confirmed':
        return 'Accepted';
      case 'preparing':
      case 'in_prep':
        return 'Preparing';
      case 'ready':
      case 'ready_for_pickup':
      case 'ready_for_delivery':
        return 'Ready for Pickup';
      case 'assigned_to_rider':
      case 'rider_assigned':
        return 'Assigned to Rider';
      case 'out_for_delivery':
      case 'delivering':
      case 'dispatched':
        return 'Out for Delivery';
      case 'delivered':
      case 'completed':
        return 'Delivered';
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

  /// Contrast-safe background for chips/badges on neutral or light surfaces (WCAG AA).
  final Color badgeBackground;

  /// Contrast-safe text & icon color for chips/badges on neutral or light surfaces (WCAG AA).
  final Color badgeForeground;

  /// Contrast-safe border for chips/badges on neutral or light surfaces.
  final Color badgeBorder;

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
    required this.badgeBackground,
    required this.badgeForeground,
    required this.badgeBorder,
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
    final norm = OrderStatusColors.normalize(rawStatus);

    Color badgeBg;
    Color badgeFg;
    Color badgeBrd;

    switch (norm) {
      case 'pending':
      case 'pending_sync':
        badgeBg = isDark
            ? const Color(0xFF3D3323)
            : AppUi.warningBg;
        badgeFg = isDark ? AppUi.warningFgDark : AppUi.warningFg;
        badgeBrd = isDark
            ? const Color(0xFF665439)
            : AppUi.warningBorder;
        break;
      case 'accepted':
        badgeBg = isDark
            ? const Color(0xFF25313D)
            : AppUi.blueSoft;
        badgeFg = isDark ? AppUi.infoFgDark : AppColors.statusConfirmed;
        badgeBrd = isDark ? const Color(0xFF3D5263) : AppUi.blueBorder;
        break;
      case 'preparing':
        badgeBg = isDark
            ? AppUi.darkSurfaceRaised
            : AppUi.lightSurfaceRaised;
        badgeFg = isDark ? AppUi.darkTextSecondary : AppColors.statusPreparing;
        badgeBrd = isDark ? AppUi.borderDark : AppUi.borderStrongLight;
        break;
      case 'ready_for_pickup':
        badgeBg = isDark
            ? const Color(0xFF203631)
            : const Color(0xFFE6EEEC);
        badgeFg = isDark
            ? const Color(0xFFA8C5C0)
            : AppColors.statusReady;
        badgeBrd = isDark
            ? const Color(0xFF3F625C)
            : const Color(0xFFC6D9D5);
        break;
      case 'out_for_delivery':
        badgeBg = isDark
            ? const Color(0xFF25333D)
            : const Color(0xFFE2EAF0);
        badgeFg = isDark
            ? const Color(0xFFA8BECC)
            : const Color(0xFF3D627A);
        badgeBrd = isDark
            ? const Color(0xFF405563)
            : const Color(0xFFC3D2DD);
        break;
      case 'delivered':
        badgeBg = isDark
            ? const Color(0xFF20352A)
            : AppUi.successBg;
        badgeFg = isDark ? AppUi.successFgDark : AppUi.successFg;
        badgeBrd = isDark
            ? const Color(0xFF365745)
            : AppUi.successBorder;
        break;
      case 'cancelled':
      case 'rejected':
        badgeBg = isDark
            ? const Color(0xFF3A2929)
            : AppUi.errorBg;
        badgeFg = isDark ? AppUi.errorFgDark : AppUi.errorFg;
        badgeBrd = isDark
            ? const Color(0xFF684343)
            : AppUi.errorBorder;
        break;
      default:
        badgeBg = isDark
            ? AppUi.darkSurfaceRaised
            : AppUi.lightSurfaceRaised;
        badgeFg = isDark ? AppUi.darkTextSecondary : AppUi.textSecondary;
        badgeBrd = isDark ? AppUi.borderDark : AppUi.borderLight;
    }

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
      badgeBackground: badgeBg,
      badgeForeground: badgeFg,
      badgeBorder: badgeBrd,
      icon: icon,
      label: label,
    );
  }
}
