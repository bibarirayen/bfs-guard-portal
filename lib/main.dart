import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crossplatformblackfabric/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/force_update_screen.dart';
import 'config/app_globals.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'services/notifications.dart';
import 'services/BackgroundLocation_Service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

const String backendUrl = 'https://api.blackfabricsecurity.com/api/errors/log';

Future<void> logErrorLocally(String message) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/error_log.txt');
    await file.writeAsString('$message\n', mode: FileMode.append);
  } catch (_) {}
}

Future<void> logErrorRemote(String message, {String stack = ''}) async {
  try {
    final url = Uri.parse(backendUrl);
    await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'message': message, 'stackTrace': stack}),
    );
  } catch (_) {}
}

Future<void> logError(String message, {String stack = ''}) async {
  await logErrorLocally(message);
  await logErrorRemote(message, stack: stack);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initBackgroundService();

  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    FirebaseCrashlytics.instance.recordFlutterError(details);
    logError(details.exceptionAsString(), stack: details.stack.toString());
  };

  runZonedGuarded(() async {
    try {
      await Firebase.initializeApp();

      NotificationSettings settings =
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await setupFlutterNotifications();
    } catch (e, stack) {
      logError('Initialization error: $e', stack: stack.toString());
    }

    loginScreenBuilder = (_) => const LoginScreen();
    runApp(const BlackFabricApp());
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack);
    logError(error.toString(), stack: stack.toString());
  });
}

class BlackFabricApp extends StatefulWidget {
  const BlackFabricApp({super.key});

  @override
  State<BlackFabricApp> createState() => _BlackFabricAppState();
}

class _BlackFabricAppState extends State<BlackFabricApp>
    with WidgetsBindingObserver {
  // Re-check the minimum required app version every 15 minutes while the app
  // is in the foreground. Combined with the on-resume check below, this means
  // a guard who leaves the app open during their shift will be kicked to the
  // update screen as soon as we publish a new minVersion on the backend \u2014 no
  // need to close + reopen the app to pick up the gate.
  static const Duration _versionPollInterval = Duration(minutes: 15);
  Timer? _versionTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startVersionPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _versionTimer?.cancel();
    super.dispose();
  }

  void _startVersionPolling() {
    _versionTimer?.cancel();
    _versionTimer = Timer.periodic(
      _versionPollInterval,
      (_) => enforceUpdateIfOutdated(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Whenever the app comes back to the foreground (e.g. user switched away
    // and returned), re-check the version immediately.
    if (state == AppLifecycleState.resumed) {
      enforceUpdateIfOutdated();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Black Fabric Security',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      locale: const Locale('en', 'US'),
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const ForceUpdateScreen(),
    );
  }
}