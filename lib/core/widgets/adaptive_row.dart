import 'package:flutter/material.dart';
import '../constants.dart';

/// A responsive widget that arranges children horizontally in a [Row] when
/// space permits, or wraps / stacks them into a [Column] when constraints are
/// narrow (< [breakpoint] or under high text scale factor), preventing
/// [RenderFlex] overflows at 320dp and 130%-150% font scaling.
class AdaptiveRow extends StatelessWidget {
  final List<Widget> children;
  final double breakpoint;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final double spacing;
  final bool forceWrapOnLargeFont;

  const AdaptiveRow({
    super.key,
    required this.children,
    this.breakpoint = 340.0,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.spacing = AppUi.space8,
    this.forceWrapOnLargeFont = true,
  });

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final isEnlargedText = forceWrapOnLargeFont && textScale > 1.25;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < breakpoint;

        if (isNarrow || isEnlargedText) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) SizedBox(height: spacing),
              ],
            ],
          );
        }

        return Row(
          mainAxisAlignment: mainAxisAlignment,
          crossAxisAlignment: crossAxisAlignment,
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (children[i] is Expanded || children[i] is Flexible)
                children[i]
              else
                Flexible(child: children[i]),
              if (i < children.length - 1) SizedBox(width: spacing),
            ],
          ],
        );
      },
    );
  }
}

