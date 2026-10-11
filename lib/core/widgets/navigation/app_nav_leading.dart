import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../routing/app_navigation.dart';

/// Back control for hero headers; adapts to the current background tone.
class HeroBackButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const HeroBackButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    if (!context.canPop()) return const SizedBox.shrink();
    final iconColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;

    return IconButton(
      onPressed: onPressed ?? () => context.popRoute(),
      icon: Icon(Icons.arrow_back_ios_new_rounded, color: iconColor),
      tooltip: 'Back',
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Standard app-bar back for light surfaces.
class AppBackButton extends StatelessWidget {
  final Color? color;
  final VoidCallback? onPressed;

  const AppBackButton({super.key, this.color, this.onPressed});

  @override
  Widget build(BuildContext context) {
    if (!context.canPop()) return const SizedBox.shrink();

    return IconButton(
      onPressed: onPressed ?? () => context.popRoute(),
      icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: color),
      tooltip: 'Back',
    );
  }
}
