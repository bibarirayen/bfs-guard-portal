import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      print('📱 [NOTIFICATIONS] Tapped: ${response.payload}');
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

  // Handle notification taps
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('📱 [NOTIFICATIONS] App opened from notification');
  });

  RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    print('📱 [NOTIFICATIONS] App launched from notification');
  }

  // Get FCM token - THIS IS THE CRITICAL PART
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