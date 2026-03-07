// lib/services/LiveLocationService.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';

import '../config/ApiService.dart';
import 'BackgroundLocation_Service.dart';

class LiveLocationService {
  static final LiveLocationService _instance =
  LiveLocationService._internal();

  factory LiveLocationService() => _instance;

  LiveLocationService._internal();

  // ─── Internal state ───────────────────────────────────────────────────────
  StompClient? stompClient;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _heartbeatTimer;
  Timer? _shiftCheckTimer;

  bool _isTracking = false;
  Position? _lastPosition;
  DateTime? _lastSentTime;
  DateTime? _lastShiftCheck; // throttle for piggyback check

  int? _currentUserId;
  int? _currentAssignmentId;

  /// HomeScreen sets this so it can update its UI when the service
  /// self-stops because the server said the shift ended.
  VoidCallback? onShiftEndedRemotely;

  // ─── Configuration ────────────────────────────────────────────────────────
  static const int _locationIntervalSeconds = 30;
  static const int _shiftCheckIntervalSeconds = 30;

  // ─── Public API ───────────────────────────────────────────────────────────

  bool get isTracking => _isTracking;
  Position? get lastPosition => _lastPosition;
  bool get isConnected => stompClient?.connected ?? false;

  /// Start GPS tracking + background shift watcher.
  void startTracking(int userId, int assignmentId) {
    stopTracking(); // clean restart

    _currentUserId = userId;
    _currentAssignmentId = assignmentId;
    _isTracking = true;

    _connectWebSocket(userId, assignmentId);
    _startShiftChecker(userId, assignmentId);

    // Start the background isolate — handles location when iOS freezes main isolate
    startBackgroundLocationService(userId, assignmentId);
  }

  /// Fully stop everything. Safe to call multiple times.
  void stopTracking() {
    _isTracking = false;

    _shiftCheckTimer?.cancel();
    _shiftCheckTimer = null;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _positionSubscription?.cancel();
    _positionSubscription = null;

    stompClient?.deactivate();
    stompClient = null;

    _lastPosition = null;
    _lastSentTime = null;
    _lastShiftCheck = null;
    _currentUserId = null;
    _currentAssignmentId = null;

    print('🛑 LiveLocationService: tracking fully stopped');

    // Stop the background isolate too
    stopBackgroundLocationService();
  }

  // ─── WebSocket ────────────────────────────────────────────────────────────

  void _connectWebSocket(int userId, int assignmentId) {
    stompClient = StompClient(
      config: StompConfig(
        url: 'wss://api.blackfabricsecurity.com/ws',
        reconnectDelay: const Duration(seconds: 5),
        onConnect: (_) {
          print('✅ WebSocket connected');
          _startLocationStream(userId, assignmentId);
        },
        onWebSocketError: (error) => print('❌ WebSocket error: $error'),
        onDisconnect: (_) => print('⚠️ WebSocket disconnected'),
      ),
    );
    stompClient!.activate();
  }

