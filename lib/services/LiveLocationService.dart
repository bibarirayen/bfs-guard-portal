// lib/services/LiveLocationService.dart
//
// Strategy:
//  Android → foreground service in BackgroundLocation_Service.dart handles HTTP.
//            This class runs the GPS stream + WebSocket in foreground.
//  iOS     → The GPS stream (with allowBackgroundLocationUpdates: true) is the
//            ONLY reliable background wakeup Apple allows without special
//            entitlements. Each GPS fix wakes the main isolate briefly — we use
//            that window to fire an HTTP POST directly (WS is dead in background).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'package:http/http.dart' as http;

import '../config/ApiService.dart';
import 'BackgroundLocation_Service.dart';

class LiveLocationService {
  static final LiveLocationService _instance = LiveLocationService._internal();
  factory LiveLocationService() => _instance;
  LiveLocationService._internal();

  // ─── Internal state ───────────────────────────────────────────────────────
  StompClient? _stompClient;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _heartbeatTimer;
  Timer? _shiftCheckTimer;

  bool _isTracking = false;
  Position? _lastPosition;
  DateTime? _lastSentTime;
  DateTime? _lastShiftCheck;

  int? _currentUserId;
  int? _currentAssignmentId;

  /// HomeScreen sets this to update UI when shift ends remotely.
  VoidCallback? onShiftEndedRemotely;

  // ─── Configuration ────────────────────────────────────────────────────────
  static const int _locationIntervalSeconds = 30;
  static const int _shiftCheckIntervalSeconds = 30;

  // ─── Public API ───────────────────────────────────────────────────────────
  bool get isTracking => _isTracking;
  Position? get lastPosition => _lastPosition;
  bool get isConnected => _stompClient?.connected ?? false;

  void startTracking(int userId, int assignmentId) {
    stopTracking(); // clean restart

    _currentUserId = userId;
    _currentAssignmentId = assignmentId;
    _isTracking = true;

    // Connect WebSocket (foreground fast path)
    _connectWebSocket(userId, assignmentId);

    // Start the GPS stream — this is the backbone for BOTH platforms.
    // On iOS: each fix wakes the main isolate; we send HTTP from here in bg.
    // On Android: the foreground service handles bg HTTP independently.
    _startLocationStream(userId, assignmentId);

    // Shift checker timer (belt-and-suspenders)
    _startShiftChecker(userId, assignmentId);

    // Android only: start foreground service isolate
    startBackgroundLocationService(userId, assignmentId);
  }

  void stopTracking() {
    _isTracking = false;

    _shiftCheckTimer?.cancel();
    _shiftCheckTimer = null;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _positionSubscription?.cancel();
    _positionSubscription = null;

    _stompClient?.deactivate();
    _stompClient = null;

    _lastPosition = null;
    _lastSentTime = null;
    _lastShiftCheck = null;
    _currentUserId = null;
    _currentAssignmentId = null;

    print('🛑 LiveLocationService: tracking fully stopped');

    stopBackgroundLocationService();
  }

  // ─── WebSocket ────────────────────────────────────────────────────────────

  void _connectWebSocket(int userId, int assignmentId) {
    _stompClient = StompClient(
      config: StompConfig(
        url: 'wss://api.blackfabricsecurity.com/ws',
        reconnectDelay: const Duration(seconds: 5),
        onConnect: (_) {
          print('✅ WebSocket connected');
        },
        onWebSocketError: (error) => print('❌ WebSocket error: $error'),
        onDisconnect: (_) => print('⚠️ WebSocket disconnected'),
      ),
    );
    _stompClient!.activate();
  }

  // ─── GPS Stream ───────────────────────────────────────────────────────────
  // Started immediately (not inside onConnect) so iOS gets GPS fixes
  // even if the WebSocket hasn't connected yet.

