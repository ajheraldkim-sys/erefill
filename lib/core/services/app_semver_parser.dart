class AppSemverParser {
  AppSemverParser._();

  /// Parse a semantic version string into [major, minor, patch] integers.
  /// Handles prefixes like 'v1.0.0', pre-releases '1.0.0-rc1', and build tags '1.0.0+2'.
  static List<int> parseVersion(String version) {
    if (version.trim().isEmpty) {
      return [0, 0, 0];
    }

    var clean = version.trim();
    if (clean.startsWith('v') || clean.startsWith('V')) {
      clean = clean.substring(1);
    }

    // Split off pre-release and build metadata
    if (clean.contains('-')) {
      clean = clean.split('-').first;
    }
    if (clean.contains('+')) {
      clean = clean.split('+').first;
    }

    final segments = clean.split('.');
    final major = segments.isNotEmpty ? _extractInt(segments[0]) : 0;
    final minor = segments.length > 1 ? _extractInt(segments[1]) : 0;
    final patch = segments.length > 2 ? _extractInt(segments[2]) : 0;

    return [major, minor, patch];
  }

  static int _extractInt(String segment) {
    final digitsOnly = segment.replaceAll(RegExp(r'\D'), '');
    return int.tryParse(digitsOnly) ?? 0;
  }

  /// Compare two versions with their respective build numbers.
  ///
  /// Returns:
  /// - Negative integer if (v1, b1) < (v2, b2)
  /// - Zero if (v1, b1) == (v2, b2)
  /// - Positive integer if (v1, b1) > (v2, b2)
  static int compare({
    required String v1,
    int b1 = 0,
    required String v2,
    int b2 = 0,
  }) {
    final s1 = parseVersion(v1);
    final s2 = parseVersion(v2);

    for (var i = 0; i < 3; i++) {
      if (s1[i] < s2[i]) return -1;
      if (s1[i] > s2[i]) return 1;
    }

    // When semver strings are equivalent, compare numeric build numbers
    if (b1 < b2) return -1;
    if (b1 > b2) return 1;

    return 0;
  }

  static bool isOlder({
    required String clientVersion,
    int clientBuild = 0,
    required String targetVersion,
    int targetBuild = 0,
  }) {
    return compare(
          v1: clientVersion,
          b1: clientBuild,
          v2: targetVersion,
          b2: targetBuild,
        ) <
        0;
  }

  static bool isAtLeast({
    required String clientVersion,
    int clientBuild = 0,
    required String minVersion,
    int minBuild = 0,
  }) {
    return compare(
          v1: clientVersion,
          b1: clientBuild,
          v2: minVersion,
          b2: minBuild,
        ) >=
        0;
  }

  /// Convenience shorthand to compare two version strings without build numbers.
  static int compareVersions(String v1, String v2) {
    return compare(v1: v1, v2: v2);
  }

  /// Convenience shorthand to compare two versions with build numbers.
  static int compareWithBuild(String v1, int b1, String v2, int b2) {
    return compare(v1: v1, b1: b1, v2: v2, b2: b2);
  }

  /// Checks if current version and build satisfy the minimum policy requirements.
  static bool isSupported({
    required String currentVersion,
    int currentBuild = 0,
    required String minSupportedVersion,
    int minSupportedBuild = 0,
  }) {
    return isAtLeast(
      clientVersion: currentVersion,
      clientBuild: currentBuild,
      minVersion: minSupportedVersion,
      minBuild: minSupportedBuild,
    );
  }
}

