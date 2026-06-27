import 'dart:io';
import 'dart:convert';
import 'package:crossplatformblackfabric/screens/conversation_screen.dart';
import 'package:crossplatformblackfabric/screens/executive_notice_screen.dart';
import 'package:crossplatformblackfabric/screens/guard_schedule_page.dart';
import 'package:crossplatformblackfabric/screens/late_arrivals_page.dart';
import 'package:crossplatformblackfabric/screens/vacation_request_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_globals.dart'; // imports navigatorKey
import 'notice_service.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

bool _isAssignmentType(String? type) {
  if (type == null) return false;
  final normalized = type.toUpperCase();
  return normalized == 'ASSIGNMENT_ASSIGNED' || normalized == 'NEW_ASSIGNMENT';
}

int? _parseAssignmentId(Map<String, dynamic> data) {
  final raw = data['assignmentId'];
  if (raw == null) return null;
  return int.tryParse(raw.toString());
}

Map<String, dynamic> _safeJsonMap(String? raw) {
  if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {}
  return <String, dynamic>{};
}

void _openAssignmentSchedule({int? assignmentId}) {
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => GuardSchedulePage(initialAssignmentId: assignmentId),
    ),
  );
}

void _handleTapByType({
  String? type,
  String? title,
  Map<String, dynamic>? data,
}) {
  final normalizedType  = (type ?? '').toUpperCase();
  final normalizedTitle = (title ?? '').toUpperCase();

  // Tapping an executive notice banner opens the gate screen
  if (normalizedType == 'EXECUTIVE_NOTICE') {
    _handleExecutiveNotice();
    return;
  }

  if (normalizedType == 'LATE_GUARD' || normalizedType == 'LATE') {
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const LateArrivalsPage()),
    );
    return;
  }

  if (normalizedType == 'CHAT') {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => const ConversationsScreen(standalone: true),
      ),
    );
    return;
  }

  if (normalizedType == 'VACATION_ACCEPTED' || normalizedType == 'VACATION_REFUSED') {
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const VacationRequestPage()),
    );
    return;
  }

  if (_isAssignmentType(normalizedType) || normalizedTitle.contains('NEW ASSIGNMENT')) {
    _openAssignmentSchedule(assignmentId: _parseAssignmentId(data ?? const <String, dynamic>{}));
  }
}

// Triggered when an EXECUTIVE_NOTICE FCM message arrives while the app is open.
// Fetches all pending notices and pushes the gate screen on top immediately.
Future<void> _handleExecutiveNotice() async {
  final prefs  = await SharedPreferences.getInstance();
  final userId = prefs.getInt('userId');
  if (userId == null) return; // guard not logged in — nothing to do

  final notices = await NoticeService().getPendingNotices(userId);
  if (notices.isEmpty) return;

  final ctx = navigatorKey.currentContext;
  if (ctx == null) return;

  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => ExecutiveNoticeScreen(
        notices:     notices,
        userId:      userId,
        destination: null, // pop back to wherever the guard was
      ),
    ),
  );
}

// Background message handler
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('📩 Background message: ${message.notification?.title}');
}

Future<void> setupFlutterNotifications() async {
  print('🔧 [NOTIFICATIONS] Starting setup...');

  // Android setup
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'Used for important notifications',
    importance: Importance.high,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // iOS setup
  const DarwinInitializationSettings initializationSettingsDarwin =
  DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  // Initialize plugin
  const InitializationSettings initializationSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: initializationSettingsDarwin,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    // ✅ When user taps a local notification (foreground), navigate if it's a late alert
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      print('📱 [NOTIFICATIONS] Tapped: ${response.payload}');
      final payload = _safeJsonMap(response.payload);
      _handleTapByType(
        type: (payload['type'] ?? '').toString(),
        title: (payload['title'] ?? '').toString(),
        data: payload,
      );
    },
  );

  // iOS specific setup
  if (Platform.isIOS) {
    print('📱 [NOTIFICATIONS] iOS detected - requesting permissions...');

    // Request local notification permissions
    final bool? result = await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    print('📱 [NOTIFICATIONS] iOS Local Permission Result: $result');

    // Set foreground notification options
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    print('✅ [NOTIFICATIONS] iOS foreground options set');
  }

  // Background message handler
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('📬 [NOTIFICATIONS] Foreground message: ${message.notification?.title}');

    // Executive notices: block the screen immediately instead of showing a banner
    if ((message.data['type'] ?? '').toString().toUpperCase() == 'EXECUTIVE_NOTICE') {
      _handleExecutiveNotice();
      return;
    }

    RemoteNotification? notification = message.notification;
    if (notification != null) {
      // Only manually show notifications on Android
      if (Platform.isAndroid) {
        // ✅ Pass the message type as payload so tap handler knows where to go
        final payload = jsonEncode({
          'type': message.data['type'] ?? '',
          'assignmentId': message.data['assignmentId'] ?? '',
          'title': notification.title ?? '',
        });
        flutterLocalNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              icon: '@mipmap/ic_launcher',
            ),
          ),
          payload: payload,
        );
      }
      // iOS: handled automatically via setForegroundNotificationPresentationOptions
    }
  });

  // ✅ Handle notification tap when app is in background (not terminated)
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('📱 [NOTIFICATIONS] App opened from notification');
    _handleTapByType(
      type: (message.data['type'] ?? '').toString(),
      title: message.notification?.title,
      data: message.data,
    );
  });

  // ✅ Handle notification tap when app was fully terminated
  RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    print('📱 [NOTIFICATIONS] App launched from notification');
    // Delay slightly to ensure navigator is ready after app startup.
    Future.delayed(const Duration(seconds: 1), () {
      _handleTapByType(
        type: (initialMessage.data['type'] ?? '').toString(),
        title: initialMessage.notification?.title,
        data: initialMessage.data,
      );
    });
  }

  // Get FCM token
  print('🔑 [NOTIFICATIONS] Attempting to get FCM token...');
  try {
    String? token = await FirebaseMessaging.instance.getToken();

    if (token != null) {
      print('✅ [NOTIFICATIONS] FCM Token obtained successfully!');
      print('📱 [NOTIFICATIONS] Token: $token');
      print('📱 [NOTIFICATIONS] Token length: ${token.length}');
    } else {
      print('❌ [NOTIFICATIONS] FCM Token is NULL!');
      print('❌ [NOTIFICATIONS] Possible causes:');
      print('   1. APNs key not uploaded to Firebase Console');
      print('   2. Entitlements file missing or wrong');
      print('   3. App not registered for remote notifications');
      print('   4. Network connection issue');
    }
  } catch (e, stackTrace) {
    print('❌ [NOTIFICATIONS] ERROR getting FCM token: $e');
    print('❌ [NOTIFICATIONS] Stack trace: $stackTrace');
  }

  // Listen for token refresh
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    print('🔄 [NOTIFICATIONS] FCM Token refreshed!');
    print('📱 [NOTIFICATIONS] New token: $newToken');
  });

  print('✅ [NOTIFICATIONS] Setup complete');
}