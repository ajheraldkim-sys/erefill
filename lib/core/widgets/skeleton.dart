import 'package:flutter/material.dart';
import 'package:erefill/core/constants.dart';

/// A lightweight animated pulse skeleton loader.
class Skeleton extends StatefulWidget {
  final double? width;
  final double? height;
  final double borderRadius;
  final bool isCircle;

  const Skeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8,
    this.isCircle = false,
  });

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark
        ? AppUi.darkSurfaceRaised
        : AppUi.lightSurfaceRaised;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Opacity(
        opacity: _animation.value,
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: base,
            shape: widget.isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.isCircle
                ? null
                : BorderRadius.circular(widget.borderRadius),
          ),
        ),
      ),
    );
  }
}

class AppLoadingSkeleton extends StatelessWidget {
  const AppLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const Skeleton(height: 116, borderRadius: 24),
              const SizedBox(height: 18),
              const Skeleton(height: 52, borderRadius: 16),
              const SizedBox(height: 20),
              const Skeleton(width: 150, height: 18),
              const SizedBox(height: 12),
              const Expanded(
                child: Column(
                  children: [
                    Expanded(child: CardSkeleton()),
                    SizedBox(height: 12),
                    Expanded(child: CardSkeleton()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A skeleton loader for list tile items
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Skeleton(width: 50, height: 50, borderRadius: 25),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(
                  width: MediaQuery.sizeOf(context).width * 0.4,
                  height: 16,
                ),
                const SizedBox(height: 8),
                Skeleton(
                  width: MediaQuery.sizeOf(context).width * 0.6,
                  height: 12,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A skeleton loader for grid/card items
class CardSkeleton extends StatelessWidget {
  const CardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppUi.cardDecorationOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Skeleton(height: 120, borderRadius: 16),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Skeleton(width: 100, height: 14),
                const SizedBox(height: 8),
                const Skeleton(width: 60, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A list of skeleton items
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int)? itemDelegate;
  final EdgeInsets? padding;

  const SkeletonList({
    super.key,
    this.itemCount = 6,
    this.itemDelegate,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: padding ?? const EdgeInsets.all(16),
      itemCount: itemCount,
      itemBuilder: itemDelegate ?? (context, index) => const ListSkeleton(),
    );
  }
}
