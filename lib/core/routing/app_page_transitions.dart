import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Smooth, high-performance slide and fade page transition for pushed routes.
///
/// Features a subtle horizontal glide with natural deceleration
/// and a soft opacity blend, providing fluid navigation.
CustomTransitionPage<T> fadeSlidePage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      final slideTween = Tween<Offset>(
        begin: const Offset(0.06, 0.0),
        end: Offset.zero,
      );

      final fadeTween = Tween<double>(
        begin: 0.0,
        end: 1.0,
      );

      return SlideTransition(
        position: slideTween.animate(curvedAnimation),
        child: FadeTransition(
          opacity: fadeTween.animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}

GoRoute fadeSlideGoRoute({
  required String path,
  required Widget Function(BuildContext, GoRouterState) builder,
  List<RouteBase> routes = const [],
}) {
  return GoRoute(
    path: path,
    pageBuilder: (context, state) => fadeSlidePage(
      key: state.pageKey,
      child: builder(context, state),
    ),
    routes: routes,
  );
}
