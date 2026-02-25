// file: lib/config/ApiService.dart
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

class ApiService {
  final String baseUrl = "https://api.blackfabricsecurity.com/api/";

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
    return http.get(Uri.parse("$baseUrl$endpoint"), headers: headers);
  }

  Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    final headers = await getHeaders();
    return http.post(
      Uri.parse("$baseUrl$endpoint"),
      headers: headers,
      body: jsonEncode(body),
    );
  }

  Future<http.Response> put(String endpoint, Map<String, dynamic> body) async {
    final headers = await getHeaders();
    return http.put(
      Uri.parse("$baseUrl$endpoint"),
      headers: headers,
      body: jsonEncode(body),
    );
  }

  Future<http.Response> delete(String endpoint) async {
    final headers = await getHeaders();
    return http.delete(Uri.parse("$baseUrl$endpoint"), headers: headers);
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
  Future<void> uploadReportDio(Map<String, dynamic> payload, List<File> files, Function(int, int) onProgress) async {
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

    await dio.post(
      '${baseUrl}reports/upload',
      data: formData,
      options: Options(
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
      ),
      onSendProgress: onProgress,
    );
  }

  // ─── COUNSELING UPLOAD ────────────────────────────────────────────────────
  Future<void> uploadCounselingDio(
      Map<String, dynamic> payload,
      List<File> files,
      Function(int sent, int total) onProgress,
      ) async {
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

    final response = await dio.post(
      '${baseUrl}counseling/upload',
      data: formData,
      options: Options(
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
        contentType: 'multipart/form-data',
      ),
      onSendProgress: onProgress,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Upload failed: ${response.statusCode}');
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