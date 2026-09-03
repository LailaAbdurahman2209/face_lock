import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'face_capture_page.dart';
import '../models/work_site.dart';
import '../services/clock_in_service.dart';

class ClockInScreen extends StatefulWidget {
  const ClockInScreen({super.key});

  @override
  _ClockInScreenState createState() => _ClockInScreenState();
}

class _ClockInScreenState extends State<ClockInScreen> {
  bool _isLoading = false;
  bool _isValidated = false;
  
  Position? _currentLocation;
  List<WorkSite> _sites = [];
  int? _selectedSiteId;
  String? _siteError; // Tracks empty sites or site loading messages

  @override
  void initState() {
    super.initState();
    _startValidationProcess();
  }

  Future<void> _startValidationProcess() async {
    setState(() {
      _isLoading = true;
      _siteError = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final dynamicRawId = prefs.get('system_id') ?? prefs.get('customer_id');
      final int customerId = dynamicRawId is int 
          ? dynamicRawId 
          : int.tryParse(dynamicRawId?.toString() ?? '0') ?? 0;
          
      final pin = prefs.getString('pin') ?? '';

      print('DEBUG - Resolved customerId: $customerId, pin: $pin');

      bool isActive = await ClockInService.validateUser(customerId, pin);
      print('DEBUG - Validation API result for user active status: $isActive');

      if (isActive) {
        _currentLocation = await ClockInService.getDeviceLocation();
        _sites = await ClockInService.fetchSites();
        
        // Explicit Empty Sites Safeguard
        if (_sites.isEmpty) {
          _siteError = "No active work sites assigned to your profile. Please contact your supervisor.";
        }

        setState(() {
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
      _showErrorDialog("An error occurred during validation.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

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
                  "Validation failed. Check your connection.", 
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
                  
                  // Display warning banner if no sites are returned
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
                    // Display Dropdown when sites are available
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
                      onPressed: (_selectedSiteId == null || _sites.isEmpty) ? null : () {
                        print("Proceeding with Site ID: $_selectedSiteId");
                        print("Coordinates: ${_currentLocation?.latitude}, ${_currentLocation?.longitude}");
                        
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => FaceCapturePage(
                              mode: FaceCaptureMode.unlock,
                              onSuccess: () {},
                              employeeName: '',
                              employeePin: '',
                              employeeId: '',
                              customerId: '',
                              siteId: _selectedSiteId.toString(),
                              latitude: _currentLocation?.latitude ?? 0.0,
                              longitude: _currentLocation?.longitude ?? 0.0,
                            ),
                          ),
                        );
                      },
                      child: const Text(
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