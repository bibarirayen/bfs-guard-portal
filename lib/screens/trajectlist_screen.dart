import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../config/ApiService.dart';
import '../models/AssignmentTrajectory.dart';
import '../models/Stop.dart';
import '../models/Trajectory.dart';
import '../models/shift_models.dart';
import '../services/ActiveTrajectManager.dart';
import '../services/shift_service.dart';

class TrajectListPage extends StatefulWidget {
  const TrajectListPage({super.key});

  @override
  State<TrajectListPage> createState() => _TrajectListPageState();
}

class _TrajectListPageState extends State<TrajectListPage> {
  List<AssignmentTrajectory> trajects = [];
  bool isLoading = true;


  bool _isDarkMode = true;

  // Theme colors getters
  Color get backgroundColor => _isDarkMode ? Color(0xFF0F172A) : Color(0xFFF8FAFC);
  Color get textColor => _isDarkMode ? Colors.white : Color(0xFF1E293B);
  Color get cardColor => _isDarkMode ? Color(0xFF1E293B) : Colors.white;
  Color get borderColor => _isDarkMode ? Color(0xFF334155) : Color(0xFFE2E8F0);
  Color get secondaryTextColor => _isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
  Color get iconColor => _isDarkMode ? Color(0xFF64B5F6) : Color(0xFF2196F3);
  Future<DateTime?> _getHawaiiTimeFromServer() async {
    try {
      final apiService = ApiService();
      final response = await apiService.get("auth/server-time");
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String serverTimeStr = data["now"];

        // Remove brackets around timezone name
        serverTimeStr = serverTimeStr.replaceAll(RegExp(r'\[.*\]'), '');

        // Keep only up to 6 digits in fractional seconds
        serverTimeStr = serverTimeStr.replaceAllMapped(
          RegExp(r'\.(\d{1,9})'),
              (match) {
            String fraction = match[1]!;
            if (fraction.length > 6) fraction = fraction.substring(0, 6);
            return '.$fraction';
          },
        );

        // Parse with timezone offset preserved
        DateTime parsed = DateTime.parse(serverTimeStr);

        // Convert to Hawaii time using timezone package
        final hawaii = tz.getLocation('Pacific/Honolulu');
        final hawaiiTime = tz.TZDateTime.from(parsed, hawaii);

        return hawaiiTime;
      } else {
        debugPrint("Failed to fetch server time: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      debugPrint("Error fetching server time: $e");
      return null;
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: RefreshIndicator(
        onRefresh: () async => _loadTrajects(),
        child: SingleChildScrollView(
          physics: BouncingScrollPhysics(),
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: cardColor,
                  border: Border.all(color: borderColor, width: 1),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: iconColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.route, size: 32, color: iconColor),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "My Patrols",
                            style: TextStyle(
                              color: textColor,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "${trajects.length} active patrol routes",
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 20),

              // Stats Row
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      trajects.length.toString(),
                      "Total Routes",
                      Icons.route,
                      Color(0xFF3B82F6),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      trajects.where((t) => t.isDone).length.toString(),
                      "Completed",
                      Icons.check_circle,
                      Color(0xFF3B82F6),
                    ),
                  ),
                  SizedBox(width: 12)
                ],
              ),

              SizedBox(height: 25),

              // Patrols List Title
              Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  "Active Patrol Routes",
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              SizedBox(height: 12),

              // Patrols List
              Column(
                children: trajects.map((t) => _buildTrajectCard(t)).toList(),
              ),



              SizedBox(height: 20),

              // Quick Action


              SizedBox(height: 90), // Padding for bottom nav
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildTrajectCard(AssignmentTrajectory traject) {
    final Color color = Color(0xFF3B82F6);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.route, color: color, size: 28),
            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    traject.name,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(traject.description,
                      style: TextStyle(color: secondaryTextColor)),
                  Text("Duration: ${traject.duration} min",
                      style: TextStyle(color: secondaryTextColor)),
                  const SizedBox(height: 12),

