import 'dart:typed_data';

import 'package:erefill/core/utils/station_orderability.dart';
import 'package:erefill/features/account/verification/id_checks.dart';
import 'package:erefill/features/account/verification/id_photo_analyzer.dart';
import 'package:erefill/features/account/verification/verification_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements VerificationRepository {
  _FakeRepo(this.state);
  VerificationState state;
  final uploaded = <String>[];
  Map<String, String?>? submitted;
  Map<String, dynamic>? checks;

  @override
  Future<VerificationState> load() async => state;

  @override
  Future<String> upload(String slot, Uint8List bytes, String ext) async {
    final path = 'uid/$slot.$ext';
    uploaded.add(path);
    return path;
  }

  @override
  Future<void> submit({
    required String idType,
    required String last4,
    required String front,
    String? back,
    required String selfie,
    String? permit,
    Map<String, dynamic>? checks,
  }) async {
    this.checks = checks;
    submitted = {
      'idType': idType,
      'last4': last4,
      'front': front,
      'back': back,
      'selfie': selfie,
      'permit': permit,
    };
    state = const VerificationState(status: 'pending', isOwner: false);
  }
}

class _FakeAnalyzer implements IdPhotoAnalyzer {
  _FakeAnalyzer(this.scan);
  final IdPhotoScan scan;

  @override
  Future<IdPhotoScan> analyze(Uint8List bytes, String ext) async => scan;
}

const _goodScan = IdPhotoScan(
  text:
      'PHILIPPINE IDENTIFICATION CARD\nPCN 1234-5678-9012-1234\nDELA CRUZ\nJUAN',
  codes: [],
  faces: 1,
);

void main() {
  group('StationOrderability verification', () {
    final base = {
      'id': 's1',
      'latitude': 9.0,
      'longitude': 126.0,
      'price_per_gallon': 25,
    };

    test('unverified stations are not orderable', () {
      expect(
        StationOrderability.isVerified({
          ...base,
          'verification_status': 'pending',
        }),
        isFalse,
      );
      expect(
        StationOrderability.isOrderable({
          ...base,
          'verification_status': 'unverified',
        }),
        isFalse,
      );
    });

    test('approved or legacy rows without the column stay orderable', () {
      expect(
        StationOrderability.isOrderable({
          ...base,
          'verification_status': 'approved',
        }),
        isTrue,
      );
      expect(StationOrderability.isOrderable(base), isTrue);
    });
  });

  group('VerificationScreen', () {
    Future<void> pump(
      WidgetTester tester,
      _FakeRepo repo, {
      IdPhotoScan scan = _goodScan,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VerificationScreen(
            repository: repo,
            pickImage: (_) async => (Uint8List.fromList([1, 2, 3]), 'jpg'),
            analyzer: _FakeAnalyzer(scan),
            liveSelfie: (_) async => (
              bytes: Uint8List.fromList([4, 5, 6]),
              result: const LivenessResult(
                passed: true,
                steps: ['turn', 'blink', 'still'],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('approved users see a verified state', (tester) async {
      await pump(
        tester,
        _FakeRepo(const VerificationState(status: 'approved', isOwner: false)),
      );
      expect(find.text('Your ID is verified'), findsOneWidget);
      expect(find.text('Submit for review'), findsNothing);
    });

    testWidgets('rejected users see the reason and can resubmit', (
      tester,
    ) async {
      await pump(
        tester,
        _FakeRepo(
          const VerificationState(
            status: 'rejected',
            isOwner: false,
            rejectionReason: 'Photo is blurry',
          ),
        ),
      );
      expect(find.textContaining('Photo is blurry'), findsOneWidget);
      expect(find.text('Submit for review'), findsOneWidget);
    });

    testWidgets('customer uploads ID front and selfie then submits', (
      tester,
    ) async {
      final repo = _FakeRepo(
        const VerificationState(status: 'unverified', isOwner: false),
      );
      await pump(tester, repo);

      expect(find.text('Business or sanitary permit'), findsNothing);
      await tester.enterText(find.byKey(const Key('id-last4')), '1234');
      for (final label in ['Front of ID', 'Live selfie holding your ID']) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Submit for review'));
      await tester.tap(find.text('Submit for review'));
      await tester.pumpAndSettle();

      expect(repo.submitted!['front'], 'uid/front.jpg');
      expect(repo.submitted!['selfie'], 'uid/selfie.jpeg');
      expect(repo.submitted!['last4'], '1234');
      expect(find.textContaining('being reviewed'), findsOneWidget);
    });

    testWidgets('on-device check results go with the submission', (
      tester,
    ) async {
      final repo = _FakeRepo(
        const VerificationState(
          status: 'unverified',
          isOwner: false,
          profileName: 'Juan Dela Cruz',
        ),
      );
      await pump(tester, repo);
      await tester.enterText(find.byKey(const Key('id-last4')), '1234');
      for (final label in ['Front of ID', 'Live selfie holding your ID']) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('National ID QR code'), findsOneWidget);
      await tester.ensureVisible(find.text('Submit for review'));
      await tester.tap(find.text('Submit for review'));
      await tester.pumpAndSettle();

      final report = IdCheckReport.fromJson(repo.checks!);
      expect(repo.checks!['checked_on_device'], isTrue);
      expect(report.liveness!.passed, isTrue);
      expect(report.last4Found, isTrue);
      expect(report.flags, contains('National ID QR code not readable'));
      expect(
        report.flags,
        isNot(contains('Name on ID does not match the profile')),
      );
    });

    testWidgets('a bad ID photo shows a hint to retake it', (tester) async {
      final repo = _FakeRepo(
        const VerificationState(
          status: 'unverified',
          isOwner: false,
          profileName: 'Maria Santos',
        ),
      );
      await pump(
        tester,
        repo,
        scan: const IdPhotoScan(text: 'blurry', codes: [], faces: 0),
      );
      await tester.ensureVisible(find.text('Front of ID'));
      await tester.tap(find.text('Front of ID'));
      await tester.pumpAndSettle();
      expect(find.textContaining("couldn't read your name"), findsOneWidget);
      expect(
        find.textContaining("couldn't see the photo on your ID"),
        findsOneWidget,
      );
    });

    testWidgets('submit is disabled until required photos are added', (
      tester,
    ) async {
      final repo = _FakeRepo(
        const VerificationState(status: 'unverified', isOwner: true),
      );
      await pump(tester, repo);
      expect(find.text('Business or sanitary permit'), findsOneWidget);
      await tester.ensureVisible(find.text('Submit for review'));
      await tester.tap(find.text('Submit for review'));
      await tester.pumpAndSettle();
      expect(repo.submitted, isNull);
    });
  });
}
