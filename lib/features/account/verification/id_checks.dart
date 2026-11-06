import 'dart:convert';

/// On-device ID screening (free, no API key): compares what ML Kit read
/// from the ID photo with the user's profile, reads the PhilSys National ID
/// QR code, and records the live-selfie result.
///
/// These checks run on the user's phone, so a tampered app could fake them.
/// They help admins review faster; they never approve anyone on their own.
abstract final class IdChecks {
  /// Fraction of a name part that must match to count as the same person.
  static const double nameThreshold = 0.67;

  static const _accents = {
    'Á': 'A',
    'À': 'A',
    'Â': 'A',
    'Ä': 'A',
    'Ã': 'A',
    'É': 'E',
    'È': 'E',
    'Ê': 'E',
    'Ë': 'E',
    'Í': 'I',
    'Ì': 'I',
    'Î': 'I',
    'Ï': 'I',
    'Ó': 'O',
    'Ò': 'O',
    'Ô': 'O',
    'Ö': 'O',
    'Õ': 'O',
    'Ú': 'U',
    'Ù': 'U',
    'Û': 'U',
    'Ü': 'U',
    'Ñ': 'N',
    'Ç': 'C',
  };

  /// Upper case, accents removed, anything that is not a letter or digit
  /// turned into a single space.
  static String normalize(String s) {
    final up = s.toUpperCase();
    final b = StringBuffer();
    for (final ch in up.split('')) {
      b.write(_accents[ch] ?? ch);
    }
    return b.toString().replaceAll(RegExp(r'[^A-Z0-9]+'), ' ').trim();
  }

  static List<String> _nameParts(String name) => [
    for (final w in normalize(name).split(' '))
      if (w.length >= 2) w,
  ];

  /// Share of the profile's name parts (2+ letters) that appear as whole
  /// words in [text]. 0 when the profile has no usable name.
  static double nameMatch(String profileName, String text) {
    final parts = _nameParts(profileName);
    if (parts.isEmpty) return 0;
    final words = normalize(text).split(' ').toSet();
    final found = parts.where(words.contains).length;
    return found / parts.length;
  }

  /// Whether the typed last 4 ID characters appear in [text]; null when the
  /// user did not type 4 characters.
  static bool? last4Found(String last4, String text) {
    final l = normalize(last4).replaceAll(' ', '');
    if (l.length != 4) return null;
    return normalize(text).replaceAll(' ', '').contains(l);
  }

  static const _titles = <String, List<String>>{
    'philsys': [
      'PHILIPPINE IDENTIFICATION',
      'PAMBANSANG PAGKAKAKILANLAN',
      'PHILSYS',
      'PHILID',
    ],
    'drivers_license': [
      'DRIVER S LICENSE',
      'DRIVERS LICENSE',
      'LAND TRANSPORTATION OFFICE',
    ],
    'umid': ['UNIFIED MULTI PURPOSE', 'UMID'],
    'passport': ['PASSPORT', 'PASAPORTE'],
    'postal': ['POSTAL IDENTITY', 'POSTAL ID', 'PHLPOST'],
    'voters': ['VOTER', 'COMMISSION ON ELECTIONS', 'COMELEC'],
    'prc': ['PROFESSIONAL REGULATION', 'PRC'],
  };

  /// Whether the printed title matches the chosen ID type; null when the
  /// type has no known title ('other').
  static bool? idTypeLooksRight(String idType, String text) {
    final titles = _titles[idType];
    if (titles == null) return null;
    final t = ' ${normalize(text)} ';
    return titles.any((k) => t.contains(' $k '));
  }

  static IdCheckReport evaluate(IdCheckInput input) {
    PhilSysQr? qr;
    for (final v in input.qrValues) {
      qr = PhilSysQr.parse(v);
      if (qr != null) break;
    }
    final last4 = normalize(input.last4).replaceAll(' ', '');
    return IdCheckReport(
      nameMatch: nameMatch(input.profileName, input.ocrText),
      last4: last4.length == 4 ? last4 : null,
      last4Found: last4Found(input.last4, input.ocrText),
      idType: input.idType,
      idTypeMatches: idTypeLooksRight(input.idType, input.ocrText),
      faceOnId: input.facesOnId > 0,
      qrFound: qr != null,
      qrNameMatches: qr == null
          ? null
          : nameMatch(input.profileName, qr.fullName) >= nameThreshold,
      qrPcnLast4Matches: qr == null || last4.length != 4 || qr.pcn.isEmpty
          ? null
          : qr.pcn
                .replaceAll(RegExp(r'[^0-9A-Za-z]'), '')
                .toUpperCase()
                .endsWith(last4),
      qrSigned: qr?.hasSignature,
      liveness: input.liveness,
    );
  }
}

