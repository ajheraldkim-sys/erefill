import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/core/models/app_version_models.dart';
import 'package:erefill/core/services/app_semver_parser.dart';
import 'package:erefill/features/update/screens/mandatory_update_screen.dart';
import 'package:erefill/features/update/widgets/optional_update_dialog.dart';

void main() {
  group('AppSemverParser Tests', () {
    test('standard semver comparison handles minor and patch increments', () {
      expect(AppSemverParser.compareVersions('1.0.1', '1.0.0'), greaterThan(0));
      expect(AppSemverParser.compareVersions('1.0.0', '1.0.1'), lessThan(0));
      expect(AppSemverParser.compareVersions('1.1.0', '1.0.9'), greaterThan(0));
      expect(AppSemverParser.compareVersions('2.0.0', '1.99.99'), greaterThan(0));
      expect(AppSemverParser.compareVersions('1.2.3', '1.2.3'), equals(0));
    });

    test('prevents lexicographical comparison bugs (e.g. 1.10.0 vs 1.9.0)', () {
      // In string compare: "1.10.0".compareTo("1.9.0") is negative (< 0) because '1' < '9'.
      // In semver compare: 1.10.0 is strictly newer than 1.9.0 (> 0).
      expect(AppSemverParser.compareVersions('1.10.0', '1.9.0'), greaterThan(0));
      expect(AppSemverParser.compareVersions('1.9.0', '1.10.0'), lessThan(0));
      expect(AppSemverParser.compareVersions('2.100.5', '2.99.9'), greaterThan(0));
    });

    test('compareWithBuild accurately differentiates build numbers', () {
      // Same version, different builds
      expect(
        AppSemverParser.compareWithBuild('1.0.0', 2, '1.0.0', 1),
        greaterThan(0),
      );
      expect(
        AppSemverParser.compareWithBuild('1.0.0', 1, '1.0.0', 2),
        lessThan(0),
      );
      expect(
        AppSemverParser.compareWithBuild('1.0.0', 5, '1.0.0', 5),
        equals(0),
      );

      // Higher semantic version always supersedes higher build on lower version
      expect(
        AppSemverParser.compareWithBuild('1.0.1', 1, '1.0.0', 999),
        greaterThan(0),
      );
      expect(
        AppSemverParser.compareWithBuild('1.0.0', 999, '1.0.1', 1),
        lessThan(0),
      );
    });

    test('isSupported evaluates version compatibility against min policy', () {
      // Exact match -> supported
      expect(
        AppSemverParser.isSupported(
          currentVersion: '1.0.0',
          currentBuild: 1,
          minSupportedVersion: '1.0.0',
          minSupportedBuild: 1,
        ),
        isTrue,
      );

      // Newer version -> supported
      expect(
        AppSemverParser.isSupported(
          currentVersion: '1.0.1',
          currentBuild: 1,
          minSupportedVersion: '1.0.0',
          minSupportedBuild: 1,
        ),
        isTrue,
      );

      // Newer build -> supported
      expect(
        AppSemverParser.isSupported(
          currentVersion: '1.0.0',
          currentBuild: 5,
          minSupportedVersion: '1.0.0',
          minSupportedBuild: 2,
        ),
        isTrue,
      );

      // Older version -> unsupported
      expect(
        AppSemverParser.isSupported(
          currentVersion: '0.9.9',
          currentBuild: 100,
          minSupportedVersion: '1.0.0',
          minSupportedBuild: 1,
        ),
        isFalse,
      );

      // Older build -> unsupported
      expect(
        AppSemverParser.isSupported(
          currentVersion: '1.0.0',
          currentBuild: 1,
          minSupportedVersion: '1.0.0',
          minSupportedBuild: 2,
        ),
        isFalse,
      );
    });

    test('handles leading v prefixes, build suffixes, and malformed strings', () {
      expect(AppSemverParser.compareVersions('v1.2.3', '1.2.3'), equals(0));
      expect(AppSemverParser.compareVersions('v2.0.0-beta.1', '1.9.9'), greaterThan(0));
      expect(AppSemverParser.compareVersions('invalid', '0.0.0'), equals(0));
      expect(AppSemverParser.compareVersions('', '0.0.0'), equals(0));
    });
  });

  group('AppVersionModels & AppUpdatePolicy Tests', () {
    test('AppVersionStatus parses strings accurately', () {
      expect(
        AppVersionStatus.fromString('UPDATE_REQUIRED'),
        equals(AppVersionStatus.updateRequired),
      );
      expect(
        AppVersionStatus.fromString('UPDATE_AVAILABLE'),
        equals(AppVersionStatus.updateAvailable),
      );
      expect(
        AppVersionStatus.fromString('MAINTENANCE'),
        equals(AppVersionStatus.maintenance),
      );
      expect(
        AppVersionStatus.fromString('VERSION_SUPPORTED'),
        equals(AppVersionStatus.supported),
      );
      expect(
        AppVersionStatus.fromString('unknown_status'),
        equals(AppVersionStatus.supported),
      );
    });

    test('AppUpdatePolicy.fromJson correctly decodes backend RPC payload', () {
      final json = {
        'status': 'UPDATE_REQUIRED',
        'is_mandatory': true,
        'installed_version': '1.0.0',
        'installed_build': 1,
        'latest_version': '1.1.0',
        'latest_build': 2,
        'min_supported_version': '1.0.1',
        'min_supported_build': 2,
        'title': 'Mandatory Security Update',
        'release_notes': 'Fixed critical delivery fee and notification issues',
        'download_url': 'https://erefill-landing.pages.dev/downloads/eRefill.apk',
        'checksum_sha256': 'a1b2c3d4e5f6',
        'file_size_bytes': 35000000,
        'published_at': '2026-10-16T12:00:00Z',
        'checked_at': '2026-10-16T12:05:00Z',
        'message': 'Your app version is unsupported. Please update.',
      };

      final policy = AppUpdatePolicy.fromJson(json);

      expect(policy.hasPolicy, isTrue);
      expect(policy.status, equals(AppVersionStatus.updateRequired));
      expect(policy.isMandatory, isTrue);
      expect(policy.latestVersion, equals('1.1.0'));
      expect(policy.latestBuild, equals(2));
      expect(policy.minSupportedVersion, equals('1.0.1'));
      expect(policy.minSupportedBuild, equals(2));
      expect(policy.downloadUrl, equals('https://erefill-landing.pages.dev/downloads/eRefill.apk'));
      expect(policy.checksumSha256, equals('a1b2c3d4e5f6'));
    });
  });

  group('Update Screens UI Tests', () {
    testWidgets('MandatoryUpdateScreen is non-dismissible with PopScope(canPop: false)', (tester) async {
      final testPolicy = AppUpdatePolicy.preview(
        latestVersion: '1.2.0',
        latestBuild: 5,
        minSupportedVersion: '1.1.0',
        minSupportedBuild: 2,
        title: 'Critical Security Update',
        releaseNotes: '- Security enforcement\n- Bug fixes',
        downloadUrl: 'https://erefill-landing.pages.dev/downloads/eRefill.apk',
        isMandatory: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MandatoryUpdateScreen(policy: testPolicy),
        ),
      );
      await tester.pumpAndSettle();

      // Verify non-dismissible PopScope exists
      final popScopeFinder = find.byWidgetPredicate((w) => w is PopScope);
      expect(popScopeFinder, findsOneWidget);

      final popScope = tester.widget<PopScope>(popScopeFinder);
      expect(popScope.canPop, isFalse);

      // Verify core UI elements exist
      expect(find.text('Update Required'), findsOneWidget);
      expect(find.text('Update Now'), findsOneWidget);
    });

    testWidgets('OptionalUpdateDialog renders details and responds to Later tap', (tester) async {
      final testPolicy = AppUpdatePolicy.preview(
        latestVersion: '1.2.0',
        latestBuild: 5,
        minSupportedVersion: '1.0.0',
        minSupportedBuild: 1,
        title: 'New Features Available',
        releaseNotes: '- Performance enhancements\n- Bug fixes',
        downloadUrl: 'https://erefill-landing.pages.dev/downloads/eRefill.apk',
        isMandatory: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => OptionalUpdateDialog.show(context, testPolicy),
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify dialog contents
      expect(find.text('Update Available'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Update Now'), findsOneWidget);

      // Tap 'Later' to dismiss
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      // Verify dialog is dismissed
      expect(find.text('Update Available'), findsNothing);
    });
  });
}

