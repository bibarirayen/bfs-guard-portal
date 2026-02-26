import 'dart:io';
import 'package:crossplatformblackfabric/screens/late_arrivals_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../main.dart'; // imports navigatorKey

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

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
      final payload = response.payload ?? '';
      if (payload.contains('LATE_GUARD') || payload.contains('late')) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const LateArrivalsPage()),
        );
      }
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

    RemoteNotification? notification = message.notification;
    if (notification != null) {
      // Only manually show notifications on Android
      if (Platform.isAndroid) {
        // ✅ Pass the message type as payload so tap handler knows where to go
        final String payload = message.data['type'] ?? '';
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
    final type = message.data['type'] ?? '';
    if (type == 'LATE_GUARD') {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const LateArrivalsPage()),
      );
    }
  });

  // ✅ Handle notification tap when app was fully terminated
  RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    print('📱 [NOTIFICATIONS] App launched from notification');
    final type = initialMessage.data['type'] ?? '';
    if (type == 'LATE_GUARD') {
      // Delay slightly to ensure navigator is ready after app startup
      Future.delayed(const Duration(seconds: 1), () {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const LateArrivalsPage()),
        );
      });
    }
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