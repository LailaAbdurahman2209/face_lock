import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'face_capture_page.dart';
import '../models/work_site.dart';
import '../services/clock_in_service.dart';

/// Screen for validating user status and location, then selecting a work site.
class ClockInScreen extends StatefulWidget {
  const ClockInScreen({super.key});

  @override
  _ClockInScreenState createState() => _ClockInScreenState();
}

class _ClockInScreenState extends State<ClockInScreen> {
  bool _isLoading = false;
  bool _isValidated = false;
  bool _isVerifyingSite = false; // Loading state for site validation call
  
  Position? _currentLocation;
  List<WorkSite> _sites = [];
  int? _selectedSiteId;
  int? _customerId; // Saved customerId for the API payload
  String? _siteError;

  @override
  void initState() {
    super.initState();
    // Validate location and user data instantly when the screen opens
    _startValidationProcess();
  }

  // Check location, verify user credentials, and fetch work sites
  Future<void> _startValidationProcess() async {
    setState(() {
      _isLoading = true;
      _siteError = null;
    });

    try {
      // Check if location services and GPS are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are turned off. Please turn on GPS in your phone settings.');
      } 

      // Check and request location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission is required to clock in. Please grant permission when prompted.');
        } 
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is permanently denied. Please enable it in your phone\'s App Settings.');
      }

      // Load stored user ID and PIN from shared preferences
      final prefs = await SharedPreferences.getInstance();
      final dynamicRawId = prefs.get('system_id') ?? prefs.get('customer_id');
      final int customerId = dynamicRawId is int 
          ? dynamicRawId 
          : int.tryParse(dynamicRawId?.toString() ?? '0') ?? 0;
          
      final pin = prefs.getString('pin') ?? '';

      print('DEBUG - Resolved customerId: $customerId, pin: $pin');

      // Verify if user is active via API
      bool isActive = await ClockInService.validateUser(customerId, pin);
      print('DEBUG - Validation API result for user active status: $isActive');

      if (isActive) {
        // Get high-accuracy GPS coordinates and fetch assigned work sites
        _currentLocation = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        _sites = await ClockInService.fetchSites();
        
        if (_sites.isEmpty) {
          _siteError = "No active work sites assigned to your profile. Please contact your supervisor.";
        }

        setState(() {
          _customerId = customerId; // Store customerId in state
          _isValidated = true;
        });
      } else {
        _showErrorDialog("Employee is no longer active or credentials invalid.");
      }
    } on TimeoutException catch (e) {
      print('DEBUG - Connection timed out: $e');
      _showErrorDialog("Connection timed out. Weak internet connection.");
    } on SocketException catch (e) {
      print('DEBUG - Network offline (SocketException): $e');
      _showErrorDialog("No Internet connection. Please turn on mobile data or Wi-Fi.");
    } on http.ClientException catch (e) {
      print('DEBUG - Network client exception: $e');
      _showErrorDialog("No Internet connection. Please turn on mobile data or Wi-Fi.");
    } catch (e) {
      print('DEBUG - Error during validation process: $e');
      final cleanMessage = e.toString().replaceAll('Exception: ', '');
      _showErrorDialog(cleanMessage);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Validate site radius with server before opening face scan
  Future<void> _handleProceedToFaceScan() async {
    if (_selectedSiteId == null || _currentLocation == null || _customerId == null) return;

    setState(() => _isVerifyingSite = true);

    try {
      final url = Uri.parse('https://s2.onguard.co.za/api/attendance/validateTnaLocation');
      
      final payload = {
        "lat": _currentLocation!.latitude,
        "lng": _currentLocation!.longitude,
        "customer_id": _customerId,
        "site_id": _selectedSiteId,
      };

      print('DEBUG - Sending Site Validation Payload: ${jsonEncode(payload)}');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      print('DEBUG - Site Validation Response Status Code: ${response.statusCode}');
      print('DEBUG - Site Validation Response Body: ${response.body}');

      // Strict Rule: If HTTP status code is NOT 200, block proceeding
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception("You are not near the site you selected to work at. Please go to the site you select and try again");
      }

      final data = jsonDecode(response.body);

      // Verify success status
      if (data['status'] == 'success') {
        if (!mounted) return;
        
        // Site radius verified! Proceed to Face Capture screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FaceCapturePage(
              mode: FaceCaptureMode.unlock,
              onSuccess: () {},
              employeeName: '',
              employeePin: '',
              employeeId: '',
              customerId: _customerId.toString(),
              siteId: _selectedSiteId.toString(),
              latitude: _currentLocation?.latitude ?? 0.0,
              longitude: _currentLocation?.longitude ?? 0.0,
            ),
          ),
        );
      } else {
        throw Exception("You are not in the right site, please move to the correct site and try again.");
      }

    } on TimeoutException {
      _showErrorDialog("Location verification timed out. Please try again.");
    } on SocketException {
      _showErrorDialog("No Internet connection. Please turn on mobile data or Wi-Fi.");
    } on http.ClientException {
      _showErrorDialog("Network error occurred. Please check your internet connection.");
    } catch (e) {
      final cleanMessage = e.toString().replaceAll('Exception: ', '');
      _showErrorDialog(cleanMessage);
    } finally {
      if (mounted) {
        setState(() => _isVerifyingSite = false);
      }
    }
  }

  // Show error popup dialog
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF04110F),
        title: const Text("Access Denied", style: TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("OK", style: TextStyle(color: Colors.tealAccent)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF04110F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Clock In Selection', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
        : !_isValidated 
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  "Validation failed. Check your connection or location settings.", 
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16),
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Location status indicator card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.tealAccent, size: 28),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                "Location Status",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              SizedBox(height: 4),
                              Text(
                                "GPS Coordinates acquired securely",
                                style: TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  const Text(
                    "Select Work Site", 
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)
                  ),
                  const SizedBox(height: 12),
                  
                  // Show site error warning box or site selection dropdown
                  if (_sites.isEmpty || _siteError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber[900]?.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amberAccent),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.amberAccent,
                            size: 36,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _siteError ?? "No active work sites assigned to your profile.",
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.amberAccent),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: _startValidationProcess,
                            icon: const Icon(Icons.refresh, color: Colors.amberAccent, size: 18),
                            label: const Text(
                              'Retry Loading Sites',
                              style: TextStyle(color: Colors.amberAccent),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    DropdownButtonFormField<int>(
                      dropdownColor: const Color(0xFF0A221F),
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.tealAccent, width: 2),
                        ),
                        hintText: "Select a site",
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                      ),
                      value: _selectedSiteId,
                      items: _sites.map((site) {
                        return DropdownMenuItem<int>(
                          value: site.id,
                          child: Text(site.name, style: const TextStyle(color: Colors.white)),
                        );
                      }).toList(),
                      onChanged: (int? newValue) {
                        setState(() {
                          _selectedSiteId = newValue;
                        });
                      },
                    ),
                  ],
                  
                  const SizedBox(height: 40),
                  
                  // Proceed to Face Scan button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.tealAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: (_selectedSiteId == null || _sites.isEmpty || _isVerifyingSite) 
                          ? null 
                          : _handleProceedToFaceScan,
                      child: _isVerifyingSite
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
                          )
                        : const Text(
                            "Proceed to Face Scan", 
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                          ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}