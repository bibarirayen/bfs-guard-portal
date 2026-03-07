// lib/services/BackgroundLocation_Service.dart
//
// Runs in a SEPARATE Dart isolate — iOS cannot freeze this.
// Sends location via HTTP every 30s independently of the main UI isolate.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

const String _baseUrl = 'https://api.blackfabricsecurity.com/api/';

// ─── Call once from main() before runApp() ────────────────────────────────────
Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onBackgroundServiceStart,
      onBackground: onIosBackground,
    ),
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

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

// ─── Background isolate entry point ──────────────────────────────────────────
@pragma('vm:entry-point')
void onBackgroundServiceStart(ServiceInstance service) async {
  Timer? locationTimer;
  int? _userId;
  int? _assignmentId;

  service.on('start').listen((data) async {
    _userId = data?['userId'] as int?;
    _assignmentId = data?['assignmentId'] as int?;
    if (_userId == null || _assignmentId == null) return;

    print('🟢 [BGService] Started — user $_userId assignment $_assignmentId');

    // Send immediately on start
    await _sendLocation(_userId!, _assignmentId!);

    // Then every 30 seconds
    locationTimer?.cancel();
    locationTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_userId != null && _assignmentId != null) {
        await _sendLocation(_userId!, _assignmentId!);
      }
    });
  });

  service.on('stop').listen((_) {
    print('🔴 [BGService] Stopped');
    locationTimer?.cancel();
    locationTimer = null;
    _userId = null;
    _assignmentId = null;
    service.stopSelf();
  });
}

// ─── Get GPS and POST to backend ─────────────────────────────────────────────
Future<void> _sendLocation(int userId, int assignmentId) async {
  try {
    // Check permission
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always) {
      print('⚠️ [BGService] No always permission');
      return;
    }

    // Get current position with timeout
    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (e) {
      // If getCurrentPosition times out, try last known position
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) {
        print('⚠️ [BGService] No position available');
        return;
      }
      position = last;
      print('⚠️ [BGService] Using last known position');
    }

    // Get JWT token
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt');
    if (token == null) {
      print('⚠️ [BGService] No JWT token');
      return;
    }

    // POST location to backend — saves to both current location + history table
    final response = await http.post(
      Uri.parse('${_baseUrl}locations/update'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'guardId': userId,
        'lat': position.latitude,
        'lng': position.longitude,
      }),
    ).timeout(const Duration(seconds: 15));

    print('📍 [BGService] ${position.latitude.toStringAsFixed(6)}, '
        '${position.longitude.toStringAsFixed(6)} → HTTP ${response.statusCode}');

  } catch (e) {
    // Never crash the background isolate — just log and continue
    print('❌ [BGService] Error (will retry in 30s): $e');
  }
}

// ─── Called from LiveLocationService ─────────────────────────────────────────

Future<void> startBackgroundLocationService(int userId, int assignmentId) async {
  try {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
      await Future.delayed(const Duration(milliseconds: 800));
    }
    service.invoke('start', {'userId': userId, 'assignmentId': assignmentId});
    print('🟢 [BGService] Start command sent');
  } catch (e) {
    print('❌ [BGService] Failed to start: $e');
  }
}

Future<void> stopBackgroundLocationService() async {
  try {
    final service = FlutterBackgroundService();
    service.invoke('stop');
    print('🔴 [BGService] Stop command sent');
  } catch (e) {
    print('❌ [BGService] Failed to stop: $e');
  }
}