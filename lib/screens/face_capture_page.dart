import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;

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

      final cameras = await availableCameras();
      if (!mounted) return;

      if (cameras.isEmpty) {
        setState(() {
          _starting = false;
          _error = 'No cameras available on this device.';
        });
        return;
      }

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final oldController = _controller;
      _controller = null;
      await oldController?.dispose();

      if (!mounted) return;

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
      final photo = await controller.takePicture();
      
      for (int i = 0; i < 10; i++) {
        if (!mounted) return;
        final file = File(photo.path);
        if (await file.exists() && await file.length() > 0) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (!mounted) return;

      // 1. FIX FOR iOS ROTATION: Bake orientation into image file BEFORE running ML Kit face detection
      final imageBytes = await File(photo.path).readAsBytes();
      final decodedImage = img.decodeImage(imageBytes);
      if (decodedImage != null) {
        final uprightImage = img.bakeOrientation(decodedImage);
        await File(photo.path).writeAsBytes(img.encodeJpg(uprightImage, quality: 90));
      }

      // 2. Pass the saved upright image file to ML Kit Face Detector
      final inputImage = InputImage.fromFilePath(photo.path);
      final options = FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.15,
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

      final leftEye = face.landmarks[FaceLandmarkType.leftEye];
      final rightEye = face.landmarks[FaceLandmarkType.rightEye];
      final nose = face.landmarks[FaceLandmarkType.noseBase];
      final mouth = face.landmarks[FaceLandmarkType.bottomMouth];

      if (leftEye == null || rightEye == null || nose == null || mouth == null) {
        throw Exception('Incomplete face detected. Ensure your eyes, nose, and mouth are fully inside the frame.');
      }

      if (!mounted) return;

      if (_enrolling) {
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

  /// Executes backend API calls and enforces site-matching rules and cooldown buffers.
  Future<void> executeClockInApiCall(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. COOLDOWN CHECK: Prevent backend errors within 2 minutes of last scan
    final lastClock = prefs.getInt('last_clock_timestamp') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final timePassed = now - lastClock;

    if (timePassed < 120000) { // 120,000 ms = 2 minutes
      final remainingSeconds = ((120000 - timePassed) / 1000).ceil();
      setState(() => _error = 'Please wait $remainingSeconds seconds before scanning again.');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF00D4FF))),
    );

    try {
      bool isClockedIn = prefs.getBool('is_clocked_in') ?? false;
      String? clockedInSiteId = prefs.getString('clocked_in_site_id');

      // RULE: If user is already clocked in, they MUST clock out at the exact same site
      if (isClockedIn && clockedInSiteId != null && clockedInSiteId != widget.siteId) {
        if (context.mounted) Navigator.pop(context);
        setState(() => _error = 'Please clock out at the site you clocked in at.');
        return;
      }

      final savedData = await UserStorage.getUserData();
      final String name = savedData['name'] ?? widget.employeeName;
      final String pin = savedData['pin'] ?? widget.employeePin;
      final String idNumber = savedData['id_number'] ?? widget.employeeId;

      if (pin.isEmpty || pin == 'null') {
        if (context.mounted) Navigator.pop(context); 
        setState(() => _error = 'Missing PIN. Please register again.');
        return; 
      }

      // 1. Attendance verification API call (checkAttendPinMobile)
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

      if (response.statusCode != 200) {
        String errorMsg = 'Server error (${response.statusCode})';
        try {
          final errData = jsonDecode(response.body);
          if (errData['message'] != null) {
            errorMsg = errData['message'].toString();
          }
        } catch (_) {}
        throw Exception(errorMsg);
      }

      // 2. OnGuard clockAttendance API Call
      final onGuardPayload = {
        "token": "9615f5f73c8819876148beba560c7df01a23c00c",
        "lat": widget.latitude,
        "lng": widget.longitude,
        "imei": "0",
        "nfc_tag": pin.trim(),
        "site_id": widget.siteId,
      };

      print('ONGUARD CLOCK URL: https://s2.onguard.co.za/api/attendance/clockAttendance');
      print('ONGUARD PAYLOAD: $onGuardPayload');

      final onGuardResponse = await http.post(
        Uri.parse('https://s2.onguard.co.za/api/attendance/clockAttendance'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode(onGuardPayload),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('OnGuard request timed out.');
        },
      );

      print('ONGUARD RESPONSE STATUS: ${onGuardResponse.statusCode}');
      print('ONGUARD RESPONSE BODY: ${onGuardResponse.body}');

      if (context.mounted) Navigator.pop(context);

      if (onGuardResponse.statusCode != 200) {
        String errorMsg = 'OnGuard server error (${onGuardResponse.statusCode})';
        try {
          final errData = jsonDecode(onGuardResponse.body);
          if (errData['message'] != null) {
            errorMsg = errData['message'].toString();
          }
        } catch (_) {}
        throw Exception(errorMsg);
      }

      // Decode OnGuard response to evaluate true state from server message
      final onGuardDecoded = jsonDecode(onGuardResponse.body);
      final String onGuardStatus = onGuardDecoded['status']?.toString().toLowerCase() ?? '';
      final String onGuardMessage = onGuardDecoded['message']?.toString() ?? '';

      // Extract the actual employee number from the OnGuard message string
      String employeeNumber = '';
      final empMatch = RegExp(r'Employee number[^\d]*(\d+)', caseSensitive: false).firstMatch(onGuardMessage);
      if (empMatch != null) {
        employeeNumber = empMatch.group(1) ?? '';
      }

      if (onGuardStatus == 'success' || onGuardStatus == 'true' || onGuardStatus == '1') {
        // 2. SAVE TIMESTAMP: Record success time to enforce 2-min buffer
        await prefs.setInt('last_clock_timestamp', DateTime.now().millisecondsSinceEpoch);

        final bool isServerClockedIn = onGuardMessage.toLowerCase().contains('in') || 
                                       onGuardMessage.toLowerCase().contains('welcome');

        if (isServerClockedIn) {
          await prefs.setBool('is_clocked_in', true);
          await prefs.setString('clocked_in_site_id', widget.siteId);

          if (context.mounted) {
            _showResultDialog(context, true, "Success! You are now clocked in.");
          }
        } else {
          await prefs.setBool('is_clocked_in', false);
          await prefs.remove('clocked_in_site_id');

          if (context.mounted) {
            _showClockOutSuccessDialog(context, "Thank you, you are now clocked out.", employeeNumber);
          }
        }
      } else {
        if (context.mounted) _showResultDialog(context, false, onGuardMessage.isNotEmpty ? onGuardMessage : 'Action failed.');
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

  /// Displays popup dialog for successful clock-out including the parsed employee number.
  void _showClockOutSuccessDialog(BuildContext context, String messageText, String employeeNumber) {
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
              const Icon(Icons.check_circle, color: Colors.green, size: 60),
              const SizedBox(height: 24.0),
              const Text("Clocked Out", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12.0),
              Text(messageText, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
              if (employeeNumber.isNotEmpty) ...[
                const SizedBox(height: 8.0),
                Text(
                  "Employee Number: $employeeNumber",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
                ),
              ],
              const SizedBox(height: 28.0),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: () => exit(0), // Instantly terminates app process on iOS
                child: const Text("Okay", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
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
                onPressed: () {
                  if (isSuccess) {
                    exit(0); // Force exit app on success
                  } else {
                    Navigator.pop(context, true); // Dismiss dialog to retry on failure
                  }
                },
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