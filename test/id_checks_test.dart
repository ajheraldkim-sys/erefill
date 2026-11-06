import 'dart:convert';

import 'package:erefill/features/account/verification/id_checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IdChecks.nameMatch', () {
    test('every name part found, ignoring case, accents and punctuation', () {
      expect(
        IdChecks.nameMatch(
          'Juan Dela Cruz',
          'REPUBLIKA NG PILIPINAS\nDELA CRUZ,\nJUAN',
        ),
        1.0,
      );
      expect(IdChecks.nameMatch('José Peña', 'PEÑA JOSE'), 1.0);
    });

    test('partial and missing names', () {
      expect(
        IdChecks.nameMatch('Maria Santos Reyes', 'MARIA REYES'),
        closeTo(2 / 3, 1e-9),
      );
      expect(IdChecks.nameMatch('Maria Santos', 'PEDRO GARCIA'), 0.0);
      expect(IdChecks.nameMatch('', 'ANYTHING'), 0.0);
    });

    test('a name part must match a whole word', () {
      // "ANA" must not match inside "SANTANA".
      expect(IdChecks.nameMatch('Ana Lim', 'SANTANA LIM'), 0.5);
    });
  });

  group('IdChecks.last4Found', () {
    test('finds the typed last 4 characters in the ID number', () {
      expect(IdChecks.last4Found('1234', 'PCN 5678-9012-1234'), isTrue);
      expect(IdChecks.last4Found('ab12', 'N01-23-AB12'), isTrue);
      expect(IdChecks.last4Found('9999', 'PCN 5678-9012-1234'), isFalse);
      expect(IdChecks.last4Found('', 'anything'), isNull);
    });
  });

  group('IdChecks.idTypeLooksRight', () {
    test('recognises the ID from its printed title', () {
      expect(
        IdChecks.idTypeLooksRight(
          'philsys',
          'PAMBANSANG PAGKAKAKILANLAN\nPhilippine Identification Card',
        ),
        isTrue,
      );
      expect(
        IdChecks.idTypeLooksRight('drivers_license', "DRIVER'S LICENSE"),
        isTrue,
      );
      expect(
        IdChecks.idTypeLooksRight('umid', 'UNIFIED MULTI-PURPOSE ID'),
        isTrue,
      );
      expect(IdChecks.idTypeLooksRight('philsys', "DRIVER'S LICENSE"), isFalse);
      expect(IdChecks.idTypeLooksRight('other', 'whatever'), isNull);
    });
  });

  group('PhilSysQr.parse', () {
    final qr = jsonEncode({
      'DateIssued': '07 March 2024',
      'Issuer': 'PSA',
      'subject': {
        'Suffix': '',
        'lName': 'DELA CRUZ',
        'fName': 'JUAN',
        'mName': 'SANTOS',
        'sex': 'Male',
        'BF': '[1,1]',
        'DOB': 'January 01, 1990',
        'POB': 'Cantilan, Surigao del Sur',
        'PCN': '1234-5678-9012-3456',
      },
      'alg': 'EDDSA',
      'signature': 'abc123',
    });

    test('reads name, PCN and signature from the National ID QR', () {
      final p = PhilSysQr.parse(qr)!;
      expect(p.firstName, 'JUAN');
      expect(p.lastName, 'DELA CRUZ');
      expect(p.pcn, '1234-5678-9012-3456');
      expect(p.hasSignature, isTrue);
    });

    test('ignores QR codes that are not a National ID', () {
      expect(PhilSysQr.parse('https://example.com'), isNull);
      expect(PhilSysQr.parse('{"foo": 1}'), isNull);
    });
  });

  group('IdChecks.evaluate', () {
    test('builds a report the admin can read', () {
      final report = IdChecks.evaluate(
        IdCheckInput(
          profileName: 'Juan Dela Cruz',
          last4: '3456',
          idType: 'philsys',
          ocrText:
              'Philippine Identification Card\nPCN 1234-5678-9012-3456\nDELA CRUZ\nJUAN SANTOS',
          qrValues: [
            jsonEncode({
              'subject': {
                'fName': 'JUAN',
                'lName': 'DELA CRUZ',
                'PCN': '1234567890123456',
              },
              'signature': 'x',
            }),
          ],
          facesOnId: 1,
          liveness: const LivenessResult(
            passed: true,
            steps: ['turn', 'blink', 'still'],
          ),
        ),
      );
      final j = report.toJson();
      expect(j['name_match'], 1.0);
      expect(j['last4_found'], isTrue);
      expect(j['id_type_matches'], isTrue);
      expect(j['face_on_id'], isTrue);
      expect(j['philsys_qr']['found'], isTrue);
      expect(j['philsys_qr']['name_matches'], isTrue);
      expect(j['philsys_qr']['pcn_last4_matches'], isTrue);
      expect(j['liveness']['passed'], isTrue);
      expect(report.flags, isEmpty);
    });

    test('flags what the admin should look at', () {
      final report = IdChecks.evaluate(
        const IdCheckInput(
          profileName: 'Maria Santos',
          last4: '1111',
          idType: 'umid',
          ocrText: 'PEDRO GARCIA',
          qrValues: [],
          facesOnId: 0,
          liveness: null,
        ),
      );
      expect(
        report.flags,
        containsAll([
          'Name on ID does not match the profile',
          'ID number does not end in 1111',
          'ID title does not look like the chosen ID type',
          'No face found on the ID photo',
          'Live selfie check not done',
        ]),
      );
    });

    test('report survives a JSON round trip', () {
      final report = IdChecks.evaluate(
        const IdCheckInput(
          profileName: 'A B',
          last4: '',
          idType: 'other',
          ocrText: '',
          qrValues: [],
          facesOnId: 1,
          liveness: LivenessResult(passed: false, steps: ['turn']),
        ),
      );
      final back = IdCheckReport.fromJson(
        jsonDecode(jsonEncode(report.toJson())),
      );
      expect(back.flags, report.flags);
    });
  });

  group('LivenessTracker', () {
    FaceSample face({double yaw = 0, double eyes = 0.9, int count = 1}) =>
        FaceSample(
          faceCount: count,
          yaw: yaw,
          leftEyeOpen: eyes,
          rightEyeOpen: eyes,
        );

    test('needs a head turn both ways, a blink, then a still look', () {
      final t = LivenessTracker();
      expect(t.step, LivenessStep.turn);
      t.add(face(yaw: 25));
      expect(t.step, LivenessStep.turn); // only one way so far
      t.add(face(yaw: -25));
      expect(t.step, LivenessStep.blink);
      t.add(face(eyes: 0.95));
      t.add(face(eyes: 0.05));
      t.add(face(eyes: 0.9));
      expect(t.step, LivenessStep.still);
      for (var i = 0; i < LivenessTracker.stillFrames; i++) {
        t.add(face(yaw: 2));
      }
      expect(t.step, LivenessStep.done);
      expect(t.result.passed, isTrue);
    });

    test('a second face or no face resets the current step and warns', () {
      final t = LivenessTracker();
      t.add(face(yaw: 25));
      t.add(face(count: 2));
      expect(t.hint, contains('only your face'));
      t.add(face(yaw: -25));
      expect(t.step, LivenessStep.turn, reason: 'turn progress was reset');
      t.add(face(count: 0));
      expect(t.hint, contains('Move your face'));
    });

    test('a photo held still cannot pass the blink', () {
      final t = LivenessTracker();
      t.add(face(yaw: 25));
      t.add(face(yaw: -25));
      for (var i = 0; i < 30; i++) {
        t.add(face(eyes: 0.9));
      }
      expect(t.step, LivenessStep.blink);
      expect(t.result.passed, isFalse);
    });
  });
}
