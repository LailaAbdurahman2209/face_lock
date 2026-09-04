import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/work_site.dart';

class ClockInService {
  // Validate the user via the API
  static Future<bool> validateUser(int customerId, String pin) async {
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
        throw TimeoutException('Request timed out.');
      },
    );

    print('API Response Status: ${response.statusCode}');
    print('API Response Body: ${response.body}');

    if (response.statusCode != 200) {
      return false;
    }

    if (response.body.isEmpty) {
      return false;
    }

    final decoded = jsonDecode(response.body);
    
    if (decoded is List) {
      return true;
    }
    
    if (decoded is Map<String, dynamic>) {
      if (decoded.containsKey('status')) {
        final status = decoded['status'];
        if (status == 'error' || status == false || status == 0 || status == 'false') {
          return false;
        }
      }
      return true;
    }
    return false;

  } on SocketException {
    //it's an offline issue, not an inactive user
    rethrow;
  } on TimeoutException {
    rethrow;
  } on http.ClientException {
    rethrow;
  } catch (e) {
    print('API Error in validateUser: $e');
    return false;
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

  // Fetch sites dynamically using the correct POST request and credentials
  static Future<List<WorkSite>> fetchSites() async {
    final url = Uri.parse('https://s2.onguard.co.za/api/attendance/validatePinMobile'); 
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final dynamicRawId = prefs.get('system_id') ?? prefs.get('customer_id');
      final int customerId = dynamicRawId is int 
          ? dynamicRawId 
          : int.tryParse(dynamicRawId?.toString() ?? '0') ?? 0;
      final pin = prefs.getString('pin') ?? '';

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

      print('Fetch Sites Response Status: ${response.statusCode}');
      print('Fetch Sites Response Body: ${response.body}');

      // Validate HTTP Status
      if (response.statusCode != 200) {
        print('HTTP Fetch Error: Received status code ${response.statusCode}');
        return [];
      }

      // Validate Response Non-Empty
      if (response.body.isEmpty) {
        print('HTTP Fetch Error: Empty response body');
        return [];
      }

      // Interrogate Data Type
      final decoded = jsonDecode(response.body);
      
      if (decoded is List) {
        // Validate List Content
        if (decoded.isEmpty) {
          print('HTTP Interrogation: Server returned an empty site list');
          return [];
        }
        return decoded.map((json) => WorkSite.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        print('HTTP Interrogation Error: Expected List but got ${decoded.runtimeType}');
        return [];
      }

    } on SocketException catch (e) {
      print('Error fetching sites (SocketException): No internet connection - $e');
      return [];
    } on TimeoutException catch (e) {
      print('Error fetching sites (TimeoutException): Connection timed out - $e');
      return [];
    } catch (e) {
      print('Error fetching sites: $e');
      return [];
    }
  }
}