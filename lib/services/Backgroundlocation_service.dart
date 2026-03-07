// lib/services/BackgroundLocationService.dart
//
// This runs in a SEPARATE Dart isolate that iOS cannot freeze.
// It handles location sending while the app is in background.
// The main isolate (LiveLocationService) handles foreground.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

// ─── Call this once from main() before runApp() ───────────────────────────────
Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    // iOS background task config
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onBackgroundServiceStart,
      onBackground: onIosBackground,
    ),
    // Android foreground service config
    androidConfiguration: AndroidConfiguration(
      autoStart: false,
      onStart: onBackgroundServiceStart,
      isForegroundMode: true,
      notificationChannelId: 'bfs_location',
      initialNotificationTitle: 'Black Fabric Security',
      initialNotificationContent: 'Location tracking active',
      foregroundServiceNotificationId: 888,
    ),
  );
}

// iOS requires this handler in the background isolate
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

// This runs in the background isolate — completely separate from Flutter UI
@pragma('vm:entry-point')
void onBackgroundServiceStart(ServiceInstance service) async {
  Timer? locationTimer;

  // Listen for start command from main isolate
  service.on('start').listen((data) async {
    final userId = data?['userId'] as int?;
    final assignmentId = data?['assignmentId'] as int?;
    if (userId == null || assignmentId == null) return;

    print('🟢 [BGService] Started for user $userId assignment $assignmentId');

    // Send location immediately, then every 30 seconds
    await _sendLocationHttp(userId, assignmentId);

    locationTimer?.cancel();
    locationTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _sendLocationHttp(userId, assignmentId);
    });
  });

  // Listen for stop command from main isolate
  service.on('stop').listen((_) {
    print('🔴 [BGService] Stopped');
    locationTimer?.cancel();
    locationTimer = null;
    service.stopSelf();
  });
}

// Gets current GPS position and POSTs it to the backend
Future<void> _sendLocationHttp(int userId, int assignmentId) async {
  try {
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always) {
      print('⚠️ [BGService] No always permission — skipping');
      return;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt');
    if (token == null) {
      print('⚠️ [BGService] No JWT token — skipping');
      return;
    }

    final response = await http.post(
      Uri.parse('https://api.blackfabricsecurity.com/api/locations/update'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'guardId': userId,
        'lat': position.latitude,
        'lng': position.longitude,
      }),
    ).timeout(const Duration(seconds: 10));

    print('📍 [BGService] Sent ${position.latitude.toStringAsFixed(6)}'
        ', ${position.longitude.toStringAsFixed(6)} → ${response.statusCode}');
  } catch (e) {
    print('❌ [BGService] Error: $e');
  }
}

// ─── Called by LiveLocationService to start/stop the background service ───────

Future<void> startBackgroundLocationService(int userId, int assignmentId) async {
  final service = FlutterBackgroundService();
  final isRunning = await service.isRunning();

  if (!isRunning) {
    await service.startService();
    // Small delay to let the isolate boot
    await Future.delayed(const Duration(milliseconds: 500));
  }

  service.invoke('start', {'userId': userId, 'assignmentId': assignmentId});
  print('🟢 [BGService] Start command sent');
}

Future<void> stopBackgroundLocationService() async {
  final service = FlutterBackgroundService();
  service.invoke('stop');
  print('🔴 [BGService] Stop command sent');
}