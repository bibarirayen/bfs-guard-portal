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

  bool _canStartShift = false;
  bool _canStopShift = false;
  bool _shiftStarted = false;
  bool _shiftEnded = false;


  late final List<Widget Function()> _screens;
  bool _isDarkMode = true;
  final List<String> _titles = [
    "Dashboard",          // 0
    "Reports",            // 1
    "New Report",         // 2
    "Patrols",            // 4
    "Profile",
    "Vacation Requests",  // 3
    "Shifts",
    "Dispatch Contacts",
    "Counseling List",
    "New Counseling Report"

  ];
  // GPS tracking variables
  Position? _currentPosition;
  bool _tracking = false;
  bool _isEmergencyActive = false;
  Future<void> _restoreLiveTrackingIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();

    final isShiftActive = prefs.getBool('shift_active') ?? false;
    final assignmentId = prefs.getInt('active_assignment_id');
    final guardId = prefs.getInt('active_guard_id');

    print("🔁 RESTORE CHECK");
    print("shift_active = $isShiftActive");
    print("assignmentId = $assignmentId");
    print("guardId = $guardId");

    if (!isShiftActive || !_hasShiftToday || assignmentId == null || guardId == null) {
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
  DateTime getHawaiiTime() {
    // Current UTC time
    final nowUtc = DateTime.now().toUtc();

    // Hawaii is UTC-10
    return nowUtc.subtract(Duration(hours: 10));
  }
  DateTime parseHawaiiTime(String timeStr) {
    final parts = timeStr.split(":");
    final now = DateTime.now(); // local date
    // create Hawaii time as a local DateTime
    return DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
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

      final apiService = ApiService(); // your existing ApiService

      final response = await apiService.post(
        "emergency/trigger/$guardId",
        {}, // no body required
      );

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
            content: Text(data['error'] ?? "Failed to send emergency alert"),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error sending emergency alert: $e"),
        ),
      );
    }
  }



  // Theme colors
  Color get _backgroundColor => _isDarkMode ? Color(0xFF0F172A) : Color(0xFFF8FAFC);
  Color get _textColor => _isDarkMode ? Colors.white : Color(0xFF1E293B);
  Color get _cardColor => _isDarkMode ? Color(0xFF1E293B) : Colors.white;
  Color get _borderColor => _isDarkMode ? Color(0xFF334155) : Color(0xFFE2E8F0);
  Color get _secondaryTextColor => _isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
  bool _assignmentActive = false;

  @override
  void initState() {
    super.initState();
    Future<void> _requestNotificationPermission() async {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    }

    _requestNotificationPermission();

    _liveLocationService = LiveLocationService(); // ✅ Initialize here
    _requestAllPermissions();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(seconds: 1)); // 🔥 IMPORTANT
      await _restoreLiveTrackingIfNeeded();
    });

    _loadDashboard();
    _screens = [
          () => _buildDashboard(), // 🔥 dynamic
          () => const ReportListPage(),
          () => const ReportPage(),
          () => TrajectListPage(),
          () => const ProfileScreen(),
          () => const VacationRequestPage(),
          () => const ShiftsPage(),
          () => const DispatchContactsPage(), // ✅ NEW (index 7)
          () => const CounselingListPage(),   // 8 ✅ NEW
          () => const CounselingUploadPage(), // 9 ✅ NEW
    ];


    Timer.periodic(const Duration(minutes: 1), (_) {
      _updateShiftButtons();
    });

  }
  Future<void> _loadDashboard() async {
    try {
      final dashboardService = DashboardService();
      final data = await dashboardService.getDashboardMobile();
      // ✅ Extract data BEFORE setState
      final guardName = data["GuardName"] ?? "Unknown Guard";
      final bool assignmentActive = data["Active"] == true;
      if (!assignmentActive) {
        _liveLocationService.stopTracking();
      }

      final guardRole = data["GuardRole"] ?? "Guard";
      final isSupervisor = guardRole.toLowerCase() == "supervisor";

      bool hasShiftToday = data["hasShiftToday"] == true;
      String shiftTime = "No shift today";
      if (!hasShiftToday) {
        print("🚫 No shift today — stopping tracking");

        _liveLocationService.stopTracking();

        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('shift_active');
        await prefs.remove('active_assignment_id');
        await prefs.remove('active_guard_id');

        setState(() {
          _assignmentActive = false;
          _shiftStarted = false;
          _shiftEnded = false;
        });
      }

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
          final shiftDateStr = data["date"]; // "2026-02-08"
          final shiftDate = DateTime.parse(shiftDateStr); // parses YYYY-MM-DD

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

  // hours in decimal (ex: 0.92h)
          double hours = shiftDuration.inMinutes / 60;

  // format nicely
          formattedHours= hours >= 1
              ? "${hours.toStringAsFixed(1)}h"
              : "${shiftDuration.inMinutes} min";

          await prefs.setInt('assignmentId', data["assignmentId"]);
          _hasAssignment = prefs.getInt('assignmentId') != null;
          await prefs.setInt('active_assignment_id', data["assignmentId"]);
          await prefs.setInt('active_guard_id', prefs.getInt('userId')!); // guardId
          await prefs.setBool('shift_active', data["Active"] == true); // if shift active

  // now restore tracking
          await _restoreLiveTrackingIfNeeded();

      }

      // ✅ ONLY sync code inside setState
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
        _hoursToday = formattedHours; // ✅ ADD THIS
        _hasAssignment = prefs.getInt('assignmentId') != null; // ✅

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
  DateTime parseServerTime(String serverTimeStr) {
    // Remove any [TimeZone] if present
    String cleaned = serverTimeStr.split('[')[0];
    return DateTime.parse(cleaned);
  }
  DateTime parseServerTimeHawaii(String serverTimeStr) {
    final utcTime = DateTime.parse(serverTimeStr.split('[')[0]);
    return utcTime.subtract(const Duration(hours: 10)); // Hawaii UTC-10
  }


  Future<DateTime?> _fetchServerTime() async {
    try {
      final apiService = ApiService();
      final response = await apiService.get("auth/server-time"); // matches your /server-time endpoint
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

  Future<void> _updateShiftButtons() async {


    if (_shiftStartDateTime == null || _shiftEndDateTime == null) {
      debugPrint("Shift times not loaded yet");
      return;
    }
    DateTime now = DateTime.now().toUtc().subtract(const Duration(hours: 10)); // fallback

    final serverTime = await _fetchServerTime();
    if (serverTime != null) {
      now = serverTime.subtract(const Duration(hours: 10)); // convert UTC -> Hawaii
    }

// Then convert it back to UTC for comparison
    debugPrint("NOW: $now");

    final startWindow = _shiftStartDateTime!.subtract(const Duration(minutes: 15));    debugPrint("SHIFT START: $_shiftStartDateTime");
    debugPrint("SHIFT END: $_shiftEndDateTime");
    debugPrint("START WINDOW: $startWindow");
    debugPrint("ASSIGNMENT ACTIVE: $_assignmentActive");
    debugPrint("CAN START SHIFT: $_canStartShift");
    setState(() {
      // START SHIFT (only if NOT active)
      _canStartShift =
          !_assignmentActive &&
              now.isAfter(startWindow) &&
              now.isBefore(_shiftEndDateTime!.add(const Duration(minutes: 5)));

      // STOP SHIFT (only if active AND end time reached)
      _canStopShift =
          _assignmentActive &&
              (now.isAfter(_shiftEndDateTime!) ||
                  now.isAtSameMomentAs(_shiftEndDateTime!));
    });
    debugPrint("CAN START SHIFT: $_canStartShift");
    debugPrint("CAN STOP SHIFT: $_canStopShift");
  }


  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
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
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 12),
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
          style: TextStyle(
            color: _secondaryTextColor,
            fontSize: 16,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Cancel",
              style: TextStyle(color: _secondaryTextColor, fontSize: 16),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // close dialog first
              await _sendEmergencyAlert(); // call backend
              setState(() {
                _isEmergencyActive = true;
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text(
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


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: CustomAppBar(
        title: _titles[_selectedIndex],  // <-- dynamic title now
        isDarkMode: _isDarkMode,
        onThemeChanged: (value) {
          setState(() {
            _isDarkMode = value;   // toggle dark/light mode
          });
        },
      ),

        body: _screens[_selectedIndex](),
      bottomNavigationBar: CustomNavbar(
        onItemTapped: _onItemTapped,
        selectedIndex: _selectedIndex,
      )
    );
  }
  Future<void> _requestAllPermissions() async {
    // Request camera permission
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      print('Camera permission denied');
    }

    // Request photo library permission
    final photosStatus = await Permission.photos.request();
    if (!photosStatus.isGranted) {
      print('Photos permission denied');
    }

    // Request microphone permission (for video recording)
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      print('Microphone permission denied');
    }

    // Notification permission is already requested in main.dart
  }
  Future<void> _getCurrentPosition() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium, // ✅ CHANGE THIS
        timeLimit: const Duration(seconds: 20),    // ✅ INCREASE
      );
      _currentPosition = position;
    } on TimeoutException {
      // ✅ fallback
      _currentPosition = await Geolocator.getLastKnownPosition();
    } catch (e) {
      debugPrint("Error getting current position: $e");
    }
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable location services')),
      );
      await Geolocator.openLocationSettings();
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permanently denied. Please enable it in settings.'),
        ),
      );
      await Geolocator.openAppSettings();
      return false;
    }

    // On iOS, request "Always" permission for background tracking
    if (Platform.isIOS && permission == LocationPermission.whileInUse) {
      // Show explanation dialog first
      final shouldRequest = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Location Access Required'),
          content: const Text(
            'BFS Guard Portal needs "Always Allow" location access to track your position during shifts, even when the app is in the background. This ensures your safety and accurate patrol tracking.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );

      if (shouldRequest != true) return false;

      // On iOS, this will show the system dialog with "Change to Always Allow" option
      permission = await Geolocator.requestPermission();
    }

    if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location access is required for shift tracking.'),
        ),
      );
      return false;
    }

    return true;
  }


  Future<void> _startShift() async {
    bool hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;
    await _getCurrentPosition();
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("GPS location not available"))
      );
        return;
      }


    try {
      final prefs = await SharedPreferences.getInstance();
      final assignmentId = prefs.getInt('assignmentId');
      final guardId = prefs.getInt('userId'); // make sure you save guardId in prefs earlier

      if (assignmentId == null || guardId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Assignment or Guard ID not found"))
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
      print("--------------------------------");
      print(_currentPosition!.latitude);
      print(_currentPosition!.longitude);
      print("--------------------------------");
      print("📍 LAT: ${_currentPosition!.latitude}");
      print("📍 LON: ${_currentPosition!.longitude}");
      print("🎯 ACCURACY (m): ${_currentPosition!.accuracy}");

      if (response.statusCode == 200) {
        setState(() {
          _assignmentActive = true;
          _shiftStarted = true;
          _canStartShift = false;
          _canStopShift = false; // recalculated by timer
        });
        final prefs = await SharedPreferences.getInstance();
        final assignmentId = prefs.getInt('assignmentId')!;
        final guardId = prefs.getInt('userId')!; // make sure guardId is saved
        final response = ShiftService().startAssignment(assignmentId);
        _liveLocationService.startTracking(guardId, assignmentId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Shift started successfully!")),
        );
        await prefs.setBool('shift_active', true);
        await prefs.setInt('active_assignment_id', assignmentId);
        await prefs.setInt('active_guard_id', guardId);

      }

      else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['error'] ?? "Failed to start shift"))
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error starting shift: $e"))
      );
    }
  }


  Future<void> _stopShift() async {
    LiveLocationService().stopTracking();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('shift_active');
    await prefs.remove('active_assignment_id');
    await prefs.remove('active_guard_id');

    setState(() {
      _assignmentActive = false;
      _shiftEnded = true;
    });
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
            Icon(Icons.person, color: Color(0xFF3B82F6)),
            SizedBox(width: 10),
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
            SizedBox(height: 8),
            Text("Email: ${_supervisorEmail ?? "N/A"}",
                style: TextStyle(color: _textColor)),
            SizedBox(height: 8),
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

  Widget _buildDashboard() {
    return SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadDashboard, // this calls your existing async function
          color: Colors.white, // indicator color
          backgroundColor: Color(0xFF4F46E5), // optional background
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(), // important!
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Header ---
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: _cardColor,
                    border: Border.all(color: _borderColor, width: 1),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 35,
                        backgroundColor: Color(0xFF4F46E5).withOpacity(0.1),
                        child: Icon(Icons.person, size: 40, color: Color(0xFF4F46E5)),
                      ),
                      SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _guardName.isEmpty ? "Loading..." : _guardName + " || "+ _guardRole,
                              style: TextStyle(
                                color: _textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 8),

                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Color(0xFF4F46E5).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.access_time, size: 14, color: Color(0xFF4F46E5)),
                                  SizedBox(width: 6),
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

            SizedBox(height: 20),

            // --- Stats Cards ---
            Row(
              children: [
                Expanded(
                  child: _buildSimpleStatCard(
                    _hoursToday,
                    "Hours Today",
                    Icons.timer,
                    Color(0xFF10B981),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _buildSimpleStatCard(
                    "",
                    "Supervisor",
                    Icons.person_outline,
                    Color(0xFF3B82F6),
                    onTap: (_hasShiftToday && _supervisorName != null)
                        ? _showSupervisorModal
                        : null,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _buildSimpleStatCard(
                    "",
                    "Open Site Map",
                    Icons.map,
                    Color(0xFF10B981),
                    onTap: _hasAssignment ? _openSiteOnMap : null, // ✅ disabled if no assignment
                  ),

                ),
              ],
            ),

            SizedBox(height: 20),

            // --- Emergency Button ---
            GestureDetector(
              onTap: (_shiftStarted && !_shiftEnded) ? _toggleEmergency : null,
              child: Opacity(
                opacity: (_shiftStarted && !_shiftEnded) ? 1.0 : 0.4,
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: _hasShiftToday
                        ? (_isEmergencyActive ? Colors.redAccent : Colors.red)
                        : Colors.grey,
                    boxShadow: _hasShiftToday
                        ? [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ]
                        : [],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, size: 28, color: Colors.white),
                      SizedBox(width: 12),
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
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              !_hasShiftToday
                                  ? "Emergency disabled outside shift"
                                  : (_isEmergencyActive
                                  ? "Assistance is on the way"
                                  : "Press for emergency"),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: 16), // ✅ ADD THIS

            if (_hasShiftToday && !_shiftEnded)
              GestureDetector(
                onTap: _canStartShift
                    ? _startShift
                    : _canStopShift
                    ? _stopShift
                    : null,
                child: Opacity(
                  opacity: (_canStartShift || _canStopShift) ? 1.0 : 0.4,
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: _shiftStarted ? Colors.redAccent : Colors.green,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _shiftStarted ? Icons.stop : Icons.play_arrow,
                          color: Colors.white,
                          size: 28,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _shiftStarted ? "STOP SHIFT" : "START SHIFT",
                                style: TextStyle(
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
                                  color: Colors.white.withOpacity(0.9),
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


            SizedBox(height: 25),

            // --- Quick Actions Title ---
            Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                "Quick Actions",
                style: TextStyle(
                  color: _textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            SizedBox(height: 12),

            // --- Grid View - SIMPLE FIX: Use Column with Rows ---
            Column(
              children: [
                // Row 1
                Row(
                  children: [
                    Expanded(
                      child: _buildSimpleActionButton(
                        Icons.beach_access,
                        "Vacation\nRequest",
                        Color(0xFF3B82F6),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _buildSimpleActionButton(
                        Icons.access_time_filled,
                        "Available\nShifts",
                        Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                // Row 2
                if (_isSupervisor)
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildSimpleActionButton(
                              Icons.message_outlined,
                              "Counseling\nStatements",
                              Color(0xFFF59E0B),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: _buildSimpleActionButton(
                              Icons.report,
                              "New Counseling\nReport",
                              Color(0xFFEF4444),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                    ],
                  ),

                SizedBox(height: 12),
                // Row 3
                Row(
                  children: [
                    Expanded(
                      child: _buildSimpleActionButton(
                        Icons.support_agent,
                        "Dispatch\nContacts",
                        Color(0xFF8B5CF6),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _buildSimpleActionButton(
                        Icons.settings_outlined,
                        "Settings\n& Profile",
                        Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            SizedBox(height: 90), // Padding for bottom nav
          ],
        ),
      ),
    ),
    );
  }
// Update the stat card to work with Expanded
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
        padding: EdgeInsets.all(12),
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
                  padding: EdgeInsets.all(6),
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
            SizedBox(height: 8),
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


  Widget _buildSimpleActionButton(IconData icon, String label, Color color) {
    return GestureDetector(
      onTap: () {
        if (label.contains("Vacation")) {
          _onItemTapped(5);
        } else if (label.contains("Shifts")) {
          _onItemTapped(6); // index of ShiftsPage
        } else if (label.contains("Dispatch")) {
          _onItemTapped(7); // ✅ DispatchContactsPage
        } else if (label.contains("Counseling\nStatements")) {
          _onItemTapped(8); // CounselingListPage
        } else if (label.contains("New Counseling\nReport")) {
          _onItemTapped(9); // CounselingUploadPage

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
            padding: EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 22, color: color),
                ),
                SizedBox(height: 8),
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
