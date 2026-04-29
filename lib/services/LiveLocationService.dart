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

  // ─── Geofence state ───────────────────────────────────────────────────────
  // Site info loaded once when shift starts.
  double? _siteLat;
  double? _siteLng;
  double? _siteRange;       // metres, from site.range
  String? _siteName;
  bool _wasInsideGeofence = true;
  DateTime? _lastGeofenceAlert;
  // 15 metres ≈ 50 feet of GPS-drift tolerance so normal standing near the
  // boundary doesn't trigger false alerts.
  static const double _geofenceBufferMetres = 45.72; // ≈ 150 ft GPS drift buffer
  // Minimum gap between repeated alerts for the same exit event (10 min).
  static const int _geofenceAlertCooldownMinutes = 10;

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
    _wasInsideGeofence = true;
    _lastGeofenceAlert = null;

    _loadSiteInfo(assignmentId); // non-blocking — populates geofence data
    _connectWebSocket(userId, assignmentId);
    _startLocationStream(userId, assignmentId);
    _startShiftChecker(userId, assignmentId);

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

    // reset geofence
    _siteLat = null;
    _siteLng = null;
    _siteRange = null;
    _siteName = null;
    _wasInsideGeofence = true;
    _lastGeofenceAlert = null;

    stopBackgroundLocationService();
  }

  // ─── Geofence ─────────────────────────────────────────────────────────────
  /// Fetches the assignment's site info once so we know the geofence centre + radius.
  Future<void> _loadSiteInfo(int assignmentId) async {
    try {
      final api = ApiService();
      final res = await api
          .get('assignments/$assignmentId')
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final site = data['site'];
        if (site != null) {
          _siteLat   = (site['latitude']  as num?)?.toDouble();
          _siteLng   = (site['longitude'] as num?)?.toDouble();
          _siteRange = (site['range']     as num?)?.toDouble() ?? 100.0;
          _siteName  = site['name']?.toString();
        }
      }
    } catch (_) {}
  }

  /// Called on every position update. Sends a geofence-exit alert to the backend
  /// (which will push-notify the site supervisors) if the guard has just left the
  /// site geofence.  Uses _geofenceBufferMetres (≈ 150 ft) of tolerance to avoid
  /// false positives from normal GPS drift.
  Future<void> _checkGeofence(double lat, double lng) async {
    if (_siteLat == null || _siteLng == null || _siteRange == null) return;

    final distanceMetres = Geolocator.distanceBetween(lat, lng, _siteLat!, _siteLng!);
    final effectiveRadius = _siteRange! + _geofenceBufferMetres;
    final isInside = distanceMetres <= effectiveRadius;

    if (!isInside && _wasInsideGeofence) {
      // Guard just crossed the boundary — send alert (with cooldown guard).
      final now = DateTime.now();
      final sinceLastAlert = _lastGeofenceAlert == null
          ? _geofenceAlertCooldownMinutes + 1
          : now.difference(_lastGeofenceAlert!).inMinutes;

      if (sinceLastAlert >= _geofenceAlertCooldownMinutes) {
        _lastGeofenceAlert = now;
        _wasInsideGeofence = false;
        await _sendGeofenceAlert(lat, lng);
      }
    } else if (isInside && !_wasInsideGeofence) {
      // Guard came back inside — reset so next exit triggers again.
      _wasInsideGeofence = true;
    }
  }

  Future<void> _sendGeofenceAlert(double lat, double lng) async {
    if (_currentAssignmentId == null) return;
    try {
      final api = ApiService();
      await api.post('geofence/alert', {
        'assignmentId': _currentAssignmentId,
        'latitude': lat,
        'longitude': lng,
      }).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  void _connectWebSocket(int userId, int assignmentId) {
    _stompClient = StompClient(
      config: StompConfig(
        url: 'wss://api.blackfabricsecurity.com/ws',
        reconnectDelay: const Duration(seconds: 5),
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

            final now = DateTime.now();
            final secondsSinceLast = _lastSentTime == null
                ? _locationIntervalSeconds + 1
                : now.difference(_lastSentTime!).inSeconds;

            if (secondsSinceLast >= _locationIntervalSeconds) {
              await _sendLocation(userId, assignmentId);
            }

            // Check geofence on every position update (independent of send interval).
            _checkGeofence(pos.latitude, pos.longitude);

            _piggybackShiftCheck(assignmentId);
          },
          onError: (error) {
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
    _heartbeatTimer = Timer.periodic(
        const Duration(seconds: _locationIntervalSeconds), (_) async {
      if (_isTracking && _lastPosition != null) {
        await _sendLocation(userId, assignmentId);
      }
    });
  }

  void _startShiftChecker(int userId, int assignmentId) {
    _shiftCheckTimer?.cancel();
    _shiftCheckTimer = Timer.periodic(
      const Duration(seconds: _shiftCheckIntervalSeconds),
          (_) async {
        if (!_isTracking) return;
        try {
          final active = await _isShiftStillActive(assignmentId);
          if (!active) await _handleRemoteShiftEnd();
        } catch (_) {}
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
      if (!active && _isTracking) _handleRemoteShiftEnd();
    }).catchError((_) {});
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
          return false;
        }
        return true;
      }
      return true;
    } catch (_) {
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

    if (Platform.isIOS) {
      await _sendViaHttp(userId, lat, lng);
      return;
    }

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
      return;
    }

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
      if (token == null) return;

      print('🌐 [LiveLoc-POST] → api/locations/update (userId=$userId)');
      final res = await http.post(
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
      print('🌐 [LiveLoc-POST] ← ${res.statusCode} locations/update');
      if (res.statusCode == 405) {
        print('🚨 [LiveLoc-POST] 405 METHOD NOT ALLOWED — server rejected POST on locations/update!');
      }
    } catch (e) {
      print('❌ [LiveLoc-POST] error: $e');
    }
  }
}