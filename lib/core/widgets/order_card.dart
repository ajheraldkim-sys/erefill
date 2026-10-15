import 'package:flutter/material.dart';
import '../constants.dart';
import '../theme/app_colors.dart';
import 'press_bounce.dart';

/// Role-aware variants for the reusable [OrderCard].
enum OrderCardRole { customer, owner, rider, admin }

/// Reusable status badge/chip following the centralized semantic color system.
class OrderStatusChip extends StatelessWidget {
  final String? status;
  final bool showIcon;
  final bool uppercase;
  final bool onFullColorSurface;

  const OrderStatusChip({
    super.key,
    required this.status,
    this.showIcon = true,
    this.uppercase = false,
    this.onFullColorSurface = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = OrderStatusStyle.resolve(status, isDark: isDark);

    final bg = onFullColorSurface
        ? style.chipBackground
        : style.subtleBackground;
    final fg = onFullColorSurface
        ? style.chipForeground
        : style.primaryColor;
    final border = onFullColorSurface
        ? style.chipBorder
        : style.subtleBorder;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(style.icon, size: 12, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            uppercase ? style.label.toUpperCase() : style.label,
            style: TextStyle(
              fontSize: uppercase ? 10 : 11,
              color: fg,
              fontWeight: FontWeight.w800,
              letterSpacing: uppercase ? 0.6 : 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// A unified, premium full-color order card consumed across Customer,
/// Owner, Rider, and Admin views.
///
/// Features rich semantic status background, high-contrast accessible typography,
/// a compact status chip, refined shadows, and role-adapted action buttons.
class OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final OrderCardRole role;
  final VoidCallback? onTap;
  final Widget? trailingAction;
  final Widget? bottomAction;
  final bool isFullColor;

  const OrderCard({
    super.key,
    required this.order,
    this.role = OrderCardRole.customer,
    this.onTap,
    this.trailingAction,
    this.bottomAction,
    this.isFullColor = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = order['status']?.toString();
    final style = OrderStatusStyle.resolve(status, isDark: isDark);

    final orderId = (order['id'] ?? '').toString();
    final shortId = orderId.length > 8 ? orderId.substring(0, 8).toUpperCase() : orderId.toUpperCase();
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0.0;

    // Resolve party title and subtitle based on viewer role
    String title;
    String subtitle;
    IconData titleIcon;

    final customerObj = order['customer'] is Map
        ? Map<String, dynamic>.from(order['customer'] as Map)
        : (order['profiles'] is Map ? Map<String, dynamic>.from(order['profiles'] as Map) : null);
    final stationName = (order['profiles'] as Map<String, dynamic>?)?['station_name'] ??
        order['station_name']?.toString() ??
        'Water Station';
    final customerName = (order['customer_name'] ?? customerObj?['full_name'] ?? 'Customer').toString();
    final address = (order['customer_address'] ?? order['delivery_address'] ?? customerObj?['complete_address'] ?? 'Station Pickup').toString();

    switch (role) {
      case OrderCardRole.customer:
        title = stationName;
        subtitle = 'Order #$shortId';
        titleIcon = Icons.water_drop_rounded;
        break;
      case OrderCardRole.owner:
      case OrderCardRole.admin:
        title = customerName;
        subtitle = 'Order #$shortId · $address';
        titleIcon = Icons.person_rounded;
        break;
      case OrderCardRole.rider:
        title = customerName;
        subtitle = address;
        titleIcon = Icons.location_on_rounded;
        break;
    }

    final createdAtRaw = order['created_at']?.toString();
    final date = DateTime.tryParse(createdAtRaw ?? '')?.toLocal() ?? DateTime.now();
    final dateStr = '${date.day}/${date.month}/${date.year}';

    if (!isFullColor) {
      return _buildNeutralCard(
        context,
        style,
        title,
        subtitle,
        titleIcon,
        shortId,
        total,
        dateStr,
      );
    }

    return RepaintBoundary(
      child: PressBounce(
        onTap: onTap,
        pressedScale: 0.985,
        child: Container(
          decoration: BoxDecoration(
            color: style.cardBackground,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: style.primaryColor.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Title, Icon, and Status Chip
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(titleIcon, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          '$subtitle · $dateStr',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: style.cardSecondaryText,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OrderStatusChip(
                    status: status,
                    onFullColorSurface: true,
                    showIcon: true,
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Items summary string
              _buildItemsPreview(order, style.cardSecondaryText),

              const SizedBox(height: 14),

              // Bottom Row: Price pill & Action button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '₱${total.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (trailingAction != null)
                    trailingAction!
                  else if (onTap != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            role == OrderCardRole.customer ? 'View Details' : 'Manage',
                            style: TextStyle(
                              color: style.primaryColor,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 13,
                            color: style.primaryColor,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (bottomAction != null) ...[
                const SizedBox(height: 12),
                bottomAction!,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemsPreview(Map<String, dynamic> order, Color textColor) {
    String previewText = 'Refill order';
    final items = order['order_items'] ?? order['items'];
    if (items is List && items.isNotEmpty) {
      final names = items
          .map((i) {
            if (i is Map) {
              final qty = i['quantity'] ?? 1;
              final name = i['water_type'] ?? i['name'] ?? 'Refill';
              return '$qty× $name';
            }
            return 'Refill';
          })
          .take(2)
          .join(', ');
      previewText = names;
    }

    return Text(
      previewText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: textColor,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildNeutralCard(
    BuildContext context,
    OrderStatusStyle style,
    String title,
    String subtitle,
    IconData titleIcon,
    String shortId,
    double total,
    String dateStr,
  ) {
    return RepaintBoundary(
      child: PressBounce(
        onTap: onTap,
        pressedScale: 0.985,
        child: Container(
          decoration: BoxDecoration(
            color: AppUi.surfaceOf(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: style.primaryColor.withValues(alpha: 0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: style.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(titleIcon, color: style.primaryColor, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppUi.textPrimaryOf(context),
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '$subtitle · $dateStr',
                            style: TextStyle(
                              color: AppUi.textSecondaryOf(context),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OrderStatusChip(status: order['status']?.toString()),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '₱${total.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: style.primaryColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    ?trailingAction,
                  ],
                ),
                if (bottomAction != null) ...[
                  const SizedBox(height: 12),
                  bottomAction!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
