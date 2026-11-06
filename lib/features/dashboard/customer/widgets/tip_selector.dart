import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants.dart';
import '../checkout_rules.dart';

/// Optional rider tip at checkout: No tip / ₱10 / ₱20 / ₱50 / Other.
class TipSelector extends StatelessWidget {
  const TipSelector({super.key, required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  static const presets = <double>[10, 20, 50];

  Future<void> _custom(BuildContext context) async {
    final result = await showDialog<double>(
      context: context,
      builder: (_) => _CustomTipDialog(
        initial: value > 0 && !presets.contains(value) ? value : null,
      ),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCustom = value > 0 && !presets.contains(value);

    Widget chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.volunteer_activism_outlined,
                color: AppUi.brandOf(context), size: 20),
            const SizedBox(width: 8),
            Text('Tip your rider', style: theme.textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Optional · 100% goes to your rider',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            chip('No tip', value == 0, () => onChanged(0)),
            for (final p in presets)
              chip('₱${p.toStringAsFixed(0)}', value == p, () => onChanged(p)),
            chip(
              isCustom ? '₱${value.toStringAsFixed(0)}' : 'Other',
              isCustom,
              () => _custom(context),
            ),
          ],
        ),
      ],
    );
  }
}

class _CustomTipDialog extends StatefulWidget {
  const _CustomTipDialog({this.initial});
  final double? initial;

  @override
  State<_CustomTipDialog> createState() => _CustomTipDialogState();
}

class _CustomTipDialogState extends State<_CustomTipDialog> {
  late final _controller = TextEditingController(
    text: widget.initial?.toStringAsFixed(0) ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tip your rider'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          prefixText: '₱',
          helperText: 'Up to ₱500',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            CheckoutRules.normalizeTip(
              double.tryParse(_controller.text.trim()) ?? 0,
            ),
          ),
          child: const Text('Add tip'),
        ),
      ],
    );
  }
}
