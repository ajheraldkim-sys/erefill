import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/models/app_version_models.dart';
import 'package:erefill/core/services/apk_downloader_service.dart';

class OptionalUpdateDialog extends StatelessWidget {
  final AppUpdatePolicy policy;

  const OptionalUpdateDialog({super.key, required this.policy});

  static bool _hasShownThisSession = false;

  static Future<void> show(BuildContext context, AppUpdatePolicy policy) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => OptionalUpdateDialog(policy: policy),
    );
  }

  static Future<void> maybeShow(BuildContext context, AppUpdatePolicy policy) async {
    if (_hasShownThisSession) return;
    _hasShownThisSession = true;
    await show(context, policy);
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = AppUi.bluePrimary;

    return AlertDialog(
      backgroundColor: AppUi.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.system_update_alt_rounded, color: primaryColor, size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Update Available',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A new version of eRefill (v${policy.latestVersion}) is now available.',
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
            ),
            const SizedBox(height: 12),
            if (policy.releaseNotes.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppUi.pageBgOf(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppUi.borderOf(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Highlights:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      policy.releaseNotes,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppUi.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            Text(
              'Would you like to install the latest version now?',
              style: TextStyle(
                fontSize: 13,
                color: AppUi.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Later'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
            ApkDownloaderService.instance.installApk(
              fallbackUrl: policy.downloadUrl,
            );
          },
          child: const Text('Update Now'),
        ),
      ],
    );
  }
}
