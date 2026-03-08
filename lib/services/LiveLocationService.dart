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
import 'package:http/http.dart' as http;

import '../config/ApiService.dart';
import 'BackgroundLocation_Service.dart';

class LiveLocationService {
  static final LiveLocationService _instance = LiveLocationService._internal();
  factory LiveLocationService() => _instance;
  LiveLocationService._internal();

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

  VoidCallback? onShiftEndedRemotely;

  static const int _locationIntervalSeconds = 30;
  static const int _shiftCheckIntervalSeconds = 30;

  bool get isTracking => _isTracking;
  Position? get lastPosition => _lastPosition;
  bool get isConnected => _stompClient?.connected ?? false;

  void startTracking(int userId, int assignmentId) {
    stopTracking();

    _currentUserId = userId;
    _currentAssignmentId = assignmentId;
    _isTracking = true;

    _connectWebSocket(userId, assignmentId);
    _startLocationStream(userId, assignmentId);
    _startShiftChecker(userId, assignmentId);

    // Android only — iOS does not use background service isolate
    startBackgroundLocationService(userId, assignmentId);

    print('🚀 LiveLocationService: tracking started for user $userId assignment $assignmentId');
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

  void _connectWebSocket(int userId, int assignmentId) {
    _stompClient = StompClient(
      config: StompConfig(
        url: 'wss://api.blackfabricsecurity.com/ws',
        reconnectDelay: const Duration(seconds: 5),
        onConnect: (_) => print('✅ WebSocket connected'),
        onWebSocketError: (error) => print('❌ WebSocket error: $error'),
        onDisconnect: (_) => print('⚠️ WebSocket disconnected'),
      ),
    );
    _stompClient!.activate();
  }

  void _startLocationStream(int userId, int assignmentId) {
    final locationSettings = Platform.isIOS
        ? AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      activityType: ActivityType.otherNavigation,
      distanceFilter: 0,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
      allowBackgroundLocationUpdates: true,
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

            // NEVER call checkPermission() inside this callback.
            // iOS returns wrong values (whileInUse) during background wakeups
            // which would kill tracking. Permission is enforced in home_screen.dart.

            final now = DateTime.now();
            final secondsSinceLast = _lastSentTime == null
                ? _locationIntervalSeconds + 1
                : now.difference(_lastSentTime!).inSeconds;

            if (secondsSinceLast >= _locationIntervalSeconds) {
              await _sendLocation(userId, assignmentId);
            }

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

    // Heartbeat — sends even if device barely moves
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
        const Duration(seconds: _locationIntervalSeconds), (_) async {
      if (_isTracking && _lastPosition != null) {
        await _sendLocation(userId, assignmentId);
      }
    });

    print('📍 Location stream started for user $userId, assignment $assignmentId');
  }

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
          // Network blip — keep running
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

    try {
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
      // On any non-200 keep alive — don't stop on server errors
      return true;
    } catch (e) {
      // Network error — keep alive
      return true;
    }
  }

  Future<void> _handleRemoteShiftEnd() async {
    stopTracking();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('shift_active', false);
    await prefs.remove('active_assignment_id');
    await prefs.remove('active_guard_id');
    onShiftEndedRemotely?.call();
  }

  Future<void> _sendLocation(int userId, int assignmentId) async {
    if (!_isTracking || _lastPosition == null) return;

    _lastSentTime = DateTime.now();
    final lat = _lastPosition!.latitude;
    final lng = _lastPosition!.longitude;

    // iOS: always HTTP — WebSocket is killed by iOS in background
    if (Platform.isIOS) {
      await _sendViaHttp(userId, lat, lng);
      return;
    }

    // Android: WebSocket first, HTTP fallback
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

    print('⚠️ WS down — HTTP fallback');
    await _sendViaHttp(userId, lat, lng);

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