import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Lightweight route page for pushed routes.
///
/// Most routes contain data-heavy lists or maps. Avoiding a full-screen fade
/// and slide keeps navigation responsive on lower-end devices.
CustomTransitionPage<T> fadeSlidePage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
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
