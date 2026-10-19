import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants.dart';
import '../../../core/services/station_data_cache.dart';
import '../../../core/widgets/app_form_fields.dart';

import 'package:erefill/core/theme/app_colors.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
class ReviewModal extends StatefulWidget {
  final String orderId;
  final String stationId;
  final String stationName;
  final VoidCallback? onReviewSubmitted;

  const ReviewModal({
    super.key,
    required this.orderId,
    required this.stationId,
    required this.stationName,
    this.onReviewSubmitted,
  });

  @override
  State<ReviewModal> createState() => _ReviewModalState();

  static void show({
    required BuildContext context,
    required String orderId,
    required String stationId,
    required String stationName,
    VoidCallback? onReviewSubmitted,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppUi.radiusSheet)),
      ),
      builder: (context) => ReviewModal(
        orderId: orderId,
        stationId: stationId,
        stationName: stationName,
        onReviewSubmitted: onReviewSubmitted,
      ),
    );
  }
}

class _ReviewModalState extends State<ReviewModal> {
  final supabase = Supabase.instance.client;
  final _commentController = TextEditingController();
  int _selectedRating = 5;
  bool _isSubmitting = false;

  Future<void> _submitReview() async {
    final customerId = supabase.auth.currentUser?.id;
    if (customerId == null) return;

    setState(() => _isSubmitting = true);

    try {
      // Check if review already exists for this order
      final existingReview = await supabase
          .from('reviews')
          .select('id')
          .eq('order_id', widget.orderId)
          .maybeSingle();

      if (existingReview != null) {
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You have already reviewed this order'),
            backgroundColor: AppColors.uiWarning,
          ),
        );
        return;
      }

      // Submit the review
      await supabase.from('reviews').insert({
        'order_id': widget.orderId,
        'customer_id': customerId,
        'station_id': widget.stationId,
        'rating': _selectedRating,
        'comment': _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
      });

      // Invalidate cache immediately so new review and updated ratings appear instantaneously
      StationDataCache.instance.invalidate(widget.stationId);
      unawaited(
        StationDataCache.instance.getOrFetch(
          widget.stationId,
          forceRefresh: true,
        ),
      );

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Thanks for rating ${widget.stationName} $_selectedRating stars!',
          ),
          backgroundColor: AppColors.uiSuccess,
        ),
      );

      widget.onReviewSubmitted?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit review: ${FriendlyErrors.message(e)}'),
          backgroundColor: AppColors.uiError,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppUi.dividerOf(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Text(
            'Rate ${widget.stationName}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'How was your delivery experience?',
            style: TextStyle(fontSize: 14, color: AppUi.textMutedOf(context)),
          ),
          const SizedBox(height: 24),

          // Star Rating
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starValue = index + 1;
                return IconButton(
                  onPressed: () => setState(() => _selectedRating = starValue),
                  icon: Icon(
                    starValue <= _selectedRating
                        ? Icons.star
                        : Icons.star_border,
                    color: AppColors.uiWarning,
                    size: 40,
                  ),
                  tooltip: '$starValue star${starValue == 1 ? '' : 's'}',
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  constraints: const BoxConstraints(),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              _getRatingText(_selectedRating),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.uiWarning,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Comment Field
          AppFormField(
            controller: _commentController,
            label: 'Feedback (Optional)',
            hintText: 'Tell us about your experience...',
            prefixIcon: Icons.rate_review_outlined,
            maxLines: 3,
            compact: true,
          ),
          AppUi.vGapLg,

          // Submit Button
          AppFormSubmitButton(
            text: 'Submit Review',
            icon: Icons.send_rounded,
            isLoading: _isSubmitting,
            onPressed: _submitReview,
          ),
          AppUi.vGapMd,
        ],
      ),
    );
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      case 5:
        return 'Excellent!';
      default:
        return '';
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }
}
