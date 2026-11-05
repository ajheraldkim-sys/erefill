import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';

/// System / Light / Dark choice. "System" follows the phone's setting and
/// updates live when the phone switches. Picking any option leaves outdoor
/// (high-contrast) mode, since that mode always renders light.
class ThemeModePicker extends StatelessWidget {
  const ThemeModePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ThemeProvider>();
    final selected = provider.isOutdoorMode ? null : provider.themeMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Theme', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          selected == ThemeMode.system
              ? 'Follows your phone\'s light or dark setting'
              : 'Choose how eRefill looks',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto_rounded),
                label: Text('System'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_rounded),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_rounded),
                label: Text('Dark'),
              ),
            ],
            selected: {?selected},
            onSelectionChanged: (choice) async {
              if (choice.isEmpty) return;
              final p = context.read<ThemeProvider>();
              if (p.isOutdoorMode) await p.setOutdoorMode(false);
              await p.setThemeMode(choice.first);
            },
          ),
        ),
      ],
    );
  }
}
