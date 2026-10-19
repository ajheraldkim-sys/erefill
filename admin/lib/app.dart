import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:erefill/core/constants.dart';

import '../providers/admin_auth_provider.dart';
import '../shell/admin_shell.dart';
import '../theme/admin_theme.dart';
import 'features/auth/login_screen.dart';

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'eRefill Admin',
      debugShowCheckedModeBanner: false,
      theme: AdminTheme.dark,
      darkTheme: AdminTheme.dark,
      themeMode: ThemeMode.dark,
      localizationsDelegates: const [shadcn.ShadcnLocalizations.delegate],
      builder: (context, child) {
        return shadcn.ShadcnLayer(
          theme: shadcn.ThemeData(
            colorScheme: shadcn.ColorSchemes.lightZinc.copyWith(
              primary: () => AppUi.bluePrimary,
              primaryForeground: () => Colors.white,
              destructive: () => AppUi.error,
              destructiveForeground: () => Colors.white,
              ring: () => AppUi.bluePrimary,
            ),
            radius: 0.5,
          ),
          darkTheme: shadcn.ThemeData.dark(
            colorScheme: shadcn.ColorSchemes.darkZinc.copyWith(
              background: () => AppUi.darkPageBg,
              foreground: () => AppUi.darkTextPrimary,
              card: () => AppUi.darkSurface,
              cardForeground: () => AppUi.darkTextPrimary,
              popover: () => AppUi.darkSurfaceRaised,
              popoverForeground: () => AppUi.darkTextPrimary,
              primary: () => AppUi.accentCyan,
              primaryForeground: () => AppUi.darkPageBg,
              secondary: () => AppUi.darkSurfaceRaised,
              secondaryForeground: () => AppUi.darkTextPrimary,
              muted: () => AppUi.darkSurfaceRaised,
              mutedForeground: () => AppUi.darkTextSecondary,
              accent: () => AppUi.darkSurfaceRaised,
              accentForeground: () => AppUi.darkTextPrimary,
              destructive: () => AppUi.errorFgDark,
              destructiveForeground: () => AppUi.darkPageBg,
              border: () => AppUi.borderDark,
              input: () => AppUi.borderDark,
              ring: () => AppUi.accentCyan,
            ),
            radius: 0.5,
          ),
          themeMode: shadcn.ThemeMode.dark,
          child: _AdminShadcnButtonThemes(
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const _AdminRoot(),
    );
  }
}

class _AdminShadcnButtonThemes extends StatelessWidget {
  const _AdminShadcnButtonThemes({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return shadcn.ComponentTheme<shadcn.OutlineButtonTheme>(
      data: shadcn.OutlineButtonTheme(
        decoration: (context, states, _) {
          final scheme = shadcn.Theme.of(context).colorScheme;
          final disabled = states.contains(WidgetState.disabled);
          final hovered = states.contains(WidgetState.hovered);
          return BoxDecoration(
            color: disabled
                ? scheme.muted
                : scheme.primary.withValues(alpha: hovered ? 0.2 : 0.1),
            border: Border.all(
              color: disabled
                  ? scheme.border
                  : scheme.primary.withValues(alpha: hovered ? 0.9 : 0.65),
            ),
            borderRadius: shadcn.Theme.of(context).borderRadiusMd,
          );
        },
        textStyle: (context, states, defaultValue) {
          final scheme = shadcn.Theme.of(context).colorScheme;
          return defaultValue.copyWith(
            color: states.contains(WidgetState.disabled)
                ? scheme.mutedForeground
                : scheme.primary,
          );
        },
        iconTheme: (context, states, defaultValue) {
          final scheme = shadcn.Theme.of(context).colorScheme;
          return defaultValue.copyWith(
            color: states.contains(WidgetState.disabled)
                ? scheme.mutedForeground
                : scheme.primary,
          );
        },
      ),
      child: shadcn.ComponentTheme<shadcn.GhostButtonTheme>(
        data: shadcn.GhostButtonTheme(
          decoration: (context, states, _) {
            final scheme = shadcn.Theme.of(context).colorScheme;
            return BoxDecoration(
              color: states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused) ||
                      states.contains(WidgetState.pressed)
                  ? scheme.primary.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: shadcn.Theme.of(context).borderRadiusMd,
            );
          },
          textStyle: (context, states, defaultValue) {
            final scheme = shadcn.Theme.of(context).colorScheme;
            return defaultValue.copyWith(
              color: states.contains(WidgetState.disabled)
                  ? scheme.mutedForeground
                  : scheme.primary,
            );
          },
          iconTheme: (context, states, defaultValue) {
            final scheme = shadcn.Theme.of(context).colorScheme;
            return defaultValue.copyWith(
              color: states.contains(WidgetState.disabled)
                  ? scheme.mutedForeground
                  : scheme.primary,
            );
          },
        ),
        child: child,
      ),
    );
  }
}

class _AdminRoot extends StatelessWidget {
  const _AdminRoot();

  @override
  Widget build(BuildContext context) {
    return Consumer<AdminAuthProvider>(
      builder: (context, auth, _) {
        if (auth.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!auth.isAuthenticated || !auth.isAdmin) {
          return const LoginScreen();
        }

        return AdminShell(displayName: auth.displayName);
      },
    );
  }
}
