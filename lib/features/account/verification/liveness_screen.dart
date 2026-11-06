import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../../core/constants.dart';
import 'id_checks.dart';

/// What the live-selfie screen returns: the final photo and the result.
typedef LiveSelfie = ({Uint8List bytes, LivenessResult result});

/// Live selfie with on-device liveness (Google ML Kit face detection):
/// turn the head both ways, blink, then hold the ID and look at the camera.
/// The photo is taken automatically at the end. Pops a [LiveSelfie], or null.
class LivenessScreen extends StatefulWidget {
  const LivenessScreen({super.key});

  static const timeLimit = Duration(seconds: 60);

  @override
  State<LivenessScreen> createState() => _LivenessScreenState();
}

class _LivenessScreenState extends State<LivenessScreen> {
  CameraController? _camera;
  final _faces = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.2,
    ),
  );
  final _tracker = LivenessTracker();
  bool _busy = false;
  bool _finishing = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final cams = await availableCameras();
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
      await controller.startImageStream((img) => _onFrame(img, front));
      _timer = Timer(LivenessScreen.timeLimit, () {
        if (mounted && _tracker.step != LivenessStep.done) {
          setState(() => _error = 'Time is up. Try again in good light.');
          _camera?.stopImageStream().catchError((_) {});
        }
      });
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _error = 'Camera unavailable. Allow camera access and try again.',
        );
      }
    }
  }

  InputImage? _toInputImage(CameraImage img, CameraDescription cam) {
    final rotation =
        InputImageRotationValue.fromRawValue(cam.sensorOrientation);
    final format = InputImageFormatValue.fromRawValue(img.format.raw as int);
    if (rotation == null || format == null || img.planes.isEmpty) return null;
    final bytes = img.planes.length == 1
        ? img.planes.first.bytes
        : Uint8List.fromList([for (final p in img.planes) ...p.bytes]);
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(img.width.toDouble(), img.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: img.planes.first.bytesPerRow,
      ),
    );
  }

  Future<void> _onFrame(CameraImage img, CameraDescription cam) async {
    if (_busy || _finishing || _error != null) return;
    _busy = true;
    try {
      final input = _toInputImage(img, cam);
      if (input == null) return;
      final faces = await _faces.processImage(input);
      final f = faces.length == 1 ? faces.first : null;
      _tracker.add(
        FaceSample(
          faceCount: faces.length,
          yaw: f?.headEulerAngleY,
          leftEyeOpen: f?.leftEyeOpenProbability,
          rightEyeOpen: f?.rightEyeOpenProbability,
        ),
      );
      if (!mounted) return;
      setState(() {});
      if (_tracker.step == LivenessStep.done) await _finish();
    } catch (e) {
      debugPrint('Liveness frame failed: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    _timer?.cancel();
    try {
      final cam = _camera!;
      await cam.stopImageStream();
      final shot = await cam.takePicture();
      final bytes = await shot.readAsBytes();
      if (mounted) {
        Navigator.pop<LiveSelfie>(context, (
          bytes: bytes,
          result: _tracker.result,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _finishing = false;
          _error = 'Could not take the photo. Try again.';
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    final cam = _camera;
    if (cam != null) {
      if (cam.value.isStreamingImages) cam.stopImageStream().catchError((_) {});
      cam.dispose();
    }
    _faces.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cam = _camera;
    final steps = LivenessStep.values
        .where((s) => s != LivenessStep.done)
        .toList();
    final current = _tracker.step;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Live selfie'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: cam == null || !cam.value.isInitialized
                  ? (_error == null
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const SizedBox.shrink())
                  : ClipOval(
                      child: AspectRatio(
                        aspectRatio: 3 / 4,
                        child: CameraPreview(cam),
                      ),
                    ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            color: AppUi.surfaceOf(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final s in steps)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          s.index < current.index
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: s.index < current.index
                              ? Colors.green
                              : AppUi.textSecondaryOf(context),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error ?? _tracker.hint,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _error != null
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
