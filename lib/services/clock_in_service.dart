import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '../models/work_site.dart';

class ClockInService {
  // Validates the user AND returns the sites in a single API call to prevent double-firing
  static Future<List<WorkSite>?> validateAndGetSites(int customerId, String pin) async {
    final url = Uri.parse('https://s2.onguard.co.za/api/attendance/validatePinMobile');
    
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'customer_id': customerId,
          'pin': pin,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Request timed out. Please check your internet connection.');
        },
      );

      print('API Response Status: ${response.statusCode}');
      print('API Response Body: ${response.body}');

      if (response.statusCode != 200 || response.body.isEmpty) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      
      // If the API returns a List, the PIN is valid and these are the sites
      if (decoded is List) {
        return decoded.map((json) => WorkSite.fromJson(json as Map<String, dynamic>)).toList();
      }
      
      // If the API returns an error map, the PIN is invalid
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('status')) {
          final status = decoded['status'];
          if (status == 'error' || status == false || status == 0 || status == 'false') {
            return null;
          }
        }
      }
      
      return []; // Fallback for a valid response with no sites

    } on SocketException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } on http.ClientException {
      rethrow;
    } catch (e) {
      print('API Error in validateAndGetSites: $e');
      return null;
    }
  }

  // Get the device's current latitude and longitude
  static Future<Position?> getDeviceLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check if GPS / Location services are turned on
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are turned off. Please turn on GPS in your phone settings.');
    } 

    // Check location permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission is required to clock in. Please grant permission when prompted.');
      } 
    }
    
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permission is permanently denied. Please enable it in your phone\'s App Settings.');
    } 

    // Fetch location if permissions and services are active
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high
    );
  }
}