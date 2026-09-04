import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;

import '../face_lock.dart';
import '../utils/app_urls.dart';
import '../utils/user_storage.dart';

/// Defines the operational mode for face capture:
enum FaceCaptureMode { enroll, unlock }

/// A screen responsible for initializing the device camera,
/// either user biometric enrollment or clock-in authentication via backend API.
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
    required this.latitude,
    required this.longitude,
  });

  final FaceCaptureMode mode;
  final VoidCallback onSuccess;
  final String employeeName;
  final String employeePin;
  final String employeeId;
  final String siteId;
  final String customerId;
  final double latitude;
  final double longitude;

  @override
  State<FaceCapturePage> createState() => _FaceCapturePageState();
}

class _FaceCapturePageState extends State<FaceCapturePage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  bool _busy = false;
  bool _starting = true;
  bool _isOpening = false; // Prevents race conditions during permission prompts

  // Helper to check if the current mode is enrollment
  bool get _enrolling => widget.mode == FaceCaptureMode.enroll;

  @override
  void initState() {
    super.initState();
    
    WidgetsBinding.instance.addObserver(this);
    _openCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Safely dispose or restart the camera stream 
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      final oldController = _controller;
      _controller = null;
      oldController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && !_isOpening) {
        _openCamera();
      }
    }
  }

  @override
  void dispose() {
    // Unregister observer and dispose camera controller to prevent memory leaks
    WidgetsBinding.instance.removeObserver(this);
    final oldController = _controller;
    _controller = null;
    oldController?.dispose();
    super.dispose();
  }

  /// Requests hardware camera permissions and initializes the front-facing camera.
  Future<void> _openCamera() async {
    if (_isOpening || !mounted) return;
    _isOpening = true;

    setState(() {
      _starting = true;
      _error = null;
    });

    try {
      // Check and request camera permission using permission_handler
      var status = await Permission.camera.status;
      if (!status.isGranted) {
        status = await Permission.camera.request();
      }
      if (!mounted) return;

      if (!status.isGranted) {
        setState(() {
          _starting = false;
          _error = 'Camera permission required.';
        });
        return;
      }

      // get list of available device cameras
      final cameras = await availableCameras();
      if (!mounted) return;

      if (cameras.isEmpty) {
        setState(() {
          _starting = false;
          _error = 'No cameras available on this device.';
        });
        return;
      }

      // Select the front-facing camera for facial scanning
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      // Safely dispose old controller if any
      final oldController = _controller;
      _controller = null;
      await oldController?.dispose();

      if (!mounted) return;

      // Initialize the camera controller with high resolution 
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
        if (_controller == controller) {
          _controller = null;
        }
        return;
      }
      
      setState(() => _starting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = 'Camera error: $e';
      });
    } finally {
      _isOpening = false;
    }
  }

  /// Captures an image frame from the active camera preview and processes it
  /// with ML Kit to verify eyes, nose, and mouth are visible before proceeding.
  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // Take a picture file from the camera controller
      final photo = await controller.takePicture();
      
      // Verify that the file exists and has data before processing
      for (int i = 0; i < 10; i++) {
        if (!mounted) return;
        final file = File(photo.path);
        if (await file.exists() && await file.length() > 0) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (!mounted) return;

      // Process image with ML Kit to validate facial landmarks (eyes, nose, mouth)
      final inputImage = InputImage.fromFilePath(photo.path);
      final options = FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: true,
      );
      final faceDetector = FaceDetector(options: options);
      
      final faces = await faceDetector.processImage(inputImage);
      await faceDetector.close();

      if (faces.isEmpty) {
        throw Exception('No face detected. Please look straight into the camera.');
      }

      if (faces.length > 1) {
        throw Exception('Multiple faces detected. Only one person allowed.');
      }

      final face = faces.first;

      // Enforce check that eyes, nose, and mouth landmarks are fully visible (prevents half-face cuts)
      final leftEye = face.landmarks[FaceLandmarkType.leftEye];
      final rightEye = face.landmarks[FaceLandmarkType.rightEye];
      final nose = face.landmarks[FaceLandmarkType.noseBase];
      final mouth = face.landmarks[FaceLandmarkType.bottomMouth];

      if (leftEye == null || rightEye == null || nose == null || mouth == null) {
        throw Exception('Incomplete face detected. Ensure your eyes, nose, and mouth are fully inside the frame.');
      }

      if (!mounted) return;

      if (_enrolling) {
        // Mode: Enrollment register face locally and save user credentials 
        print('REGISTERING USER: Name: ${widget.employeeName}, ID: ${widget.employeeId}, PIN: ${widget.employeePin}, Customer ID: ${widget.customerId}');
        await FaceLock.instance.enroll(photo.path);
        await UserStorage.saveUserData(
          systemId: widget.customerId,
          name: widget.employeeName,
          idNumber: widget.employeeId,
          pin: widget.employeePin,
          siteId: widget.siteId,
        );
      } else {
        // Mode: Unlock/Verification match captured face against enrolled template
        final matched = await FaceLock.instance.matches(photo.path);
        if (!matched) throw Exception('face not recognized');
      }
      
      if (!mounted) return;

      if (_enrolling) {
        widget.onSuccess();
      } else {
        // Proceed to execute backend clock-in verification API call upon successful match
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

  /// Executes the backend API call to record the employee clock-in with location and credentials.
  Future<void> executeClockInApiCall(BuildContext context) async {
    // Show loading indicator dialog during network request
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF00D4FF))),
    );

    try {
      // get stored user profile information as fallback
      final savedData = await UserStorage.getUserData();
      final String name = savedData['name'] ?? widget.employeeName;
      final String pin = savedData['pin'] ?? widget.employeePin;
      final String idNumber = savedData['id_number'] ?? widget.employeeId;

      if (pin.isEmpty || pin == 'null') {
        if (context.mounted) Navigator.pop(context); 
        setState(() => _error = 'Missing PIN. Please register again.');
        return; 
      }

      // Construct payload for attendance verification
      final requestBody = {
        'name': name.trim(), 
        'id_number': idNumber.trim(), 
        'pin': pin.trim(),
        'site_id': widget.siteId,
        'latitude': widget.latitude,
        'longitude': widget.longitude,
      };

      print('CLOCK-IN REQUEST URL: ${AppUrls.checkAttendPinMobile}');
      print('CLOCK-IN REQUEST PAYLOAD: $requestBody');
      
      // Perform POST request with a 10-second timeout safeguard
      final response = await http.post(
        Uri.parse(AppUrls.checkAttendPinMobile),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Request timed out. Please check your internet connection.');
        },
      );

      print('CLOCK-IN RESPONSE STATUS: ${response.statusCode}');
      print('CLOCK-IN RESPONSE BODY: ${response.body}');

      if (context.mounted) Navigator.pop(context);

      // Validate HTTP response status codes
      if (response.statusCode != 200) {
        if (response.statusCode >= 500) {
          throw Exception('Server error (${response.statusCode}). Please try again later.');
        } else if (response.statusCode == 404) {
          throw Exception('Endpoint not found (${response.statusCode}).');
        } else {
          throw Exception('Server returned status code ${response.statusCode}');
        }
      }

      if (response.body.isEmpty) {
        throw Exception('Empty response received from server.');
      }

      final dynamic decodedBody = jsonDecode(response.body);

      if (decodedBody is! Map<String, dynamic>) {
        throw Exception('Unexpected data format received from server.');
      }

      final String status = decodedBody['status']?.toString().toLowerCase() ?? '';
      final String message = decodedBody['message']?.toString() ?? 'Clock-in completed.';

      // Handle server status outcome
      if (status == 'success' || status == 'true' || status == '1') {
        if (context.mounted) _showResultDialog(context, true, message);
      } else {
        if (context.mounted) _showResultDialog(context, false, message.isNotEmpty ? message : 'Clock-in failed.');
      }

    } on SocketException catch (e) {
      print('CLOCK-IN ERROR (SocketException): $e');
      if (context.mounted) Navigator.pop(context);
      setState(() => _error = 'No Internet connection. Please turn on mobile data or Wi-Fi.');
    } on TimeoutException catch (e) {
      print('CLOCK-IN ERROR (TimeoutException): $e');
      if (context.mounted) Navigator.pop(context);
      setState(() => _error = 'Connection timed out. Weak internet connection.');
    } on http.ClientException catch (e) {
      print('CLOCK-IN ERROR (ClientException): $e');
      if (context.mounted) Navigator.pop(context);
      setState(() => _error = 'Network error: Unable to reach server.');
    } catch (e) {
      print('CLOCK-IN ERROR: $e');
      if (context.mounted) Navigator.pop(context);
      final cleanMessage = e.toString().replaceAll('Exception: ', '');
      setState(() => _error = cleanMessage);
    }
  }

  /// Displays a popup dialog showing the final success or failure result of the clock-in process.
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
          // Live camera preview when initialized, otherwise show background placeholder
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

          // Overlay guiding oval shape for facial alignment
          IgnorePointer(
            child: CustomPaint(
              painter: _OvalGuidePainter(),
              child: const SizedBox.expand(),
            ),
          ),

          // User interface controls overlaid on top of camera stream
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
                  // Display error banner if any error state occurs
                  if (_error != null)
                    Material(
                      color: Colors.red[900]?.withAlpha(230),
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

/// Custom painter to draw an oval guide mask over the camera preview for facial positioning.
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