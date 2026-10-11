import 'package:flutter/material.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/app_form_fields.dart';

class DeliveryCompletionDetails {
  const DeliveryCompletionDetails({
    this.deliveryNote,
    this.emptyGallonsReturned = 0,
  });

  final String? deliveryNote;
  final int emptyGallonsReturned;
}

/// Rider delivery completion: empty gallons + optional note.
Future<DeliveryCompletionDetails?> showDeliveryCompletionSheet(
  BuildContext context, {
  int suggestedEmptyGallons = 0,
}) {
  return showModalBottomSheet<DeliveryCompletionDetails>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppUi.surfaceOf(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _DeliveryCompletionSheet(
      suggestedEmptyGallons: suggestedEmptyGallons,
    ),
  );
}

class _DeliveryCompletionSheet extends StatefulWidget {
  const _DeliveryCompletionSheet({required this.suggestedEmptyGallons});

  final int suggestedEmptyGallons;

  @override
  State<_DeliveryCompletionSheet> createState() =>
      _DeliveryCompletionSheetState();
}

class _DeliveryCompletionSheetState extends State<_DeliveryCompletionSheet> {
  late int _emptyCount;
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _emptyCount = widget.suggestedEmptyGallons;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Complete delivery',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppUi.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Record empty gallons returned by the customer.',
            style: TextStyle(
              color: AppUi.textSecondaryOf(context),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Empty gallons returned',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppUi.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: _emptyCount > 0
                    ? () => setState(() => _emptyCount--)
                    : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              Expanded(
                child: Text(
                  '$_emptyCount',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: () => setState(() => _emptyCount++),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppFormField(
            controller: _noteController,
            label: 'Delivery Note (Optional)',
            prefixIcon: Icons.note_alt_outlined,
            maxLength: 240,
            maxLines: 2,
            compact: true,
          ),
          AppUi.vGapLg,
          AppFormSubmitButton(
            text: 'Confirm Delivery Details',
            icon: Icons.check_circle_rounded,
            onPressed: () => Navigator.pop(
              context,
              DeliveryCompletionDetails(
                emptyGallonsReturned: _emptyCount,
                deliveryNote: _noteController.text.trim().isEmpty
                    ? null
                    : _noteController.text.trim(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
