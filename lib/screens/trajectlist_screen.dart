import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ndef/ndef.dart' as ndef;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../config/ApiService.dart';
import '../models/AssignmentTrajectory.dart';
import '../models/Stop.dart';
import '../services/shift_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TRAJECT LIST PAGE
// ─────────────────────────────────────────────────────────────────────────────
class TrajectListPage extends StatefulWidget {
  const TrajectListPage({super.key});

  @override
  State<TrajectListPage> createState() => _TrajectListPageState();
}

class _TrajectListPageState extends State<TrajectListPage> {
  List<AssignmentTrajectory> trajects = [];
  bool isLoading = true;
  bool _isDarkMode = true;
  Timer? _refreshTimer;

  Color get backgroundColor =>
      _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get textColor =>
      _isDarkMode ? Colors.white : const Color(0xFF1E293B);
  Color get cardColor =>
      _isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  Color get borderColor =>
      _isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get secondaryTextColor =>
      _isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
  Color get iconColor =>
      _isDarkMode ? const Color(0xFF64B5F6) : const Color(0xFF2196F3);

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    _loadTrajects();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _loadTrajects());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTrajects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final assignmentId = prefs.getInt('assignmentId');
      if (assignmentId == null) {
        if (mounted) setState(() => isLoading = false);
        return;
      }
      final data =
      await ShiftService().getAssignmentTrajectories(assignmentId);
      if (!mounted) return;
      setState(() {
        trajects = data.map((t) {
          t.instanceKey = '${t.id}';
          return t;
        }).toList();
        isLoading = false;
      });
    } catch (e) {
      debugPrint('ERROR loading trajectories: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _startTraject(AssignmentTrajectory traject) async {
    try {
      if (traject.expiresAt != null &&
          traject.expiresAt!.isBefore(DateTime.now())) {
        _showErrorDialog(
            'This patrol route has expired and cannot be started.');
        return;
      }
      await ShiftService().startTrajectory(traject.id);
      await _loadTrajects();

      setState(() {
        for (final t in trajects) {
          t.isActive = t.instanceKey == traject.instanceKey;
        }
      });

      final refresh = await Navigator.push<bool>(
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
      if (refresh == true) await _loadTrajects();
    } catch (e) {
      debugPrint('START TRAJECTORY ERROR: $e');
      _showErrorDialog(e.toString());
    }
  }

  void _resumeTraject(AssignmentTrajectory traject) async {
    final refresh = await Navigator.push<bool>(
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
    if (refresh == true) await _loadTrajects();
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: cardColor,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.error, color: Colors.red),
          const SizedBox(width: 8),
          Text('Error',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w700)),
        ]),
        content: Text(message, style: TextStyle(color: secondaryTextColor)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child:
            const Text('Understood', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: RefreshIndicator(
        onRefresh: _loadTrajects,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header card ───────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: cardColor,
                  border: Border.all(color: borderColor),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.route, size: 32, color: iconColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('My Patrols',
                            style: TextStyle(
                                color: textColor,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                            '${trajects.length} patrol route${trajects.length == 1 ? '' : 's'} assigned',
                            style: TextStyle(
                                color: secondaryTextColor, fontSize: 14)),
                      ],
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 20),

              // ── Stats ─────────────────────────────────────────────────
              Row(children: [
                Expanded(
                    child: _buildStatCard(
                        trajects.length.toString(),
                        'Total',
                        Icons.route,
                        const Color(0xFF3B82F6))),
                const SizedBox(width: 12),
                Expanded(
                    child: _buildStatCard(
                        trajects.where((t) => t.isDone).length.toString(),
                        'Completed',
                        Icons.check_circle,
                        const Color(0xFF10B981))),
                const SizedBox(width: 12),
                Expanded(
                    child: _buildStatCard(
                        trajects.where((t) => t.isActive).length.toString(),
                        'In Progress',
                        Icons.pending_actions,
                        const Color(0xFFF59E0B))),
              ]),

              const SizedBox(height: 25),

              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text('Patrol Routes',
                    style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
              ),

              const SizedBox(height: 12),

              if (isLoading)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: iconColor),
                  ),
                )
              else if (trajects.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(children: [
                    Icon(Icons.route_outlined,
                        size: 48, color: secondaryTextColor),
                    const SizedBox(height: 12),
                    Text('No patrol routes assigned',
                        style: TextStyle(
                            color: secondaryTextColor, fontSize: 15)),
                  ]),
                )
              else
                Column(
                    children:
                    trajects.map((t) => _buildTrajectCard(t)).toList()),

              const SizedBox(height: 90),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrajectCard(AssignmentTrajectory traject) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.route,
                  color: Color(0xFF3B82F6), size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(traject.name,
                      style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  if (traject.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(traject.description,
                          style: TextStyle(
                              color: secondaryTextColor, fontSize: 13)),
                    ),
                  Row(children: [
                    Icon(Icons.timer_outlined,
                        size: 13, color: secondaryTextColor),
                    const SizedBox(width: 4),
                    Text('${traject.duration} min',
                        style: TextStyle(
                            color: secondaryTextColor, fontSize: 12)),
                    if (traject.expiresAt != null) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.event_outlined,
                          size: 13,
                          color: traject.expiresAt!.isBefore(DateTime.now())
                              ? Colors.red
                              : secondaryTextColor),
                      const SizedBox(width: 4),
                      Text(
                        _formatExpiry(traject.expiresAt!),
                        style: TextStyle(
                          color:
                          traject.expiresAt!.isBefore(DateTime.now())
                              ? Colors.red
                              : secondaryTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 12),
                  _buildActionButton(traject),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatExpiry(DateTime dt) {
    final now = DateTime.now();
    final diff = dt.difference(now);
    if (diff.isNegative) return 'Expired';
    if (diff.inHours < 1) return 'Expires in ${diff.inMinutes}m';
    if (diff.inDays < 1) return 'Expires in ${diff.inHours}h';
    return 'Exp. ${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildActionButton(AssignmentTrajectory traject) {
    if (traject.isDone) {
      return ElevatedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check_circle, size: 16),
        label: const Text('Completed'),
        style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF10B981),
            disabledForegroundColor: Colors.white),
      );
    }
    if (traject.isFailed) {
      return ElevatedButton.icon(
        onPressed: () =>
            _showErrorDialog('This patrol route has expired and cannot be resumed.'),
        icon: const Icon(Icons.block, size: 16),
        label: const Text('Expired'),
        style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey[700],
            foregroundColor: Colors.white),
      );
    }
    if (traject.isActive) {
      return ElevatedButton.icon(
        onPressed: () => _resumeTraject(traject),
        icon: const Icon(Icons.play_circle, size: 16),
        label: const Text('Resume'),
        style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B82F6),
            foregroundColor: Colors.white),
      );
    }
    return ElevatedButton.icon(
      onPressed: () => _startTraject(traject),
      icon: const Icon(Icons.flag, size: 16),
      label: const Text('Start Patrol'),
      style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3B82F6),
          foregroundColor: Colors.white),
    );
  }

  Widget _buildStatCard(
      String value, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: cardColor,
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 16, color: color),
            ),
            const Spacer(),
            Text(value,
                style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(color: secondaryTextColor, fontSize: 11)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CHECKPOINTS SCREEN
// ─────────────────────────────────────────────────────────────────────────────
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
  List<Stop> checkpoints = [];
  bool isLoading = true;
  bool _isScanning = false;

  Color get backgroundColor =>
      widget.isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get textColor =>
      widget.isDarkMode ? Colors.white : const Color(0xFF1E293B);
  Color get cardColor =>
      widget.isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  Color get borderColor =>
      widget.isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get secondaryTextColor =>
      widget.isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
  Color get successColor => const Color(0xFF10B981);
  Color get primaryColor => const Color(0xFF3B82F6);
  Color get warningColor => const Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _loadCheckpoints();
  }

  Future<void> _loadCheckpoints() async {
    try {
      final stops =
      await ShiftService().getStops(widget.assignmentTrajectoryId);
      if (!mounted) return;
      setState(() {
        checkpoints = stops;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Failed to load checkpoints: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  bool _canScan(int index) {
    if (index == 0) return true;
    return checkpoints[index - 1].isScanned;
  }

  // ── Range / Accuracy calculation ──────────────────────────────────────────
  //
  //  distance ≤ range            → 100%  (fully inside the valid zone)
  //  range < distance < range×2  → linear decay  100% → 0%
  //  distance ≥ range×2          → 0%   (too far, rejected)
  //
  //  Formula:  accuracy = (range×2 - distance) / range  × 100
  //  Minimum accepted accuracy: 70%
  // ─────────────────────────────────────────────────────────────────────────
  int _calculateAccuracy(double distanceM) {
    const rangeM = 10.0;     // full accuracy within 10 m
    const maxDist = 15.0;    // anything beyond 15 m is rejected (0%)

    if (distanceM <= rangeM) return 100;           // inside valid zone
    if (distanceM >= maxDist) return 0;           // too far
    // linear decay between 10 and 15 meters
    return ((maxDist - distanceM) / (maxDist - rangeM) * 100.0)
        .clamp(0.0, 100.0)
        .round();
  }


  // ── Main scan handler ─────────────────────────────────────────────────────
  Future<void> _scanCheckpoint(int index) async {
    if (_isScanning) return;
    final stop = checkpoints[index];

    // 1. NFC availability check
    final availability = await FlutterNfcKit.nfcAvailability;
    if (availability != NFCAvailability.available) {
      _snack('NFC is not available on this device.', error: true);
      return;
    }

    setState(() => _isScanning = true);
    _showNfcWaitDialog(stop.name); // show UI while waiting for tag

    String? scannedText;

    try {
      // 2. Poll for the NFC tag
      await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 20),
        iosMultipleTagMessage: 'Present only one NFC tag.',
        iosAlertMessage: 'Hold your phone near the checkpoint tag.',
      );

      // 3. Read NDEF records from the tag
      final records = await FlutterNfcKit.readNDEFRecords();

      // 4. Extract text from the first TextRecord
      for (final record in records) {
        if (record is ndef.TextRecord) {
          scannedText = record.text;
          break;
        }
        // Fallback: decode raw payload (TextRecord format: 1-byte flags + lang + text)
        final payload = record.payload;
        if (payload != null && payload.length > 1) {
          try {
            final langLen = payload[0] & 0x3F;
            scannedText =
                String.fromCharCodes(payload.sublist(1 + langLen));
            break;
          } catch (_) {}
        }
      }

      await FlutterNfcKit.finish(iosAlertMessage: 'Tag read!');
    } catch (e) {
      try {
        await FlutterNfcKit.finish(iosErrorMessage: 'Scan failed.');
      } catch (_) {}
      if (mounted) {
        _dismissNfcDialog();
        setState(() => _isScanning = false);
        final s = e.toString().toLowerCase();
        if (s.contains('cancel') || s.contains('user')) {
          _snack('Scan cancelled.');
        } else if (s.contains('timeout')) {
          _snack('NFC timeout. Bring the tag closer and try again.',
              error: true);
        } else if (s.contains('tag connection lost')) {
          _snack('Tag moved away. Hold it steady and retry.', error: true);
        } else {
          _snack('NFC error: $e', error: true);
        }
      }
      return;
    }

    if (!mounted) return;
    _dismissNfcDialog();

    // 5. Validate tag content is non-empty
    if (scannedText == null || scannedText.trim().isEmpty) {
      setState(() => _isScanning = false);
      _snack('NFC tag is empty or unreadable. Reassign it in admin.',
          error: true);
      return;
    }

    // 6. Validate tag encodes the correct stop ID
    //    The admin page writes stopId.toString() into the tag.
    final scannedStopId = int.tryParse(scannedText.trim());
    if (scannedStopId == null || scannedStopId != stop.stopId) {
      setState(() => _isScanning = false);
      _snack(
          'Wrong tag! This tag belongs to a different checkpoint (read: "${scannedText.trim()}", expected: ${stop.stopId}).',
          error: true);
      return;
    }

    // 7. Acquire GPS position
    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (e) {
      setState(() => _isScanning = false);
      _snack(
          'Could not obtain GPS position. Enable location and try again.',
          error: true);
      return;
    }

    // 8. Distance + accuracy
    final distanceM = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      stop.latitude,
      stop.longitude,
    );
    final accuracy = _calculateAccuracy(distanceM);

    debugPrint(
        '📍 [${stop.name}] dist=${distanceM.toStringAsFixed(1)}m  range=${stop.range}m  accuracy=$accuracy%');

    // 9. Reject if guard is too far away
    if (accuracy < 70) {
      setState(() => _isScanning = false);
      _showTooFarDialog(distanceM: distanceM, rangeM: stop.range, accuracy: accuracy);
      return;
    }

    // 10. Send to backend
    try {
      await ShiftService().sendStopScan(
        assignmentTrajectoryId: widget.assignmentTrajectoryId,
        trajectoryStopId: stop.trajectoryStopId,
        stopId: stop.stopId,
        distance: distanceM,
        accuracy: accuracy,
        isLate: false, // extend this when backend exposes expectedAt per stop
        lateMinutes: 0,
      );
    } catch (e) {
      // If backend says "already scanned" that's fine — mark locally
      final s = e.toString().toLowerCase();
      if (!s.contains('already') && !s.contains('duplicate')) {
        setState(() => _isScanning = false);
        _snack('Server error: $e', error: true);
        return;
      }
    }

    // 11. Success
    if (mounted) {
      setState(() {
        stop.isScanned = true;
        _isScanning = false;
      });
      _snack(
          '✅ ${stop.name} validated! (${distanceM.toStringAsFixed(0)} m, $accuracy%)');
    }
  }

  // ── NFC waiting dialog ────────────────────────────────────────────────────
  void _showNfcWaitDialog(String checkpointName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          backgroundColor: cardColor,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24)),
          contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            // animated NFC icon
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withOpacity(0.1),
                border: Border.all(
                    color: primaryColor.withOpacity(0.3), width: 2),
              ),
              child: Icon(Icons.nfc, size: 50, color: primaryColor),
            ),
            const SizedBox(height: 20),
            Text('Ready to Scan',
                style: TextStyle(
                    color: textColor,
                    fontSize: 19,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(checkpointName,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text(
              'Hold the back of your phone against\nthe NFC tag at this checkpoint.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: secondaryTextColor, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: primaryColor),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () async {
                try {
                  await FlutterNfcKit.finish();
                } catch (_) {}
                if (mounted) Navigator.pop(context); // close only the dialog
              },
              child: Text('Cancel',
                  style: TextStyle(color: secondaryTextColor, fontSize: 14)),
            ),
          ]),
        ),
      ),
    );
  }

  void _dismissNfcDialog() {
    if (mounted) {
      try {
        Navigator.of(context, rootNavigator: true).pop(); // just close the topmost dialog
      } catch (_) {}
    }
  }


  // ── Too-far dialog ────────────────────────────────────────────────────────
  void _showTooFarDialog({
    required double distanceM,
    required double rangeM,
    required int accuracy,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.location_off, color: warningColor),
          const SizedBox(width: 8),
          Text('Too Far Away',
              style: TextStyle(
                  color: textColor, fontWeight: FontWeight.w700)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _infoRow('Your distance',
                '${distanceM.toStringAsFixed(0)} m', isHighlight: true),
            _infoRow('Valid range', '≤ ${rangeM.toStringAsFixed(0)} m'),
            _infoRow('Accuracy', '$accuracy% (min 70%)'),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: warningColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: warningColor.withOpacity(0.3)),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, color: warningColor, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Move closer to the checkpoint and scan again.',
                    style: TextStyle(color: warningColor, fontSize: 12),
                  ),
                ),
              ]),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child:
            const Text('Got it', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
              TextStyle(color: secondaryTextColor, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  color: isHighlight ? Colors.red : textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red[700] : successColor,
      behavior: SnackBarBehavior.floating,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _completeTrajectory() async {
    try {
      await ShiftService()
          .completeTrajectory(widget.assignmentTrajectoryId);
      if (!mounted) return;
      _snack('Patrol completed successfully ✅');
      Navigator.pop(context, true);
    } catch (e) {
      _snack('Failed to complete patrol. Try again.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final completed = checkpoints.where((c) => c.isScanned).length;
    final total = checkpoints.length;
    final progress = total > 0 ? completed / total : 0.0;
    final allDone = !isLoading && total > 0 && completed == total;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.route, color: primaryColor, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.trajectName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                Text('Patrol Route',
                    style: TextStyle(
                        color: secondaryTextColor, fontSize: 11)),
              ],
            ),
          ),
        ]),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: primaryColor.withOpacity(0.3)),
            ),
            child: Row(children: [
              Icon(Icons.check_circle,
                  size: 14,
                  color: allDone ? successColor : primaryColor),
              const SizedBox(width: 5),
              Text('$completed/$total',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      ),
      body: SafeArea(
        child: isLoading
            ? Center(
            child: CircularProgressIndicator(color: primaryColor))
            : SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Progress card ────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Route Progress',
                            style: TextStyle(
                                color: textColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        Text('${(progress * 100).toInt()}%',
                            style: TextStyle(
                                color: allDone
                                    ? successColor
                                    : primaryColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: borderColor,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            allDone ? successColor : primaryColor),
                        minHeight: 10,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$completed validated  •  ${total - completed} remaining',
                      style: TextStyle(
                          color: secondaryTextColor,
                          fontSize: 12),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── NFC hint ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: primaryColor.withOpacity(0.2)),
                ),
                child: Row(children: [
                  Icon(Icons.nfc, color: primaryColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tap "Scan" then hold your phone to the NFC tag at each checkpoint. Complete them in order.',
                      style: TextStyle(
                          color: textColor,
                          fontSize: 12,
                          height: 1.4),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 20),

              Text('Checkpoints',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),

              const SizedBox(height: 10),

              // ── Checkpoints list ─────────────────────────────────
              Column(
                children: List.generate(
                    checkpoints.length,
                        (i) =>
                        _buildCheckpointCard(checkpoints[i], i)),
              ),

              const SizedBox(height: 20),

              // ── Complete patrol button ────────────────────────────
              if (allDone)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.flag),
                    label: const Text('Complete Patrol'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: successColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(12)),
                    ),
                    onPressed: _completeTrajectory,
                  ),
                ),

              const SizedBox(height: 90),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckpointCard(Stop checkpoint, int index) {
    final canScan = _canScan(index);
    final scanned = checkpoint.isScanned;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: scanned
              ? successColor.withOpacity(0.4)
              : canScan
              ? primaryColor.withOpacity(0.3)
              : borderColor,
          width: (scanned || canScan) ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          // Step number / check icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scanned
                  ? successColor.withOpacity(0.12)
                  : canScan
                  ? primaryColor.withOpacity(0.1)
                  : Colors.transparent,
              border: Border.all(
                color: scanned
                    ? successColor
                    : canScan
                    ? primaryColor
                    : secondaryTextColor,
                width: 2,
              ),
            ),
            child: Center(
              child: scanned
                  ? Icon(Icons.check, size: 18, color: successColor)
                  : Text(
                '${index + 1}',
                style: TextStyle(
                  color:
                  canScan ? primaryColor : secondaryTextColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),

          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(checkpoint.name,
                    style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                if (checkpoint.description != null &&
                    checkpoint.description!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(checkpoint.description!,
                      style: TextStyle(
                          color: secondaryTextColor, fontSize: 12)),
                ],
                const SizedBox(height: 5),
                Row(children: [
                  Icon(Icons.radar, size: 12, color: secondaryTextColor),
                  const SizedBox(width: 4),
                  Text(
                      'Range: ${checkpoint.range.toStringAsFixed(0)} m',
                      style: TextStyle(
                          color: secondaryTextColor, fontSize: 11)),
                  const SizedBox(width: 12),
                  Icon(Icons.nfc, size: 12, color: secondaryTextColor),
                  const SizedBox(width: 4),
                  Text('NFC',
                      style: TextStyle(
                          color: secondaryTextColor, fontSize: 11)),
                ]),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // Scan button
          ElevatedButton.icon(
            onPressed: (scanned || !canScan || _isScanning)
                ? null
                : () => _scanCheckpoint(index),
            icon: Icon(
              scanned
                  ? Icons.check
                  : (!canScan)
                  ? Icons.lock
                  : Icons.nfc,
              size: 15,
            ),
            label: Text(
              scanned
                  ? 'Done'
                  : (!canScan)
                  ? 'Locked'
                  : _isScanning
                  ? '...'
                  : 'Scan',
              style: const TextStyle(fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: scanned
                  ? successColor
                  : canScan
                  ? primaryColor
                  : Colors.grey[700],
              foregroundColor: Colors.white,
              disabledBackgroundColor: scanned
                  ? successColor.withOpacity(0.7)
                  : Colors.grey[800],
              disabledForegroundColor: Colors.white70,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
            ),
          ),
        ]),
      ),
    );
  }
}