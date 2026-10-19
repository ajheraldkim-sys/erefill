import 'dart:math' as math;

import 'package:erefill/core/constants.dart';
import 'package:erefill/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.x relative contrast ratio between two opaque colors.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('Design token contrast (WCAG 2.2 AA)', () {
    test('light text tokens read on every light surface', () {
      for (final bg in [AppUi.surface, AppUi.pageBg, AppUi.lightSurfaceRaised]) {
        expect(contrast(AppUi.textPrimary, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(AppUi.textSecondary, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(AppUi.textMuted, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(AppUi.bluePrimary, bg), greaterThanOrEqualTo(4.5));
      }
      expect(contrast(AppUi.navUnselected, AppUi.surface), greaterThanOrEqualTo(4.5));
    });

    test('dark text tokens read on every dark surface', () {
      for (final bg in [
        AppUi.darkPageBg,
        AppUi.darkSurface,
        AppUi.darkSurfaceRaised,
      ]) {
        expect(contrast(AppUi.darkTextPrimary, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(AppUi.darkTextSecondary, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(AppUi.darkTextMuted, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(AppUi.accentCyan, bg), greaterThanOrEqualTo(4.5));
      }
    });

    test('semantic feedback pairs are readable', () {
      expect(contrast(AppUi.successFg, AppUi.successBg), greaterThanOrEqualTo(4.5));
      expect(contrast(AppUi.warningFg, AppUi.warningBg), greaterThanOrEqualTo(4.5));
      expect(contrast(AppUi.errorFg, AppUi.errorBg), greaterThanOrEqualTo(4.5));
      expect(contrast(AppUi.bluePrimary, AppUi.blueSoft), greaterThanOrEqualTo(4.5));
      for (final c in [
        AppColors.uiSuccess,
        AppColors.uiWarning,
        AppColors.uiError,
      ]) {
        expect(contrast(c, AppUi.surface), greaterThanOrEqualTo(4.5));
      }
    });

    test('every order status carries white text on its solid fill', () {
      for (final status in [
        'pending',
        'accepted',
        'preparing',
        'ready_for_pickup',
        'out_for_delivery',
        'delivered',
        'cancelled',
        'rejected',
      ]) {
        final style = OrderStatusStyle.resolve(status);
        expect(
          contrast(style.cardForeground, style.cardBackground),
          greaterThanOrEqualTo(4.5),
          reason: '$status card text',
        );
        expect(
          contrast(style.badgeForeground, style.badgeBackground),
          greaterThanOrEqualTo(4.5),
          reason: '$status badge text',
        );
      }
    });

    test('status tones produce readable light-mode badges', () {
      for (final tone in StatusTone.values) {
        final style = StatusToneStyle.of(tone);
        expect(
          contrast(style.foreground, style.background),
          greaterThanOrEqualTo(4.5),
          reason: tone.name,
        );
      }
    });

    test('payment and account states map to consistent tones', () {
      expect(StatusToneStyle.paymentTone('paid'), StatusTone.success);
      expect(StatusToneStyle.paymentTone('PENDING'), StatusTone.warning);
      expect(StatusToneStyle.paymentTone('failed'), StatusTone.danger);
      expect(StatusToneStyle.paymentTone('refunded'), StatusTone.info);
      expect(StatusToneStyle.accountTone('suspended'), StatusTone.danger);
      expect(StatusToneStyle.accountTone('active'), StatusTone.success);
      expect(StatusToneStyle.accountTone(null), StatusTone.neutral);
    });
  });
}
