import 'dart:convert';
import 'dart:developer' as dev;

import '../config/ApiService.dart';

class CallOffService {
  final ApiService api = ApiService();

  Future<List<Map<String, dynamic>>> getSupervisorReports(int userId) async {
    dev.log('[CallOff] getSupervisorReports userId=$userId', name: 'CallOff');
    final response = await api.get('call-off/supervisor/$userId');
    dev.log('[CallOff] getSupervisorReports → ${response.statusCode}', name: 'CallOff');
    if (response.statusCode == 200) {
      final List data = response.body.isNotEmpty ? List.from(jsonDecode(response.body)) : [];
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load call-off reports (${response.statusCode})');
  }

  Future<List<Map<String, dynamic>>> getSiteOptions(int userId) async {
    dev.log('[CallOff] getSiteOptions userId=$userId', name: 'CallOff');
    final response = await api.get('call-off/options/$userId/sites');
    if (response.statusCode == 200) {
      final List data = response.body.isNotEmpty ? List.from(jsonDecode(response.body)) : [];
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load sites (${response.statusCode})');
  }

  Future<List<Map<String, dynamic>>> getAllGuards() async {
    dev.log('[CallOff] getAllGuards', name: 'CallOff');
    final response = await api.get('call-off/guards');
    if (response.statusCode == 200) {
      final List data = response.body.isNotEmpty ? List.from(jsonDecode(response.body)) : [];
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load guards (${response.statusCode})');
  }

  Future<List<Map<String, dynamic>>> getShiftOptions(int userId, int siteId) async {
    dev.log('[CallOff] getShiftOptions userId=$userId siteId=$siteId', name: 'CallOff');
    final response = await api.get('call-off/options/$userId/site/$siteId/shifts');
    if (response.statusCode == 200) {
      final List data = response.body.isNotEmpty ? List.from(jsonDecode(response.body)) : [];
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load shifts (${response.statusCode})');
  }

  Future<void> create(Map<String, dynamic> payload) async {
    dev.log('[CallOff] create payload: ${jsonEncode(payload)}', name: 'CallOff');
    final response = await api.post('call-off', payload);
    dev.log('[CallOff] create → ${response.statusCode}', name: 'CallOff');
    if (response.statusCode == 200) return;
    String msg = 'Failed to submit call-off report';
    try {
      final body = jsonDecode(response.body);
      if (body['error'] != null) msg = body['error'].toString();
    } catch (_) {}
    throw Exception(msg);
  }
}
