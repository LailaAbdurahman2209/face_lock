
import 'package:shared_preferences/shared_preferences.dart';

class UserStorage {
  static const String _keySystemId = 'system_id';
  static const String _keyName = 'name';
  static const String _keyIdNumber = 'id_number';
  static const String _keyPin = 'pin';
  static const String _keySiteId = 'site_id';

  // Save data after successful registration
  static Future<void> saveUserData({
    required String systemId,
    required String name,
    required String idNumber,
    required String pin,
    required String siteId,
  }) async {



    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySystemId, systemId);
    await prefs.setString(_keyName, name);
    await prefs.setString(_keyIdNumber, idNumber);
    await prefs.setString(_keyPin, pin);
    await prefs.setString(_keySiteId, siteId);
  }

  // Retrieve saved user data for clock-in/verification
  static Future<Map<String, String?>> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'system_id': prefs.getString(_keySystemId),
      'name': prefs.getString(_keyName),
      'id_number': prefs.getString(_keyIdNumber),
      'pin': prefs.getString(_keyPin),
      'site_id': prefs.getString(_keySiteId),
    };
  }
}