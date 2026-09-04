import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io'; 
import 'dart:async'; 
import 'package:geolocator/geolocator.dart'; 

import '../utils/app_urls.dart';

/// Screen for entering employee details and checking location/GPS.
class RegistrationFormScreen extends StatefulWidget {
  const RegistrationFormScreen({
    super.key,
    required this.onNextPressed,
    required this.onBackPressed,
  });

  final void Function(String name, String idNumber, String pin, String customerId) onNextPressed;
  final VoidCallback onBackPressed;

  @override
  State<RegistrationFormScreen> createState() => _RegistrationFormScreenState();
}

class _RegistrationFormScreenState extends State<RegistrationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Input controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _idNumberController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePin = true; 
  String? _apiError;

  // Theme colors
  final Color brandCyan = const Color(0xFF00D4FF);
  final Color bgDarkBlue = const Color(0xFF020B1A);
  final Color bgLightBlue = const Color(0xFF051B38);

  @override
  void initState() {
    super.initState();
    // Check GPS right after screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLocationOnStartup();
    });
  }

  @override
  void dispose() {
    // Dispose controllers to free memory
    _nameController.dispose();
    _idNumberController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  // Check if GPS service and location permissions are enabled
  Future<void> _checkLocationOnStartup() async {
    if (!mounted) return;
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;
    if (!serviceEnabled) {
      _showLocationPopup('Location services are turned off. Please turn on GPS in your phone settings.');
      return;
    } 

    LocationPermission permission = await Geolocator.checkPermission();
    if (!mounted) return;
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (!mounted) return;
      if (permission == LocationPermission.denied) {
        _showLocationPopup('Location permission is required to register. Please grant permission when prompted.');
        return;
      } 
    }
    
    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      _showLocationPopup('Location permission is permanently denied. Please enable it in your phone\'s App Settings.');
      return;
    }
  }

  // Show popup alert if location is disabled
  void _showLocationPopup(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF051B38),
        title: const Text('Location Required', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: TextStyle(color: brandCyan, fontSize: 16)),
          ),
        ],
      ),
    );
  }

  // Validate form inputs, check location, and send API verification request
  Future<void> _validateAndProceed() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _apiError = null;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are turned off. Please turn on GPS in your phone settings.');
      } 

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission is required to register. Please grant permission when prompted.');
        } 
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is permanently denied. Please enable it in your phone\'s App Settings.');
      }

      final uri = Uri.parse(AppUrls.checkAttendPinMobile);
      
      // Post credentials to backend
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'name': _nameController.text.trim(),
          'id_number': _idNumberController.text.trim(),
          'pin': _pinController.text.trim(),
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Request timed out. Please check your internet connection.');
        },
      );

      if (!mounted) return;

      final Map<String, dynamic> responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (responseData['status'] == 'success') {
          final String customerId = responseData['customer_id']?.toString() ?? '';
          widget.onNextPressed(
            _nameController.text.trim(),
            _idNumberController.text.trim(),
            _pinController.text.trim(),
            customerId,
          );
        } else {
          setState(() {
            _apiError = responseData['message'] ?? 'Invalid ID number or PIN.';
          });
        }
      } else {
        setState(() {
          _apiError = responseData['message'] ?? 'Server error (${response.statusCode})';
        });
      }
    } on SocketException {
      if (mounted) setState(() => _apiError = 'No Internet connection. Please turn on mobile data or Wi-Fi.');
    } on TimeoutException {
      if (mounted) setState(() => _apiError = 'Connection timed out. Weak internet connection.');
    } on http.ClientException {
      if (mounted) setState(() => _apiError = 'Network error: Unable to reach server.');
    } catch (e) {
      if (mounted) {
        final cleanMessage = e.toString().replaceAll('Exception: ', '');
        setState(() => _apiError = cleanMessage);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Helper for input field styles
  InputDecoration _customInputDecoration(String label, IconData icon, {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: brandCyan),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFF061833),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: brandCyan.withAlpha(77)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: brandCyan, width: 2),
      ),
      errorStyle: const TextStyle(color: Colors.redAccent),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgLightBlue, bgDarkBlue],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back button
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: widget.onBackPressed,
                  ),
                  const SizedBox(height: 20),
                  
                  const Text(
                    'Employee Verification',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Verify your details before scanning your face.',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 30),

                  // Error banner
                  if (_apiError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withAlpha(51),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent),
                      ),
                      child: Text(
                        _apiError!,
                        style: const TextStyle(color: Colors.redAccent),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Name field
                  TextFormField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white),
                    textCapitalization: TextCapitalization.words,
                    decoration: _customInputDecoration('Name', Icons.person),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Please enter your name';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // ID Number field (13 digits)
                  TextFormField(
                    controller: _idNumberController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 13,
                    decoration: _customInputDecoration('ID Number', Icons.badge).copyWith(counterText: ""),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Please enter your ID number';
                      if (!RegExp(r'^[0-9]{13}$').hasMatch(value)) return 'ID must be exactly 13 digits';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // PIN field with toggle visibility
                  TextFormField(
                    controller: _pinController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    obscureText: _obscurePin,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _customInputDecoration(
                      'Supervisor PIN',
                      Icons.lock,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePin ? Icons.visibility_off : Icons.visibility,
                          color: brandCyan,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePin = !_obscurePin;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Please enter the PIN';
                      return null;
                    },
                  ),
                  const SizedBox(height: 40),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _isLoading ? null : _validateAndProceed,
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Verify & Capture Face',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}