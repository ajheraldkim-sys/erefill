import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../providers/theme_provider.dart';

/// Settings control for the app-wide text size. Changes apply instantly and
/// stack on top of the phone's own font size setting.
class TextSizeSlider extends StatelessWidget {
  const TextSizeSlider({super.key});

  static const double _step = 0.05;

  @override
  Widget build(BuildContext context) {
    final scale = context.select<ThemeProvider, double>((p) => p.textScale);
    final theme = Theme.of(context);
    final percent = '${(scale * 100).round()}%';
    final divisions =
        ((ThemeProvider.maxTextScale - ThemeProvider.minTextScale) / _step)
            .round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Text size', style: theme.textTheme.titleSmall),
            ),
            Text(
              percent,
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppUi.brandOf(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Live preview. The app root already applies the chosen scale.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppUi.surfaceRaisedOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppUi.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Order #1024 · 3 gallons',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(
                'This is a preview of how text will look across eRefill.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        Row(
          children: [
            ExcludeSemantics(
              child: Text('A', style: theme.textTheme.bodySmall),
            ),
            Expanded(
              child: Slider(
                value: scale,
                min: ThemeProvider.minTextScale,
                max: ThemeProvider.maxTextScale,
                divisions: divisions,
                label: percent,
                semanticFormatterCallback: (v) =>
                    'Text size ${(v * 100).round()} percent',
                onChanged: (v) => context.read<ThemeProvider>().setTextScale(v),
              ),
            ),
            ExcludeSemantics(
              child: Text(
                'A',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: scale == 1.0
                ? null
                : () => context.read<ThemeProvider>().setTextScale(1.0),
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('Reset'),
          ),
        ),
      ],
    );
  }
}
