class AppUrls {
  static const String baseUrl = 'https://s2.onguard.co.za/api';

  static const String checkAttendPinMobile = '$baseUrl/attendance/checkAttendPinMobile';
  
  // Try changing this to match your backend controller's route:
  static const String registerEndpoint = '$baseUrl/attendance/store';
  // If that still gives a 404, check your backend routes/api.php and use:
  // static const String registerEndpoint = '$baseUrl/attendance/enroll';
}