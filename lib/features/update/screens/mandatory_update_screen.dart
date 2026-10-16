import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/models/app_version_models.dart';
import 'package:erefill/core/services/app_update_service.dart';
import 'package:erefill/core/services/apk_downloader_service.dart';
import 'package:erefill/core/widgets/brand/erefill_logo.dart';

class MandatoryUpdateScreen extends StatefulWidget {
  final AppUpdatePolicy? policy;

  const MandatoryUpdateScreen({super.key, this.policy});

  @override
  State<MandatoryUpdateScreen> createState() => _MandatoryUpdateScreenState();
}

class _MandatoryUpdateScreenState extends State<MandatoryUpdateScreen> {
  StreamSubscription<DownloadProgress>? _downloadSub;
  DownloadProgress? _progress;
  bool _isDownloading = false;
  String? _errorMessage;

  AppUpdatePolicy get _effectivePolicy =>
      widget.policy ??
      AppUpdateService.instance.currentPolicy ??
      AppUpdatePolicy.initial();

  @override
  void dispose() {
    _downloadSub?.cancel();
    super.dispose();
  }

  void _startUpdate() {
    final policy = _effectivePolicy;
    if (policy.downloadUrl.isEmpty) {
      setState(() {
        _errorMessage = 'Download link is unavailable. Please check your internet connection.';
      });
      return;
    }

    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = const DownloadProgress(
        bytesDownloaded: 0,
        totalBytes: 0,
        progressPercent: 0,
        isCompleted: false,
      );
    });
    HapticFeedback.lightImpact();

    _downloadSub?.cancel();
    _downloadSub = ApkDownloaderService.instance
        .downloadApk(
          downloadUrl: policy.downloadUrl,
          expectedSha256: policy.checksumSha256,
        )
        .listen(
          (progress) {
            if (!mounted) return;
            setState(() {
              _progress = progress;
              if (progress.isCompleted) {
                _isDownloading = false;
              }
            });
          },
          onError: (error) {
            if (!mounted) return;
            setState(() {
              _isDownloading = false;
              _errorMessage = error.toString().replaceFirst('Exception: ', '');
            });
          },
        );
  }

  Future<void> _checkAgain() async {
    HapticFeedback.lightImpact();
    setState(() => _errorMessage = null);
    await AppUpdateService.instance.checkForUpdates(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final policy = _effectivePolicy;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppUi.bluePrimary;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // Strict guard: Prevent back navigation out of mandatory update
        HapticFeedback.heavyImpact();
      },
      child: Scaffold(
        backgroundColor: AppUi.pageBgOf(context),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Brand Icon & Logo
                    const ERefillLogo(size: 80),
                    const SizedBox(height: 24),

                    // Critical Alert Icon Badge
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppUi.error.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.system_update_rounded,
                        color: AppUi.error,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Heading
                    Text(
                      'Update Required',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: AppUi.textPrimaryOf(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    Text(
                      'To continue using eRefill securely, you need to update to the latest supported version.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: AppUi.textSecondaryOf(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // Version Compare Badges
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppUi.surfaceOf(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppUi.borderOf(context)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'CURRENT VERSION',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                    color: AppUi.textSecondaryOf(context),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'v${policy.installedVersion} (Build ${policy.installedBuild})',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppUi.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            height: 36,
                            width: 1,
                            color: AppUi.borderOf(context),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'REQUIRED VERSION',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                    color: AppUi.textSecondaryOf(context),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'v${policy.latestVersion} (Build ${policy.latestBuild})',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppUi.successFg,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Release Notes Card
                    if (policy.releaseNotes.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : Colors.black.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppUi.borderOf(context)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.new_releases_outlined,
                                    size: 16, color: primaryColor),
                                const SizedBox(width: 8),
                                Text(
                                  'What\'s New in v${policy.latestVersion}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: AppUi.textPrimaryOf(context),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              policy.releaseNotes,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: AppUi.textSecondaryOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Progress or Error States
                    if (_isDownloading && _progress != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppUi.surfaceOf(context),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppUi.borderOf(context)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Downloading eRefill update...',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${(_progress!.progressPercent * 100).toInt()}%',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: primaryColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: _progress!.progressPercent > 0
                                    ? _progress!.progressPercent
                                    : null,
                                minHeight: 8,
                                backgroundColor: isDark
                                    ? Colors.white12
                                    : Colors.black12,
                                color: primaryColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_progress!.formattedDownloadedMb} MB of ${_progress!.formattedTotalMb} MB downloaded',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppUi.textSecondaryOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    if (_errorMessage != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppUi.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppUi.error.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: AppUi.error, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppUi.error,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Action Buttons
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _isDownloading ? null : _startUpdate,
                        icon: _isDownloading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.download_rounded, size: 22),
                        label: Text(
                          _isDownloading ? 'Preparing Installation...' : 'Update Now',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppUi.textSecondaryOf(context),
                      ),
                      onPressed: _isDownloading ? null : _checkAgain,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text(
                        'I have already updated — check again',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