  // ─── Shift checker (Timer-based) ─────────────────────────────────────────
  // Runs every 30 s as long as iOS keeps this singleton alive via the
  // active location stream. Covers the normal background case.

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
          // Network blip — keep running, don't stop on transient errors
          print('⚠️ Shift timer check error (keeping alive): $e');
        }
      },
    );
  }

  // ─── Location stream ──────────────────────────────────────────────────────

  void _startLocationStream(int userId, int assignmentId) {
    final locationSettings = Platform.isIOS
        ? AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      activityType: ActivityType.otherNavigation,
      distanceFilter: 0,
      pauseLocationUpdatesAutomatically: false, // CRITICAL
      showBackgroundLocationIndicator: true,    // Blue bar on iOS
      allowBackgroundLocationUpdates: true,
    )
        : AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 3,
      intervalDuration:
      const Duration(seconds: _locationIntervalSeconds),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationText: 'Location tracking active',
        notificationTitle: 'Black Fabric Security',
        enableWakeLock: true,
      ),
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen(
              (Position pos) async {
            _lastPosition = pos;
            if (!_isTracking) return;

            // ── Permission guard (background safety net) ─────────────────────
            // Each time iOS/Android delivers a GPS fix, verify "Always" is
            // still granted. The guard may have changed it to "While In Use"
            // or "Denied" from Settings while the app was in the background.
            final LocationPermission perm = await Geolocator.checkPermission();
            if (perm != LocationPermission.always) {
              print('🔒 [Stream] "Always" permission lost — stopping tracking');
              await _handleRemoteShiftEnd();
              return;
            }
            // ────────────────────────────────────────────────────────────────

            final now = DateTime.now();

            // Send location every 30 s
            if (_lastSentTime == null ||
                now.difference(_lastSentTime!).inSeconds >=
                    _locationIntervalSeconds) {
              _sendLocation(userId, assignmentId);
            }

            // ── PIGGYBACK shift check ────────────────────────────────────────
            // Safety net for iOS suspension: every time iOS wakes the app for
            // a GPS fix we also verify the shift is still active.
            // Throttled to once per 30 s so it doesn't spam the server.
            _piggybackShiftCheck(assignmentId);
            // ────────────────────────────────────────────────────────────────
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

    // Safety heartbeat — fires even if the device barely moves
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
        const Duration(seconds: _locationIntervalSeconds), (_) {
      if (_isTracking && _lastPosition != null) {
        _sendLocation(userId, assignmentId);
      }
    });

    print(
        '📍 Location stream started for user $userId, assignment $assignmentId');
  }

  /// Called from inside the position stream callback.
  /// Throttled: actually hits the server at most once every 30 s.
  void _piggybackShiftCheck(int assignmentId) {
    final now = DateTime.now();
    if (_lastShiftCheck != null &&
        now.difference(_lastShiftCheck!).inSeconds <
            _shiftCheckIntervalSeconds) {
      return; // too soon
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

  // ─── Server call ─────────────────────────────────────────────────────────

  /// Uses the same dashboard endpoint the HomeScreen already trusts.
  /// No new backend route needed.
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
      // If the server returned a different assignment, treat as ended
      if (serverAssignmentId != null &&
          serverAssignmentId != assignmentId) {
        print(
            '⚠️ Assignment mismatch (server=$serverAssignmentId, local=$assignmentId)');
        return false;
      }
      return true;
    }

    // 401 / other error → stop tracking
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

  // ─── Send ─────────────────────────────────────────────────────────────────

  void _sendLocation(int userId, int assignmentId) {
    if (!_isTracking || _lastPosition == null) return;

    _lastSentTime = DateTime.now();

    final body = jsonEncode({
      'userId': userId,
      'shiftId': assignmentId,
      'lat': _lastPosition!.latitude,
      'lng': _lastPosition!.longitude,
      'speed': _lastPosition!.speed,
      'accuracy': _lastPosition!.accuracy,
      'timestamp': _lastSentTime!.toIso8601String(),
      'platform': Platform.isIOS ? 'iOS' : 'Android',
    });

    // Try WebSocket first (foreground fast path)
    if (stompClient != null && stompClient!.connected) {
      stompClient!.send(destination: '/app/location', body: body);
      print('📍 [WS] Sent: ${_lastPosition!.latitude.toStringAsFixed(6)}, '
          '${_lastPosition!.longitude.toStringAsFixed(6)}');
      return;
    }

    // WebSocket is dead — HTTP fallback
    print('⚠️ WS down — HTTP fallback');
    ApiService().post('locations/update', {
      'guardId': userId,
      'lat': _lastPosition!.latitude,
      'lng': _lastPosition!.longitude,
    }).timeout(const Duration(seconds: 10)).then((res) {
      print('📍 [HTTP] \${res.statusCode}');
    }).catchError((e) {
      print('❌ [HTTP] \$e');
    });

    // Try to reconnect WebSocket for next time
    Future.delayed(const Duration(seconds: 3), () {
      if (_isTracking && (stompClient == null || !stompClient!.connected)) {
        _connectWebSocket(userId, assignmentId);
      }
    });
  }
}