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
import 'package:crossplatformblackfabric/screens/no_call_no_show_page.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:crossplatformblackfabric/screens/Late_Arrivals_page.dart';
import 'package:crossplatformblackfabric/screens/supervisor_assignments_page.dart';
import 'package:crossplatformblackfabric/screens/supervisor_live_map_page.dart';
import 'package:crossplatformblackfabric/screens/supervisor_attendance_page.dart';
import 'package:crossplatformblackfabric/screens/guard_sop_page.dart';
import 'package:crossplatformblackfabric/screens/admin_sop_page.dart';
import 'package:crossplatformblackfabric/screens/employee_handbook_page.dart';
import 'package:crossplatformblackfabric/screens/guard_schedule_page.dart';

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
  DateTime? _shiftStopDateTime; // ✅ for overnight: today's date + endTime (no +1 day)
  String _sessionFromDate = "";
  String _sessionToDate = "";
  double? _siteLat;
  double? _siteLng;
  String _siteName = "";
  int? _siteId;
  String _hoursToday = "0h";
  String? _supervisorName;
  String? _supervisorEmail;
  String? _supervisorPhone;
  String? _shiftInstructions;

  late LiveLocationService _liveLocationService;

  Timer? _dashboardRefreshTimer;
  Timer? _shiftButtonUpdateTimer;

  bool _canStartShift = false;
  bool _canStopShift = false;
  bool _shiftStarted = false;
  bool _shiftEnded = false;
  bool _isStartingShift = false; // blocks double-tap while API call is in flight

  // ── Unread chat badge ──────────────────────────────────────────
  int _unreadChatCount = 0;
  StreamSubscription<ChatMessage>? _chatBadgeSub;

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
    "No Call No Show",
  ];

  Position? _currentPosition;
  bool _tracking = false;
  bool _isEmergencyActive = false;
  bool _isSendingEmergency = false;   // prevents double-tap / duplicate sends
  bool _assignmentActive = false;

  bool _isLocationDialogVisible = false;
  final _locationDialogKey = GlobalKey();
  BuildContext? _locationDialogContext;

  bool get _canManageNoCallNoShow {
    final role = _guardRole.toLowerCase();
    return role == "supervisor" ||
        role == "regular admin" ||
        role == "full admin" ||
        role == "admin";
  }

  // ── DEBUG LOG OVERLAY ────────────────────────────────────────────────────────
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

    // ─────────────────────────────────────────────────────────────────────────

    _liveLocationService.onShiftEndedRemotely = () {
      if (!mounted) return;
      setState(() {
        _shiftStarted = false;
        _shiftEnded = false; // ✅ FIX: let _updateShiftButtons control button visibility
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
      await Future.delayed(const Duration(milliseconds: 500));
      await _enforceAlwaysPermission();
    });

    // NOTE: removed the old 1-second delayed _restoreLiveTrackingIfNeeded call.
    // It was broken because _hasShiftToday=false at that point.
    // _loadDashboard now calls _restoreLiveTrackingIfNeeded with an override.

    _loadDashboard();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('userId');
      if (userId != null) {
        ChatService().connect(userId);
        // Initial unread count fetch
        _refreshUnreadChatCount();
        // Listen for incoming messages and refresh the badge in real time
        _chatBadgeSub = ChatService().messageStream.listen((msg) async {
          final p = await SharedPreferences.getInstance();
          final myId = p.getInt('userId');
          // Only bump badge when message is for me and chat tab is not open
          if (myId != null && msg.receiverId == myId && _selectedIndex != 2) {
            _refreshUnreadChatCount();
          }
        });
      }
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
              () => const NoCallNoShowPage(),
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
    _chatBadgeSub?.cancel();
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
    while (true) {
      final permission = await Geolocator.checkPermission();
      final bool granted = permission == LocationPermission.always ||
          (Platform.isIOS && permission == LocationPermission.whileInUse);
      if (granted) return;

      await _showLocationBlockDialog(
        title: 'Location Set to "Always" Required',
        message:
        'This app requires location access set to "Always" for shift tracking '
            'and safety monitoring.\n\n'
            'Go to Settings → [App] → Location → select "Always".',
        buttonLabel: 'Open Settings',
        onTap: () => openAppSettings(),
      );
      await Future.delayed(const Duration(milliseconds: 300));
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
            _shiftEnded = false; // ✅ FIX: don't hide the button — let _updateShiftButtons decide based on time
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
      String parsedFromDate = "";
      String parsedToDate = "";
      String? parsedInstructions;
      final prefs = await SharedPreferences.getInstance();

      // FIX 3: only wipe keys when no shift today. Previously wiped every 30s
      // unconditionally, before the shift block could write them back.
      if (!hasShiftToday) {
        await prefs.remove('active_assignment_id');
        await prefs.remove('assignmentId');
        await prefs.remove('sessionId');
      }

      if (hasShiftToday && data["shift"] != null) {
        final start = data["shift"]["startTime"];
        final end = data["shift"]["endTime"];
        final site = data["site"];
        if (site != null) {
          _siteLat = site["latitude"];
          _siteLng = site["longitude"];
          _siteName = site["name"] ?? "Site";
          _siteId = site["id"] is int ? site["id"] : int.tryParse(site["id"].toString());
          _supervisorName = site["supervisorname"];
          _supervisorEmail = site["supervisoremail"];
          _supervisorPhone = site["supervisornumber"];
        }

        final rawInstructions = data["shift"]["specialInstructions"];
        parsedInstructions = (rawInstructions != null && rawInstructions.toString().trim().isNotEmpty)
            ? rawInstructions.toString().trim()
            : null;

        final shiftDateStr = data["date"];           // session START date from backend
        final sessionEndDateStr = data["sessionEndDate"]; // session END date from backend
        final shiftDate = DateTime.parse(shiftDateStr);
        final sessionEndDate = sessionEndDateStr != null
            ? DateTime.parse(sessionEndDateStr as String)
            : shiftDate;
        String fmtDate(DateTime d) => "${d.month.toString().padLeft(2,"0")}/${d.day.toString().padLeft(2,"0")}/${d.year}";
        parsedFromDate = fmtDate(shiftDate);
        parsedToDate = fmtDate(sessionEndDate);
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

        // endDateTime = used for shift hours display and start window check
        endDateTime = DateTime.utc(
          shiftDate.year, shiftDate.month, shiftDate.day, endHour, endMin,
        );
        if (isOvernightShift) {
          endDateTime = endDateTime!.add(const Duration(days: 1));
        }

        _shiftStartDateTime = startDateTime;
        _shiftEndDateTime = endDateTime;

        // ✅ FIX: stopDateTime uses sessionEndDate from backend
        // Backend already knows if we're on the after-midnight side and sends
        // the correct end date (today vs tomorrow)
        _shiftStopDateTime = DateTime.utc(
          sessionEndDate.year, sessionEndDate.month, sessionEndDate.day,
          endHour, endMin,
        );

        shiftTime = "${_toAmPm(start)} - ${_toAmPm(end)}";

        debugPrint("📅 [Dashboard] sessionStartDate   : $shiftDateStr");
        debugPrint("📅 [Dashboard] sessionEndDate     : $sessionEndDateStr");
        debugPrint("📅 [Dashboard] startTime from API : $start");
        debugPrint("📅 [Dashboard] endTime from API   : $end");
        debugPrint("📅 [Dashboard] isOvernightShift   : $isOvernightShift");
        debugPrint("📅 [Dashboard] startDateTime built: $startDateTime");
        debugPrint("📅 [Dashboard] stopDateTime built : $_shiftStopDateTime");
        debugPrint("📅 [Dashboard] Active from API    : ${data["Active"]}");

        final totalMins = endDateTime!.difference(startDateTime!).inMinutes;
        final h = totalMins ~/ 60;
        final m = totalMins % 60;
        formattedHours = h > 0 ? "${h}h ${m}m" : "${m}m";

        await prefs.setInt('assignmentId', data["assignmentId"]);
        _hasAssignment = prefs.getInt('assignmentId') != null;
        await prefs.setInt('active_assignment_id', data["assignmentId"]);
        if (data["sessionId"] is int) {
          await prefs.setInt('sessionId', data["sessionId"]);
        }
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
        if (hasShiftToday) {
          _sessionFromDate = parsedFromDate;
          _sessionToDate = parsedToDate;
          _shiftInstructions = parsedInstructions;
        } else {
          _shiftInstructions = null;
        }
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
    if (_shiftStartDateTime == null || _shiftEndDateTime == null) {
      debugPrint("⛔ [ShiftButtons] Skipping — shiftStart or shiftEnd is null");
      return;
    }

    DateTime now = DateTime.now().toUtc().subtract(const Duration(hours: 10));
    debugPrint("🕐 [ShiftButtons] local fallback now (UTC-10): $now");

    final serverTime = await _fetchServerTime();
    if (serverTime != null) {
      debugPrint("🌐 [ShiftButtons] raw serverTime from API: $serverTime");
      now = serverTime.subtract(const Duration(hours: 10));
      debugPrint("🕐 [ShiftButtons] now after -10h from server: $now");
    } else {
      debugPrint("⚠️ [ShiftButtons] serverTime is null, using local fallback");
    }

    final startWindow = _shiftStartDateTime!.subtract(const Duration(minutes: 15));

    debugPrint("📋 [ShiftButtons] _shiftStartDateTime : $_shiftStartDateTime (isUtc=${_shiftStartDateTime!.isUtc})");
    debugPrint("📋 [ShiftButtons] _shiftEndDateTime   : $_shiftEndDateTime (isUtc=${_shiftEndDateTime!.isUtc})");
    debugPrint("📋 [ShiftButtons] _shiftStopDateTime  : $_shiftStopDateTime");
    debugPrint("📋 [ShiftButtons] startWindow (-15min): $startWindow");
    debugPrint("📋 [ShiftButtons] now                 : $now");
    debugPrint("📋 [ShiftButtons] _assignmentActive   : $_assignmentActive");

    final canStart = !_assignmentActive &&
        now.isAfter(startWindow) &&
        now.isBefore(_shiftEndDateTime!.add(const Duration(minutes: 5)));

    final canStop = _assignmentActive &&
        _shiftStopDateTime != null &&
        (now.isAfter(_shiftStopDateTime!) ||
            now.isAtSameMomentAs(_shiftStopDateTime!));

    debugPrint("✅ [ShiftButtons] canStart=$canStart  canStop=$canStop");
    debugPrint("   └─ !_assignmentActive=${!_assignmentActive}");
    debugPrint("   └─ now.isAfter(startWindow)=${now.isAfter(startWindow)}");
    debugPrint("   └─ now.isBefore(endTime+5min)=${now.isBefore(_shiftEndDateTime!.add(const Duration(minutes: 5)))}");
    debugPrint("   └─ now.isAfter(stopTime)=${_shiftStopDateTime != null ? now.isAfter(_shiftStopDateTime!) : 'stopTime null'}");

    setState(() {
      _canStartShift = canStart;
      _canStopShift = canStop;
    });
  }

  Future<void> _sendEmergencyAlert() async {
    // Hard guard — prevents any second call while first is in flight
    if (_isSendingEmergency || _isEmergencyActive) return;
    setState(() {
      _isSendingEmergency = true;
      _isEmergencyActive  = true;   // flip immediately so UI blocks re-taps
    });
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
    } finally {
      if (mounted) setState(() => _isSendingEmergency = false);
    }
  }

  Future<void> _startShift() async {
    if (_isStartingShift) return; // guard against double-tap
    setState(() => _isStartingShift = true);

    final bool hasPermission = await _ensureLocationPermission();
    if (!hasPermission) {
      setState(() => _isStartingShift = false);
      return;
    }

    await _getCurrentPosition();
    if (_currentPosition == null) {
      if (mounted) setState(() => _isStartingShift = false);
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
        if (mounted) setState(() => _isStartingShift = false);
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
          _isStartingShift = false;
        });

        await ShiftService().startAssignment(assignmentId);
        _liveLocationService.startTracking(guardId, assignmentId);

        await prefs.setBool('shift_active', true);
        await prefs.setInt('active_assignment_id', assignmentId);
        await prefs.setInt('active_guard_id', guardId);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Shift started successfully!")),
        );
      } else {
        final data = jsonDecode(response.body);
        if (mounted) setState(() => _isStartingShift = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error'] ?? "Failed to start shift")),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isStartingShift = false);
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
        await prefs.remove('assignmentId');
        await prefs.remove('sessionId');

        setState(() {
          _assignmentActive = false;
          _shiftEnded = false; // ✅ let _loadDashboard + _updateShiftButtons control visibility
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

        // ✅ Reload dashboard so next session's START button appears immediately
        await _loadDashboard();
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

    if (permission == LocationPermission.always) return true;

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

    _isLocationDialogVisible = false;
    _locationDialogContext = null;
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
      // Clear the unread badge when the user opens the chat tab
      if (index == 2) _unreadChatCount = 0;
    });
  }

  Future<void> _refreshUnreadChatCount() async {
    final count = await ChatService().getUnreadCount();
    if (mounted) setState(() => _unreadChatCount = count);
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



        ],
      ),
      bottomNavigationBar: CustomNavbar(
        onItemTapped: _onItemTapped,
        selectedIndex: _selectedIndex,
        unreadChatCount: _unreadChatCount,
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
    final Uri url;
    if (Platform.isIOS) {
      // q= drops a pin; ll= centers the map
      url = Uri.parse('https://maps.apple.com/?q=$_siteLat,$_siteLng&ll=$_siteLat,$_siteLng&z=15');
    } else {
      // Google Maps web URL — always drops a pin at the given coordinates
      url = Uri.parse('https://maps.google.com/maps?q=$_siteLat,$_siteLng');
    }
    await launchUrl(url, mode: LaunchMode.externalApplication);
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
    // Block if already sending or already active
    if (_isSendingEmergency || _isEmergencyActive) return;
    bool _confirmed = false;   // local flag — blocks dialog button double-tap
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
              if (_confirmed) return;
              _confirmed = true;
              Navigator.pop(context);
              await _sendEmergencyAlert();
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
                          if (_hasShiftToday && _sessionFromDate.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_today,
                                      size: 14, color: Color(0xFFF59E0B)),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text("$_sessionFromDate → $_sessionToDate",
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: _textColor,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                            ),
                          ],
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

              const SizedBox(height: 16),

              if (_hasShiftToday && !_shiftEnded)
                GestureDetector(
                  onTap: (_canStartShift && !_isStartingShift)
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
                    (_isStartingShift || _canStartShift || _canStopShift) ? 1.0 : 0.4,
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
                          _isStartingShift
                              ? const SizedBox(
                                  width: 28, height: 28,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ))
                              : Icon(
                                  _shiftStarted ? Icons.stop : Icons.play_arrow,
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
                                  _isStartingShift
                                      ? "STARTING SHIFT..."
                                      : (_shiftStarted ? "STOP SHIFT" : "START SHIFT"),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  _isStartingShift
                                      ? "Please wait..."
                                      : (_shiftStarted
                                          ? "Available at shift end"
                                          : "Available 20 minutes before start"),
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

              const SizedBox(height: 16),

              // ── Shift Instructions Box ──────────────────────────────────
              if (_hasShiftToday)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: _shiftInstructions != null
                        ? const Color(0xFFFEF3C7)
                        : (_isDarkMode ? const Color(0xFF374151) : const Color(0xFFF3F4F6)),
                    border: Border.all(
                      color: _shiftInstructions != null
                          ? const Color(0xFFF59E0B)
                          : (_isDarkMode ? const Color(0xFF4B5563) : const Color(0xFFD1D5DB)),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _shiftInstructions != null ? Icons.info_outline : Icons.check_circle_outline,
                        color: _shiftInstructions != null ? const Color(0xFFD97706) : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Shift Instructions",
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: _shiftInstructions != null
                                    ? const Color(0xFF92400E)
                                    : (_isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _shiftInstructions ?? "No special instructions",
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: _shiftInstructions != null
                                    ? const Color(0xFF78350F)
                                    : (_isDarkMode ? Colors.grey[500] : Colors.grey[500]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GuardSchedulePage()),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF06B6D4).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF06B6D4).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF06B6D4).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.calendar_month_outlined,
                            color: Color(0xFF06B6D4), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'My Schedule',
                              style: TextStyle(
                                  color: _textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                            Text(
                              'All assignments, sites, and supervisor contacts',
                              style: TextStyle(
                                  color: _secondaryTextColor,
                                  fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios,
                          size: 14, color: Color(0xFF06B6D4)),
                    ],
                  ),
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

              if (_canManageNoCallNoShow) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildSimpleActionButton(
                        Icons.event_busy_rounded,
                        "No Call\nNo Show",
                        const Color(0xFFF97316),
                      ),
                    ),
                  ],
                ),
              ],

              
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildSimpleActionButton(
                        Icons.assignment_outlined,
                        "Assignments",
                        const Color(0xFF06B6D4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSimpleActionButton(
                        Icons.map_outlined,
                        "Live Map",
                        const Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSimpleActionButton(
                        Icons.history,
                        "Attendance",
                        const Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
              ],

              // SOP button — guards (active shift only) and supervisors/admins
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  if (_isSupervisor) {
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const AdminSopPage()));
                  } else {
                    if (!_hasShiftToday || _siteId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('SOP is only available during an active shift.'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => GuardSopPage(
                                siteId: _siteId!,
                                siteName: _siteName)));
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: const Color(0xFF6366F1).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.menu_book_outlined,
                            color: Color(0xFF6366F1), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "SOP",
                              style: TextStyle(
                                  color: _textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                            Text(
                              "Standard Operating Procedure",
                              style: TextStyle(
                                  color: _secondaryTextColor,
                                  fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios,
                          size: 14, color: Color(0xFF6366F1)),
                    ],
                  ),
                ),
              ),

              // ── Employee Handbook — visible to everyone ──────────
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const EmployeeHandbookPage()),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: const Color(0xFF10B981).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.import_contacts_outlined,
                            color: Color(0xFF10B981), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Employee Handbook',
                              style: TextStyle(
                                  color: _textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                            Text(
                              'Company documents & policies',
                              style: TextStyle(
                                  color: _secondaryTextColor,
                                  fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios,
                          size: 14, color: Color(0xFF10B981)),
                    ],
                  ),
                ),
              ),

              // ── Emergency Alert Button ──────────────────────────────
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _toggleEmergency,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: _isEmergencyActive
                        ? Colors.red.shade700
                        : Colors.red,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isEmergencyActive
                            ? Icons.warning_amber_rounded
                            : Icons.emergency,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _isEmergencyActive
                            ? "EMERGENCY SENT"
                            : "EMERGENCY ALERT",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

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
        } else if (label.contains("No Call\nNo Show")) {
          _onItemTapped(11);
        } else if (label.contains("Assignments")) {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SupervisorAssignmentsPage()));
        } else if (label.contains("Live Map")) {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SupervisorLiveMapPage()));
        } else if (label.contains("Attendance")) {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SupervisorAttendancePage()));
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