import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:erefill/core/constants.dart';
import 'package:erefill/core/theme/app_colors.dart';
class PaymentBrandMark extends StatelessWidget {
  final String method;
  final double width;
  final double height;

  const PaymentBrandMark({
    super.key,
    required this.method,
    this.width = 58,
    this.height = 36,
  });

  @override
  Widget build(BuildContext context) {
    final child = switch (method) {
      'gcash' => ClipRRect(
        borderRadius: BorderRadius.circular(AppUi.radiusSm),
        child: Image.asset(
          'assets/payment/gcash-webclip.png',
          width: height,
          height: height,
          fit: BoxFit.cover,
          semanticLabel: 'GCash logo',
        ),
      ),
      'maya' => Container(
        width: width,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppUi.radiusSm),
        ),
        child: SvgPicture.asset(
          'assets/payment/maya.svg',
          fit: BoxFit.contain,
          semanticsLabel: 'Maya logo',
        ),
      ),
      'card' => Container(
        width: width,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppUi.radiusSm),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SvgPicture.asset(
              'assets/payment/visa.svg',
              width: width * 0.45,
              semanticsLabel: 'Visa logo',
            ),
            SvgPicture.asset(
              'assets/payment/mastercard.svg',
              width: height * 0.62,
              semanticsLabel: 'Mastercard logo',
            ),
          ],
        ),
      ),
      _ => Container(
        width: height,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1D6),
          borderRadius: BorderRadius.circular(AppUi.radiusSm),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.payments_outlined,
          color: AppColors.uiWarning,
          size: 20,
          semanticLabel: 'Cash on delivery',
        ),
      ),
    };

    return SizedBox(width: width, height: height, child: child);
  }
}
