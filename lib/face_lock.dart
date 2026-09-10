import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart'; // Added for decodeImageFromList
import 'package:face_verification/face_verification.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

class FaceLock {
  FaceLock._();
  static final FaceLock instance = FaceLock._();

  static const ownerId = 'owner';
  static const sampleId = 'primary';
  
  // Set match threshold strictly between 0.65 and 0.70
  static const matchThreshold = 0.58; 

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

    // Get exact image dimensions to perform percentage-based boundary checks
    final bytes = await file.readAsBytes();
    final decodedImage = await decodeImageFromList(bytes);
    final double imgW = decodedImage.width.toDouble();
    final double imgH = decodedImage.height.toDouble();

    final faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: true, 
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.35, 
      ),
    );

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await faceDetector.processImage(inputImage);

      if (faces.isEmpty) throw Exception('NO_FACE_DETECTED');
      if (faces.length > 1) throw Exception('MULTIPLE_FACES');

      final face = faces.first;
      final box = face.boundingBox;

      // STRICT BOUNDARY CHECKS
      // Blocks the face if it spills off the top, bottom, or sides of the photo frame.
      if (box.top < (imgH * 0.08) || 
          box.bottom > (imgH * 0.92) || 
          box.left < (imgW * 0.05) || 
          box.right > (imgW * 0.95)) {
        throw Exception('INCOMPLETE_FACE');
      }

      // PROXIMITY CHECK (The Forehead Exploit Fix)
      // If the bounding box takes up more than 75% of the screen height, they are too close.
      if (box.height > (imgH * 0.75)) {
        throw Exception('INCOMPLETE_FACE');
      }

      // Strict Head Rotation Angles (Blocks side views, ears, tilted heads)
      final rotY = face.headEulerAngleY; 
      final rotZ = face.headEulerAngleZ; 
      final rotX = face.headEulerAngleX; 

      if (rotY == null || rotZ == null || rotY.abs() > 10.0 || rotZ.abs() > 10.0 || (rotX != null && rotX.abs() > 10.0)) {
        throw Exception('INCOMPLETE_FACE'); 
      }

      // Strict Eye Probability Check
      if (face.leftEyeOpenProbability == null || 
          face.rightEyeOpenProbability == null || 
          face.leftEyeOpenProbability! < 0.5 || 
          face.rightEyeOpenProbability! < 0.5) {
        throw Exception('INCOMPLETE_FACE');
      }

      // Extract Required Landmarks
      final leftEye = face.landmarks[FaceLandmarkType.leftEye];
      final rightEye = face.landmarks[FaceLandmarkType.rightEye];
      final noseBase = face.landmarks[FaceLandmarkType.noseBase];
      final mouth = face.landmarks[FaceLandmarkType.bottomMouth];

      if (leftEye == null || rightEye == null || noseBase == null || mouth == null) {
        throw Exception('INCOMPLETE_FACE');
      }

      // Top Margin Proportion Check
      final double avgEyeY = (leftEye.position.y + rightEye.position.y) / 2;
      final double eyeTopDistance = avgEyeY - box.top;

      if (eyeTopDistance < (box.height * 0.20)) {
        throw Exception('INCOMPLETE_FACE');
      }

      // Bottom Margin Check
      final double mouthBottomDistance = box.bottom - mouth.position.y;
      if (mouthBottomDistance < (box.height * 0.10)) {
        throw Exception('INCOMPLETE_FACE');
      }

      // Deflated Bounding Box Boundary Check
      const double padding = 15.0; 
      final deflatedBox = box.deflate(padding);

      if (!deflatedBox.contains(Offset(leftEye.position.x.toDouble(), leftEye.position.y.toDouble())) ||
          !deflatedBox.contains(Offset(rightEye.position.x.toDouble(), rightEye.position.y.toDouble())) ||
          !deflatedBox.contains(Offset(noseBase.position.x.toDouble(), noseBase.position.y.toDouble())) ||
          !deflatedBox.contains(Offset(mouth.position.x.toDouble(), mouth.position.y.toDouble()))) {
        throw Exception('INCOMPLETE_FACE');
      }

      // Proportional Eye Spacing
      final eyeDistance = (leftEye.position.x - rightEye.position.x).abs();
      if (eyeDistance < (box.width * 0.22)) {
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
    await _validateFullFacePresent(imagePath);

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