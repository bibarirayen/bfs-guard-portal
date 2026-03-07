// lib/services/BackgroundLocation_Service.dart
//
// Android: Runs in a FOREGROUND SERVICE isolate — survives background.
// iOS:     flutter_background_service cannot persist on iOS (Apple restriction).
//          On iOS we rely on the GPS stream in LiveLocationService instead.
//          This file is Android-only in practice.

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
  // flutter_background_service on iOS is unreliable for persistent background.
  // We only configure it for Android where it runs as a true foreground service.
  if (!Platform.isAndroid) return;

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
      initialNotificationContent: 'Tracking your location during shift...',
      foregroundServiceNotificationId: 888,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

// ─── Background isolate entry point ──────────────────────────────────────────
// FIX: We no longer WAIT for a 'start' event to begin the timer.
// The isolate reads userId/assignmentId directly from SharedPreferences on boot,
// eliminating the race condition where invoke('start') fired before the listener
// was registered.
@pragma('vm:entry-point')
void onBackgroundServiceStart(ServiceInstance service) async {
  Timer? locationTimer;
  int? _userId;
  int? _assignmentId;

  // ── FIX: Read credentials immediately from SharedPreferences ──────────────
  try {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getInt('active_guard_id');
    _assignmentId = prefs.getInt('active_assignment_id');

    if (_userId != null && _assignmentId != null) {
      print('🟢 [BGService] Auto-started — user $_userId assignment $_assignmentId');
      await _sendLocation(_userId!, _assignmentId!);

      locationTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
        if (_userId != null && _assignmentId != null) {
          await _sendLocation(_userId!, _assignmentId!);
        }
      });
    }
  } catch (e) {
    print('⚠️ [BGService] Failed to read prefs on start: $e');
  }

  // Still listen for explicit start commands (updates userId/assignmentId if needed)
  service.on('start').listen((data) async {
    _userId = data?['userId'] as int?;
    _assignmentId = data?['assignmentId'] as int?;
    if (_userId == null || _assignmentId == null) return;

    print('🟢 [BGService] Start event — user $_userId assignment $_assignmentId');
    await _sendLocation(_userId!, _assignmentId!);

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
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always) {
      print('⚠️ [BGService] No always permission — skipping');
      return;
    }

    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (e) {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) {
        print('⚠️ [BGService] No position available');
        return;
      }
      position = last;
      print('⚠️ [BGService] Using last known position');
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt');
    if (token == null) {
      print('⚠️ [BGService] No JWT token');
      return;
    }

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
    print('❌ [BGService] Error (will retry in 30s): $e');
  }
}

// ─── Called from LiveLocationService ─────────────────────────────────────────

Future<void> startBackgroundLocationService(int userId, int assignmentId) async {
  // iOS: do nothing — LiveLocationService GPS stream handles background on iOS.
  if (!Platform.isAndroid) return;

  try {
    // FIX: Write credentials to SharedPreferences BEFORE starting the service.
    // The isolate reads these immediately on startup — no race condition.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('active_guard_id', userId);
    await prefs.setInt('active_assignment_id', assignmentId);

    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();

    if (!isRunning) {
      await service.startService();
      // Give isolate time to boot and register listeners
      await Future.delayed(const Duration(milliseconds: 1500));
    }

    // Also send explicit start event (in case already running with old data)
    service.invoke('start', {'userId': userId, 'assignmentId': assignmentId});
    print('🟢 [BGService] Start command sent for user $userId');
  } catch (e) {
    print('❌ [BGService] Failed to start: $e');
  }
}

Future<void> stopBackgroundLocationService() async {
  if (!Platform.isAndroid) return;

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_guard_id');
    await prefs.remove('active_assignment_id');

    final service = FlutterBackgroundService();
    service.invoke('stop');
    print('🔴 [BGService] Stop command sent');
  } catch (e) {
    print('❌ [BGService] Failed to stop: $e');
  }
}
