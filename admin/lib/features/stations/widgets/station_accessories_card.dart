import 'package:erefill/core/constants.dart';
import 'package:erefill/features/dashboard/owner/services/accessory_repository.dart';
import 'package:flutter/material.dart';

import '../../../widgets/admin_ui.dart';

/// Accessories a station sells (caps, seals, gallons, dispensers), with an
/// admin "Remove" action for listings that break the rules.
///
/// [onRemove] gets the product id and the admin's reason. Accessories that
/// are already on orders are hidden by the server instead of deleted.
class StationAccessoriesCard extends StatelessWidget {
  const StationAccessoriesCard({
    super.key,
    required this.rows,
    required this.onRemove,
  });

  final List<Map<String, dynamic>> rows;
  final Future<void> Function(String id, String reason) onRemove;

  Future<void> _confirm(BuildContext context, Accessory a) async {
    final reason = await showAdminPromptDialog(
      context,
      title: 'Remove ${a.name}?',
      subtitle:
          'Customers will no longer see it. If it is on past orders, '
          'it is hidden instead so receipts stay correct.',
      icon: Icons.delete_outline_rounded,
      iconColor: AppUi.error,
      label: 'Reason (shown in the audit log)',
      hint: 'e.g. Not a water accessory',
      confirmLabel: 'Remove',
    );
    if (reason == null) return;
    if (reason.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add a reason to remove an accessory.')),
        );
      }
      return;
    }
    await onRemove(a.id, reason);
  }

  @override
  Widget build(BuildContext context) {
    final items = [for (final r in rows) Accessory.fromRow(r)];
    return AdminCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Accessories (${items.length})',
                  style: adminSectionTitleStyle(context),
                ),
                const SizedBox(height: 2),
                Text(
                  'Added by the owner and sold next to their water',
                  style: adminCaptionTextStyle(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: AdminEmptyState(
                message: 'This station sells no accessories.',
                icon: Icons.inventory_2_outlined,
              ),
            )
          else
            for (final (i, a) in items.indexed) ...[
              if (i > 0) const Divider(height: 1),
              ListTile(
                leading: AccessoryThumb(accessory: a),
                title: Text(
                  a.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  '${Accessory.categories[a.category]} · '
                  '${a.isAvailable ? 'Shown to customers' : 'Hidden'} · '
                  '${a.inStock ? '${a.stock} in stock' : 'Out of stock'}',
                  style: adminCaptionTextStyle(context),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatPeso(a.price),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppUi.brandOf(context),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Remove ${a.name}',
                      icon: const Icon(Icons.delete_outline_rounded),
                      color: AppUi.error,
                      onPressed: () => _confirm(context, a),
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}
