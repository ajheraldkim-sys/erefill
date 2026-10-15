import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:erefill/core/providers/connectivity_provider.dart';
import 'package:erefill/core/theme/app_colors.dart';

/// Banner shown in the offline delivery-management module when there is no network.
class DmOfflineBanner extends StatelessWidget {
  const DmOfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectivityProvider>(
      builder: (context, provider, _) {
        if (!provider.isOffline) return const SizedBox.shrink();

        return Material(
          color: AppColors.uiWarning,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Offline mode — changes sync when you reconnect',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
