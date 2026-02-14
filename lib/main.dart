import 'dart:async';
import 'dart:io';
import 'package:crossplatformblackfabric/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/notifications.dart'; // ✅ keep this

// Function to log errors to a file
void logError(String message) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/error_log.txt');
    await file.writeAsString('$message\n', mode: FileMode.append);
  } catch (e) {
    // fallback: print if file fails
    print('Failed to log error: $e');
  }
}

// Catch all Flutter errors
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch Flutter errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
    logError(details.toString());
  };

  // Catch async errors
  runZonedGuarded(() async {
    await Firebase.initializeApp();

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
