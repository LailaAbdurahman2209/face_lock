import 'dart:io';
import 'package:face_verification/face_verification.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

class FaceLock {
  FaceLock._();
  static final FaceLock instance = FaceLock._();

  static const ownerId = 'owner';
  static const sampleId = 'primary';
  
  // Set match threshold strictly between 0.65 and 0.70
  static const matchThreshold = 0.68; 

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    await FaceVerification.instance.init();
    _ready = true;
  }

  Future<bool> isEnrolled() {
    return FaceVerification.instance.isFaceRegistered(ownerId);
  }

Future<void> _validateFullFacePresent(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw Exception('Image file does not exist.');
    }

    final faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: true, // <-- ADDED: Required for eye visibility/probabilities
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.25, // Requires face to occupy at least 25% of frame
      ),
    );

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        throw Exception('NO_FACE_DETECTED');
      }
      if (faces.length > 1) {
        throw Exception('MULTIPLE_FACES');
      }

      final face = faces.first;

      // ---> ADDED: Strict head pose angle checks <---
      final rotY = face.headEulerAngleY; // Left/Right turn
      final rotZ = face.headEulerAngleZ; // Tilt (ear-to-shoulder)

      // If head is turned or tilted more than 10 degrees, reject it
      if (rotY == null || rotZ == null || rotY.abs() > 10.0 || rotZ.abs() > 10.0) {
        throw Exception('INCOMPLETE_FACE'); 
      }

      final leftEye = face.landmarks[FaceLandmarkType.leftEye];
      final rightEye = face.landmarks[FaceLandmarkType.rightEye];
      final noseBase = face.landmarks[FaceLandmarkType.noseBase];
      final mouth = face.landmarks[FaceLandmarkType.bottomMouth];

      // Reject foreheads, ceilings, teacups, and obscured faces instantly
      if (leftEye == null || rightEye == null || noseBase == null || mouth == null) {
        throw Exception('INCOMPLETE_FACE');
      }

      // Enforce minimum eye-spacing distance to block close-up noses or objects
      final eyeDistance = (leftEye.position.x - rightEye.position.x).abs();
      if (eyeDistance < 60) {
        throw Exception('INCOMPLETE_FACE');
      }
    } finally {
      await faceDetector.close();
    }
  }
Future<void> enroll(String imagePath) async {
    try {
      print('🔒 [FaceLock] Starting strict ML Kit validation...');
      await _validateFullFacePresent(imagePath);
      print('✅ [FaceLock] ML Kit validation passed!');

      if (await isEnrolled()) {
        print('🗑️ [FaceLock] Deleting existing enrollment...');
        await FaceVerification.instance.deleteUserFaces(ownerId);
      }
      
      print('📝 [FaceLock] Registering face embedding...');
      await FaceVerification.instance.registerFromImagePath(
        id: ownerId,
        imagePath: imagePath,
        imageId: sampleId,
        name: 'Owner',
      );
      print('🎉 [FaceLock] Enrollment successfully completed!');
    } catch (e) {
      print('❌ [FaceLock] ENROLL FAILED WITH ERROR: $e');
      rethrow;
    }
  }
  Future<bool> matches(String imagePath) async {
    // MUST pass ML Kit face check before verification plugin is executed
    await _validateFullFacePresent(imagePath);


    // Perform embedding match
    final matchId = await FaceVerification.instance.verifyFromImagePath(
      imagePath: imagePath,
      threshold: matchThreshold,
      staffId: ownerId,
    );

    return matchId == ownerId;
  }

  Future<void> reset() {
    return FaceVerification.instance.deleteUserFaces(ownerId);
  }

  Future<PermissionStatus> requestCamera() {
    return Permission.camera.request();
  }

  static String describeError(Object error) {
    final text = error.toString();
    if (text.contains('NO_FACE_DETECTED')) return 'No face detected in frame. Point camera at your face.';
    if (text.contains('INCOMPLETE_FACE')) return 'Full face required. Both eyes and mouth must be visible.';
    if (text.contains('MULTIPLE_FACES')) return 'Multiple faces detected. Only one person allowed.';
    return 'Face not recognized. Ensure good lighting and face the camera directly.';
  }
}