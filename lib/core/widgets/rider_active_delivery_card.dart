import 'package:flutter/material.dart';

import '../constants.dart';
import 'refill_status_widgets.dart';

double _safeDouble(dynamic value, {double fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  if (value is String) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9.-]'), '').trim();
    if (cleaned.isEmpty || cleaned == '-' || cleaned == '.') {
      return fallback;
    }
    return double.tryParse(cleaned) ?? fallback;
  }
  return double.tryParse(value.toString()) ?? fallback;
}

/// Hero card for rider's current active delivery.
class RiderActiveDeliveryCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback? onTap;

  const RiderActiveDeliveryCard({super.key, required this.order, this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = order['status']?.toString() ?? 'assigned_to_rider';
    final customer = (order['customer'] is Map)
        ? Map<String, dynamic>.from(order['customer'] as Map)
        : (order['profiles'] is Map)
            ? Map<String, dynamic>.from(order['profiles'] as Map)
            : null;
    final customerName = (customer?['full_name'] ??
            (customer?['first_name'] != null
                ? '${customer!['first_name']} ${customer['last_name'] ?? ''}'.trim()
                : null) ??
            order['customer_name'] ??
            order['full_name'] ??
            'Customer')
        .toString();
    final rawAddress = (customer?['complete_address'] ??
            order['delivery_address'] ??
            order['address'] ??
            customer?['barangay'] ??
            'Delivery address')
        .toString();
    final landmark = (order['customer_landmark'] ??
            order['landmark'] ??
            customer?['landmark'] ??
            '')
        .toString()
        .trim();
    final address = landmark.isNotEmpty && !rawAddress.toLowerCase().contains(landmark.toLowerCase())
        ? '$rawAddress (Near $landmark)'
        : rawAddress;
    final total = _safeDouble(order['total_amount']);
    final paymentMethod =
        (order['payment_method'] ?? 'cod').toString().toLowerCase();
    final paymentStatus =
        (order['payment_status'] ?? 'pending').toString().toLowerCase();
    final isPaid = paymentStatus == 'success' || paymentStatus == 'paid';
    final isCod = paymentMethod == 'cod' || paymentMethod == 'cash';

    return Material(
      color: AppUi.surfaceOf(context),
      borderRadius: BorderRadius.circular(AppUi.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppUi.radiusCard),
            color: AppUi.bluePrimary,
            boxShadow: [
              BoxShadow(
                color: AppUi.bluePrimary.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.local_shipping_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Active delivery',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  OrderStatusBadge(status: status, showIcon: false),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                customerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                address,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    '₱${total.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isPaid
                          ? const Color(0xFF10B981)
                          : isCod
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isPaid
                          ? 'PAID ONLINE'
                          : isCod
                          ? 'COLLECT CASH'
                          : 'UNPAID',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: AppUi.pillRadius,
                    ),
                    child: const Text(
                      'View delivery',
                      style: TextStyle(
                        color: AppUi.bluePrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