                  // 🔥 ACTION BUTTON
                  _buildTrajectActionButton(traject),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrajectActionButton(AssignmentTrajectory traject) {
    print(traject.isFailed);
    if (traject.isDone) {
      return ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Color(0xFF10B981),
          foregroundColor: Colors.white,
        ),
        child: const Text("Completed"),
      );
    }

    if (traject.isFailed ?? false) {
      return ElevatedButton(
        onPressed: () => _showExpiredDialog(),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey,
          foregroundColor: Colors.white,
        ),
        child: const Text("Expired"),
      );
    }

    if (traject.isActive) {
      return ElevatedButton(
        onPressed: () => _resumeTraject(traject),
        style: ElevatedButton.styleFrom(
          backgroundColor: Color(0xFF3B82F6),
          foregroundColor: Colors.white,
        ),
        child: const Text("Resume"),
      );
    }

    return ElevatedButton(
      onPressed: () => _startTraject(traject),
      style: ElevatedButton.styleFrom(
        backgroundColor: Color(0xFF3B82F6),
        foregroundColor: Colors.white,
      ),
      child: const Text("Start"),
    );
  }


  void _showExpiredDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text('Patrol Expired'),
          ],
        ),
        content: const Text(
          'This patrol route has expired and cannot be resumed.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  void _resumeTraject(AssignmentTrajectory traject) async {
    final refresh = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckpointsScreen(
          trajectId: traject.trajectoryId,
          trajectName: traject.name,
          duration: traject.duration,
          isDarkMode: _isDarkMode,
          assignmentTrajectoryId: traject.id,
        ),
      ),
    );

    if (refresh == true) {
      await _loadTrajects();
    }
  }


  void _completeTraject(AssignmentTrajectory traject) async {
    try {
      await ShiftService().completeTrajectory(traject.id);

      setState(() {
        traject.isActive = false;
        traject.isDone = true;
      });
      await _loadTrajects();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Trajectory completed ✅'),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      debugPrint("Failed to complete trajectory: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to complete trajectory'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }



  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();

    _loadTrajects();

    Timer.periodic(Duration(seconds: 30), (_) async {
      await _loadTrajects();
    });
  }

  Future<void> _loadTrajects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final assignmentId = prefs.getInt('assignmentId');

      final data =
      await ShiftService().getAssignmentTrajectories(assignmentId!);

      setState(() {
        trajects = data.map((t) {
          t.instanceKey = '${t.id}'; // runtime-only field
          return t;
        }).toList();
        isLoading = false;
      });
    } catch (e) {
      debugPrint("ERROR loading trajectories: $e");
      setState(() => isLoading = false);
    }
  }




  void _startTraject(AssignmentTrajectory traject) async {
    try {
      if (traject.expiresAt != null && traject.expiresAt!.isBefore(DateTime.now())) {
        _showTrajectErrorDialog("This patrol route has expired and cannot be started.");
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final assignmentId = prefs.getInt('assignmentId');

      // Call backend to start trajectory
      await ShiftService().startTrajectory(traject.id);
      await _loadTrajects();


      setState(() {
        for (var t in trajects) {
          t.isActive = t.instanceKey == traject.instanceKey;
        }
      });

      // Navigate to checkpoints
      final refresh = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CheckpointsScreen(
            trajectId: traject.trajectoryId,
            assignmentTrajectoryId: traject.id,
            trajectName: traject.name,
            duration: traject.duration,
            isDarkMode: _isDarkMode,
          ),
        ),
      );

      if (refresh == true) {
        await _loadTrajects();
      }


    } catch (e) {
      debugPrint("START TRAJECTORY ERROR: $e");
      _showTrajectErrorDialog(e.toString());
    }
  }
  void _showTrajectErrorDialog(String errorMessage) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: const [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text('Failed to Start Patrol'),
          ],
        ),
        content: Text(errorMessage),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }


  void _showActiveTrajectDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: const [
            Icon(Icons.security, color: Colors.orange),
            SizedBox(width: 8),
            Text('Active Patrol Detected'),
          ],
        ),
        content: const Text(
          'You already have an active patrol route.\n\n'
              'For security reasons, you must complete it before starting a new one.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }



  Widget _buildStatCard(String value, String label, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: cardColor,
        border: Border.all(color: borderColor, width: 1),
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
              Spacer(),
              Text(
                value,
                style: TextStyle(
                  color: textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// Now we'll create a full screen for Checkpoints with proper navigation structure
class CheckpointsScreen extends StatefulWidget {
  final int trajectId;
  final String trajectName;
  final int duration;
  final bool isDarkMode;
  final int assignmentTrajectoryId;

  const CheckpointsScreen({
    super.key,
    required this.trajectId,
    required this.assignmentTrajectoryId,

    required this.trajectName,
    required this.duration,
    required this.isDarkMode,
  });

  @override
  State<CheckpointsScreen> createState() => _CheckpointsScreenState();
}

class _CheckpointsScreenState extends State<CheckpointsScreen> {
  int _selectedIndex = 0; // For navbar if needed
  List<Stop> checkpoints = [];
  bool isLoading = true;
  @override
  void initState() {
    super.initState();
    _loadCheckpoints(); // <-- THIS is what actually fetches the stops
  }
  bool _canScan(int index) {
    // First checkpoint is always allowed
    if (index == 0) return true;

    // Allow only if previous checkpoint is scanned
    return checkpoints[index - 1].isScanned;
  }

  void _loadCheckpoints() async {
    try {
      final stops = await ShiftService().getStops(widget.assignmentTrajectoryId);
      setState(() {
        checkpoints = stops;
        isLoading = false;
      });
    } catch (e) {
      debugPrint("Failed to load checkpoints: $e");
      setState(() => isLoading = false);
    }
  }

  void _completeTrajectory() async {
    try {
      await ShiftService()
          .completeTrajectory(widget.assignmentTrajectoryId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Patrol completed successfully ✅'),
          backgroundColor: successColor,
        ),
      );

      Navigator.pop(context, true); // <-- pass "true" to signal refresh
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to complete patrol'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Theme colors getters
  Color get backgroundColor => widget.isDarkMode ? Color(0xFF0F172A) : Color(0xFFF8FAFC);
  Color get textColor => widget.isDarkMode ? Colors.white : Color(0xFF1E293B);
  Color get cardColor => widget.isDarkMode ? Color(0xFF1E293B) : Colors.white;
  Color get borderColor => widget.isDarkMode ? Color(0xFF334155) : Color(0xFFE2E8F0);
  Color get secondaryTextColor => widget.isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
  Color get successColor => Color(0xFF10B981);
  Color get primaryColor => Color(0xFF3B82F6);
  int calculateAccuracy(double distance, double range) {
    if (distance <= range) {
      return 100;
    }

    final maxDistance = range * 2;

    if (distance >= maxDistance) {
      return 0;
    }

    final accuracy =
        ((maxDistance - distance) / range) * 100;

    return accuracy.clamp(0, 100).round();
  }

  void _openScanner(int index) async {
    final ok = true;
    /*await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QRScannerScreen(
          checkpointName: checkpoints[index].name,
          isDarkMode: widget.isDarkMode,
        ),
      ),
    );*/
    if (ok != true) return;

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    final stop = checkpoints[index];

    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      stop.latitude,
      stop.longitude,
    );

    final accuracy = calculateAccuracy(distance, stop.range);

    final now = DateTime.now();
    final expected = DateTime.now().subtract(const Duration(minutes: 2));

    final late = now.isAfter(expected);
    final lateMinutes =
    late ? now.difference(expected).inMinutes : 0;


    if (accuracy >= 70) {  // <-- ONLY allow valid scans
      try {
        await ShiftService().sendStopScan(
          assignmentTrajectoryId: widget.assignmentTrajectoryId,
          trajectoryStopId: stop.trajectoryStopId,
          stopId: stop.stopId,
          distance: distance,
          accuracy: accuracy,
          isLate: late,
          lateMinutes: lateMinutes,
        );

        setState(() {
          stop.isScanned = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Checkpoint validated (${accuracy}%) ✅'),
          ),
        );

      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Checkpoint already scanned ✅"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else {
      // Accuracy too low → do NOT mark scanned
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Checkpoint too far (${accuracy}%) ⚠️'),
          backgroundColor: Colors.red,
        ),
      );
    }

  }


  Widget _buildCheckpointCard(Stop checkpoint, int index) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: checkpoint.isScanned ? successColor.withOpacity(0.1) : borderColor,
                border: Border.all(
                  color: checkpoint.isScanned ? successColor : secondaryTextColor,
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: checkpoint.isScanned ? successColor : secondaryTextColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    checkpoint.name,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (checkpoint.description != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        checkpoint.description!,
                        style: TextStyle(
                          color: secondaryTextColor,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 14, color: secondaryTextColor),
                      SizedBox(width: 4),
                      Text(
                        'Verification: ${checkpoint.verificationType}',
                        style: TextStyle(
                          color: secondaryTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 12),
            ElevatedButton(
              onPressed: (checkpoint.isScanned || !_canScan(index))
                  ? null
                  : () => _openScanner(index),
              style: ElevatedButton.styleFrom(
                backgroundColor: checkpoint.isScanned
                    ? successColor
                    : _canScan(index)
                    ? primaryColor
                    : Colors.grey,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    checkpoint.isScanned
                        ? Icons.check
                        : _canScan(index)
                        ? Icons.qr_code_scanner
                        : Icons.lock,
                    size: 16,
                  ),
                  SizedBox(width: 6),
                  Text(
                    checkpoint.isScanned
                        ? 'Done'
                        : _canScan(index)
                        ? 'Scan'
                        : 'Locked',
                  ),
                ],
              ),
            )

          ],
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    int completed = checkpoints.where((c) => c.isScanned).length;
    int total = checkpoints.length;
    double progress = total > 0 ? completed / total : 0;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.route, color: primaryColor, size: 24),
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.trajectName,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  "Patrol Route",
                  style: TextStyle(
                    color: secondaryTextColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: primaryColor.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, size: 14, color: successColor),
                SizedBox(width: 6),
                Text(
                  "$completed/$total",
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(

        child: SingleChildScrollView(
          physics: BouncingScrollPhysics(),
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Progress Section
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  color: cardColor,
                  border: Border.all(color: borderColor, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Route Progress",
                          style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          "${(progress * 100).toInt()}%",
                          style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: borderColor,
                      valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                      borderRadius: BorderRadius.circular(10),
                      minHeight: 10,
                    ),
                    SizedBox(height: 8),
                    Text(
                      "$completed checkpoints validated • ${total - completed} remaining",
                      style: TextStyle(
                        color: secondaryTextColor,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 25),

              // Checkpoints Title
              Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  "Checkpoints",
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              SizedBox(height: 12),

              // Checkpoints List
              Column(
                children: List.generate(
                  checkpoints.length,
                      (index) => _buildCheckpointCard(checkpoints[index], index),
                ),
              ),

              SizedBox(height: 20),

              // Completion Button
              if (!isLoading && completed == total)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.flag),
                    label: const Text("Complete Patrol"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: successColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _completeTrajectory,
                  ),
                ),


              SizedBox(height: 90), // Padding for bottom nav
            ],
          ),
        ),
      ),
      // Uncomment this if you want a bottom navbar in this screen


    );
  }
}

