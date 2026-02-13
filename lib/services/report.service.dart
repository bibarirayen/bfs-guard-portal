import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/ApiService.dart';
import '../models/report.dart';

class ReportService {
  final ApiService _api = ApiService();
  Future<int> getOfficerId() async {
    final prefs = await SharedPreferences.getInstance();
    final int? id = prefs.getInt('userId');

    if (id == null) {
      throw Exception('User not logged in');
    }

    return id;
  }

  Future<List<Report>> getReports() async {
    final officerId = await getOfficerId();

    final http.Response res = await _api.get('reports/mobile/$officerId');

    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((e) => Report.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load reports');
    }
  }
}
