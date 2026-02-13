import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class ApiService {
  final String baseUrl = "https://api.blackfabricsecurity.com/api/";

  Future<Map<String, String>> getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('jwt');

    return {
      "Content-Type": "application/json",
      if (token != null) "Authorization": "Bearer $token", // 🔑 add JWT
    };
  }

  Future<http.Response> get(String endpoint) async {
    final headers = await getHeaders();
    print("$baseUrl$endpoint");
    return await http.get(Uri.parse("$baseUrl$endpoint"), headers: headers);
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
