import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class DownloadProgress {
  final int bytesDownloaded;
  final int totalBytes;
  final double progressPercent;
  final bool isCompleted;
  final String? error;

  const DownloadProgress({
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.progressPercent,
    required this.isCompleted,
    this.error,
  });

  String get formattedDownloadedMb =>
      (bytesDownloaded / (1024 * 1024)).toStringAsFixed(1);
  String get formattedTotalMb =>
      totalBytes > 0 ? (totalBytes / (1024 * 1024)).toStringAsFixed(1) : '--';
}

class ApkDownloaderService {
  ApkDownloaderService._();
  static final ApkDownloaderService instance = ApkDownloaderService._();

  http.Client? _activeClient;
  bool _isDownloading = false;

  bool get isDownloading => _isDownloading;

  /// Download official APK from HTTPS source with progress streaming and SHA-256 validation.
  Stream<DownloadProgress> downloadApk({
    required String downloadUrl,
    String? expectedSha256,
  }) async* {
    if (_isDownloading) {
      throw StateError('A download is already in progress.');
    }

    _isDownloading = true;
    _activeClient = http.Client();

    final client = _activeClient!;
    File? tempFile;

    try {
      final uri = Uri.parse(downloadUrl);
      if (uri.scheme != 'https') {
        throw const FormatException('Security violation: APK download must use HTTPS.');
      }

      final request = http.Request('GET', uri);
      final response = await client.send(request);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Failed to download update artifact (HTTP ${response.statusCode})',
          uri: uri,
        );
      }

      final totalBytes = response.contentLength ?? -1;
      int bytesDownloaded = 0;

      final tempDir = await getTemporaryDirectory();
      tempFile = File('${tempDir.path}/eRefill_update.apk');
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      final sink = tempFile.openWrite();

      await for (final chunk in response.stream) {
        bytesDownloaded += chunk.length;
        sink.add(chunk);

        final percent = totalBytes > 0
            ? (bytesDownloaded / totalBytes).clamp(0.0, 1.0)
            : 0.0;

        yield DownloadProgress(
          bytesDownloaded: bytesDownloaded,
          totalBytes: totalBytes,
          progressPercent: percent,
          isCompleted: false,
        );
      }

      await sink.flush();
      await sink.close();

      // Verify SHA-256 Checksum if provided
      if (expectedSha256 != null && expectedSha256.trim().isNotEmpty) {
        final fileBytes = await tempFile.readAsBytes();
        final actualHash = sha256.convert(fileBytes).toString().toLowerCase();
        final cleanExpected = expectedSha256.trim().toLowerCase();

        if (actualHash != cleanExpected) {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
          throw StateError(
            'Cryptographic verification failed: Downloaded file checksum does not match official release signature.',
          );
        }
        debugPrint('SHA-256 signature verified successfully: $actualHash');
      }

      yield DownloadProgress(
        bytesDownloaded: bytesDownloaded,
        totalBytes: bytesDownloaded,
        progressPercent: 1.0,
        isCompleted: true,
      );

      // Trigger installation
      await installApk(
        file: tempFile,
        fallbackUrl: downloadUrl,
      );
    } catch (e) {
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      yield DownloadProgress(
        bytesDownloaded: 0,
        totalBytes: 0,
        progressPercent: 0,
        isCompleted: false,
        error: e.toString(),
      );
      rethrow;
    } finally {
      _isDownloading = false;
      client.close();
      _activeClient = null;
    }
  }

  /// Launch official APK or App Store URL using external application handler
  Future<bool> installApk({
    File? file,
    required String fallbackUrl,
  }) async {
    final uri = Uri.parse(fallbackUrl);

    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      debugPrint('Error launching installation URL: $e');
    }
    return false;
  }

  void cancelDownload() {
    _activeClient?.close();
    _activeClient = null;
    _isDownloading = false;
  }
}
