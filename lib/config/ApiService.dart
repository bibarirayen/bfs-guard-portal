import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart'; // ✅ for MediaType

class ApiService {
  final String baseUrl = "https://api.blackfabricsecurity.com/api/";

  Future<Map<String, String>> getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('jwt');

    return {
      "Content-Type": "application/json",
      if (token != null) "Authorization": "Bearer $token",
    };
  }

  Future<http.Response> get(String endpoint) async {
    final headers = await getHeaders();
    print("$baseUrl$endpoint");
    return await http.get(Uri.parse("$baseUrl$endpoint"), headers: headers);
  }

  // ✅ Returns the correct MediaType for a file based on its extension.
  // Without this, Multer on the backend gets no content-type and rejects the file.
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

  Future<void> uploadReportDio(
      Map<String, dynamic> payload,
      List<File> files,
      Function(int sent, int total) onProgress,
      ) async {
    final prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('jwt');

    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 30);
    dio.options.sendTimeout = const Duration(minutes: 30);
    // ✅ Receive timeout bumped — server needs time to process + respond after upload
    dio.options.receiveTimeout = const Duration(minutes: 10);

    final formData = FormData();
    formData.fields.add(MapEntry('payload', jsonEncode(payload)));

    for (final file in files) {
      final filename = file.path.split('/').last;
      final mediaType = _mediaTypeForFile(file.path); // ✅ explicit MIME type

      formData.files.add(MapEntry(
        'files',
        await MultipartFile.fromFile(
          file.path,
          filename: filename,
          contentType: mediaType, // ✅ this is what fixes the 3% error
        ),
      ));
    }

    final response = await dio.post(
      '${baseUrl}reports/upload',
      data: formData,
      options: Options(
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
        // ✅ Tell server what we're sending
        contentType: 'multipart/form-data',
      ),
      onSendProgress: onProgress,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Upload failed: ${response.statusCode}');
    }
  }
  Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    final headers = await getHeaders();
    return await http.post(
      Uri.parse("$baseUrl$endpoint"),
      headers: headers,
      body: jsonEncode(body),
    );
  }
  Future<http.StreamedResponse> uploadReport(
      Map<String, dynamic> payload,
      List<File> files, // can be images or videos
      ) async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('jwt');

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('${baseUrl}reports/upload'),
    );

    // Add JWT header
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    // Send payload as JSON string
    request.fields['payload'] = jsonEncode(payload);

    // Send all files under the name "files" to match backend
    for (var file in files) {
      request.files.add(await http.MultipartFile.fromPath('files', file.path));
    }

    // Send request
    return await request.send();
  }

  Future<void> updateFcmToken(int userId, String fcmToken) async {
    await put(
      "users/$userId/fcm-token",
      {"fcmToken": fcmToken},
    );
  }
  Future<http.StreamedResponse> uploadMultipart(
      String endpoint,
      Map<String, dynamic> payload,
      List<File> files,
      {String fileFieldName = 'files'}) async {

    final headersMap = await getHeaders();
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl$endpoint'),
    );

    // Add JWT header
    if (headersMap.containsKey('Authorization')) {
      request.headers['Authorization'] = headersMap['Authorization']!;
    }

    // Add payload as JSON string
    request.fields['payload'] = jsonEncode(payload);

    // Add files
    for (var f in files) {
      request.files.add(await http.MultipartFile.fromPath(fileFieldName, f.path));
    }

    return await request.send();
  }

  Future<http.Response> put(String endpoint, Map<String, dynamic> body) async {
    final headers = await getHeaders();
    return await http.put(
      Uri.parse("$baseUrl$endpoint"),
      headers: headers,
      body: jsonEncode(body),
    );
  }

  Future<http.Response> delete(String endpoint) async {
    final headers = await getHeaders();
    return await http.delete(Uri.parse("$baseUrl$endpoint"), headers: headers);
  }
}