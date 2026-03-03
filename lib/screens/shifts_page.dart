import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:awesome_dialog/awesome_dialog.dart';

import '../config/ApiService.dart';
import '../widgets/custom_appbar.dart';
import 'home_screen.dart';

class ShiftsPage extends StatefulWidget {
  const ShiftsPage({super.key});

  @override
  State<ShiftsPage> createState() => _ShiftsPageState();
}

class _ShiftsPageState extends State<ShiftsPage> {
  bool _isDarkMode = true;
  List<Map<String, dynamic>> _shifts = [];

  @override
  void initState() {
    super.initState();
    _fetchShifts();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AM/PM converter: "HH:MM" or "HH:MM:SS" → "h:MM AM/PM"
  // ─────────────────────────────────────────────────────────────────────────
  String _toAmPm(String timeStr) {
    if (timeStr.isEmpty) return timeStr;
    final parts = timeStr.split(':');
    int hour   = int.parse(parts[0]);
    int minute = int.parse(parts[1]);
    final period = hour >= 12 ? 'PM' : 'AM';
    int displayHour = hour % 12;
    if (displayHour == 0) displayHour = 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Date formatter: "YYYY-MM-DD" → "MM/DD/YYYY"
  // ─────────────────────────────────────────────────────────────────────────
  String _formatDate(String date) {
    if (date.isEmpty) return "-";
    final d = DateTime.parse(date);
    return "${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}";
  }

  // ================= FETCH SHIFTS =================
  Future<void> _fetchShifts() async {
    final api = ApiService();

    try {
      final response = await api.get('assignments/OpenShift');

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);

        setState(() {
          _shifts = data.map<Map<String, dynamic>>((assignment) {
            final shift = assignment["shift"];
            final client = shift["client"];
            final site = shift["site"];
            final fromDate = assignment["fromDate"];
            final toDate = assignment["toDate"];
            final start = shift["startTime"];
            final end = shift["endTime"];

            int duration = 0;
            if (start != null && end != null) {
              final startDT = DateTime.parse('${assignment["fromDate"]}T$start');
              var endDT = DateTime.parse('${assignment["fromDate"]}T$end');
              if (endDT.isBefore(startDT)) {
                endDT = endDT.add(const Duration(days: 1));
              }
              duration = endDT.difference(startDT).inHours;
            }

            return {
              "client": client?["name"] ?? "Unknown Client",
              "site": site?["name"] ?? "Unknown Site",
              "description": "",
              "contact": "",
              "from": start ?? "",
              "to": end ?? "",
              "fromDate": fromDate ?? "",
              "toDate": toDate ?? "",
              "duration": duration,
              "location": LatLng(
                (site?["latitude"] ?? 36.81897).toDouble(),
                (site?["longitude"] ?? 10.16579).toDouble(),
              ),
              "assignmentId": assignment["id"],
              // ✅ Supervisor fields from root assignment object (nullable)
              "supervisorName":  assignment["SupervisorName"]  ?? "",
              "supervisorEmail": assignment["SupervisorEmail"] ?? "",
              "supervisorPhone": assignment["SupervisorPhone"] ?? "",
            };
          }).toList();
        });
      } else {
        throw Exception("Failed to load assignments");
      }
    } catch (e) {
      debugPrint("ERROR FETCHING ASSIGNMENTS: $e");
    }
  }

  // ================= THEME =================
  Color get _backgroundColor =>
      _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _cardColor =>
      _isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  Color get _textColor =>
      _isDarkMode ? Colors.white : const Color(0xFF1E293B);
  Color get _secondaryTextColor =>
      _isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
  Color get _borderColor =>
      _isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