class IdCheckInput {
  const IdCheckInput({
    required this.profileName,
    required this.last4,
    required this.idType,
    required this.ocrText,
    required this.qrValues,
    required this.facesOnId,
    required this.liveness,
  });

  final String profileName;
  final String last4;
  final String idType;

  /// All text ML Kit read from the front (and back) of the ID.
  final String ocrText;

  /// Raw values of every QR / barcode found on the ID photos.
  final List<String> qrValues;
  final int facesOnId;

  /// Null when the live-selfie check was not done (no camera, skipped).
  final LivenessResult? liveness;
}

/// Name and card number from a PhilSys National ID QR code.
///
/// The QR is signed by the PSA, but its public key is not published for
/// apps, so the signature is only reported as present, not verified. Admins
/// can confirm a card on the government's eVerify site.
class PhilSysQr {
  const PhilSysQr({
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.pcn,
    required this.hasSignature,
  });

  final String firstName;
  final String middleName;
  final String lastName;

  /// PhilSys Card Number, as printed in the QR.
  final String pcn;
  final bool hasSignature;

  String get fullName => '$firstName $middleName $lastName';

  static PhilSysQr? parse(String raw) {
    Object? data;
    try {
      data = jsonDecode(raw.trim());
    } catch (_) {
      return null;
    }
    if (data is! Map) return null;
    String? pick(Map m, String key) {
      for (final e in m.entries) {
        if (e.key.toString().toLowerCase() == key.toLowerCase()) {
          final v = e.value?.toString().trim();
          return (v == null || v.isEmpty) ? null : v;
        }
      }
      return null;
    }

    Map? subject;
    for (final e in data.entries) {
      if (e.key.toString().toLowerCase() == 'subject' && e.value is Map) {
        subject = e.value as Map;
      }
    }
    final s = subject ?? data;
    final first = pick(s, 'fName') ?? pick(s, 'firstName') ?? '';
    final last = pick(s, 'lName') ?? pick(s, 'lastName') ?? '';
    if (first.isEmpty && last.isEmpty) return null;
    return PhilSysQr(
      firstName: first,
      middleName: pick(s, 'mName') ?? pick(s, 'middleName') ?? '',
      lastName: last,
      pcn: pick(s, 'PCN') ?? pick(data, 'PCN') ?? '',
      hasSignature: pick(data, 'signature') != null,
    );
  }
}

class LivenessResult {
  const LivenessResult({required this.passed, required this.steps});

  final bool passed;

  /// Steps completed, e.g. ['turn', 'blink', 'still'].
  final List<String> steps;

  Map<String, dynamic> toJson() => {'passed': passed, 'steps': steps};

  factory LivenessResult.fromJson(Map<String, dynamic> j) => LivenessResult(
    passed: j['passed'] == true,
    steps: [for (final s in (j['steps'] as List? ?? const [])) s.toString()],
  );
}

/// What the device found, saved with the submission for the admin.
class IdCheckReport {
  const IdCheckReport({
    required this.nameMatch,
    required this.last4,
    required this.last4Found,
    required this.idType,
    required this.idTypeMatches,
    required this.faceOnId,
    required this.qrFound,
    required this.qrNameMatches,
    required this.qrPcnLast4Matches,
    required this.qrSigned,
    required this.liveness,
  });

  final double nameMatch;
  final String? last4;
  final bool? last4Found;
  final String idType;
  final bool? idTypeMatches;
  final bool faceOnId;
  final bool qrFound;
  final bool? qrNameMatches;
  final bool? qrPcnLast4Matches;
  final bool? qrSigned;
  final LivenessResult? liveness;

  /// Plain-language problems for the admin, most important first.
  List<String> get flags => [
    if (liveness == null) 'Live selfie check not done',
    if (liveness != null && !liveness!.passed) 'Live selfie check failed',
    if (nameMatch < IdChecks.nameThreshold)
      'Name on ID does not match the profile',
    if (last4Found == false) 'ID number does not end in $last4',
    if (idTypeMatches == false)
      'ID title does not look like the chosen ID type',
    if (!faceOnId) 'No face found on the ID photo',
    if (idType == 'philsys' && !qrFound) 'National ID QR code not readable',
    if (qrNameMatches == false) 'National ID QR name does not match',
    if (qrPcnLast4Matches == false) 'National ID QR number does not match',
  ];

  /// Things that checked out, for the admin's summary.
  List<String> get passes => [
    if (liveness?.passed == true) 'Live selfie passed',
    if (nameMatch >= IdChecks.nameThreshold) 'Name matches profile',
    if (last4Found == true) 'ID number matches',
    if (idTypeMatches == true) 'ID type matches',
    if (faceOnId) 'Face found on ID',
    if (qrNameMatches == true) 'National ID QR name matches',
    if (qrPcnLast4Matches == true) 'National ID QR number matches',
  ];

