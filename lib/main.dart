import 'dart:async';
import 'dart:convert';
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
import 'package:http/http.dart' as http;

// Replace with your backend URL
const String backendUrl = 'https://api.blackfabricsecurity.com/api/errors/log';

// Save error locally
Future<void> logErrorLocally(String message) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/error_log.txt');
    await file.writeAsString('$message\n', mode: FileMode.append);
  } catch (e) {
    print('Failed to write local log: $e');
  }
}

// Send error to backend API
Future<void> logErrorRemote(String message, {String stack = ''}) async {
  try {
    final url = Uri.parse(backendUrl);
    await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'message': message, 'stackTrace': stack}),
    );
  } catch (e) {
    print('Failed to send error to backend: $e');
  }
}

// Unified error logger
Future<void> logError(String message, {String stack = ''}) async {
  await logErrorLocally(message);
  await logErrorRemote(message, stack: stack);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch Flutter framework errors
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    FirebaseCrashlytics.instance.recordFlutterError(details);
    logError(details.exceptionAsString(), stack: details.stack.toString());
  };

  // Catch all async errors
  runZonedGuarded(() async {
    try {
      await Firebase.initializeApp();
      FirebaseCrashlytics.instance.log("App started");

      // Request notifications
      NotificationSettings settings =
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      print('User granted permission: ${settings.authorizationStatus}');
      await setupFlutterNotifications();

      // Clear SharedPreferences (optional)
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

    } catch (e, stack) {
      // Catch initialization errors
      logError('Initialization error: $e', stack: stack.toString());
    }

    // Launch app
    runApp(BlackFabricApp());

    // Extra safety: log synchronous errors right after app launch
    logError('App launched successfully');
  }, (error, stack) {
    print('Caught by runZonedGuarded: $error');
    FirebaseCrashlytics.instance.recordError(error, stack);
    logError(error.toString(), stack: stack.toString());
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
      home: LoginScreen(),
    );
  }
}
