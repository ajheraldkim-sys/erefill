import 'dart:typed_data';

import 'package:erefill/core/utils/station_orderability.dart';
import 'package:erefill/features/account/verification/verification_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements VerificationRepository {
  _FakeRepo(this.state);
  VerificationState state;
  final uploaded = <String>[];
  Map<String, String?>? submitted;

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
  }) async {
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
        StationOrderability.isVerified({...base, 'verification_status': 'pending'}),
        isFalse,
      );
      expect(
        StationOrderability.isOrderable({...base, 'verification_status': 'unverified'}),
        isFalse,
      );
    });

    test('approved or legacy rows without the column stay orderable', () {
      expect(
        StationOrderability.isOrderable({...base, 'verification_status': 'approved'}),
        isTrue,
      );
      expect(StationOrderability.isOrderable(base), isTrue);
    });
  });

  group('VerificationScreen', () {
    Future<void> pump(WidgetTester tester, _FakeRepo repo) async {
      await tester.pumpWidget(MaterialApp(
        home: VerificationScreen(
          repository: repo,
          pickImage: (_) async => (Uint8List.fromList([1, 2, 3]), 'jpg'),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('approved users see a verified state', (tester) async {
      await pump(tester,
          _FakeRepo(const VerificationState(status: 'approved', isOwner: false)));
      expect(find.text('Your ID is verified'), findsOneWidget);
      expect(find.text('Submit for review'), findsNothing);
    });

    testWidgets('rejected users see the reason and can resubmit', (tester) async {
      await pump(
        tester,
        _FakeRepo(const VerificationState(
          status: 'rejected',
          isOwner: false,
          rejectionReason: 'Photo is blurry',
        )),
      );
      expect(find.textContaining('Photo is blurry'), findsOneWidget);
      expect(find.text('Submit for review'), findsOneWidget);
    });

    testWidgets('customer uploads ID front and selfie then submits',
        (tester) async {
      final repo =
          _FakeRepo(const VerificationState(status: 'unverified', isOwner: false));
      await pump(tester, repo);

      expect(find.text('Business or sanitary permit'), findsNothing);
      await tester.enterText(find.byKey(const Key('id-last4')), '1234');
      for (final label in ['Front of ID', 'Selfie holding your ID']) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Submit for review'));
      await tester.tap(find.text('Submit for review'));
      await tester.pumpAndSettle();

      expect(repo.submitted!['front'], 'uid/front.jpg');
      expect(repo.submitted!['selfie'], 'uid/selfie.jpg');
      expect(repo.submitted!['last4'], '1234');
      expect(find.textContaining('being reviewed'), findsOneWidget);
    });

    testWidgets('submit is disabled until required photos are added',
        (tester) async {
      final repo =
          _FakeRepo(const VerificationState(status: 'unverified', isOwner: true));
      await pump(tester, repo);
      expect(find.text('Business or sanitary permit'), findsOneWidget);
      await tester.ensureVisible(find.text('Submit for review'));
      await tester.tap(find.text('Submit for review'));
      await tester.pumpAndSettle();
      expect(repo.submitted, isNull);
    });
  });
}