  Map<String, dynamic> toJson() => {
    'version': 1,
    'name_match': nameMatch,
    'last4': last4,
    'last4_found': last4Found,
    'id_type': idType,
    'id_type_matches': idTypeMatches,
    'face_on_id': faceOnId,
    'philsys_qr': {
      'found': qrFound,
      'name_matches': qrNameMatches,
      'pcn_last4_matches': qrPcnLast4Matches,
      'signed': qrSigned,
    },
    'liveness': liveness?.toJson(),
  };

  factory IdCheckReport.fromJson(Map<String, dynamic> j) {
    final qr = (j['philsys_qr'] as Map?)?.cast<String, dynamic>() ?? const {};
    final live = (j['liveness'] as Map?)?.cast<String, dynamic>();
    return IdCheckReport(
      nameMatch: (j['name_match'] as num?)?.toDouble() ?? 0,
      last4: j['last4'] as String?,
      last4Found: j['last4_found'] as bool?,
      idType: (j['id_type'] ?? 'other').toString(),
      idTypeMatches: j['id_type_matches'] as bool?,
      faceOnId: j['face_on_id'] == true,
      qrFound: qr['found'] == true,
      qrNameMatches: qr['name_matches'] as bool?,
      qrPcnLast4Matches: qr['pcn_last4_matches'] as bool?,
      qrSigned: qr['signed'] as bool?,
      liveness: live == null ? null : LivenessResult.fromJson(live),
    );
  }
}

/// One camera frame as seen by the face detector.
class FaceSample {
  const FaceSample({
    required this.faceCount,
    this.yaw,
    this.leftEyeOpen,
    this.rightEyeOpen,
  });

  final int faceCount;

  /// Head turn in degrees (ML Kit headEulerAngleY).
  final double? yaw;
  final double? leftEyeOpen;
  final double? rightEyeOpen;
}

enum LivenessStep { turn, blink, still, done }

/// Live-selfie challenge: turn the head both ways, blink, then look at the
/// camera. A printed photo or a still screen cannot blink or turn.
class LivenessTracker {
  static const double turnDegrees = 18;
  static const double stillDegrees = 10;
  static const int stillFrames = 5;

  LivenessStep step = LivenessStep.turn;
  final List<String> _done = [];
  String? _warning;

  bool _seenLeft = false;
  bool _seenRight = false;
  bool _eyesWereOpen = false;
  bool _eyesClosed = false;
  int _still = 0;

  String get hint =>
      _warning ??
      switch (step) {
        LivenessStep.turn => 'Slowly turn your head left, then right',
        LivenessStep.blink => 'Now blink once',
        LivenessStep.still =>
          'Hold your ID next to your face and look at the camera',
        LivenessStep.done => 'Done! Taking your photo…',
      };

  LivenessResult get result =>
      LivenessResult(passed: step == LivenessStep.done, steps: [..._done]);

  void _resetStep() {
    _seenLeft = _seenRight = false;
    _eyesWereOpen = _eyesClosed = false;
    _still = 0;
  }

  void _advance(LivenessStep next, String name) {
    _done.add(name);
    step = next;
    _resetStep();
  }

  void add(FaceSample f) {
    if (step == LivenessStep.done) return;
    if (f.faceCount != 1) {
      _warning = f.faceCount == 0
          ? 'Move your face into the frame'
          : 'Keep only your face in the frame';
      _resetStep();
      return;
    }
    _warning = null;
    final yaw = f.yaw ?? 0;
    final l = f.leftEyeOpen;
    final r = f.rightEyeOpen;
    switch (step) {
      case LivenessStep.turn:
        if (yaw > turnDegrees) _seenLeft = true;
        if (yaw < -turnDegrees) _seenRight = true;
        if (_seenLeft && _seenRight) _advance(LivenessStep.blink, 'turn');
      case LivenessStep.blink:
        if (l == null || r == null) return;
        if (l > 0.7 && r > 0.7) {
          if (_eyesClosed) {
            _advance(LivenessStep.still, 'blink');
          } else {
            _eyesWereOpen = true;
          }
        } else if (_eyesWereOpen && l < 0.3 && r < 0.3) {
          _eyesClosed = true;
        }
      case LivenessStep.still:
        final eyesOk = l == null || r == null || (l > 0.5 && r > 0.5);
        _still = yaw.abs() < stillDegrees && eyesOk ? _still + 1 : 0;
        if (_still >= stillFrames) _advance(LivenessStep.done, 'still');
      case LivenessStep.done:
        break;
    }
  }
}
