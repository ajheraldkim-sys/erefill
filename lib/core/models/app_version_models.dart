enum AppVersionStatus {
  supported,
  updateAvailable,
  updateRequired,
  maintenance,
  error;

  static AppVersionStatus fromString(String? value) {
    switch (value?.toUpperCase()) {
      case 'UPDATE_REQUIRED':
        return AppVersionStatus.updateRequired;
      case 'UPDATE_AVAILABLE':
        return AppVersionStatus.updateAvailable;
      case 'MAINTENANCE':
        return AppVersionStatus.maintenance;
      case 'VERSION_SUPPORTED':
        return AppVersionStatus.supported;
      default:
        return AppVersionStatus.supported;
    }
  }

  String get displayName {
    switch (this) {
      case AppVersionStatus.supported:
        return 'Supported';
      case AppVersionStatus.updateAvailable:
        return 'Update Available';
      case AppVersionStatus.updateRequired:
        return 'Update Required';
      case AppVersionStatus.maintenance:
        return 'Maintenance';
      case AppVersionStatus.error:
        return 'Check Failed';
    }
  }
}

class AppUpdatePolicy {
  final bool hasPolicy;
  final AppVersionStatus status;
  final bool isMandatory;
  final String installedVersion;
  final int installedBuild;
  final String latestVersion;
  final int latestBuild;
  final String minSupportedVersion;
  final int minSupportedBuild;
  final String title;
  final String releaseNotes;
  final String downloadUrl;
  final String? checksumSha256;
  final int? fileSizeBytes;
  final DateTime? publishedAt;
  final DateTime checkedAt;
  final String message;

  const AppUpdatePolicy({
    required this.hasPolicy,
    required this.status,
    required this.isMandatory,
    required this.installedVersion,
    required this.installedBuild,
    required this.latestVersion,
    required this.latestBuild,
    required this.minSupportedVersion,
    required this.minSupportedBuild,
    required this.title,
    required this.releaseNotes,
    required this.downloadUrl,
    this.checksumSha256,
    this.fileSizeBytes,
    this.publishedAt,
    required this.checkedAt,
    required this.message,
  });

  factory AppUpdatePolicy.initial({
    String currentVersion = '1.0.0',
    int currentBuild = 1,
  }) {
    return AppUpdatePolicy(
      hasPolicy: false,
      status: AppVersionStatus.supported,
      isMandatory: false,
      installedVersion: currentVersion,
      installedBuild: currentBuild,
      latestVersion: currentVersion,
      latestBuild: currentBuild,
      minSupportedVersion: currentVersion,
      minSupportedBuild: currentBuild,
      title: 'eRefill',
      releaseNotes: '',
      downloadUrl: '',
      checkedAt: DateTime.now(),
      message: 'Checking for updates...',
    );
  }

  factory AppUpdatePolicy.preview({
    required String latestVersion,
    required int latestBuild,
    required String minSupportedVersion,
    required int minSupportedBuild,
    required String title,
    required String releaseNotes,
    required String downloadUrl,
    String? checksumSha256,
    int? fileSizeBytes,
    bool isMandatory = true,
  }) {
    return AppUpdatePolicy(
      hasPolicy: true,
      status: isMandatory ? AppVersionStatus.updateRequired : AppVersionStatus.updateAvailable,
      isMandatory: isMandatory,
      installedVersion: '1.0.0',
      installedBuild: 1,
      latestVersion: latestVersion,
      latestBuild: latestBuild,
      minSupportedVersion: minSupportedVersion,
      minSupportedBuild: minSupportedBuild,
      title: title,
      releaseNotes: releaseNotes,
      downloadUrl: downloadUrl,
      checksumSha256: checksumSha256,
      fileSizeBytes: fileSizeBytes,
      publishedAt: DateTime.now(),
      checkedAt: DateTime.now(),
      message: isMandatory ? 'Mandatory update required' : 'Update available',
    );
  }

