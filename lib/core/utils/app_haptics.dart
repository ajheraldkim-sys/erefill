import 'package:flutter/services.dart';

/// Centralized haptic feedback controller providing consistent tactile responses
/// across all interactions in the eRefill ecosystem.
abstract final class AppHaptics {
  /// Subtle feedback for button presses, tabs, and toggles.
  static Future<void> light() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// Distinct feedback for standard actions (e.g. quantity change, card tap).
  static Future<void> medium() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Prominent feedback for major actions (e.g. order placed, payment submitted).
  static Future<void> heavy() async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Snappy feedback for micro-selections (e.g. wheel scroll, segment switch).
  static Future<void> selection() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// Two-pulse celebratory haptic for successfully completed operations.
  static Future<void> success() async {
    try {
      await HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 90));
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// Warning feedback pattern for errors, invalid fields, or network alerts.
  static Future<void> error() async {
    try {
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Energetic triple-pulse pattern alerting Owners & Riders to incoming orders.
  static Future<void> orderAlert() async {
    try {
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 110));
      await HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 110));
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }
}

