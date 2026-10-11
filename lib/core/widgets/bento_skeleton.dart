import 'package:flutter/material.dart';

import 'skeleton.dart';

class BentoSkeleton extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const BentoSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }

  static Widget listPlaceholder() {
    return const Column(
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BentoSkeleton(width: 80, height: 12),
              SizedBox(height: 8),
              BentoSkeleton(width: double.infinity, height: 100),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  BentoSkeleton(width: 120, height: 16),
                  BentoSkeleton(width: 60, height: 16),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BentoSkeleton(width: 80, height: 12),
              SizedBox(height: 8),
              BentoSkeleton(width: double.infinity, height: 100),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  BentoSkeleton(width: 120, height: 16),
                  BentoSkeleton(width: 60, height: 16),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BentoSkeleton(width: 80, height: 12),
              SizedBox(height: 8),
              BentoSkeleton(width: double.infinity, height: 100),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  BentoSkeleton(width: 120, height: 16),
                  BentoSkeleton(width: 60, height: 16),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
