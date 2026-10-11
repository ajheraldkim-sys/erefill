import 'package:flutter/material.dart';
import 'erefill_header.dart';

class PremiumHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final bool showAvatar;
  final Color? accentColor;

  const PremiumHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.showAvatar = true,
    this.accentColor,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        subtitle == null ? 72.0 : 88.0,
      );

  @override
  Widget build(BuildContext context) {
    return ERefillHeader(
      type: ERefillHeaderType.dashboard,
      title: title,
      subtitle: subtitle,
      actions: actions,
    );
  }
}
