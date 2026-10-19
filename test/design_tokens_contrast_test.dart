import 'dart:io';
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

Iterable<File> _dartFiles(Directory directory) sync* {
  if (!directory.existsSync()) return;
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
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

    test('status tones produce readable dark-mode badges', () {
      for (final tone in StatusTone.values) {
        final style = StatusToneStyle.of(tone, isDark: true);
        expect(
          contrast(style.foreground, style.background),
          greaterThanOrEqualTo(4.5),
          reason: tone.name,
        );
      }
    });

    test('brand and order status colors stay muted', () {
      final colors = [
        AppUi.bluePrimary,
        AppUi.bluePrimaryDark,
        AppUi.accentCyan,
        AppUi.accentGreen,
        AppColors.brandSecondary,
        AppColors.statusPending,
        AppColors.statusConfirmed,
        AppColors.statusPreparing,
        AppColors.statusReady,
        AppColors.statusOutForDelivery,
        AppColors.statusCompleted,
        AppColors.statusCancelled,
        AppColors.statusRejected,
      ];

      for (final color in colors) {
        expect(
          HSLColor.fromColor(color).saturation,
          lessThanOrEqualTo(0.75),
          reason: color.toString(),
        );
      }
    });

    test('status colors avoid purple and indigo hues', () {
      final statusColors = [
        AppColors.statusPending,
        AppColors.statusConfirmed,
        AppColors.statusPreparing,
        AppColors.statusReady,
        AppColors.statusOutForDelivery,
        AppColors.statusCompleted,
        AppColors.statusCancelled,
        AppColors.statusRejected,
        for (final tone in [StatusTone.info, StatusTone.progress])
          StatusToneStyle.of(tone).foreground,
        for (final tone in [StatusTone.info, StatusTone.progress])
          StatusToneStyle.of(tone).background,
        for (final tone in [StatusTone.info, StatusTone.progress])
          StatusToneStyle.of(tone).border,
        for (final tone in [StatusTone.info, StatusTone.progress])
          StatusToneStyle.of(tone, isDark: true).foreground,
        for (final tone in [StatusTone.info, StatusTone.progress])
          StatusToneStyle.of(tone, isDark: true).background,
        for (final tone in [StatusTone.info, StatusTone.progress])
          StatusToneStyle.of(tone, isDark: true).border,
      ];

      for (final color in statusColors) {
        final hsl = HSLColor.fromColor(color);
        final isPurpleOrIndigo =
            hsl.saturation >= 0.2 && hsl.hue >= 250 && hsl.hue <= 300;
        expect(isPurpleOrIndigo, isFalse, reason: color.toString());
      }
    });

    test('app and admin source contain no gradients or glass effects', () {
      final bannedPattern = RegExp(
        r'\b(?:LinearGradient|RadialGradient|SweepGradient|BackdropFilter|AdminGlassCard|purple|indigo|violet|glassmorphism)\b|ImageFilter\.blur',
        caseSensitive: false,
      );
      final colorLiteralPattern = RegExp(
        r'Color\(\s*0xFF([0-9A-Fa-f]{6})\s*\)',
      );
      final offenders = <String>[];

      for (final directory in [Directory('lib'), Directory('admin/lib')]) {
        for (final file in _dartFiles(directory)) {
          final source = file.readAsStringSync();
          final hasBannedEffect = bannedPattern.hasMatch(source);
          final hasPurpleLiteral = colorLiteralPattern
              .allMatches(source)
              .any((match) {
                final color = Color(
                  0xFF000000 | int.parse(match.group(1)!, radix: 16),
                );
                final hsl = HSLColor.fromColor(color);
                return hsl.saturation >= 0.2 &&
                    hsl.hue >= 250 &&
                    hsl.hue <= 300;
              });
          if (hasBannedEffect || hasPurpleLiteral) {
            offenders.add(file.path);
          }
        }
      }

      expect(offenders, isEmpty, reason: offenders.join('\n'));
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
