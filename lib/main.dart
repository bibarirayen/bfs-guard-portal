import 'dart:async';
import 'dart:io';
import 'package:crossplatformblackfabric/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'services/notifications.dart';
import 'package:path_provider/path_provider.dart';

void logError(String message) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/error_log.txt');
    await file.writeAsString('$message\n', mode: FileMode.append);
  } catch (e) {
    print('Failed to log error: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Crashlytics catch Flutter errors
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    FirebaseCrashlytics.instance.recordFlutterError(details);
    logError(details.toString());
  };

  runZonedGuarded(() async {
    await Firebase.initializeApp();

    // 🔹 Test FirebaseCrashlytics
    FirebaseCrashlytics.instance.log("App started");

    NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    print('User granted permission: ${settings.authorizationStatus}');
    await setupFlutterNotifications();

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    runApp(BlackFabricApp());
  }, (error, stack) {
    print('Caught by runZonedGuarded: $error');
    FirebaseCrashlytics.instance.recordError(error, stack);
    logError('Caught by runZonedGuarded: $error\n$stack');
  });
}

class BlackFabricApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Black Fabric Security',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: LoginScreen(), // start with login
    );
  }
}
