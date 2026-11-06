import 'package:erefill/features/quality/station_certificates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

StationCert cert(String type, DateTime issued, DateTime expires,
        {String status = 'approved'}) =>
    StationCert(
      id: '$type-$issued',
      type: type,
      issuedOn: issued,
      expiresOn: expires,
      status: status,
      filePath: 'o/certs/x.pdf',
    );

class _Repo implements CertificateRepository {
  final certs = <StationCert>[];
  @override
  Future<List<StationCert>> forStation(String ownerId) async => [...certs];
  @override
  Future<String> uploadFile(List<int> bytes, String ext) async => 'o/certs/new.$ext';
  @override
  Future<void> submit(String type, DateTime issued, DateTime expires, String path) async =>
      certs.add(cert(type, issued, expires, status: 'pending'));
  @override
  Future<Uri?> fileUrl(String path) async => null;
}

void main() {
  final now = DateTime(2026, 11, 5);

  test('badge uses the newest valid approved lab test', () {
    final certs = [
      cert('bacteriological', DateTime(2026, 6, 1), DateTime(2026, 12, 1)),
      cert('bacteriological', DateTime(2026, 10, 2), DateTime(2027, 4, 2)),
      cert('sanitary_permit', DateTime(2026, 11, 1), DateTime(2027, 11, 1)),
      cert('physical_chemical', DateTime(2026, 11, 3), DateTime(2027, 5, 1),
          status: 'pending'),
    ];
    expect(StationCert.badgeLabel(certs, now), 'Water tested · Oct 2026');
  });

  test('no badge when lab tests are expired or missing', () {
    expect(
      StationCert.badgeLabel(
          [cert('bacteriological', DateTime(2025, 1, 1), DateTime(2026, 1, 1))], now),
      isNull,
    );
    expect(
      StationCert.badgeLabel(
          [cert('sanitary_permit', DateTime(2026, 1, 1), DateTime(2027, 1, 1))], now),
      isNull,
    );
  });

  testWidgets('owner adds a certificate with dates and a file', (tester) async {
    final repo = _Repo();
    await tester.pumpWidget(MaterialApp(
      home: CertificatesScreen(
        ownerId: 'o',
        repository: repo,
        pickFile: () async => ([1, 2], 'pdf'),
        today: () => now,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('No certificates yet.'), findsOneWidget);

    await tester.tap(find.text('Add certificate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attach file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(repo.certs, hasLength(1));
    expect(repo.certs.single.type, 'bacteriological');
    expect(repo.certs.single.expiresOn.isAfter(now), isTrue);
    expect(find.textContaining('Waiting for review'), findsOneWidget);
  });
}
