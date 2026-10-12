import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/utils/safe_supabase.dart';
import 'package:erefill/core/widgets/app_header.dart';
import 'package:erefill/widgets/app_widgets.dart';
import 'rider_management_screen.dart';

class RiderPerformanceScreen extends StatefulWidget {
  final String riderId;
  final String riderName;

  const RiderPerformanceScreen({
    super.key,
    required this.riderId,
    required this.riderName,
  });

  @override
  State<RiderPerformanceScreen> createState() => _RiderPerformanceScreenState();
}

class _RiderPerformanceScreenState extends State<RiderPerformanceScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  Map<String, dynamic>? _riderProfile;
  Map<String, dynamic> _performance = {
    'totalDeliveries': 0,
    'monthlyDeliveries': 0,
    'totalEarnings': 0.0,
    'totalOrderValue': 0.0,
    'onTimeRate': 0.0,
    'rating': 0.0,
  };
  List<Map<String, dynamic>> _recentDeliveries = [];

  @override
  void initState() {
    super.initState();
    _loadPerformanceData();
  }

  Future<void> _loadPerformanceData() async {
    try {
      // 1. Fetch rider's authoritative profile record
      final profileData = await supabase
          .from('profiles')
          .select()
          .eq('id', widget.riderId)
          .maybeSingle();

      // 2. Get all completed deliveries for this rider
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1).toIso8601String();

      final deliveries = await supabase
          .from('orders')
          .select('*, customer:customer_id(full_name)')
          .eq('assigned_rider_id', widget.riderId)
          .eq('status', 'delivered')
          .order('updated_at', ascending: false);

      final monthlyDeliveries = await supabase
          .from('orders')
          .select('total_amount, delivery_fee')
          .eq('assigned_rider_id', widget.riderId)
          .eq('status', 'delivered')
          .gte('updated_at', monthStart);

      // Calculate metrics
      final totalDeliveries = deliveries.length;
      final monthlyCount = monthlyDeliveries.length;

      final totalEarnings = monthlyDeliveries.fold<double>(
        0,
        (sum, d) => sum + ((d['delivery_fee'] as num?)?.toDouble() ?? 0),
      );

      final totalOrderValue = monthlyDeliveries.fold<double>(
        0,
        (sum, d) => sum + ((d['total_amount'] as num?)?.toDouble() ?? 0),
      );

      final onTimeRate = _calculateOnTimeRate(deliveries);
      final rating = _deriveRating(totalDeliveries, onTimeRate);

      if (mounted) {
        setState(() {
          _riderProfile = profileData != null ? Map<String, dynamic>.from(profileData) : null;
          _performance = {
            'totalDeliveries': totalDeliveries,
            'monthlyDeliveries': monthlyCount,
            'totalEarnings': totalEarnings,
            'totalOrderValue': totalOrderValue,
            'onTimeRate': onTimeRate,
            'rating': rating,
          };
          _recentDeliveries = List<Map<String, dynamic>>.from(
            deliveries.take(5),
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading performance: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatCurrency(double amount) {
    return '₱${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
  }

  double _calculateOnTimeRate(List<dynamic> deliveries) {
    if (deliveries.isEmpty) return 0;

    var measured = 0;
    var onTime = 0;
    for (final raw in deliveries) {
      if (raw is! Map) continue;
      final createdAt = _parseDate(raw['created_at']);
      final completedAt =
          _parseDate(raw['actual_completion_at']) ??
          _parseDate(raw['delivered_at']) ??
          _parseDate(raw['updated_at']);
      if (createdAt == null || completedAt == null) continue;

      measured += 1;
      final minutes = completedAt.difference(createdAt).inMinutes;
      if (minutes <= 60) onTime += 1;
    }

    if (measured == 0) return 0;
    return onTime / measured;
  }

  double _deriveRating(int completedDeliveries, double onTimeRate) {
    if (completedDeliveries == 0) return 0;
    final score = 3.0 + (onTimeRate * 2.0);
    return double.parse(score.clamp(1.0, 5.0).toStringAsFixed(1));
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  @override
  Widget build(BuildContext context) {
    final totalDeliveries =
        (_performance['totalDeliveries'] as num?)?.toInt() ?? 0;
    final rating = (_performance['rating'] as num?)?.toDouble() ?? 0;
    final onTimeRate =
        (_performance['onTimeRate'] as num?)?.toDouble() ?? 0;

    final p = _riderProfile ?? {};
    final displayName = p['full_name']?.toString() ?? widget.riderName;
    final username = p['username']?.toString() ?? 'username';
    final rawPhone = p['phone']?.toString().trim();
    final phone = (rawPhone != null && rawPhone.isNotEmpty) ? rawPhone : null;
    final rawVehicle = p['vehicle_type']?.toString().trim();
    final vehicle = (rawVehicle != null && rawVehicle.isNotEmpty) ? rawVehicle : null;
    final rawLicense = p['license_number']?.toString().trim();
    final license = (rawLicense != null && rawLicense.isNotEmpty) ? rawLicense : null;
    final rawEmail = p['email']?.toString().trim();
    final email = (rawEmail != null && rawEmail.isNotEmpty) ? rawEmail : null;
    final isOnline = p['is_online'] == true;
    final isSuspended = p['is_suspended'] == true;
    final registeredDate = _formatDate(p['created_at']?.toString());

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      appBar: AppTopBar(
        title: displayName,
        subtitle: 'Rider intelligence',
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: AppUi.bluePrimary,
            tooltip: 'Edit Rider Information',
            onPressed: () async {
              HapticFeedback.lightImpact();
              final riderMap = _riderProfile ?? {
                'id': widget.riderId,
                'full_name': widget.riderName,
              };
              final updated = await RiderManagementScreen.showEditRiderCredentialsDialog(
                context,
                riderMap,
                onUpdated: _loadPerformanceData,
              );
              if (updated == true && mounted) {
                await _loadPerformanceData();
              }
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert_rounded,
              size: 20,
              color: AppUi.textMuted,
            ),
            tooltip: 'Rider Actions',
            shape: RoundedRectangleBorder(
              borderRadius: AppUi.cardRadius,
            ),
            onSelected: (val) {
              HapticFeedback.lightImpact();
              final riderMap = _riderProfile ?? {
                'id': widget.riderId,
                'full_name': widget.riderName,
                'is_suspended': isSuspended,
              };
              if (val == 'status') {
                RiderManagementScreen.showToggleStatusDialog(
                  context,
                  riderMap,
                  onStatusChanged: _loadPerformanceData,
                );
              } else if (val == 'unlink') {
                RiderManagementScreen.showUnlinkRiderDialog(
                  context,
                  riderMap,
                  onUnlinked: () {
                    if (context.mounted) Navigator.of(context).pop();
                  },
                );
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'status',
                child: Row(
                  children: [
                    Icon(
                      isSuspended
                          ? Icons.check_circle_outline
                          : Icons.block_outlined,
                      size: 18,
                      color: isSuspended
                          ? const Color(0xFF10B981)
                          : Colors.orange,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      isSuspended ? 'Activate Rider' : 'Suspend Rider',
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'unlink',
                child: Row(
                  children: [
                    Icon(
                      Icons.person_remove_outlined,
                      size: 18,
                      color: Color(0xFFEF4444),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Unlink from Station',
                      style: TextStyle(
                        color: Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const LoadingState(message: 'Loading rider performance...')
          : SingleChildScrollView(
              padding: AppUi.pagePaddingLoose,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Rider Profile Information Card
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: AppUi.cardPaddingLoose,
                    decoration: BoxDecoration(
                      color: AppUi.surfaceOf(context),
                      borderRadius: AppUi.cardRadius,
                      border: Border.all(color: AppUi.borderOf(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: AppUi.bluePrimary.withValues(alpha: 0.1),
                                borderRadius: AppUi.cardRadius,
                              ),
                              child: const Icon(
                                Icons.two_wheeler_rounded,
                                color: AppUi.bluePrimary,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                      color: AppUi.textPrimaryOf(context),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '@$username',
                                    style: const TextStyle(
                                      color: AppUi.textMuted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: (isSuspended
                                        ? const Color(0xFFEF4444)
                                        : const Color(0xFF10B981))
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isSuspended ? 'SUSPENDED' : (isOnline ? 'ONLINE' : 'ACTIVE'),
                                style: TextStyle(
                                  color: isSuspended
                                      ? const Color(0xFFEF4444)
                                      : const Color(0xFF10B981),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 14),
                        // Profile fields grid
                        _detailRow(Icons.email_outlined, 'Email', email ?? 'Not specified'),
                        const SizedBox(height: 8),
                        _detailRow(Icons.phone_outlined, 'Phone', phone ?? 'Not specified'),
                        const SizedBox(height: 8),
                        _detailRow(Icons.two_wheeler_outlined, 'Vehicle', vehicle ?? 'Motorcycle / Standard'),
                        const SizedBox(height: 8),
                        _detailRow(Icons.badge_outlined, 'License', license ?? 'Not specified'),
                        const SizedBox(height: 8),
                        _detailRow(Icons.calendar_today_outlined, 'Registered', registeredDate),
                      ],
                    ),
                  ),

                  // Performance Header Card
                  Container(
                    width: double.infinity,
                    padding: AppUi.cardPaddingLoose,
                    decoration: BoxDecoration(
                      color: AppUi.surfaceOf(context),
                      borderRadius: AppUi.cardRadius,
                      border: Border.all(color: AppUi.borderOf(context)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Rider performance score',
                          style: TextStyle(
                            color: AppUi.textSecondaryOf(context),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Color(0xFFF59E0B),
                              size: 38,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              rating.toStringAsFixed(1),
                              style: TextStyle(
                                color: AppUi.textPrimaryOf(context),
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                            ),
                            const Text(
                              ' / 5.0',
                              style: TextStyle(
                                color: AppUi.textMuted,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            totalDeliveries == 0
                                ? 'NO DELIVERIES YET'
                                : '${(onTimeRate * 100).toInt()}% '
                                      'ON-TIME DELIVERY',
                            style: const TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  _sectionHeader('Key Insights'),
                  const SizedBox(height: 16),

                  // Stats Grid
                  Row(
                    children: [
                      Expanded(
                        child: _statCard(
                          'Total Trips',
                          '${_performance['totalDeliveries'] ?? 0}',
                          Icons.insights_rounded,
                          AppUi.bluePrimary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _statCard(
                          'Monthly',
                          '${_performance['monthlyDeliveries'] ?? 0}',
                          Icons.calendar_today_rounded,
                          const Color(0xFF6366F1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _statCard(
                          'Base Pay',
                          _formatCurrency(
                            (_performance['totalEarnings'] as num?)
                                    ?.toDouble() ??
                                0,
                          ),
                          Icons.wallet_rounded,
                          const Color(0xFF10B981),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _statCard(
                          'Logistics Val',
                          _formatCurrency(
                            (_performance['totalOrderValue'] as num?)
                                    ?.toDouble() ??
                                0,
                          ),
                          Icons.local_shipping_rounded,
                          const Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  _sectionHeader('Activity Log'),
                  const SizedBox(height: 16),

                  if (_recentDeliveries.isEmpty)
                    _emptyActivity()
                  else
                    ..._recentDeliveries.map(
                      (delivery) => _buildRecentItem(delivery),
                    ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w900,
        color: AppUi.textPrimaryOf(context),
        letterSpacing: 0,
      ),
    );
  }

  Widget _emptyActivity() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: AppUi.cardRadius,
        border: Border.all(color: AppUi.borderOf(context)),
      ),
      child: const EmptyState(
        icon: Icons.route_outlined,
        title: 'No completed deliveries yet',
        message:
            'Delivered refill orders assigned to this rider will appear here.',
      ),
    );
  }

  Widget _buildRecentItem(Map<String, dynamic> delivery) {
    final customerName = delivery['customer']?['full_name'] ?? 'Guest';
    final amount = (delivery['total_amount'] as num?)?.toDouble() ?? 0;
    final deliveredAt = delivery['delivered_at'] ?? delivery['updated_at'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: AppUi.pillRadius,
        border: Border.all(color: AppUi.borderOf(context)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF10B981),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customerName,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
                Text(
                  _formatDate(deliveredAt),
                  style: TextStyle(
                    color: AppUi.textSecondaryOf(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _formatCurrency(amount),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: AppUi.textPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: AppUi.pillRadius,
        border: Border.all(color: AppUi.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: AppUi.textSecondaryOf(context),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppUi.textPrimaryOf(context),
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? timestamp) {
    if (timestamp == null || timestamp.trim().isEmpty) return 'Unknown';

    final dt = SafeParse.dateTime(timestamp);
    if (dt == null) return 'Unknown';

    final local = dt.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppUi.bluePrimary),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 13,
            color: AppUi.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: AppUi.textPrimaryOf(context),
              fontWeight: FontWeight.w800,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