  factory AppUpdatePolicy.fromJson(
    Map<String, dynamic> json, {
    String fallbackInstalledVersion = '1.0.0',
    int fallbackInstalledBuild = 1,
  }) {
    final statusStr = json['status']?.toString();
    final status = AppVersionStatus.fromString(statusStr);
    final isMandatory = json['is_mandatory'] == true ||
        status == AppVersionStatus.updateRequired;

    return AppUpdatePolicy(
      hasPolicy: json['has_policy'] != false,
      status: status,
      isMandatory: isMandatory,
      installedVersion: json['installed_version']?.toString() ?? fallbackInstalledVersion,
      installedBuild: (json['installed_build'] as num?)?.toInt() ?? fallbackInstalledBuild,
      latestVersion: json['latest_version']?.toString() ?? fallbackInstalledVersion,
      latestBuild: (json['latest_build'] as num?)?.toInt() ?? fallbackInstalledBuild,
      minSupportedVersion: json['min_supported_version']?.toString() ?? '1.0.0',
      minSupportedBuild: (json['min_supported_build'] as num?)?.toInt() ?? 1,
      title: json['title']?.toString() ?? 'eRefill Update',
      releaseNotes: json['release_notes']?.toString() ?? '',
      downloadUrl: json['download_url']?.toString() ?? '',
      checksumSha256: json['checksum_sha256']?.toString(),
      fileSizeBytes: (json['file_size_bytes'] as num?)?.toInt(),
      publishedAt: json['published_at'] != null
          ? DateTime.tryParse(json['published_at'].toString())
          : null,
      checkedAt: json['checked_at'] != null
          ? (DateTime.tryParse(json['checked_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      message: json['message']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'has_policy': hasPolicy,
      'status': status.name,
      'is_mandatory': isMandatory,
      'installed_version': installedVersion,
      'installed_build': installedBuild,
      'latest_version': latestVersion,
      'latest_build': latestBuild,
      'min_supported_version': minSupportedVersion,
      'min_supported_build': minSupportedBuild,
      'title': title,
      'release_notes': releaseNotes,
      'download_url': downloadUrl,
      'checksum_sha256': checksumSha256,
      'file_size_bytes': fileSizeBytes,
      'published_at': publishedAt?.toIso8601String(),
      'checked_at': checkedAt.toIso8601String(),
      'message': message,
    };
  }
}

class AppReleaseRecord {
  final String id;
  final String platform;
  final String channel;
  final String version;
  final int buildNumber;
  final String minSupportedVersion;
  final int minSupportedBuild;
  final String title;
  final String releaseNotes;
  final String updateType;
  final String status;
  final String downloadUrl;
  final String? checksumSha256;
  final int? fileSizeBytes;
  final bool isActive;
  final DateTime? publishedAt;
  final String? publishedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AppReleaseRecord({
    required this.id,
    required this.platform,
    required this.channel,
    required this.version,
    required this.buildNumber,
    required this.minSupportedVersion,
    required this.minSupportedBuild,
    required this.title,
    required this.releaseNotes,
    required this.updateType,
    required this.status,
    required this.downloadUrl,
    this.checksumSha256,
    this.fileSizeBytes,
    required this.isActive,
    this.publishedAt,
    this.publishedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AppReleaseRecord.fromJson(Map<String, dynamic> json) {
    return AppReleaseRecord(
      id: json['id']?.toString() ?? '',
      platform: json['platform']?.toString() ?? 'android',
      channel: json['channel']?.toString() ?? 'official_apk',
      version: json['version']?.toString() ?? '1.0.0',
      buildNumber: (json['build_number'] as num?)?.toInt() ?? 1,
      minSupportedVersion: json['min_supported_version']?.toString() ?? '1.0.0',
      minSupportedBuild: (json['min_supported_build'] as num?)?.toInt() ?? 1,
      title: json['title']?.toString() ?? 'eRefill Release',
      releaseNotes: json['release_notes']?.toString() ?? '',
      updateType: json['update_type']?.toString() ?? 'optional',
      status: json['status']?.toString() ?? 'draft',
      downloadUrl: json['download_url']?.toString() ?? '',
      checksumSha256: json['checksum_sha256']?.toString(),
      fileSizeBytes: (json['file_size_bytes'] as num?)?.toInt(),
      isActive: json['is_active'] == true,
      publishedAt: json['published_at'] != null
          ? DateTime.tryParse(json['published_at'].toString())
          : null,
      publishedBy: json['published_by']?.toString(),
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? (DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'platform': platform,
      'channel': channel,
      'version': version,
      'build_number': buildNumber,
      'min_supported_version': minSupportedVersion,
      'min_supported_build': minSupportedBuild,
      'title': title,
      'release_notes': releaseNotes,
      'update_type': updateType,
      'status': status,
      'download_url': downloadUrl,
      'checksum_sha256': checksumSha256,
      'file_size_bytes': fileSizeBytes,
      'is_active': isActive,
      'published_at': publishedAt?.toIso8601String(),
      'published_by': publishedBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
