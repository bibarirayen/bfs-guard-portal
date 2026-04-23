import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/ApiService.dart';

class SopService {
  final ApiService _api = ApiService();

  /// Fetch SOP info for a specific site.
  /// Returns null if no SOP is configured (204 response).
  Future<Map<String, String>?> getSop(int siteId) async {
    final res = await _api.get('sites/$siteId/sop');
    if (res.statusCode == 204 || res.body.isEmpty) return null;
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return {
        'sopFileName': data['sopFileName'] ?? '',
        'sopFileUrl': data['sopFileUrl'] ?? '',
      };
    }
    throw Exception('Failed to load SOP');
  }

  /// Fetch all sites (with sopFileName and sopFileUrl included).
  Future<List<Map<String, dynamic>>> getAllSitesWithSop() async {
    final res = await _api.get('sites');
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load sites');
  }
}