  // ================= OPEN MAPS =================
  Future<void> _openInMaps(LatLng location) async {
    final url = Uri.parse(
        "https://www.google.com/maps/search/?api=1&query=${location.latitude},${location.longitude}");
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Copy to clipboard helper
  // ─────────────────────────────────────────────────────────────────────────
  void _copyToClipboard(BuildContext ctx, String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text('$label copied'),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF4F46E5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Info row — plain (no copy button)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text("$label:", style: TextStyle(color: _secondaryTextColor)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontWeight: FontWeight.w500, color: _textColor)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Info row WITH copy button
  // ─────────────────────────────────────────────────────────────────────────
  Widget _copyableInfoRow(BuildContext ctx, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text("$label:", style: TextStyle(color: _secondaryTextColor)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontWeight: FontWeight.w500, color: _textColor)),
          ),
          GestureDetector(
            onTap: () => _copyToClipboard(ctx, value, label),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.copy_rounded, size: 15, color: Color(0xFF4F46E5)),
            ),
          ),
        ],
      ),
    );
  }

  // ================= DETAILS MODAL =================
  void _showShiftDetails(Map<String, dynamic> shift) {
    bool isSatellite = false;
    final mapController = MapController();

    final bool hasSupervisor = (shift["supervisorName"] as String).isNotEmpty ||
        (shift["supervisorEmail"] as String).isNotEmpty ||
        (shift["supervisorPhone"] as String).isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 50,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _secondaryTextColor.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Title
                Text(
                  "${shift["client"]} - ${shift["site"]}",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _textColor,
                  ),
                ),

                const SizedBox(height: 12),

                // ── Shift info ────────────────────────────────────────────
                _infoRow("Date",
                    "${_formatDate(shift["fromDate"])} → ${_formatDate(shift["toDate"])}"),
                const SizedBox(height: 4),
                _infoRow("From", _toAmPm(shift["from"])),
                _infoRow("To",   _toAmPm(shift["to"])),

                const SizedBox(height: 16),

                // ── Supervisor section ────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: hasSupervisor
                        ? const Color(0xFF3B82F6).withOpacity(0.07)
                        : _secondaryTextColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: hasSupervisor
                          ? const Color(0xFF3B82F6).withOpacity(0.25)
                          : _borderColor,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.person_pin_outlined,
                            size: 18,
                            color: hasSupervisor
                                ? const Color(0xFF3B82F6)
                                : _secondaryTextColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "Supervisor",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: hasSupervisor
                                  ? const Color(0xFF3B82F6)
                                  : _secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (!hasSupervisor)
                        Text(
                          "No supervisor assigned",
                          style: TextStyle(
                              color: _secondaryTextColor,
                              fontStyle: FontStyle.italic,
                              fontSize: 13),
                        )
                      else ...[
                        if ((shift["supervisorName"] as String).isNotEmpty)
                          _infoRow("Name", shift["supervisorName"]),
                        if ((shift["supervisorEmail"] as String).isNotEmpty)
                          _copyableInfoRow(ctx, "Email", shift["supervisorEmail"]),
                        if ((shift["supervisorPhone"] as String).isNotEmpty)
                          _copyableInfoRow(ctx, "Phone", shift["supervisorPhone"]),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Map ───────────────────────────────────────────────────
                Text("Location",
                    style: TextStyle(fontWeight: FontWeight.bold, color: _textColor)),
                const SizedBox(height: 8),

                Container(
                  height: 260,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _borderColor),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: mapController,
                          options: MapOptions(
                            initialCenter: shift["location"],
                            initialZoom: 15,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: isSatellite
                                  ? "https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
                                  : "https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png",
                              subdomains: const ['a', 'b', 'c'],
                              userAgentPackageName:
                              'com.blackfabricsecurity.crossplatformblackfabric',
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: shift["location"],
                                  width: 50,
                                  height: 50,
                                  child: GestureDetector(
                                    onTap: () => _openInMaps(shift["location"]),
                                    child: const Icon(Icons.location_on,
                                        color: Colors.red, size: 40),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        // Satellite toggle
                        Positioned(
                          top: 10,
                          right: 10,
                          child: FloatingActionButton(
                            mini: true,
                            heroTag: 'satellite_toggle',
                            backgroundColor: Colors.black87,
                            onPressed: () =>
                                setModalState(() => isSatellite = !isSatellite),
                            child: Icon(
                              isSatellite ? Icons.map : Icons.satellite,
                              color: Colors.white,
                            ),
                          ),
                        ),

                        // Center button
                        Positioned(
                          bottom: 10,
                          right: 10,
                          child: FloatingActionButton(
                            mini: true,
                            heroTag: 'center_map',
                            backgroundColor: Colors.black87,
                            onPressed: () =>
                                mapController.move(shift["location"], 15),
                            child:
                            const Icon(Icons.my_location, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Action buttons ─────────────────────────────────────────
                Center(
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            try {
                              final prefs = await SharedPreferences.getInstance();
                              final userId = prefs.getInt('userId');
                              if (userId == null) {
                                AwesomeDialog(
                                  context: ctx,
                                  dialogType: DialogType.error,
                                  title: 'Error',
                                  desc: 'User not logged in',
                                  btnOkOnPress: () {},
                                ).show();
                                return;
                              }
                              final api = ApiService();
                              final response = await api.put(
                                'assignments/assign/${shift["assignmentId"]}',
                                {"userId": userId},
                              );

                              if (response.statusCode == 200) {
                                AwesomeDialog(
                                  context: ctx,
                                  dialogType: DialogType.success,
                                  title: 'Done',
                                  desc:
                                  'You will be contacted by email for the details',
                                  btnOkOnPress: () {
                                    Navigator.of(context).pushAndRemoveUntil(
                                      MaterialPageRoute(
                                        builder: (_) => const HomeScreen(),
                                      ),
                                          (route) => false,
                                    );
                                  },
                                ).show();
                              } else if (response.statusCode == 409) {
                                AwesomeDialog(
                                  context: ctx,
                                  dialogType: DialogType.warning,
                                  title: 'Conflict',
                                  desc: response.body,
                                  btnOkOnPress: () {},
                                ).show();
                              } else {
                                AwesomeDialog(
                                  context: ctx,
                                  dialogType: DialogType.error,
                                  title: 'Error',
                                  desc: 'Failed to send request.',
                                  btnOkOnPress: () {},
                                ).show();
                              }
                            } catch (e) {
                              debugPrint("ERROR SENDING REQUEST: $e");
                            }
                          },
                          icon: const Icon(Icons.send, color: Colors.white),
                          label: const Text("Take the shift",
                              style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4F46E5),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _openInMaps(shift["location"]),
                          icon: const Icon(Icons.map, color: Colors.white),
                          label: const Text("Open in Maps",
                              style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ================= SHIFT CARD =================
  Widget _buildShiftCard(Map<String, dynamic> shift) {
    return GestureDetector(
      onTap: () => _showShiftDetails(shift),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: _borderColor),
        ),
        child: Row(
          children: [
            const Icon(Icons.work_outline, size: 32, color: Color(0xFF4F46E5)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${shift["client"]} - ${shift["site"]}",
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: _textColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${_toAmPm(shift["from"])} - ${_toAmPm(shift["to"])}",
                    style:
                    TextStyle(fontSize: 12, color: _secondaryTextColor),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                size: 18, color: _secondaryTextColor),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _shifts.length,
        itemBuilder: (context, i) => _buildShiftCard(_shifts[i]),
      ),
    );
  }
}