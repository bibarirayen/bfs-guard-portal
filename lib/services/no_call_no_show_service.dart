import 'dart:convert';
import 'dart:developer' as dev;

import '../config/ApiService.dart';

class NoCallNoShowService {
  final ApiService api = ApiService();

  Future<List<Map<String, dynamic>>> getSupervisorReports(int userId) async {
    dev.log('[NCNS] getSupervisorReports userId=$userId', name: 'NoCallNoShow');
    final response = await api.get('no-call-no-show/supervisor/$userId');
    dev.log('[NCNS] getSupervisorReports → ${response.statusCode}', name: 'NoCallNoShow');
    if (response.statusCode == 200) {
      final List data = response.body.isNotEmpty ? List.from(jsonDecode(response.body)) : [];
      return data.cast<Map<String, dynamic>>();
    }
    dev.log('[NCNS] getSupervisorReports error body: ${response.body}', name: 'NoCallNoShow');
    throw Exception('Failed to load reports (${response.statusCode})');
  }

  Future<List<Map<String, dynamic>>> getSiteOptions(int userId) async {
    dev.log('[NCNS] getSiteOptions userId=$userId', name: 'NoCallNoShow');
    final response = await api.get('no-call-no-show/options/$userId/sites');
    dev.log('[NCNS] getSiteOptions → ${response.statusCode}', name: 'NoCallNoShow');
    if (response.statusCode == 200) {
      final List data = response.body.isNotEmpty ? List.from(jsonDecode(response.body)) : [];
      dev.log('[NCNS] sites loaded: ${data.length}', name: 'NoCallNoShow');
      return data.cast<Map<String, dynamic>>();
    }
    dev.log('[NCNS] getSiteOptions error body: ${response.body}', name: 'NoCallNoShow');
    throw Exception('Failed to load sites (${response.statusCode})');
  }

  Future<List<Map<String, dynamic>>> getAllGuards() async {
    dev.log('[NCNS] getAllGuards via no-call-no-show/guards', name: 'NoCallNoShow');
    final response = await api.get('no-call-no-show/guards');
    dev.log('[NCNS] getAllGuards → ${response.statusCode}', name: 'NoCallNoShow');
    if (response.statusCode == 200) {
      final List data = response.body.isNotEmpty ? List.from(jsonDecode(response.body)) : [];
      dev.log('[NCNS] guards loaded: ${data.length}', name: 'NoCallNoShow');
      return data.cast<Map<String, dynamic>>();
    }
    dev.log('[NCNS] getAllGuards error body: ${response.body}', name: 'NoCallNoShow');
    throw Exception('Failed to load guards (${response.statusCode})');
  }

  Future<List<Map<String, dynamic>>> getShiftOptions(int userId, int siteId) async {
    dev.log('[NCNS] getShiftOptions userId=$userId siteId=$siteId', name: 'NoCallNoShow');
    final response = await api.get('no-call-no-show/options/$userId/site/$siteId/shifts');
    dev.log('[NCNS] getShiftOptions → ${response.statusCode}', name: 'NoCallNoShow');
    if (response.statusCode == 200) {
      final List data = response.body.isNotEmpty ? List.from(jsonDecode(response.body)) : [];
      dev.log('[NCNS] shifts loaded: ${data.length}', name: 'NoCallNoShow');
      return data.cast<Map<String, dynamic>>();
    }
    dev.log('[NCNS] getShiftOptions error body: ${response.body}', name: 'NoCallNoShow');
    throw Exception('Failed to load shifts (${response.statusCode})');
  }

  Future<void> create(Map<String, dynamic> payload) async {
    dev.log('[NCNS] create payload: ${jsonEncode(payload)}', name: 'NoCallNoShow');
    final response = await api.post('no-call-no-show', payload);
    dev.log('[NCNS] create → ${response.statusCode} body: ${response.body}', name: 'NoCallNoShow');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Extract the backend error message so it shows to the user
      String backendMessage = 'Server error (${response.statusCode})';
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        backendMessage = (decoded['error'] ?? decoded['message'] ?? backendMessage).toString();
      } catch (_) {
        if (response.body.isNotEmpty) backendMessage = response.body;
      }
      dev.log('[NCNS] create failed: $backendMessage', name: 'NoCallNoShow');
      throw Exception(backendMessage);
    }
  }
}
