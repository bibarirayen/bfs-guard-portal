import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/ApiService.dart';

class EmployeeHandbookService {
  final ApiService _api = ApiService();

  /// Fetch all handbook entries, newest first.
  Future<List<Map<String, dynamic>>> getAll() async {
    final res = await _api.get('handbook');
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load handbook');
  }
}
