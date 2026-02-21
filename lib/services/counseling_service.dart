import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/ApiService.dart';

class CounselingService {
  final ApiService api = ApiService();

  // Fetch all guards
  Future<List<Map<String, dynamic>>> getAllGuards() async {
    final response = await api.get('users/getGuards'); // GET /api/getGuards
    if (response.statusCode == 200) {
      final List data = response.body.isNotEmpty ? List.from(jsonDecode(response.body)) : [];
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to fetch guards');
    }
  }

  // Fetch all counseling statements (for list page)
  Future<List<Map<String, dynamic>>> getAllStatements() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    final response = await api.get('counseling/supervisor/$userId');
    if (response.statusCode == 200) {
      final List data = response.body.isNotEmpty ? List.from(jsonDecode(response.body)) : [];
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to fetch statements');
    }
  }

  // Upload counseling statement with media — uses Dio for real progress + MIME types
  Future<void> uploadStatementDio(
      Map<String, dynamic> payload,
      List<File> files,
      Function(int sent, int total) onProgress,
      ) async {
    return await api.uploadCounselingDio(payload, files, onProgress);
  }
}