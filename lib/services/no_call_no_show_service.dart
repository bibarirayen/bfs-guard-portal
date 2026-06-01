import 'dart:convert';

import '../config/ApiService.dart';

class NoCallNoShowService {
  final ApiService api = ApiService();

  Future<List<Map<String, dynamic>>> getSupervisorReports(int userId) async {
    final response = await api.get('no-call-no-show/supervisor/$userId');
    if (response.statusCode == 200) {
      final List data = response.body.isNotEmpty ? List.from(jsonDecode(response.body)) : [];
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load no call no show reports');
  }

  Future<List<Map<String, dynamic>>> getSiteOptions(int userId) async {
    final response = await api.get('no-call-no-show/options/$userId/sites');
    if (response.statusCode == 200) {
      final List data = response.body.isNotEmpty ? List.from(jsonDecode(response.body)) : [];
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load sites');
  }

  Future<List<Map<String, dynamic>>> getGuardOptions(int userId, int siteId) async {
    final response = await api.get('no-call-no-show/options/$userId/site/$siteId/guards');
    if (response.statusCode == 200) {
      final List data = response.body.isNotEmpty ? List.from(jsonDecode(response.body)) : [];
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load guards');
  }

  Future<List<Map<String, dynamic>>> getShiftOptions(int userId, int siteId) async {
    final response = await api.get('no-call-no-show/options/$userId/site/$siteId/shifts');
    if (response.statusCode == 200) {
      final List data = response.body.isNotEmpty ? List.from(jsonDecode(response.body)) : [];
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load shifts');
  }

  Future<void> create(Map<String, dynamic> payload) async {
    final response = await api.post('no-call-no-show', payload);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to create no call no show report');
    }
  }
}
