import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class NoticeItem {
  final int    id;
  final String title;
  final String content;
  final List<String> attachmentUrls;
  final String targetType;
  final String createdByName;
  final String createdAt;

  const NoticeItem({
    required this.id,
    required this.title,
    required this.content,
    required this.attachmentUrls,
    required this.targetType,
    required this.createdByName,
    required this.createdAt,
  });

  factory NoticeItem.fromJson(Map<String, dynamic> j) => NoticeItem(
    id:             j['id'] as int,
    title:          j['title'] as String,
    content:        j['content'] as String,
    attachmentUrls: List<String>.from(j['attachmentUrls'] ?? []),
    targetType:     j['targetType'] as String,
    createdByName:  j['createdByName'] as String? ?? '',
    createdAt:      j['createdAt'] as String? ?? '',
  );
}

class NoticeService {
  static final NoticeService _instance = NoticeService._internal();
  factory NoticeService() => _instance;
  NoticeService._internal();

  // ApiService().baseUrl is "https://api.blackfabricsecurity.com/api/" (trailing slash included)
  final String _base = "https://api.blackfabricsecurity.com/api";

  Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt') ?? '';
  }

  Future<List<NoticeItem>> getPendingNotices(int userId) async {
    try {
      final token = await _token();
      final res = await http.get(
        Uri.parse('$_base/notices/pending?userId=$userId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type':  'application/json',
        },
      );
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        return data.map((e) => NoticeItem.fromJson(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> acknowledgeNotice(int noticeId, int userId) async {
    try {
      final token = await _token();
      final res = await http.post(
        Uri.parse('$_base/notices/$noticeId/acknowledge?userId=$userId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
