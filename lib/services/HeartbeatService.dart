import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/ApiService.dart';

class HeartbeatService {
  static final HeartbeatService _instance = HeartbeatService._internal();
  factory HeartbeatService() => _instance;
  HeartbeatService._internal();

  Timer? _timer;

  void startHeartbeat(int userId) {
    if (_timer != null) return;

    _timer = Timer.periodic(const Duration(seconds: 10), (_) async {
      await ApiService().post('heartbeat/$userId', {});
    });
  }

  void stopHeartbeat() {
    _timer?.cancel();
    _timer = null;
  }
}

