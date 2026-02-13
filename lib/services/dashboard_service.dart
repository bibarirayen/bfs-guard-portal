import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/ApiService.dart';

class DashboardService {
  final String baseUrl = "https://api.blackfabricsecurity.com/api";
  final ApiService _api = ApiService();

  Future<Map<String, dynamic>> getDashboardMobile() async {
    final prefs = await SharedPreferences.getInstance();
    final guardId = prefs.getInt('userId'); // ✅ stored at login
    if (guardId == null) {
      throw Exception('User not logged in');
    }
    final response = await _api.get('assignments/dashboard-mobile/$guardId');

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to load dashboard");
    }
  }
}
