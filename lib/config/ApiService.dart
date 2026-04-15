// file: lib/config/ApiService.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'app_globals.dart';
import '../services/HeartbeatService.dart';
import '../screens/login_screen.dart';

class ApiService {
  final String baseUrl = "https://api.blackfabricsecurity.com/api/";

  // ─── SESSION EXPIRY ───────────────────────────────────────────────────────
  // Triggered automatically when the server returns 401 or 403.
  // Clears the session, stops background services, and routes back to login.
  Future<void> _handleSessionExpiry() async {
    final prefs         = await SharedPreferences.getInstance();
    final savedEmail    = prefs.getString('saved_email');
    final savedPassword = prefs.getString('saved_password');
    final rememberMe    = prefs.getBool('remember_me') ?? false;
    await prefs.clear();
    if (rememberMe && savedEmail != null && savedPassword != null) {
      await prefs.setString('saved_email',    savedEmail);
      await prefs.setString('saved_password', savedPassword);
      await prefs.setBool('remember_me',      true);
    }
    HeartbeatService().stopHeartbeat();
    pendingSessionExpiredMessage = true;
    final builder = loginScreenBuilder;
    if (builder != null) {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: builder),
        (route) => false,
      );
    }
  }

  // ─── FRIENDLY ERROR MESSAGES ──────────────────────────────────────────────
  // Converts raw technical errors into plain-language messages for guards.
  static String friendlyError(dynamic error, {int? statusCode}) {
    final code = statusCode;
    if (code == 500 || code == 502 || code == 503) {
      return 'The server is having issues right now. Please try again in a few minutes.';
    }
    if (code == 404) {
      return 'The information was not found. Make sure your shift is active and try again.';
    }
    final str = error.toString().toLowerCase();
    if (str.contains('status:500') || str.contains('status:502') || str.contains('status:503')) {
      return 'The server is having issues right now. Please try again in a few minutes.';
    }
    if (str.contains('socketexception') ||
        str.contains('failed host lookup') ||
        str.contains('no address associated') ||
        str.contains('network is unreachable') ||
        str.contains('connection refused')) {
      return 'No internet connection. Please check your Wi-Fi or mobile data and try again.';
    }
    if (str.contains('timeout') || str.contains('timed out')) {
      return 'The request took too long. Check your connection and try again.';
    }
    if (str.contains('cancel')) {
      return 'Upload cancelled.';
    }
    return 'Something went wrong. Please try again or contact your supervisor.';
  }

  Future<Map<String, String>> getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('jwt');
    return {
      "Content-Type": "application/json",
      if (token != null) "Authorization": "Bearer $token",
    };
  }

  Future<http.Response> get(String endpoint) async {
    final headers = await getHeaders();
    final response = await http.get(Uri.parse("$baseUrl$endpoint"), headers: headers);
    if (response.statusCode == 401 || response.statusCode == 403) {
      await _handleSessionExpiry();
    }
    return response;
  }

  Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    final headers = await getHeaders();
    final response = await http.post(
      Uri.parse("$baseUrl$endpoint"),
      headers: headers,
      body: jsonEncode(body),
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      await _handleSessionExpiry();
    }
    return response;
  }

  Future<http.Response> put(String endpoint, Map<String, dynamic> body) async {
    final headers = await getHeaders();
    final response = await http.put(
      Uri.parse("$baseUrl$endpoint"),
      headers: headers,
      body: jsonEncode(body),
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      await _handleSessionExpiry();
    }
    return response;
  }

  Future<http.Response> delete(String endpoint) async {
    final headers = await getHeaders();
    final response = await http.delete(Uri.parse("$baseUrl$endpoint"), headers: headers);
    if (response.statusCode == 401 || response.statusCode == 403) {
      await _handleSessionExpiry();
    }
    return response;
  }

  // ─── MIME TYPE HELPER ─────────────────────────────────────────────────────
  MediaType _mediaTypeForFile(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4':  return MediaType('video', 'mp4');
      case 'mov':  return MediaType('video', 'quicktime');
      case 'avi':  return MediaType('video', 'x-msvideo');
      case 'mkv':  return MediaType('video', 'x-matroska');
      case 'jpg':
      case 'jpeg': return MediaType('image', 'jpeg');
      case 'png':  return MediaType('image', 'png');
      case 'heic': return MediaType('image', 'heic');
      case 'webp': return MediaType('image', 'webp');
      default:     return MediaType('application', 'octet-stream');
    }
  }

  // ─── REPORT UPLOAD ────────────────────────────────────────────────────────
  // Sends the report payload + all media files (already compressed by report_page.dart)
  // in a single multipart request. Server saves files, stores report, fires email.
  // Progress callback drives the real upload progress bar on the Submit button.
  Future<void> uploadReportDio(Map<String, dynamic> payload, List<File> files, Function(int, int) onProgress, {CancelToken? cancelToken}) async {
    final prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('jwt');
    print("JWT TOKEN: $token");
    final dio = Dio();
    // Long timeouts for large video uploads — prevents timeout on slow connections
    dio.options.connectTimeout = const Duration(seconds: 60);
    dio.options.sendTimeout    = const Duration(minutes: 60);
    dio.options.receiveTimeout = const Duration(minutes: 10);

    final formData = FormData();

    // Add JSON payload
    formData.fields.add(
      MapEntry('payload', jsonEncode(payload)),
    );

    // Add files with correct MIME types
    for (final f in files) {
      final filename  = f.path.split('/').last;
      final mediaType = _mediaTypeForFile(f.path);
      formData.files.add(MapEntry(
        'files',
        await MultipartFile.fromFile(f.path, filename: filename, contentType: mediaType),
      ));
    }

    try {
      await dio.post(
        '${baseUrl}reports/upload',
        data: formData,
        cancelToken: cancelToken,
        options: Options(
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ),
        onSendProgress: onProgress,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        await _handleSessionExpiry();
        return;
      }
      rethrow;
    }
  }

  // ─── COUNSELING UPLOAD ────────────────────────────────────────────────────
  Future<void> uploadCounselingDio(
      Map<String, dynamic> payload,
      List<File> files,
      Function(int sent, int total) onProgress, {
        CancelToken? cancelToken,
      }) async {
    final prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('jwt');

    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 60);
    dio.options.sendTimeout    = const Duration(minutes: 60);
    dio.options.receiveTimeout = const Duration(minutes: 10);

    final formData = FormData();
    formData.fields.add(MapEntry('payload', jsonEncode(payload)));

    for (final file in files) {
      final filename  = file.path.split('/').last;
      final mediaType = _mediaTypeForFile(file.path);
      formData.files.add(MapEntry(
        'files',
        await MultipartFile.fromFile(file.path, filename: filename, contentType: mediaType),
      ));
    }

    try {
      final response = await dio.post(
        '${baseUrl}counseling/upload',
        data: formData,
        cancelToken: cancelToken,
        options: Options(
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
          contentType: 'multipart/form-data',
        ),
        onSendProgress: onProgress,
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Upload failed: ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        await _handleSessionExpiry();
        return;
      }
      rethrow;
    }
  }

  // ─── GENERIC MULTIPART ────────────────────────────────────────────────────
  Future<http.StreamedResponse> uploadMultipart(
      String endpoint,
      Map<String, dynamic> payload,
      List<File> files, {
        String fileFieldName = 'files',
      }) async {
    final headersMap = await getHeaders();
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl$endpoint'));
    if (headersMap.containsKey('Authorization')) {
      request.headers['Authorization'] = headersMap['Authorization']!;
    }
    request.fields['payload'] = jsonEncode(payload);
    for (var f in files) {
      request.files.add(await http.MultipartFile.fromPath(fileFieldName, f.path));
    }
    return request.send();
  }

  // ─── MISC ─────────────────────────────────────────────────────────────────
  Future<void> updateFcmToken(int userId, String fcmToken) async {
    await put("users/$userId/fcm-token", {"fcmToken": fcmToken});
  }
}