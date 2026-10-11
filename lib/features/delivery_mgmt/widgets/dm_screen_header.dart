import 'package:flutter/material.dart';
import 'package:erefill/core/widgets/brand/hero_header.dart';

/// Header for offline delivery-management screens.
class DmScreenHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget>? actions;
  final Widget? bottom;

  const DmScreenHeader({
    super.key,
    required this.title,
    this.subtitle = 'Offline logs · syncs when online',
    this.actions,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    return TabScreenHeroHeader(
      title: title,
      subtitle: subtitle,
      actions: actions,
      bottom: bottom,
    );
  }
}