  void _startLocationStream(int userId, int assignmentId) {
    final locationSettings = Platform.isIOS
        ? AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      activityType: ActivityType.otherNavigation,
      distanceFilter: 0,
      pauseLocationUpdatesAutomatically: false, // CRITICAL — never pause
      showBackgroundLocationIndicator: true,    // blue status bar on iOS
      allowBackgroundLocationUpdates: true,     // CRITICAL — bg wakeups
    )
        : AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 3,
      intervalDuration: const Duration(seconds: _locationIntervalSeconds),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationText: 'Tracking your location during shift',
        notificationTitle: 'Black Fabric Security',
        enableWakeLock: true,
      ),
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
              (Position pos) async {
            _lastPosition = pos;
            if (!_isTracking) return;

            // ── Permission safety net ────────────────────────────────────────────
            final LocationPermission perm = await Geolocator.checkPermission();
            if (perm != LocationPermission.always) {
              print('🔒 [Stream] "Always" permission lost — stopping tracking');
              await _handleRemoteShiftEnd();
              return;
            }

            final now = DateTime.now();
            final secondsSinceLast = _lastSentTime == null
                ? _locationIntervalSeconds + 1
                : now.difference(_lastSentTime!).inSeconds;

            if (secondsSinceLast >= _locationIntervalSeconds) {
              await _sendLocation(userId, assignmentId);
            }

            // Piggyback shift check (throttled)
            _piggybackShiftCheck(assignmentId);
          },
          onError: (error) {
            print('❌ Location stream error: $error');
            Future.delayed(const Duration(seconds: 5), () {
              if (_isTracking) {
                _positionSubscription?.cancel();
                _startLocationStream(userId, assignmentId);
              }
            });
          },
          cancelOnError: false,
        );

    // Heartbeat timer — fires even if device barely moves (on Android in foreground)
    // On iOS this is mostly redundant since the stream fires continuously, but
    // it adds a safety net for edge cases.
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
        const Duration(seconds: _locationIntervalSeconds), (_) async {
      if (_isTracking && _lastPosition != null) {
        await _sendLocation(userId, assignmentId);
      }
    });

    print('📍 Location stream started for user $userId, assignment $assignmentId');
  }

  // ─── Shift checker ────────────────────────────────────────────────────────

  void _startShiftChecker(int userId, int assignmentId) {
    _shiftCheckTimer?.cancel();
    _shiftCheckTimer = Timer.periodic(
      const Duration(seconds: _shiftCheckIntervalSeconds),
          (_) async {
        if (!_isTracking) return;
        try {
          final active = await _isShiftStillActive(assignmentId);
          if (!active) {
            print('🛑 [Timer] Shift ended → stopping tracking');
            await _handleRemoteShiftEnd();
          }
        } catch (e) {
          print('⚠️ Shift timer check error (keeping alive): $e');
        }
      },
    );
  }

  void _piggybackShiftCheck(int assignmentId) {
    final now = DateTime.now();
    if (_lastShiftCheck != null &&
        now.difference(_lastShiftCheck!).inSeconds < _shiftCheckIntervalSeconds) {
      return;
    }
    _lastShiftCheck = now;

    _isShiftStillActive(assignmentId).then((active) {
      if (!active && _isTracking) {
        print('🛑 [Piggyback] Shift ended → stopping tracking');
        _handleRemoteShiftEnd();
      }
    }).catchError((e) {
      print('⚠️ Piggyback shift check error: $e');
    });
  }

  Future<bool> _isShiftStillActive(int assignmentId) async {
    final api = ApiService();
    final prefs = await SharedPreferences.getInstance();
    final guardId = prefs.getInt('userId');
    if (guardId == null) return false;

    final response = await api
        .get('assignments/dashboard-mobile/$guardId')
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final bool active = data['Active'] == true;
      final int? serverAssignmentId = data['assignmentId'] as int?;

      if (!active) return false;
      if (serverAssignmentId != null && serverAssignmentId != assignmentId) {
        print('⚠️ Assignment mismatch (server=$serverAssignmentId, local=$assignmentId)');
        return false;
      }
      return true;
    }

    print('⚠️ Dashboard returned ${response.statusCode} → stopping');
    return false;
  }

  Future<void> _handleRemoteShiftEnd() async {
    stopTracking();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('shift_active', false);
    await prefs.remove('active_assignment_id');
    await prefs.remove('active_guard_id');
    onShiftEndedRemotely?.call();
  }

  // ─── Send location ────────────────────────────────────────────────────────
  // FIX: Made async so iOS can await the HTTP call inside the GPS stream callback.
  // FIX: Fixed Dart string interpolation bug (was \\${ instead of ${}).
  // FIX: iOS always uses HTTP (WebSocket is killed by iOS in background).
  //      Android tries WebSocket first, falls back to HTTP.

  Future<void> _sendLocation(int userId, int assignmentId) async {
    if (!_isTracking || _lastPosition == null) return;

    _lastSentTime = DateTime.now();

    final lat = _lastPosition!.latitude;
    final lng = _lastPosition!.longitude;

    // ── iOS: always HTTP — WebSocket is unreliable in background on iOS ──────
    if (Platform.isIOS) {
      await _sendViaHttp(userId, lat, lng);
      return;
    }

    // ── Android: try WebSocket first (lower latency in foreground) ───────────
    final wsBody = jsonEncode({
      'userId': userId,
      'shiftId': assignmentId,
      'lat': lat,
      'lng': lng,
      'speed': _lastPosition!.speed,
      'accuracy': _lastPosition!.accuracy,
      'timestamp': _lastSentTime!.toIso8601String(),
      'platform': 'Android',
    });

    if (_stompClient != null && _stompClient!.connected) {
      _stompClient!.send(destination: '/app/location', body: wsBody);
      print('📍 [WS] Sent: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}');
      return;
    }

    // WebSocket is down — use HTTP fallback and reconnect
    print('⚠️ WS down — HTTP fallback');
    await _sendViaHttp(userId, lat, lng);

    // Try to reconnect WebSocket for next send
    Future.delayed(const Duration(seconds: 3), () {
      if (_isTracking && (_stompClient == null || !_stompClient!.connected)) {
        _connectWebSocket(userId, assignmentId);
      }
    });
  }

  Future<void> _sendViaHttp(int userId, double lat, double lng) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt');
      if (token == null) {
        print('⚠️ [HTTP] No JWT token');
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
          'lat': lat,
          'lng': lng,
        }),
      ).timeout(const Duration(seconds: 10));

      print('📍 [HTTP] ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)} → ${response.statusCode}');
    } catch (e) {
      print('❌ [HTTP] Error: $e');
    }
  }
}
