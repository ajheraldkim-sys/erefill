import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// What the phone found on one ID photo.
class IdPhotoScan {
  const IdPhotoScan({
    required this.text,
    required this.codes,
    required this.faces,
  });

  static const empty = IdPhotoScan(text: '', codes: [], faces: 0);

  final String text;
  final List<String> codes;
  final int faces;
}

abstract interface class IdPhotoAnalyzer {
  Future<IdPhotoScan> analyze(Uint8List bytes, String ext);
}

/// Google ML Kit, fully on-device: free, no quota, no key, nothing sent out.
class MlKitIdPhotoAnalyzer implements IdPhotoAnalyzer {
  @override
  Future<IdPhotoScan> analyze(Uint8List bytes, String ext) async {
    final dir = await Directory.systemTemp.createTemp('erefill_id_');
    final file = File('${dir.path}/id.$ext');
    await file.writeAsBytes(bytes, flush: true);
    final image = InputImage.fromFilePath(file.path);

    final text = TextRecognizer();
    final codes = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
    final faces = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.05,
      ),
    );
    try {
      final results = await Future.wait([
        text.processImage(image),
        codes.processImage(image),
        faces.processImage(image),
      ]);
      return IdPhotoScan(
        text: (results[0] as RecognizedText).text,
        codes: [
          for (final b in results[1] as List<Barcode>)
            if (b.rawValue != null) b.rawValue!,
        ],
        faces: (results[2] as List<Face>).length,
      );
    } finally {
      await Future.wait([text.close(), codes.close(), faces.close()]);
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }
}
