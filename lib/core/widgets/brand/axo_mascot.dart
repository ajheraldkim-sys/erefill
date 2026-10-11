import 'package:flutter/material.dart';

import 'axo_states.dart';

/// Mascot deliberately removed from the app UI. This shim keeps the legacy
/// widget name available without rendering any character art.
class AxoMascot extends StatelessWidget {
  final AxoPose pose;
  final double size;
  final bool animate;
  final bool preferLottie;

  const AxoMascot({
    super.key,
    this.pose = AxoPose.wave,
    this.size = 120,
    this.animate = false,
    this.preferLottie = false,
  });

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
