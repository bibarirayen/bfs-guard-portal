import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crossplatformblackfabric/screens/report_list_page.dart';
import 'package:crossplatformblackfabric/screens/vacation_request_page.dart';
import 'package:crossplatformblackfabric/services/shift_service.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/ApiService.dart';
import '../services/HeartbeatService.dart';
import '../services/LiveLocationService.dart';
import '../services/dashboard_service.dart';
import '../services/permission_helper.dart';
import '../widgets/navbar.dart';
import 'chat_screen.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  String _shiftTime = "No shift today";
  bool _hasShiftToday = false;
  bool _hasAssignment = false;
  String _guardRole = "";
  bool _isSupervisor = false;

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

  // ⭐ Timers for periodic updates
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
    "Reports",
    "New Report",
    "Patrols",
    "Profile",
    "Vacation Requests",
    "Shifts",
    "Dispatch Contacts",
    "Counseling List",
    "New Counseling Report"
  ];

  // GPS tracking variables
  Position? _currentPosition;
  bool _tracking = false;
  bool _isEmergencyActive = false;
  bool _assignmentActive = false;

  // ─────────────────────────────────────────────────────────────────────────
  // Theme helpers
  // ─────────────────────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    Future<void> _requestNotificationPermission() async {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    }

    _requestNotificationPermission();

    // ── FIX 1: initialise service and register remote-end callback ──────────
    _liveLocationService = LiveLocationService();

    _liveLocationService.onShiftEndedRemotely = () {
      if (!mounted) return;
      setState(() {
        _shiftStarted = false;
        _shiftEnded = true;
        _assignmentActive = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white),
              SizedBox(width: 8),
              Text('Shift ended — GPS tracking stopped'),
            ],
          ),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 4),
        ),
      );
    };
    // ────────────────────────────────────────────────────────────────────────

    _requestAllPermissions();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(seconds: 1));
      await _restoreLiveTrackingIfNeeded();
    });

    _loadDashboard();

    _screens = [
          () => _buildDashboard(),
          () => const ReportListPage(),
          () => const ReportPage(),
          () => TrajectListPage(),
          () => const ProfileScreen(),
          () => const VacationRequestPage(),
          () => const ShiftsPage(),
          () => const DispatchContactsPage(),
          () => const CounselingListPage(),
          () => const CounselingUploadPage(),
    ];

    // Refresh dashboard every 30 s to detect remote shift-end while foreground
    _dashboardRefreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) {
          print('🔄 Auto-refreshing dashboard...');
          _loadDashboard();
        });

    _shiftButtonUpdateTimer =
        Timer.periodic(const Duration(minutes: 1), (_) {
          _updateShiftButtons();
        });
  }

  @override
  void dispose() {
    _dashboardRefreshTimer?.cancel();
    _shiftButtonUpdateTimer?.cancel();
    // ── FIX 3: clear callback to prevent memory leak ──────────────────────
    _liveLocationService.onShiftEndedRemotely = null;
    // ─────────────────────────────────────────────────────────────────────
    print('🧹 Timers cleaned up');
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Restore tracking on app resume / hot-restart
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _restoreLiveTrackingIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();

    final isShiftActive = prefs.getBool('shift_active') ?? false;
    final assignmentId = prefs.getInt('active_assignment_id');
    final guardId = prefs.getInt('active_guard_id');

    print("🔁 RESTORE CHECK");
    print("shift_active = $isShiftActive");
    print("assignmentId = $assignmentId");
    print("guardId = $guardId");

    if (!isShiftActive ||
        !_hasShiftToday ||
        assignmentId == null ||
        guardId == null) {
      print("❌ Restore aborted (no active shift)");
      return;
    }

    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) {
      print("❌ Restore aborted (permission denied)");
      return;
    }

    print("✅ Restoring live location tracking...");
    _liveLocationService.startTracking(guardId, assignmentId);

    setState(() {
      _assignmentActive = true;
      _shiftStarted = true;
      _shiftEnded = false;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Dashboard load — FIX 2: uncommented GPS-stop block
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadDashboard() async {
    try {
      final dashboardService = DashboardService();
      final data = await dashboardService.getDashboardMobile();

      final guardName = data["GuardName"] ?? "Unknown Guard";
      final bool assignmentActive = data["Active"] == true;

      // ── FIX 2: Stop GPS when server says shift is no longer active ────────
      if (!assignmentActive && _liveLocationService.isTracking) {
        print('🛑 Dashboard: shift not active → stopping GPS tracking');
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
              content: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Shift ended — GPS tracking stopped'),
                ],
              ),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
      // ─────────────────────────────────────────────────────────────────────

      final guardRole = data["GuardRole"] ?? "Guard";
      final isSupervisor = guardRole.toLowerCase() == "supervisor";

      bool hasShiftToday = data["hasShiftToday"] == true;
      String shiftTime = "No shift today";

      DateTime? startDateTime;
      DateTime? endDateTime;
      String formattedHours = "0h";
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_assignment_id');
      await prefs.remove('assignmentId');

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
          shiftDate.year,
          shiftDate.month,
          shiftDate.day,
          int.parse(startParts[0]),
          int.parse(startParts[1]),
        );

        endDateTime = DateTime.utc(
          shiftDate.year,
          shiftDate.month,
          shiftDate.day,
          int.parse(endParts[0]),
          int.parse(endParts[1]),
        );

        _shiftStartDateTime = startDateTime;
        _shiftEndDateTime = endDateTime;

        shiftTime = "$start - $end";

        Duration shiftDuration = endDateTime!.difference(startDateTime!);
        double hours = shiftDuration.inMinutes / 60;
        formattedHours = hours >= 1
            ? "${hours.toStringAsFixed(1)}h"
            : "${shiftDuration.inMinutes} min";

        await prefs.setInt('assignmentId', data["assignmentId"]);
        _hasAssignment = prefs.getInt('assignmentId') != null;
        await prefs.setInt('active_assignment_id', data["assignmentId"]);
        await prefs.setInt('active_guard_id', prefs.getInt('userId')!);
        await prefs.setBool('shift_active', data["Active"] == true);

        await _restoreLiveTrackingIfNeeded();
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

  // ─────────────────────────────────────────────────────────────────────────
  // Time helpers
  // ─────────────────────────────────────────────────────────────────────────

  DateTime getHawaiiTime() {
    final nowUtc = DateTime.now().toUtc();
    return nowUtc.subtract(const Duration(hours: 10));
  }

  DateTime parseHawaiiTime(String timeStr) {
    final parts = timeStr.split(":");
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  DateTime parseServerTime(String serverTimeStr) {
    String cleaned = serverTimeStr.split('[')[0];
    return DateTime.parse(cleaned);
  }

  DateTime parseServerTimeHawaii(String serverTimeStr) {
    final utcTime = DateTime.parse(serverTimeStr.split('[')[0]);
    return utcTime.subtract(const Duration(hours: 10));
  }

  Future<DateTime?> _fetchServerTime() async {
    try {
      final apiService = ApiService();
      final response = await apiService.get("auth/server-time");
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final serverTimeStr = data["now"];
        return parseServerTime(serverTimeStr);
      } else {
        debugPrint("Failed to fetch server time: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      debugPrint("Error fetching server time: $e");
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Shift button logic
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _updateShiftButtons() async {
    if (_shiftStartDateTime == null || _shiftEndDateTime == null) {
      debugPrint("Shift times not loaded yet");
      return;
    }
    DateTime now =
    DateTime.now().toUtc().subtract(const Duration(hours: 10));

    final serverTime = await _fetchServerTime();
    if (serverTime != null) {
      now = serverTime.subtract(const Duration(hours: 10));
    }

    debugPrint("NOW: $now");

    final startWindow =
    _shiftStartDateTime!.subtract(const Duration(minutes: 15));
    debugPrint("SHIFT START: $_shiftStartDateTime");
    debugPrint("SHIFT END: $_shiftEndDateTime");
    debugPrint("START WINDOW: $startWindow");
    debugPrint("ASSIGNMENT ACTIVE: $_assignmentActive");

    setState(() {
      _canStartShift = !_assignmentActive &&
          now.isAfter(startWindow) &&
          now.isBefore(
              _shiftEndDateTime!.add(const Duration(minutes: 5)));

      _canStopShift = _assignmentActive &&
          (now.isAfter(_shiftEndDateTime!) ||
              now.isAtSameMomentAs(_shiftEndDateTime!));
    });

    debugPrint("CAN START SHIFT: $_canStartShift");
    debugPrint("CAN STOP SHIFT: $_canStopShift");
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Emergency
  // ─────────────────────────────────────────────────────────────────────────

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
      final response =
      await apiService.post("emergency/trigger/$guardId", {});

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
          SnackBar(
            content:
            Text(data['error'] ?? "Failed to send emergency alert"),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error sending emergency alert: $e")),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Start / Stop shift
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _startShift() async {
    // ── Step 1: ensure location permission is sufficient ──────────────────
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
          const SnackBar(
              content: Text("Assignment or Guard ID not found")),
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

      print("📍 LAT: ${_currentPosition!.latitude}");
      print("📍 LON: ${_currentPosition!.longitude}");
      print("🎯 ACCURACY (m): ${_currentPosition!.accuracy}");

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
          SnackBar(
              content:
              Text(data['error'] ?? "Failed to start shift")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error starting shift: $e")),
      );
    }
  }

  Future<void> _stopShift() async {
    print('🛑 Stopping location tracking...');
    _liveLocationService.stopTracking();

    if (!_liveLocationService.isTracking) {
      print('✅ Location tracking stopped successfully');
    } else {
      print('⚠️ Warning: Location tracking may still be active');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('shift_active', false);
    await prefs.remove('shift_active');
    await prefs.remove('active_assignment_id');
    await prefs.remove('active_guard_id');

    setState(() {
      _assignmentActive = false;
      _shiftEnded = true;
      _shiftStarted = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('Shift ended - GPS tracking stopped'),
          ],
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Permissions & position
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _requestAllPermissions() async {
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) print('Camera permission denied');

    final photosStatus = await Permission.photos.request();
    if (!photosStatus.isGranted) print('Photos permission denied');

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) print('Microphone permission denied');
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

  /// Correct iOS + Android location permission flow:
  ///
  /// iOS sequence:
  ///   denied → request() → shows "While Using / Don't Allow" system dialog
  ///   whileInUse → request() again → shows "Change to Always Allow" banner
  ///   always → good to go
  ///   deniedForever → only then send to Settings
  ///
  /// Android: same but "always" is a separate runtime permission after
  ///   "while using" is granted.
  Future<bool> _ensureLocationPermission() async {
    // 1. Check location service is on
    final bool serviceEnabled =
    await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Please turn on Location Services in Settings')),
        );
      }
      await Geolocator.openLocationSettings();
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    // 2. Never asked before → request (shows system dialog)
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // 3. User hit "Don't Allow" permanently → send to Settings
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Location Permission Required'),
            content: const Text(
              'Location access was permanently denied. '
                  'Please open Settings → Privacy & Security → Location Services '
                  '→ [App Name] and select "Always".',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
      return false;
    }

    // 4. "While Using" granted → ask for "Always" (iOS shows upgrade banner;
    //    Android shows a separate system dialog)
    if (permission == LocationPermission.whileInUse) {
      if (Platform.isIOS) {
        // Show explanation before the system upgrade banner appears
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.location_on, color: Color(0xFF4F46E5)),
                SizedBox(width: 8),
                Text('Background Location'),
              ],
            ),
            content: const Text(
              'To track your patrol while the app is in the background, '
                  'please select "Always" on the next screen.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not Now'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
        if (proceed != true) {
          // "While Using" is still acceptable — tracking works in foreground
          return true;
        }
      }
      // This call triggers the iOS "Change to Always Allow" banner
      // or the Android background-location dialog
      permission = await Geolocator.requestPermission();
    }

    // 5. Final check — "always" is ideal; "whileInUse" is acceptable fallback
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      return true;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permission is required to start a shift.'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return false;
  }

  /// Used by _restoreLiveTrackingIfNeeded (silent check, no UI dialogs)
  Future<bool> _handleLocationPermission() async {
    final bool serviceEnabled =
    await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Navigation
  // ─────────────────────────────────────────────────────────────────────────

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

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
      body: _screens[_selectedIndex](),
      bottomNavigationBar: CustomNavbar(
        onItemTapped: _onItemTapped,
        selectedIndex: _selectedIndex,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Map & supervisor modals
  // ─────────────────────────────────────────────────────────────────────────

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
            Text(
              "Supervisor Info",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _textColor,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Name: ${_supervisorName ?? "N/A"}",
                style: TextStyle(color: _textColor)),
            const SizedBox(height: 8),
            Text("Email: ${_supervisorEmail ?? "N/A"}",
                style: TextStyle(color: _textColor)),
            const SizedBox(height: 8),
            Text("Phone: ${_supervisorPhone ?? "N/A"}",
                style: TextStyle(color: _textColor)),
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
            Text(
              "Emergency Alert",
              style: TextStyle(
                color: _textColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          "Emergency signal will be sent to security control center. Are you sure you want to proceed?",
          style: TextStyle(color: _secondaryTextColor, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Cancel",
              style:
              TextStyle(color: _secondaryTextColor, fontSize: 16),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _sendEmergencyAlert();
              setState(() {
                _isEmergencyActive = true;
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
            ),
            child: const Text(
              "Confirm",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Dashboard UI
  // ─────────────────────────────────────────────────────────────────────────

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
              // Header card
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
                            _guardName.isEmpty
                                ? "Loading..."
                                : _guardName,
                            style: TextStyle(
                              color: _textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981)
                                  .withOpacity(0.1),
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
                                Text(
                                  _guardRole,
                                  style: TextStyle(
                                    color: _textColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4F46E5)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.access_time,
                                    size: 14,
                                    color: Color(0xFF4F46E5)),
                                const SizedBox(width: 6),
                                Text(
                                  _shiftTime,
                                  style: TextStyle(
                                    color: _textColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
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

              // Stats row
              Row(
                children: [
                  Expanded(
                    child: _buildSimpleStatCard(
                      _hoursToday,
                      "Hours Today",
                      Icons.timer,
                      const Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSimpleStatCard(
                      "",
                      "Supervisor",
                      Icons.person_outline,
                      const Color(0xFF3B82F6),
                      onTap: (_hasShiftToday && _supervisorName != null)
                          ? _showSupervisorModal
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSimpleStatCard(
                      "",
                      "Open Site Map",
                      Icons.map,
                      const Color(0xFF10B981),
                      onTap:
                      _hasAssignment ? _openSiteOnMap : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Emergency button
              GestureDetector(
                onTap: (_shiftStarted && !_shiftEnded)
                    ? _toggleEmergency
                    : null,
                child: Opacity(
                  opacity:
                  (_shiftStarted && !_shiftEnded) ? 1.0 : 0.4,
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
                          offset: const Offset(0, 4),
                        ),
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
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
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
                                  color: Colors.white,
                                ),
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
                                  color:
                                  Colors.white.withOpacity(0.9),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward,
                            color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Start / Stop shift button
              if (_hasShiftToday && !_shiftEnded)
                GestureDetector(
                  onTap: _canStartShift
                      ? _startShift
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
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  _shiftStarted
                                      ? "Available at shift end"
                                      : "Available 20 minutes before start",
                                  style: TextStyle(
                                    color:
                                    Colors.white.withOpacity(0.9),
                                    fontSize: 12,
                                  ),
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

              // Quick Actions
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  "Quick Actions",
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildSimpleActionButton(
                          Icons.beach_access,
                          "Vacation\nRequest",
                          const Color(0xFF3B82F6),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSimpleActionButton(
                          Icons.access_time_filled,
                          "Available\nShifts",
                          const Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_isSupervisor)
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildSimpleActionButton(
                                Icons.message_outlined,
                                "Counseling\nStatements",
                                const Color(0xFFF59E0B),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildSimpleActionButton(
                                Icons.report,
                                "New Counseling\nReport",
                                const Color(0xFFEF4444),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSimpleActionButton(
                          Icons.support_agent,
                          "Dispatch\nContacts",
                          const Color(0xFF8B5CF6),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSimpleActionButton(
                          Icons.settings_outlined,
                          "Settings\n& Profile",
                          const Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 90),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Widget helpers
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSimpleStatCard(
      String value,
      String label,
      IconData icon,
      Color color, {
        VoidCallback? onTap,
      }) {
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
                    child: Text(
                      value,
                      style: TextStyle(
                        color: _textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: _secondaryTextColor,
                fontSize: 12,
              ),
            ),
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
          _onItemTapped(5);
        } else if (label.contains("Shifts")) {
          _onItemTapped(6);
        } else if (label.contains("Dispatch")) {
          _onItemTapped(7);
        } else if (label.contains("Counseling\nStatements")) {
          _onItemTapped(8);
        } else if (label.contains("New Counseling\nReport")) {
          _onItemTapped(9);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("$label clicked!"),
              backgroundColor: _cardColor,
            ),
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
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}