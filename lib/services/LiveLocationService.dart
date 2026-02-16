// lib/services/LiveLocationService.dart - ENHANCED VERSION

import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  static const int updateIntervalSeconds = 10;   // Fixed 10-second updates as requested
  static const double movementSpeedThreshold = 1.0; // m/s (~3.6 km/h) - kept for logging

  void startTracking(int userId, int assignmentId) {
    stopTracking(); // clean restart
    _isTracking = true;

    stompClient = StompClient(
      config: StompConfig(
        url: 'wss://api.blackfabricsecurity.com/ws',
        reconnectDelay: const Duration(seconds: 5),
        onConnect: (_) {
          print('✅ WebSocket connected');
          _startLocationStream(userId, assignmentId);
        },
        onWebSocketError: (error) {
          print("❌ WebSocket error: $error");
        },
        onDisconnect: (_) {
          print('⚠️ WebSocket disconnected');
        },
      ),
    );

    stompClient!.activate();
  }

  void _startLocationStream(int userId, int assignmentId) {
    // ============================================
    // iOS-OPTIMIZED SETTINGS FOR BACKGROUND TRACKING
    // ============================================
    final locationSettings = Platform.isIOS
        ? AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      activityType: ActivityType.otherNavigation,
      distanceFilter: 3, // Update every 3 meters
      pauseLocationUpdatesAutomatically: false, // CRITICAL - never pause
      showBackgroundLocationIndicator: true, // Shows blue bar on iOS
      // iOS 14+ specific - explicitly enable background updates
      allowBackgroundLocationUpdates: true,
    )
        : const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 3,
    );

    // ============================================
    // START LOCATION STREAM WITH ERROR HANDLING
    // ============================================
    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen(
              (Position pos) {
            _lastPosition = pos;

            if (!_isTracking) return;

            final now = DateTime.now();

            // Send location every 10 seconds (fixed interval)
            if (_lastSentTime == null ||
                now.difference(_lastSentTime!).inSeconds >= updateIntervalSeconds) {
              _sendLocation(userId, assignmentId);
            }
          },
          onError: (error) {
            print("❌ Location stream error: $error");

            // Attempt to restart stream after error
            Future.delayed(const Duration(seconds: 5), () {
              if (_isTracking) {
                print('🔄 Attempting to restart location stream...');
                _positionSubscription?.cancel();
                _startLocationStream(userId, assignmentId);
              }
            });
          },
          cancelOnError: false, // Don't cancel on error, keep trying
        );

    // ============================================
    // SAFETY HEARTBEAT (every 10 seconds)
    // ============================================
    // Ensures update even if location stream pauses or fails
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: updateIntervalSeconds), (_) {
          if (_isTracking && _lastPosition != null) {
            _sendLocation(userId, assignmentId);
          } else if (_isTracking && _lastPosition == null) {
            print('⚠️ Heartbeat: No location available');
          }
        });

    print('📍 Location tracking started for user $userId, assignment $assignmentId');
  }

  void _sendLocation(int userId, int assignmentId) {
    if (!_isTracking ||
        stompClient == null ||
        !stompClient!.connected ||
        _lastPosition == null) {
      if (_isTracking && _lastPosition != null && stompClient?.connected != true) {
        print('⚠️ Cannot send location: WebSocket not connected');
      }
      return;
    }

    _lastSentTime = DateTime.now();

    final locationData = {
      "userId": userId,
      "shiftId": assignmentId,
      "lat": _lastPosition!.latitude,
      "lng": _lastPosition!.longitude,
      "speed": _lastPosition!.speed,
      "accuracy": _lastPosition!.accuracy,
      "timestamp": DateTime.now().toIso8601String(),
      "platform": Platform.isIOS ? "iOS" : "Android",
    };

    stompClient!.send(
      destination: '/app/location',
      body: jsonEncode(locationData),
    );

    print(
        "📍 Sent location: ${_lastPosition!.latitude.toStringAsFixed(6)}, "
            "${_lastPosition!.longitude.toStringAsFixed(6)} | "
            "speed: ${_lastPosition!.speed.toStringAsFixed(2)} m/s | "
            "accuracy: ${_lastPosition!.accuracy.toStringAsFixed(1)}m");
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

    print('🛑 Location tracking stopped');
  }

  // Getters for current state
  bool get isTracking => _isTracking;
  Position? get lastPosition => _lastPosition;
  bool get isConnected => stompClient?.connected ?? false;
}