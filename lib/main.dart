import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crossplatformblackfabric/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/force_update_screen.dart';
import 'screens/executive_notice_screen.dart';
import 'config/app_globals.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'services/notifications.dart';
import 'services/notice_service.dart';
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
  static const Duration _versionPollInterval = Duration(minutes: 15);
  static const Duration _noticePollInterval  = Duration(minutes: 5);

  Timer? _versionTimer;
  Timer? _noticeTimer;

  // Guard against concurrent notice fetches or double-push while the notice
  // screen is already showing.
  bool _noticeFetchInFlight = false;
  bool _noticesShowing      = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startVersionPolling();
    _startNoticePolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _versionTimer?.cancel();
    _noticeTimer?.cancel();
    super.dispose();
  }

  void _startVersionPolling() {
    _versionTimer?.cancel();
    _versionTimer = Timer.periodic(
      _versionPollInterval,
      (_) => enforceUpdateIfOutdated(),
    );
  }

  void _startNoticePolling() {
    _noticeTimer?.cancel();
    _noticeTimer = Timer.periodic(
      _noticePollInterval,
      (_) => _checkAndShowNotices(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      enforceUpdateIfOutdated();
      _checkAndShowNotices();
    }
  }

  Future<void> _checkAndShowNotices() async {
    if (_noticeFetchInFlight || _noticesShowing) return;
    _noticeFetchInFlight = true;
    try {
      final prefs  = await SharedPreferences.getInstance();
      final userId = prefs.getInt('userId') ?? 0;
      final token  = prefs.getString('jwt') ?? '';
      // Skip when not logged in.
      if (userId == 0 || token.isEmpty) return;

      final notices = await NoticeService().getPendingNotices(userId);
      if (notices.isEmpty) return;

      final navState = navigatorKey.currentState;
      if (navState == null) return;

      _noticesShowing = true;
      navState.push(
        MaterialPageRoute(
          builder: (_) => ExecutiveNoticeScreen(
            notices:     notices,
            userId:      userId,
            destination: null, // pops back to wherever the guard was
          ),
        ),
      ).then((_) => _noticesShowing = false);
    } finally {
      _noticeFetchInFlight = false;
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