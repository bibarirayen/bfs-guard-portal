import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';

class LiveLocationService {
  static final LiveLocationService _instance =
  LiveLocationService._internal();

  factory LiveLocationService() => _instance;

  LiveLocationService._internal();

  StompClient? stompClient;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _heartbeatTimer;

  bool _isTracking = false;

  Position? _lastPosition;
  DateTime? _lastSentTime;

  /// CONFIGURATION (you can tune these)
  static const int movingIntervalSeconds = 10;   // while moving
  static const int idleIntervalSeconds = 40;     // heartbeat while idle
  static const double movementSpeedThreshold = 1.0; // m/s (~3.6 km/h)

  void startTracking(int userId, int assignmentId) {
    stopTracking(); // clean restart
    _isTracking = true;

    stompClient = StompClient(
      config: StompConfig(
        url: 'wss://api.blackfabricsecurity.com/ws',
        reconnectDelay: const Duration(seconds: 5),
        onConnect: (_) {
          _startLocationStream(userId, assignmentId);
        },
        onWebSocketError: (error) {
          print("❌ WebSocket error: $error");
        },
      ),
    );

    stompClient!.activate();
  }

  void _startLocationStream(int userId, int assignmentId) {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 3, // movement sensitivity
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((Position pos) {
          _lastPosition = pos;

          if (!_isTracking) return;

          final now = DateTime.now();

          final bool isMoving =
              (pos.speed) > movementSpeedThreshold;

          final int requiredInterval =
          isMoving ? movingIntervalSeconds : idleIntervalSeconds;

          if (_lastSentTime == null ||
              now.difference(_lastSentTime!).inSeconds >= requiredInterval) {
            _sendLocation(userId, assignmentId);
          }
        });

    // ❤️ Safety heartbeat (ensures update even if speed detection fails)
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: idleIntervalSeconds), (_) {
          if (_isTracking && _lastPosition != null) {
            _sendLocation(userId, assignmentId);
          }
        });
  }

  void _sendLocation(int userId, int assignmentId) {
    if (!_isTracking ||
        stompClient == null ||
        !stompClient!.connected ||
        _lastPosition == null) {
      return;
    }

    _lastSentTime = DateTime.now();

    stompClient!.send(
      destination: '/app/location',
      body: jsonEncode({
        "userId": userId,
        "shiftId": assignmentId,
        "lat": _lastPosition!.latitude,
        "lng": _lastPosition!.longitude,
        "speed": _lastPosition!.speed,
        "accuracy": _lastPosition!.accuracy,
        "timestamp": DateTime.now().toIso8601String(),
      }),
    );

    print(
        "📍 Sent ${_lastPosition!.latitude}, ${_lastPosition!.longitude} | speed: ${_lastPosition!.speed}");
  }

  void stopTracking() {
    _isTracking = false;

    _positionSubscription?.cancel();
    _positionSubscription = null;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    stompClient?.deactivate();
    stompClient = null;

    _lastPosition = null;
    _lastSentTime = null;
  }
}
