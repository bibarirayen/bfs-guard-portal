import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crossplatformblackfabric/screens/report_list_page.dart';
import 'package:crossplatformblackfabric/screens/vacation_request_page.dart';
import 'package:crossplatformblackfabric/services/shift_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/ApiService.dart';
import '../services/HeartbeatService.dart';
import '../services/LiveLocationService.dart';
import '../services/chat_service.dart';
import '../services/dashboard_service.dart';
import '../services/permission_helper.dart';
import '../widgets/navbar.dart';
import 'chat_screen.dart';
import 'conversation_screen.dart';
import 'report_page.dart';
import 'favorites_screen.dart';
import 'profile_screen.dart';
import 'trajectlist_screen.dart';
import 'package:crossplatformblackfabric/screens/shifts_page.dart';
import '../widgets/custom_appbar.dart';
import 'package:crossplatformblackfabric/screens/dispatch_contacts_page.dart';
import 'package:crossplatformblackfabric/screens/counseling_upload_page.dart';
import 'package:crossplatformblackfabric/screens/counseling_list_page.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:crossplatformblackfabric/screens/Late_Arrivals_page.dart';

class HomeScreen extends StatefulWidget {
  final String guardName;
  final String shiftTime;

  const HomeScreen({
    super.key,
    this.guardName = "Rayen Bibari",
    this.shiftTime = "08:00 - 16:00",
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  String _shiftTime = "No shift today";
  bool _hasShiftToday = false;
  bool _hasAssignment = false;
  String _guardRole = "";
  bool _isSupervisor = false;
  bool _guardName_loading = false;
  String _guardName = "";
  DateTime? _shiftStartDateTime;
  DateTime? _shiftEndDateTime;
  double? _siteLat;
  double? _siteLng;
  String _siteName = "";
  String _hoursToday = "0h";
  String? _supervisorName;
  String? _supervisorEmail;
  String? _supervisorPhone;

  late LiveLocationService _liveLocationService;

  Timer? _dashboardRefreshTimer;
  Timer? _shiftButtonUpdateTimer;

  bool _canStartShift = false;
  bool _canStopShift = false;
  bool _shiftStarted = false;
  bool _shiftEnded = false;

  late final List<Widget Function()> _screens;
  bool _isDarkMode = true;

  final List<String> _titles = [
    "Dashboard",
    "Patrols",
    "Chat",
    "Profile",
    "Vacation Requests",
    "Shifts",
    "Dispatch Contacts",
    "Counseling List",
    "New Counseling Report",
    "Reports",
    "New Report",
  ];

  Position? _currentPosition;
  bool _tracking = false;
  bool _isEmergencyActive = false;
  bool _assignmentActive = false;

  bool _isLocationDialogVisible = false;
  final _locationDialogKey = GlobalKey();
  BuildContext? _locationDialogContext;

  // ── DEBUG LOG OVERLAY ────────────────────────────────────────────────────────
  final List<String> _debugLogs = [];
  bool _showDebugPanel = false;
  // ─────────────────────────────────────────────────────────────────────────────

  Color get _backgroundColor =>
      _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _textColor =>
      _isDarkMode ? Colors.white : const Color(0xFF1E293B);
  Color get _cardColor =>
      _isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  Color get _borderColor =>
      _isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get _secondaryTextColor =>
      _isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _liveLocationService = LiveLocationService();

    // ── Wire up debug log callback ───────────────────────────────────────────
    _liveLocationService.onDebugLog = (msg) {
      if (!mounted) return;
      setState(() {
        final now = DateTime.now();
        final ts =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
        _debugLogs.insert(0, '[$ts] $msg');
        if (_debugLogs.length > 60) _debugLogs.removeLast();
      });
    };
    // ─────────────────────────────────────────────────────────────────────────

    _liveLocationService.onShiftEndedRemotely = () {
      if (!mounted) return;
      setState(() {
        _shiftStarted = false;
        _shiftEnded = true;
        _assignmentActive = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(children: [
            Icon(Icons.info_outline, color: Colors.white),
            SizedBox(width: 8),
            Text('Shift ended — GPS tracking stopped'),
          ]),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 4),
        ),
      );
    };

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _requestAllPermissions();
      // The 500ms was too short — on some devices the system permission dialog
      // dismiss animation was still running, causing showDialog to silently fail.
      // _enforceAlwaysPermission now adds its own 800ms delay internally.
      await _enforceAlwaysPermission();
    });

    // NOTE: removed the old 1-second delayed _restoreLiveTrackingIfNeeded call.
    // It was broken because _hasShiftToday=false at that point.
    // _loadDashboard now calls _restoreLiveTrackingIfNeeded with an override.

    _loadDashboard();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('userId');
      if (userId != null) ChatService().connect(userId);
    });

    _screens = [
          () => _buildDashboard(),
          () => TrajectListPage(),
          () => const ConversationsScreen(),
          () => const ProfileScreen(),
          () => const VacationRequestPage(),
          () => const ShiftsPage(),
          () => const DispatchContactsPage(),
          () => const CounselingListPage(),
          () => const CounselingUploadPage(),
          () => const ReportListPage(),
          () => const ReportPage(),
    ];

    _dashboardRefreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) async {
          print('🔄 Auto-refreshing dashboard...');
          _loadDashboard();

          if (_liveLocationService.isTracking) {
            final permission = await Geolocator.checkPermission();
            final bool actuallyRevoked =
                permission == LocationPermission.denied ||
                    permission == LocationPermission.deniedForever;
            if (actuallyRevoked) {
              _liveLocationService.stopTracking();
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('shift_active', false);
              await prefs.remove('active_assignment_id');
              await prefs.remove('active_guard_id');
              if (mounted) {
                setState(() {
                  _shiftStarted = false;
                  _assignmentActive = false;
                });
                _showLocationBlockDialog(
                  title: 'Location Set to "Always" Required',
                  message:
                  'Your location permission was revoked. '
                      'Background tracking has been stopped.\n\n'
                      'Go to Settings → [App] → Location → select "Always" to resume your shift.',
                  buttonLabel: 'Open Settings',
                  onTap: () => openAppSettings(),
                );
              }
            }
          }
        });

    _shiftButtonUpdateTimer =
        Timer.periodic(const Duration(minutes: 1), (_) {
          _updateShiftButtons();
        });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dashboardRefreshTimer?.cancel();
    _shiftButtonUpdateTimer?.cancel();
    _liveLocationService.onShiftEndedRemotely = null;
    _liveLocationService.onDebugLog = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  Future<void> _onAppResumed() async {
    final permission = await Geolocator.checkPermission();
    final bool actuallyDenied =
        permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever;

    if (!actuallyDenied) {
      if (_isLocationDialogVisible && _locationDialogContext != null) {
        if (mounted && Navigator.canPop(_locationDialogContext!)) {
          Navigator.pop(_locationDialogContext!);
        }
      }
      return;
    }

    if (_liveLocationService.isTracking) {
      _liveLocationService.stopTracking();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('shift_active', false);
      await prefs.remove('active_assignment_id');
      await prefs.remove('active_guard_id');
      if (mounted) {
        setState(() {
          _shiftStarted = false;
          _assignmentActive = false;
        });
      }
    }

    if (mounted && !_isLocationDialogVisible) {
      _showLocationBlockDialog(
        title: 'Location Set to "Always" Required',
        message:
        'Your location permission was revoked. Background tracking stopped.\n\n'
            'Go to Settings → [App] → Location → select "Always" to continue your shift.',
        buttonLabel: 'Open Settings',
        onTap: () => openAppSettings(),
      );
    }
  }

  Future<void> _requestAllPermissions() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
      await Future.delayed(const Duration(milliseconds: 600));
    }
    LocationPermission locationPerm = await Geolocator.checkPermission();
    if (locationPerm == LocationPermission.denied) {
      locationPerm = await Geolocator.requestPermission();
      await Future.delayed(const Duration(milliseconds: 600));
    }
  }

  Future<void> _enforceAlwaysPermission() async {
    // Give the navigator a full frame to settle after any system permission
    // dialogs. Without this, showDialog can silently fail if called while
    // the system dialog's dismiss animation is still running.
    await Future.delayed(const Duration(milliseconds: 800));

    while (true) {
      if (!mounted) return;

      final permission = await Geolocator.checkPermission();
      final bool granted = permission == LocationPermission.always ||
          (Platform.isIOS && permission == LocationPermission.whileInUse);
      if (granted) return;

      // deniedForever → can only fix via Settings, no point looping
      if (permission == LocationPermission.deniedForever) {
        await _showLocationBlockDialog(
          title: 'Location Permission Blocked',
          message:
          'Location access was permanently denied.\n\n'
              'Go to Settings → [App] → Location → select "Always".',
          buttonLabel: 'Open Settings',
          onTap: () => openAppSettings(),
        );
        return;
      }

      await _showLocationBlockDialog(
        title: 'Location Set to "Always" Required',
        message:
        'This app requires location access set to "Always" for shift tracking '
            'and safety monitoring.\n\n'
            'Go to Settings → [App] → Location → select "Always".',
        buttonLabel: 'Open Settings',
        onTap: () => openAppSettings(),
      );

      // Wait for the user to come back from Settings before rechecking
      await Future.delayed(const Duration(milliseconds: 500));
      final recheckPerm = await Geolocator.checkPermission();
      final bool recheckGranted = recheckPerm == LocationPermission.always ||
          (Platform.isIOS && recheckPerm == LocationPermission.whileInUse);
      if (recheckGranted) return;
    }
  }

  // ── FIX 1 + 2 ────────────────────────────────────────────────────────────
  // FIX 1: accepts hasShiftTodayOverride so it works before setState runs.
  //        _hasShiftToday is still false when called from _loadDashboard
  //        because setState hasn't fired yet — always returned early before.
  // FIX 2: guards against restarting an already-running stream.
  //        Without this, every 30s dashboard refresh killed the iOS stream.
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _restoreLiveTrackingIfNeeded({bool? hasShiftTodayOverride}) async {
    if (_liveLocationService.isTracking) return; // FIX 2

    final prefs = await SharedPreferences.getInstance();
    final isShiftActive = prefs.getBool('shift_active') ?? false;
    final assignmentId = prefs.getInt('active_assignment_id');
    final guardId = prefs.getInt('active_guard_id');

    final bool shiftToday = hasShiftTodayOverride ?? _hasShiftToday; // FIX 1

    if (!isShiftActive || !shiftToday || assignmentId == null || guardId == null) return;

    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    _liveLocationService.startTracking(guardId, assignmentId);
    setState(() {
      _assignmentActive = true;
      _shiftStarted = true;
      _shiftEnded = false;
    });
  }

  String _toAmPm(String timeStr) {
    final parts = timeStr.split(':');
    int hour = int.parse(parts[0]);
    int minute = int.parse(parts[1]);
    final period = hour >= 12 ? 'PM' : 'AM';
    int displayHour = hour % 12;
    if (displayHour == 0) displayHour = 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  Future<void> _loadDashboard() async {
    try {
      final dashboardService = DashboardService();
      final data = await dashboardService.getDashboardMobile();

      final guardName = data["GuardName"] ?? "Unknown Guard";
      final bool assignmentActive = data["Active"] == true;

      if (!assignmentActive && _liveLocationService.isTracking) {
        _liveLocationService.stopTracking();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('shift_active', false);
        await prefs.remove('active_assignment_id');
        await prefs.remove('active_guard_id');
        if (mounted) {
          setState(() {
            _shiftStarted = false;
            _shiftEnded = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(children: [
                Icon(Icons.info_outline, color: Colors.white),
                SizedBox(width: 8),
                Text('Shift ended — GPS tracking stopped'),
              ]),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }

      final guardRole = data["GuardRole"] ?? "Guard";
      final isSupervisor = guardRole.toLowerCase() == "supervisor";

      bool hasShiftToday = data["hasShiftToday"] == true;
      String shiftTime = "No shift today";

      DateTime? startDateTime;
      DateTime? endDateTime;
      String formattedHours = "0h";
      final prefs = await SharedPreferences.getInstance();

      // FIX 3: only wipe keys when no shift today. Previously wiped every 30s
      // unconditionally, before the shift block could write them back.
      if (!hasShiftToday) {
        await prefs.remove('active_assignment_id');
        await prefs.remove('assignmentId');
      }

      if (hasShiftToday && data["shift"] != null) {
        final start = data["shift"]["startTime"];
        final end = data["shift"]["endTime"];
        final site = data["site"];
        if (site != null) {
          _siteLat = site["latitude"];
          _siteLng = site["longitude"];
          _siteName = site["name"] ?? "Site";
          _supervisorName = site["supervisorname"];
          _supervisorEmail = site["supervisoremail"];
          _supervisorPhone = site["supervisornumber"];
        }

        final shiftDateStr = data["date"];
        final shiftDate = DateTime.parse(shiftDateStr);
        final startParts = start.split(":");
        final endParts = end.split(":");

        startDateTime = DateTime.utc(
          shiftDate.year, shiftDate.month, shiftDate.day,
          int.parse(startParts[0]), int.parse(startParts[1]),
        );

        final endHour = int.parse(endParts[0]);
        final endMin = int.parse(endParts[1]);
        final startHour = int.parse(startParts[0]);
        final startMin = int.parse(startParts[1]);
        final isOvernightShift =
            (endHour * 60 + endMin) <= (startHour * 60 + startMin);

        endDateTime = DateTime.utc(
          shiftDate.year, shiftDate.month, shiftDate.day, endHour, endMin,
        );
        if (isOvernightShift) {
          endDateTime = endDateTime!.add(const Duration(days: 1));
        }

        _shiftStartDateTime = startDateTime;
        _shiftEndDateTime = endDateTime;
        shiftTime = "${_toAmPm(start)} - ${_toAmPm(end)}";

        final totalMins = endDateTime!.difference(startDateTime!).inMinutes;
        final h = totalMins ~/ 60;
        final m = totalMins % 60;
        formattedHours = h > 0 ? "${h}h ${m}m" : "${m}m";

        await prefs.setInt('assignmentId', data["assignmentId"]);
        _hasAssignment = prefs.getInt('assignmentId') != null;
        await prefs.setInt('active_assignment_id', data["assignmentId"]);
        await prefs.setInt('active_guard_id', prefs.getInt('userId')!);
        await prefs.setBool('shift_active', data["Active"] == true);

        // FIX 1: pass real value so restore works before setState runs
        await _restoreLiveTrackingIfNeeded(hasShiftTodayOverride: hasShiftToday);
      }

      setState(() {
        _guardName = guardName;
        _hasShiftToday = hasShiftToday;
        _shiftTime = shiftTime;
        _shiftStartDateTime = startDateTime;
        _shiftEndDateTime = endDateTime;
        _assignmentActive = assignmentActive;
        _shiftStarted = assignmentActive;
        _guardRole = guardRole;
        _isSupervisor = isSupervisor;
        _hoursToday = formattedHours;
        _hasAssignment = prefs.getInt('assignmentId') != null;
      });

      _updateShiftButtons();
    } catch (e) {
      debugPrint("Dashboard error: $e");
      setState(() {
        _guardName = "Unknown Guard";
        _shiftTime = "No shift today";
        _hasShiftToday = false;
      });
    }
  }

  DateTime getHawaiiTime() =>
      DateTime.now().toUtc().subtract(const Duration(hours: 10));

  DateTime parseServerTime(String serverTimeStr) =>
      DateTime.parse(serverTimeStr.split('[')[0]);

  Future<DateTime?> _fetchServerTime() async {
    try {
      final apiService = ApiService();
      final response = await apiService.get("auth/server-time");
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return parseServerTime(data["now"]);
      }
      return null;
    } catch (e) {
      debugPrint("Error fetching server time: $e");
      return null;
    }
  }

  Future<void> _updateShiftButtons() async {
    if (_shiftStartDateTime == null || _shiftEndDateTime == null) return;

    DateTime now = DateTime.now().toUtc().subtract(const Duration(hours: 10));
    final serverTime = await _fetchServerTime();
    if (serverTime != null) now = serverTime.subtract(const Duration(hours: 10));

    final startWindow = _shiftStartDateTime!.subtract(const Duration(minutes: 15));

    setState(() {
      _canStartShift = !_assignmentActive &&
          now.isAfter(startWindow) &&
          now.isBefore(_shiftEndDateTime!.add(const Duration(minutes: 5)));

      _canStopShift = _assignmentActive &&
          (now.isAfter(_shiftEndDateTime!) ||
              now.isAtSameMomentAs(_shiftEndDateTime!));
    });
  }

  Future<void> _sendEmergencyAlert() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final guardId = prefs.getInt('userId');
      if (guardId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Guard ID not found")),
        );
        return;
      }
      final apiService = ApiService();
      final response = await apiService.post("emergency/trigger/$guardId", {});
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Emergency alert sent successfully!"),
            backgroundColor: Colors.redAccent,
          ),
        );
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error'] ?? "Failed to send emergency alert")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error sending emergency alert: $e")),
      );
    }
  }

  Future<void> _startShift() async {
    final bool hasPermission = await _ensureLocationPermission();
    if (!hasPermission) return;

    await _getCurrentPosition();
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("GPS location not available")),
      );
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final assignmentId = prefs.getInt('assignmentId');
      final guardId = prefs.getInt('userId');

      if (assignmentId == null || guardId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Assignment or Guard ID not found")),
        );
        return;
      }

      final apiService = ApiService();
      final response = await apiService.put(
        "assignments/Start/$assignmentId/$guardId",
        {
          "latitude": _currentPosition!.latitude,
          "longitude": _currentPosition!.longitude,
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          _assignmentActive = true;
          _shiftStarted = true;
          _canStartShift = false;
          _canStopShift = false;
        });

        ShiftService().startAssignment(assignmentId);
        _liveLocationService.startTracking(guardId, assignmentId);

        await prefs.setBool('shift_active', true);
        await prefs.setInt('active_assignment_id', assignmentId);
        await prefs.setInt('active_guard_id', guardId);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Shift started successfully!")),
        );
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error'] ?? "Failed to start shift")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error starting shift: $e")),
      );
    }
  }

  Future<void> _stopShift() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final assignmentId = prefs.getInt('assignmentId');
      final guardId = prefs.getInt('userId');

      if (assignmentId == null || guardId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Assignment or Guard ID not found")),
        );
        return;
      }

      final apiService = ApiService();
      final response = await apiService.put(
        "assignments/stop/$assignmentId/$guardId",
        {},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _liveLocationService.stopTracking();

        await prefs.setBool('shift_active', false);
        await prefs.remove('active_assignment_id');
        await prefs.remove('active_guard_id');

        setState(() {
          _assignmentActive = false;
          _shiftEnded = true;
          _shiftStarted = false;
          _canStopShift = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                "Shift stopped successfully\nTotal hours: ${data["totalHours"]}"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error'] ?? "Failed to stop shift")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error stopping shift: $e")),
      );
    }
  }

  Future<void> _getCurrentPosition() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 20),
      );
      _currentPosition = position;
    } on TimeoutException {
      _currentPosition = await Geolocator.getLastKnownPosition();
    } catch (e) {
      debugPrint("Error getting current position: $e");
    }
  }

  Future<bool> _ensureLocationPermission() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await _showLocationBlockDialog(
        title: 'Turn On Location Services',
        message: 'GPS is disabled on your device. Please turn on Location Services.',
        buttonLabel: 'Open Location Settings',
        onTap: () => Geolocator.openLocationSettings(),
      );
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) return true;

    await _showLocationBlockDialog(
      title: 'Location Set to "Always" Required',
      message:
      'This app requires location access set to "Always" for shift tracking.\n\n'
          'Go to Settings → [App] → Location → select "Always".',
      buttonLabel: 'Open Settings',
      onTap: () => openAppSettings(),
    );
    return false;
  }

  Future<void> _showLocationBlockDialog({
    required String title,
    required String message,
    required String buttonLabel,
    required VoidCallback onTap,
  }) async {
    if (!mounted) return;
    if (_isLocationDialogVisible) return;

    _isLocationDialogVisible = true;
    _locationDialogContext = null;

    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          _locationDialogContext = ctx;
          return WillPopScope(
            onWillPop: () async => false,
            child: AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text(title, style: const TextStyle(color: Colors.white)),
              content: Text(message, style: const TextStyle(color: Colors.white70)),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onTap();
                  },
                  child: Text(buttonLabel),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      // Always reset — even if showDialog throws or widget unmounts mid-dialog.
      _isLocationDialogVisible = false;
      _locationDialogContext = null;
    }
  }

  Future<bool> _handleLocationPermission() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: CustomAppBar(
        title: _titles[_selectedIndex],
        isDarkMode: _isDarkMode,
        onThemeChanged: (value) {
          setState(() {
            _isDarkMode = value;
          });
        },
      ),
      body: Stack(
        children: [
          _screens[_selectedIndex](),

          // ── ON-SCREEN DEBUG LOG PANEL ──────────────────────────────────────
          if (_showDebugPanel)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.black.withOpacity(0.93),
                child: SizedBox(
                  height: 220,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Text('📡 GPS Debug Log',
                              style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => setState(() => _debugLogs.clear()),
                            child: const Padding(
                              padding: EdgeInsets.only(right: 12),
                              child: Text('clear',
                                  style: TextStyle(
                                      color: Colors.orange, fontSize: 11)),
                            ),
                          ),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _showDebugPanel = false),
                            child: const Text('close',
                                style:
                                TextStyle(color: Colors.red, fontSize: 11)),
                          ),
                        ]),
                        const Divider(color: Colors.green, height: 6),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _debugLogs.length,
                            itemBuilder: (_, i) => Text(
                              _debugLogs[i],
                              style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 10,
                                  height: 1.4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── FLOATING DEBUG TOGGLE BUTTON ───────────────────────────────────
          Positioned(
            bottom: _showDebugPanel ? 224 : 8,
            right: 8,
            child: GestureDetector(
              onTap: () => setState(() => _showDebugPanel = !_showDebugPanel),
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _showDebugPanel
                      ? Colors.green.withOpacity(0.85)
                      : Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _showDebugPanel
                          ? Colors.greenAccent
                          : Colors.grey.withOpacity(0.5)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.bug_report, size: 13, color: Colors.white),
                  SizedBox(width: 4),
                  Text('Debug',
                      style: TextStyle(color: Colors.white, fontSize: 11)),
                ]),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: CustomNavbar(
        onItemTapped: _onItemTapped,
        selectedIndex: _selectedIndex,
      ),
    );
  }

  Future<void> _openSiteOnMap() async {
    if (_siteLat == null || _siteLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Site location not available")),
      );
      return;
    }
    final url = Uri.parse(
      "https://www.google.com/maps/search/?api=1&query=$_siteLat,$_siteLng",
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open maps")),
      );
    }
  }

  void _showSupervisorModal() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: _borderColor, width: 1),
        ),
        title: Row(
          children: [
            const Icon(Icons.person, color: Color(0xFF3B82F6)),
            const SizedBox(width: 10),
            Text("Supervisor Info",
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: _textColor)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Name: ${_supervisorName ?? "N/A"}",
                style: TextStyle(color: _textColor)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text("Email: ${_supervisorEmail ?? "N/A"}",
                      style: TextStyle(color: _textColor)),
                ),
                if (_supervisorEmail != null)
                  IconButton(
                    icon: Icon(Icons.copy,
                        size: 16, color: _secondaryTextColor),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: _supervisorEmail!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text("Email copied"),
                            duration: Duration(seconds: 1)),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text("Phone: ${_supervisorPhone ?? "N/A"}",
                      style: TextStyle(color: _textColor)),
                ),
                if (_supervisorPhone != null)
                  IconButton(
                    icon: Icon(Icons.copy,
                        size: 16, color: _secondaryTextColor),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: _supervisorPhone!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text("Phone copied"),
                            duration: Duration(seconds: 1)),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Close", style: TextStyle(color: _textColor)),
          ),
        ],
      ),
    );
  }

  void _toggleEmergency() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(25),
          side: BorderSide(color: Colors.red.withOpacity(0.3), width: 1),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.redAccent, size: 28),
            const SizedBox(width: 12),
            Text("Emergency Alert",
                style: TextStyle(
                    color: _textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          "Emergency signal will be sent to security control center. Are you sure?",
          style: TextStyle(color: _secondaryTextColor, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel",
                style:
                TextStyle(color: _secondaryTextColor, fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _sendEmergencyAlert();
              setState(() => _isEmergencyActive = true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
              padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text("Confirm",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadDashboard,
        color: Colors.white,
        backgroundColor: const Color(0xFF4F46E5),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: _cardColor,
                  border: Border.all(color: _borderColor, width: 1),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 35,
                      backgroundColor:
                      const Color(0xFF4F46E5).withOpacity(0.1),
                      child: const Icon(Icons.person,
                          size: 40, color: Color(0xFF4F46E5)),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _guardName.isEmpty ? "Loading..." : _guardName,
                            style: TextStyle(
                                color: _textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color:
                              const Color(0xFF10B981).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isSupervisor
                                      ? Icons.admin_panel_settings
                                      : Icons.security,
                                  size: 14,
                                  color: const Color(0xFF10B981),
                                ),
                                const SizedBox(width: 6),
                                Text(_guardRole,
                                    style: TextStyle(
                                        color: _textColor,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color:
                              const Color(0xFF4F46E5).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.access_time,
                                    size: 14, color: Color(0xFF4F46E5)),
                                const SizedBox(width: 6),
                                Text(_shiftTime,
                                    style: TextStyle(
                                        color: _textColor,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: _buildSimpleStatCard(
                      _hoursToday, "Hours Today", Icons.timer,
                      const Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSimpleStatCard(
                      "", "Supervisor", Icons.person_outline,
                      const Color(0xFF3B82F6),
                      onTap: (_hasShiftToday && _supervisorName != null)
                          ? _showSupervisorModal
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSimpleStatCard(
                      "", "Open Site Map", Icons.map,
                      const Color(0xFF10B981),
                      onTap: _hasAssignment ? _openSiteOnMap : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              GestureDetector(
                onTap: (_shiftStarted && !_shiftEnded)
                    ? _toggleEmergency
                    : null,
                child: Opacity(
                  opacity: (_shiftStarted && !_shiftEnded) ? 1.0 : 0.4,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: _hasShiftToday
                          ? (_isEmergencyActive
                          ? Colors.redAccent
                          : Colors.red)
                          : Colors.grey,
                      boxShadow: _hasShiftToday
                          ? [
                        BoxShadow(
                            color: Colors.red.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4))
                      ]
                          : [],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning,
                            size: 28, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                !_hasShiftToday
                                    ? "NO ACTIVE SHIFT"
                                    : (_isEmergencyActive
                                    ? "EMERGENCY ACTIVE"
                                    : "EMERGENCY ALERT"),
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                !_hasShiftToday
                                    ? "Emergency disabled outside shift"
                                    : (_isEmergencyActive
                                    ? "Assistance is on the way"
                                    : "Press for emergency"),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withOpacity(0.9)),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              if (_hasShiftToday && !_shiftEnded)
                GestureDetector(
                  onTap: _canStartShift
                      ? () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: _cardColor,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                            BorderRadius.circular(20)),
                        contentPadding: const EdgeInsets.fromLTRB(
                            24, 28, 24, 16),
                        content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                    Icons.location_on,
                                    color: Colors.green,
                                    size: 36),
                              ),
                              const SizedBox(height: 16),
                              Text('Location Tracking',
                                  style: TextStyle(
                                      color: _textColor,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 10),
                              Text(
                                'Your location will be tracked for the duration of your shift until you clock out.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: _secondaryTextColor,
                                    fontSize: 14,
                                    height: 1.5),
                              ),
                            ]),
                        actions: [
                          Row(children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () =>
                                    Navigator.pop(ctx, false),
                                style: TextButton.styleFrom(
                                  padding:
                                  const EdgeInsets.symmetric(
                                      vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(12),
                                    side: BorderSide(
                                        color: _borderColor),
                                  ),
                                ),
                                child: Text('Cancel',
                                    style: TextStyle(
                                        color: _secondaryTextColor,
                                        fontWeight:
                                        FontWeight.w600)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () =>
                                    Navigator.pop(ctx, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding:
                                  const EdgeInsets.symmetric(
                                      vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                      BorderRadius.circular(
                                          12)),
                                  elevation: 0,
                                ),
                                child: const Text('Confirm',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight:
                                        FontWeight.w700)),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    );
                    if (confirmed == true) _startShift();
                  }
                      : _canStopShift
                      ? _stopShift
                      : null,
                  child: Opacity(
                    opacity:
                    (_canStartShift || _canStopShift) ? 1.0 : 0.4,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: _shiftStarted
                            ? Colors.redAccent
                            : Colors.green,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _shiftStarted
                                ? Icons.stop
                                : Icons.play_arrow,
                            color: Colors.white,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _shiftStarted
                                      ? "STOP SHIFT"
                                      : "START SHIFT",
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  _shiftStarted
                                      ? "Available at shift end"
                                      : "Available 20 minutes before start",
                                  style: TextStyle(
                                      color:
                                      Colors.white.withOpacity(0.9),
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 25),

              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  "Quick Actions",
                  style: TextStyle(
                      color: _textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w700),
                ),
              ),

              if (_isSupervisor) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LateArrivalsPage()),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color:
                          const Color(0xFFEF4444).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444)
                                .withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.warning_amber_rounded,
                              color: Color(0xFFEF4444), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Late Arrivals",
                            style: TextStyle(
                                color: _textColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios,
                            size: 14, color: Color(0xFFEF4444)),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _buildSimpleActionButton(
                      Icons.beach_access, "Vacation\nRequest",
                      const Color(0xFF3B82F6),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSimpleActionButton(
                      Icons.access_time_filled, "Shift\nMarketplace",
                      const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _buildSimpleActionButton(
                      Icons.description_outlined, "Reports",
                      const Color(0xFF6366F1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSimpleActionButton(
                      Icons.support_agent, "Dispatch\nContacts",
                      const Color(0xFF8B5CF6),
                    ),
                  ),
                ],
              ),

              if (_isSupervisor) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildSimpleActionButton(
                        Icons.article_outlined,
                        "Counseling\nStatements",
                        const Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSimpleActionButton(
                        Icons.note_add_outlined,
                        "New Counseling\nReport",
                        const Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 90),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSimpleStatCard(
      String value, String label, IconData icon, Color color,
      {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: _cardColor,
          border: Border.all(color: _borderColor, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(value,
                        style: TextStyle(
                            color: _textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(label,
                style:
                TextStyle(color: _secondaryTextColor, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleActionButton(
      IconData icon, String label, Color color) {
    return GestureDetector(
      onTap: () {
        if (label.contains("Vacation")) {
          _onItemTapped(4);
        } else if (label.contains("Shift\nMarketplace")) {
          _onItemTapped(5);
        } else if (label.contains("Reports")) {
          _onItemTapped(9);
        } else if (label.contains("Dispatch")) {
          _onItemTapped(6);
        } else if (label.contains("Counseling\nStatements")) {
          _onItemTapped(7);
        } else if (label.contains("New Counseling\nReport")) {
          _onItemTapped(8);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text("$label clicked!"),
                backgroundColor: _cardColor),
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: _cardColor,
          border: Border.all(color: _borderColor, width: 1),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 22, color: color),
                ),
                const SizedBox(height: 8),
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}