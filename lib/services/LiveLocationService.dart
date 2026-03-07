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

class LiveLocationService {
  static final LiveLocationService _instance = LiveLocationService._internal();
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
  DateTime? _lastShiftCheck;

  // Reconnect guard — prevents spamming reconnects in background
  bool _isReconnecting = false;
  DateTime? _lastReconnectAttempt;

  int? _currentUserId;
  int? _currentAssignmentId;

  VoidCallback? onShiftEndedRemotely;

  // ─── Configuration ────────────────────────────────────────────────────────
  static const int _locationIntervalSeconds = 30;
  static const int _shiftCheckIntervalSeconds = 30;
  static const int _reconnectCooldownSeconds = 10;

  // ─── Public API ───────────────────────────────────────────────────────────
  bool get isTracking => _isTracking;
  Position? get lastPosition => _lastPosition;
  bool get isConnected => stompClient?.connected ?? false;

  void startTracking(int userId, int assignmentId) {
    stopTracking();
    _currentUserId = userId;
    _currentAssignmentId = assignmentId;
    _isTracking = true;
    _connectWebSocket(userId, assignmentId);
    _startShiftChecker(userId, assignmentId);
  }

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
    _lastReconnectAttempt = null;
    _isReconnecting = false;
    _currentUserId = null;
    _currentAssignmentId = null;
    print('🛑 LiveLocationService: tracking fully stopped');
  }

  // ─── WebSocket ────────────────────────────────────────────────────────────

  void _connectWebSocket(int userId, int assignmentId) {
    stompClient?.deactivate();
    stompClient = null;

    stompClient = StompClient(
      config: StompConfig(
        url: 'wss://api.blackfabricsecurity.com/ws-ws',
        reconnectDelay: const Duration(seconds: 5),
        onConnect: (_) {
          print('✅ WebSocket connected');
          _isReconnecting = false;
          _startLocationStream(userId, assignmentId);
        },
        onWebSocketError: (error) {
          print('❌ WebSocket error: $error');
          // Built-in stomp reconnect won't fire when Dart isolate is frozen
          // in background, so we schedule our own reconnect manually
          _scheduleReconnect(userId, assignmentId);
        },
        onDisconnect: (_) {
          print('⚠️ WebSocket disconnected');
          _scheduleReconnect(userId, assignmentId);
        },
      ),
    );
    stompClient!.activate();
  }

  /// Reconnect with cooldown. Called on WS error/disconnect AND when
  /// _sendLocation detects the socket is dead. The GPS wake-up gives us
  /// CPU time to do this even in background.
  void _scheduleReconnect(int userId, int assignmentId) {
    if (!_isTracking || _isReconnecting) return;
    final now = DateTime.now();
    if (_lastReconnectAttempt != null &&
        now.difference(_lastReconnectAttempt!).inSeconds < _reconnectCooldownSeconds) {
      return;
    }
    _isReconnecting = true;
    _lastReconnectAttempt = now;
    print('🔄 WebSocket reconnect scheduled in 5s...');
    Future.delayed(const Duration(seconds: 5), () {
      if (_isTracking) {
        print('🔄 Reconnecting WebSocket...');
        _connectWebSocket(userId, assignmentId);
      } else {
        _isReconnecting = false;
      }
    });
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

  // ─── Location stream ──────────────────────────────────────────────────────

  void _startLocationStream(int userId, int assignmentId) {
    // Cancel first to avoid duplicate streams on WS reconnect
    _positionSubscription?.cancel();
    _positionSubscription = null;

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
        notificationText: 'Location tracking active',
        notificationTitle: 'Black Fabric Security',
        enableWakeLock: true,
      ),
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
              (Position pos) async {
            _lastPosition = pos;
            if (!_isTracking) return;

            final LocationPermission perm = await Geolocator.checkPermission();
            if (perm != LocationPermission.always) {
              print('🔒 [Stream] "Always" permission lost — stopping tracking');
              await _handleRemoteShiftEnd();
              return;
            }

            final now = DateTime.now();
            if (_lastSentTime == null ||
                now.difference(_lastSentTime!).inSeconds >= _locationIntervalSeconds) {
              _sendLocation(userId, assignmentId);
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

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: _locationIntervalSeconds), (_) {
      if (_isTracking && _lastPosition != null) {
        _sendLocation(userId, assignmentId);
      }
    });

    print('📍 Location stream started for user $userId, assignment $assignmentId');
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

  // ─── Server calls ─────────────────────────────────────────────────────────

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

  // ─── Send ─────────────────────────────────────────────────────────────────

  void _sendLocation(int userId, int assignmentId) {
    if (!_isTracking || _lastPosition == null) return;

    _lastSentTime = DateTime.now();

    // ── Try WebSocket first ──────────────────────────────────────────────────
    if (stompClient != null && stompClient!.connected) {
      stompClient!.send(
        destination: '/app/location',
        body: jsonEncode({
          'userId': userId,
          'shiftId': assignmentId,
          'lat': _lastPosition!.latitude,
          'lng': _lastPosition!.longitude,
          'speed': _lastPosition!.speed,
          'accuracy': _lastPosition!.accuracy,
          'timestamp': _lastSentTime!.toIso8601String(),
          'platform': Platform.isIOS ? 'iOS' : 'Android',
        }),
      );
      print('📍 [WS] Sent: ${_lastPosition!.latitude.toStringAsFixed(6)}, '
          '${_lastPosition!.longitude.toStringAsFixed(6)}');
      return;
    }

    // ── WebSocket is dead (common in background) → HTTP fallback ────────────
    // This ensures the location reaches the server even when the socket
    // is suspended by the OS. Also triggers a reconnect for next time.
    print('⚠️ WebSocket down — sending via HTTP fallback & scheduling reconnect');
    _scheduleReconnect(userId, assignmentId);

    // POST /api/locations/update — matches existing backend endpoint exactly
    ApiService().post('locations/update', {
      'guardId': userId,
      'lat': _lastPosition!.latitude,
      'lng': _lastPosition!.longitude,
    }).timeout(const Duration(seconds: 10)).then((response) {
      if (response.statusCode == 200 || response.statusCode == 201) {
        print('📍 [HTTP] Location sent successfully');
      } else {
        print('⚠️ [HTTP] Location send failed: ${response.statusCode}');
      }
    }).catchError((e) {
      print('❌ [HTTP] Location send error: $e');
    });
  }
}