class QRScannerScreen extends StatelessWidget {
  final String checkpointName;
  final bool isDarkMode;

  const QRScannerScreen({super.key, required this.checkpointName, required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    Color backgroundColor = isDarkMode ? Color(0xFF0F172A) : Color(0xFFF8FAFC);
    Color textColor = isDarkMode ? Colors.white : Color(0xFF1E293B);
    Color cardColor = isDarkMode ? Color(0xFF1E293B) : Colors.white;
    Color primaryColor = Color(0xFF3B82F6);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Scan Checkpoint",
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              checkpointName,
              style: TextStyle(
                color: primaryColor,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              child: Stack(
                children: [
                  MobileScanner(
                    onDetect: (capture) {
                      final barcode = capture.barcodes.first;
                      // Simulate validation
                      Future.delayed(Duration(milliseconds: 500), () {
                        Navigator.pop(context, true);
                      });
                    },
                    controller: MobileScannerController(
                      formats: [BarcodeFormat.qrCode],
                      detectionSpeed: DetectionSpeed.normal,
                      facing: CameraFacing.back,
                      torchEnabled: false,
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withOpacity(0.8),
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Instructions
          Container(
            padding: EdgeInsets.all(20),
            color: cardColor,
            child: Column(
              children: [
                Text(
                  "Align QR code within the frame",
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  "Hold your device steady until the checkpoint is validated",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textColor.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.flash_on, color: textColor),
                    SizedBox(width: 8),
                    Text(
                      "Use flash in dark areas",
                      style: TextStyle(color: textColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}