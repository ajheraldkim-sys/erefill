import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/theme/app_colors.dart';
import 'package:erefill/core/utils/app_haptics.dart';

class AdminModerationView extends StatefulWidget {
  const AdminModerationView({super.key});

  @override
  State<AdminModerationView> createState() => _AdminModerationViewState();
}

class _AdminModerationViewState extends State<AdminModerationView>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late final TabController _tabController;

  List<Map<String, dynamic>> _disputes = [];
  List<Map<String, dynamic>> _reviews = [];
  bool _loading = true;
  String? _error;
  String _disputeFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1. Fetch Disputes
      List<Map<String, dynamic>> disputes = [];
      try {
        final res = await supabase
            .from('disputes')
            .select('*')
            .order('created_at', ascending: false)
            .limit(50);
        disputes = List<Map<String, dynamic>>.from(res);
      } catch (_) {
        // Fallback: Check orders with refund/cancel disputes
        final res = await supabase
            .from('orders')
            .select('*')
            .eq('status', 'cancelled')
            .order('created_at', ascending: false)
            .limit(20);
        disputes = List<Map<String, dynamic>>.from(res).map((o) => {
          'id': o['id'],
          'order_id': o['id'],
          'reason': o['notes'] ?? 'Order cancelled / disputed by user',
          'status': 'open',
          'created_at': o['created_at'],
          'customer_name': o['customer_name'] ?? 'Customer',
        }).toList();
      }

      // 2. Fetch Flagged / Low Reviews
      List<Map<String, dynamic>> reviews = [];
      try {
        final res = await supabase
            .from('reviews')
            .select('*')
            .lte('rating', 2)
            .order('created_at', ascending: false)
            .limit(50);
        reviews = List<Map<String, dynamic>>.from(res);
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _disputes = disputes;
        _reviews = reviews;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolveDispute(Map<String, dynamic> dispute, String newStatus) async {
    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(newStatus == 'resolved' ? 'Resolve Dispute' : 'Dismiss Dispute'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dispute #${dispute['id']?.toString().substring(0, 8) ?? ""}'),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'Resolution Notes',
                hintText: 'Enter findings or action taken…',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus == 'resolved'
                  ? AppColors.statusDelivered
                  : AppColors.statusCancelled,
              foregroundColor: Colors.white,
            ),
            child: Text(newStatus == 'resolved' ? 'Resolve' : 'Dismiss'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      AppHaptics.medium();
      await supabase.from('disputes').update({
        'status': newStatus,
        'resolution_notes': notesController.text.trim(),
        'resolved_at': DateTime.now().toIso8601String(),
      }).eq('id', dispute['id']);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dispute marked as $newStatus'),
          backgroundColor: AppColors.statusDelivered,
        ),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppUi.error),
      );
    }
  }

  Future<void> _deleteReview(Map<String, dynamic> review) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Review?'),
        content: const Text(
          'This will permanently delete this review from the station profile. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppUi.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      AppHaptics.medium();
      await supabase.from('reviews').delete().eq('id', review['id']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Review removed from station profile'),
          backgroundColor: AppColors.statusDelivered,
        ),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting review: $e'), backgroundColor: AppUi.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      appBar: AppBar(
        backgroundColor: AppUi.surfaceOf(context),
        elevation: 0,
        title: Text(
          'Moderation & Disputes',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppUi.textPrimaryOf(context),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppUi.bluePrimary,
          unselectedLabelColor: AppUi.textMuted,
          indicatorColor: AppUi.bluePrimary,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.gavel_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text('Disputes (${_disputes.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star_half_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text('Flagged Reviews (${_reviews.length})'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppUi.bluePrimary))
          : _error != null && _disputes.isEmpty && _reviews.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppUi.error, size: 40),
                        const SizedBox(height: 8),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDisputesTab(),
                    _buildReviewsTab(),
                  ],
                ),
    );
  }

  Widget _buildDisputesTab() {
    final filtered = _disputes.where((d) {
      if (_disputeFilter == 'all') return true;
      return (d['status']?.toString().toLowerCase() ?? 'open') == _disputeFilter;
    }).toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppUi.surfaceOf(context),
          child: Row(
            children: [
              _filterChip('All', 'all'),
              const SizedBox(width: 8),
              _filterChip('Open', 'open'),
              const SizedBox(width: 8),
              _filterChip('Resolved', 'resolved'),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 48, color: AppColors.statusDelivered),
                      const SizedBox(height: 12),
                      Text(
                        'No disputes found',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppUi.textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Everything in the marketplace is running smoothly.',
                        style: TextStyle(color: AppUi.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final d = filtered[index];
                    final status = (d['status'] ?? 'open').toString().toLowerCase();
                    final isOpen = status == 'open';

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppUi.surfaceOf(context),
                        borderRadius: AppUi.radiusLg,
                        border: Border.all(color: AppUi.borderOf(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (isOpen ? AppColors.statusPending : AppColors.statusDelivered)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: isOpen ? AppColors.statusPending : AppColors.statusDelivered,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Order #${(d['order_id'] ?? d['id']).toString().substring(0, 8)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: AppUi.textPrimaryOf(context),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            d['reason'] ?? 'No complaint details provided',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppUi.textPrimaryOf(context),
                            ),
                          ),
                          if (d['resolution_notes'] != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppUi.pageBgOf(context),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Resolution: ${d['resolution_notes']}',
                                style: TextStyle(fontSize: 11, color: AppUi.textSecondaryOf(context)),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          if (isOpen)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton(
                                  onPressed: () => _resolveDispute(d, 'dismissed'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    foregroundColor: AppUi.error,
                                  ),
                                  child: const Text('Dismiss'),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () => _resolveDispute(d, 'resolved'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    backgroundColor: AppColors.statusDelivered,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Mark Resolved'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildReviewsTab() {
    if (_reviews.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.star_rounded, size: 48, color: Color(0xFFF59E0B)),
            const SizedBox(height: 12),
            Text(
              'No low-rating reviews',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppUi.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Station ratings and customer satisfaction are high!',
              style: TextStyle(color: AppUi.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _reviews.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final r = _reviews[index];
        final rating = (r['rating'] as num?)?.toInt() ?? 1;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppUi.surfaceOf(context),
            borderRadius: AppUi.radiusLg,
            border: Border.all(color: AppUi.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Row(
                    children: List.generate(
                      5,
                      (i) => Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: i < rating ? const Color(0xFFF59E0B) : AppUi.textMuted.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: AppUi.error, size: 20),
                    tooltip: 'Delete review',
                    onPressed: () => _deleteReview(r),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                r['comment'] ?? 'No comment written',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Station ID: ${r['station_id'] ?? "Unknown"} • User: ${r['user_id'] ?? "Anonymous"}',
                style: TextStyle(fontSize: 11, color: AppUi.textMuted),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _disputeFilter == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        AppHaptics.selection();
        setState(() => _disputeFilter = value);
      },
      selectedColor: AppUi.blueSoft,
      checkmarkColor: AppUi.bluePrimary,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: selected ? AppUi.bluePrimary : AppUi.textSecondaryOf(context),
      ),
    );
  }
}
