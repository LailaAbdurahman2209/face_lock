import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

import '../face_lock.dart';
import '../utils/app_urls.dart';
import '../utils/user_storage.dart';

enum FaceCaptureMode { enroll, unlock }

class FaceCapturePage extends StatefulWidget {
  const FaceCapturePage({
    super.key,
    required this.mode,
    required this.onSuccess,
    required this.employeeName,
    required this.employeePin,
    required this.employeeId,
    required this.siteId,
    required this.customerId,
  });

  final FaceCaptureMode mode;
  final VoidCallback onSuccess;
  final String employeeName;
  final String employeePin;
  final String employeeId;
  final String siteId;
  final String customerId;

  @override
  State<FaceCapturePage> createState() => _FaceCapturePageState();
}

class _FaceCapturePageState extends State<FaceCapturePage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  bool _busy = false;
  bool _starting = true;

  bool get _enrolling => widget.mode == FaceCaptureMode.enroll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _openCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _openCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _openCamera() async {
    setState(() {
      _starting = true;
      _error = null;
    });

    final status = await Permission.camera.request();
    if (!mounted) return;

    if (!status.isGranted) {
      setState(() {
        _starting = false;
        _error = 'Camera permission required.';
      });
      return;
    }

    try {
      final cameras = await availableCameras();
      if (!mounted) return;

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      await _controller?.dispose();
      final controller = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      
      _controller = controller;
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _starting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = 'Camera error: $e';
      });
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final photo = await controller.takePicture();
      
      for (int i = 0; i < 10; i++) {
        final file = File(photo.path);
        if (await file.exists() && await file.length() > 0) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // --- CRITICAL GATEKEEPER ADDITION ---
      // Run ML Kit explicitly on the photo file before allowing enrollment or matching
      final inputImage = InputImage.fromFilePath(photo.path);
      final faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableLandmarks: true,
          performanceMode: FaceDetectorMode.accurate,
        ),
      );
      
      try {
        final faces = await faceDetector.processImage(inputImage);
        if (faces.isEmpty) {
          throw Exception('NO_FACE_DETECTED');
        }
        final face = faces.first;
        // Check for essential landmarks to block foreheads, ceilings, and walls
        if (face.landmarks[FaceLandmarkType.leftEye] == null ||
            face.landmarks[FaceLandmarkType.rightEye] == null ||
            face.landmarks[FaceLandmarkType.bottomMouth] == null) {
          throw Exception('INCOMPLETE_FACE');
        }
      } finally {
        await faceDetector.close();
      }
      // -------------------------------------
      
      if (_enrolling) {
        print('REGISTERING USER: Name: ${widget.employeeName}, ID: ${widget.employeeId}, PIN: ${widget.employeePin}');
        await FaceLock.instance.enroll(photo.path);
        await UserStorage.saveUserData(
          systemId: widget.customerId,
          name: widget.employeeName,
          idNumber: widget.employeeId,
          pin: widget.employeePin,
          siteId: widget.siteId,
        );
      } else {
        final matched = await FaceLock.instance.matches(photo.path);
        if (!matched) throw Exception('face not recognized');
      }
      
      if (!mounted) return;

      if (_enrolling) {
        widget.onSuccess();
      } else {
        await executeClockInApiCall(context);
      }

    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = FaceLock.describeError(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  Future<void> executeClockInApiCall(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF00D4FF))),
    );

    try {
      final savedData = await UserStorage.getUserData();
      final String name = savedData['name'] ?? widget.employeeName;
      final String pin = savedData['pin'] ?? widget.employeePin;
      final String idNumber = savedData['id_number'] ?? widget.employeeId;

      if (pin.isEmpty || pin == 'null') {
        if (context.mounted) Navigator.pop(context); 
        setState(() => _error = 'Missing PIN. Please register again.');
        return; 
      }

      final requestBody = {'name': name.trim(), 'id_number': idNumber.trim(), 'pin': pin.trim()};
      
      final response = await http.post(
        Uri.parse(AppUrls.checkAttendPinMobile),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode(requestBody),
      );

      final responseData = jsonDecode(response.body);
      if (context.mounted) Navigator.pop(context);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        if (context.mounted) _showResultDialog(context, true, responseData['message'] ?? 'Clocked in.');
      } else {
        if (context.mounted) _showResultDialog(context, false, responseData['message'] ?? 'Failed.');
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      setState(() => _error = 'Network error: $e');
    }
  }

  void _showResultDialog(BuildContext context, bool isSuccess, String messageText) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isSuccess ? Icons.check_circle : Icons.error_outline,
                  color: isSuccess ? Colors.green : Colors.red, size: 60),
              const SizedBox(height: 24.0),
              Text(isSuccess ? "Success" : "Failed", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12.0),
              Text(messageText, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
              const SizedBox(height: 28.0),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSuccess ? Colors.blue : Colors.red,
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: () => isSuccess ? SystemNavigator.pop() : Navigator.pop(context, true),
                child: const Text("Okay", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller != null && _controller!.value.isInitialized && !_starting;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.previewSize!.height,
                height: _controller!.value.previewSize!.width,
                child: CameraPreview(_controller!),
              ),
            )
          else
            const ColoredBox(color: Color(0xFF04110F)),

          IgnorePointer(
            child: CustomPaint(
              painter: _OvalGuidePainter(),
              child: const SizedBox.expand(),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _enrolling ? 'Register your face' : 'Unlock with your face',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  const Spacer(),
                  if (_error != null)
                    Material(
                      color: Colors.red[900]?.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!, style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (_starting)
                    const CircularProgressIndicator()
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: ready && !_busy ? _capture : null,
                        icon: _busy ? const CircularProgressIndicator(color: Colors.white) : Icon(_enrolling ? Icons.person_add : Icons.face),
                        label: Text(_busy ? 'Processing...' : (_enrolling ? 'Capture' : 'Scan')),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OvalGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final oval = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.42), width: size.width * 0.62, height: size.height * 0.42);
    canvas.drawPath(Path()..addRect(Offset.zero & size)..addOval(oval)..fillType = PathFillType.evenOdd, Paint()..color = Colors.black54);
    canvas.drawOval(oval, Paint()..color = Colors.tealAccent..style = PaintingStyle.stroke..strokeWidth = 3);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}