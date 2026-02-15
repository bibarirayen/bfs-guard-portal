// lib/services/notifications.dart

import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

// Background message handler (MUST be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('📩 Background message: ${message.notification?.title}');
}

Future<void> setupFlutterNotifications() async {
  print('🔧 Setting up notifications...');

  // ============================================
  // ANDROID SETUP
  // ============================================
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'Used for important notifications',
    importance: Importance.high,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // ============================================
  // iOS SETUP
  // ============================================
  const DarwinInitializationSettings initializationSettingsDarwin =
  DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  // ============================================
  // INITIALIZE PLUGIN
  // ============================================
  const InitializationSettings initializationSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: initializationSettingsDarwin,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      print('📱 Notification tapped: ${response.payload}');
    },
  );

  // ============================================
  // iOS: REQUEST PERMISSIONS EXPLICITLY
  // ============================================
  if (Platform.isIOS) {
    print('📱 Requesting iOS notification permissions...');

    // Request local notification permissions
    final bool? localResult = await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    print('📱 iOS Local Notification Permission: $localResult');

    // Set foreground notification options
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    print('✅ iOS foreground notification options set');
  }

  // ============================================
  // BACKGROUND MESSAGE HANDLER
  // ============================================
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // ============================================
  // LISTEN TO FOREGROUND MESSAGES
  // ============================================
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('📬 Foreground message received: ${message.notification?.title}');

    RemoteNotification? notification = message.notification;

    if (notification != null) {
      if (Platform.isAndroid) {
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
          payload: message.data.toString(),
        );
      } else if (Platform.isIOS) {
        flutterLocalNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          const NotificationDetails(
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          payload: message.data.toString(),
        );
      }
    }
  });

  // ============================================
  // HANDLE NOTIFICATION TAPS
  // ============================================
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('📱 Notification opened app: ${message.notification?.title}');
  });

  // Check if app was opened from notification
  RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    print('📱 App opened from notification: ${initialMessage.notification?.title}');
  }

  // ============================================
  // GET FCM TOKEN
  // ============================================
  try {
    String? token = await FirebaseMessaging.instance.getToken();
    print('📱 FCM Token: $token');

    if (token == null) {
      print('❌ ERROR: FCM Token is null!');
      print('❌ This means APNs is not properly configured!');
    }
  } catch (e) {
    print('❌ ERROR getting FCM token: $e');
  }

  // Listen for token refresh
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    print('📱 FCM Token refreshed: $newToken');
  });

  print('✅ Notification setup complete');
}
