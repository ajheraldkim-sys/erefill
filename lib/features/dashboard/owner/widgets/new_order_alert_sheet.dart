import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants.dart';
import '../../../../core/utils/app_haptics.dart';

import 'package:erefill/core/theme/app_colors.dart';
import 'package:erefill/core/utils/money.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
/// Full-screen urgent alert sheet displayed to station owners when a new refill order arrives.
/// Features a continuous repeating haptic alert, visual countdown timer (60s),
/// prominent order details, and oversized touch targets (56dp+) for quick acknowledgment.
class NewOrderAlertSheet extends StatefulWidget {
  final Map<String, dynamic> order;
  final Future<void> Function(String orderId) onAccept;
  final Future<void> Function(String orderId)? onDecline;

  const NewOrderAlertSheet({
    super.key,
    required this.order,
    required this.onAccept,
    this.onDecline,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> order,
    required Future<void> Function(String orderId) onAccept,
    Future<void> Function(String orderId)? onDecline,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => NewOrderAlertSheet(
        order: order,
        onAccept: onAccept,
        onDecline: onDecline,
      ),
    );
  }

  @override
  State<NewOrderAlertSheet> createState() => _NewOrderAlertSheetState();
}

class _NewOrderAlertSheetState extends State<NewOrderAlertSheet>
    with SingleTickerProviderStateMixin {
  static const int _initialCountdownSeconds = 60;
  late int _remainingSeconds;
  Timer? _countdownTimer;
  Timer? _repeatingHapticTimer;
  bool _isProcessing = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = _initialCountdownSeconds;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Initial alert blast
    AppHaptics.heavy();
    SystemSound.play(SystemSoundType.alert);

    // Repeating alert every 1.5s until dismissed/accepted
    _repeatingHapticTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) {
        if (mounted) {
          AppHaptics.heavy();
          SystemSound.play(SystemSoundType.alert);
        }
      },
    );

    // 60-second countdown timer
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remainingSeconds <= 1) {
        timer.cancel();
        _repeatingHapticTimer?.cancel();
        Navigator.of(context).maybePop();
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _repeatingHapticTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handleAccept() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    _repeatingHapticTimer?.cancel();
    AppHaptics.success();

    final orderId = widget.order['id']?.toString() ?? '';
    try {
      await widget.onAccept(orderId);
      if (mounted) {
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept order: ${FriendlyErrors.message(e)}')),
        );
      }
    }
  }

  Future<void> _handleDecline() async {
    if (_isProcessing) return;
    _repeatingHapticTimer?.cancel();
    AppHaptics.medium();

    final orderId = widget.order['id']?.toString() ?? '';
    if (widget.onDecline != null) {
      setState(() => _isProcessing = true);
      try {
        await widget.onDecline!(orderId);
        if (mounted) Navigator.of(context).maybePop();
      } catch (e) {
        if (mounted) {
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to decline order: ${FriendlyErrors.message(e)}'),
            ),
          );
        }
      }
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final order = widget.order;
    final customerName = (order['customer_name'] ??
            (order['customer'] as Map<String, dynamic>?)?['full_name'] ??
            'Customer')
        .toString();
    final address = (order['delivery_address'] ??
            (order['customer'] as Map<String, dynamic>?)?['complete_address'] ??
            'Station Delivery')
        .toString();
    final total = ((order['total_amount'] as num?) ?? 0.0).toDouble();
    final payment = (order['payment_method'] ?? 'COD').toString().toUpperCase();
    final gallons = ((order['gallons'] as num?) ?? 1).toDouble();
    final progress = _remainingSeconds / _initialCountdownSeconds;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppUi.textPrimary : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppUi.radiusPill)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        AppUi.screenPadding,
        16,
        AppUi.screenPadding,
        MediaQuery.paddingOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppUi.borderOf(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header: Urgent Alert Title & Countdown
          Row(
            children: [
              ScaleTransition(
                scale: _pulseScale,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppUi.warningBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.uiWarning, width: 2),
                  ),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    color: AppColors.uiWarning,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'NEW REFILL ORDER!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        color: AppColors.uiWarning,
                      ),
                    ),
                    Text(
                      'Respond within ${_remainingSeconds}s to accept',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppUi.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _remainingSeconds <= 15
                      ? AppUi.errorBg
                      : AppUi.warningBg,
                  borderRadius: BorderRadius.circular(AppUi.radiusSheet),
                  border: Border.all(
                    color: _remainingSeconds <= 15
                        ? AppColors.uiError
                        : AppColors.uiWarning,
                  ),
                ),
                child: Text(
                  '${_remainingSeconds}s',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _remainingSeconds <= 15
                        ? AppColors.uiError
                        : AppColors.uiWarning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Countdown progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(AppUi.radiusXs),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppUi.borderOf(context),
              valueColor: AlwaysStoppedAnimation<Color>(
                _remainingSeconds <= 15
                    ? AppColors.uiError
                    : AppColors.uiWarning,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Order details card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppUi.darkSurfaceRaised : AppUi.pageBg,
              borderRadius: BorderRadius.circular(AppUi.radiusSheet),
              border: Border.all(color: AppUi.borderOf(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        customerName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      formatPeso(total),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppUi.brandOf(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.water_drop_rounded,
                      size: 16,
                      color: AppUi.textSecondaryOf(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${gallons.toStringAsFixed(0)} Gallons • $payment',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppUi.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 16,
                      color: AppUi.textSecondaryOf(context),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        address,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppUi.textSecondaryOf(context),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Primary Actions with min 56dp touch targets
          Row(
            children: [
              Expanded(
                flex: 1,
                child: SizedBox(
                  height: AppUi.kRiderTouchTarget,
                  child: OutlinedButton(
                    onPressed: _isProcessing ? null : _handleDecline,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppUi.borderOf(context), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                      ),
                      foregroundColor: AppUi.textSecondaryOf(context),
                    ),
                    child: const Text(
                      'Decline',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: AppUi.kRiderTouchTarget,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _handleAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.uiSuccess,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                      ),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_rounded, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Accept Order',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
