import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:awesome_dialog/awesome_dialog.dart';

import '../config/ApiService.dart';
import '../widgets/custom_appbar.dart';

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

  // ================= FETCH SHIFTS =================
  Future<void> _fetchShifts() async {
    final api = ApiService();

    try {
      // ✅ Updated endpoint to fetch openShift assignments
      final response = await api.get('assignments/OpenShift');

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);

        setState(() {
          _shifts = data.map<Map<String, dynamic>>((assignment) {
            final shift = assignment["shift"];
            final client = shift["client"];
            final site = shift["site"];
            final fromDate = assignment["fromDate"]; // e.g., "2026-01-21"
            final toDate = assignment["toDate"];
            final start = shift["startTime"];
            final end = shift["endTime"];

            int duration = 0;
            if (start != null && end != null) {
              // Combine with a fake date so DateTime.parse works
              final startDT = DateTime.parse('${assignment["fromDate"]}T$start');
              final endDT = DateTime.parse('${assignment["fromDate"]}T$end');
              duration = endDT.difference(startDT).inHours;
            }


            return {
              "client": client?["name"] ?? "Unknown Client",
              "site": site?["name"] ?? "Unknown Site",
              "description": "", // optional
              "contact": "", // optional
              "from": start ?? "",
              "to": end ?? "",
              "fromDate": fromDate ?? "",
              "toDate": toDate ?? "",
              "duration": duration,
              "location": LatLng(
                (site?["latitude"] ?? 36.81897).toDouble(),
                (site?["longitude"] ?? 10.16579).toDouble(),
              ),
              "assignmentId": assignment["id"], // optional if needed
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

  String _formatDate(String date) {
    if (date.isEmpty) return "-";
    final d = DateTime.parse(date);
    return "${d.day}/${d.month}/${d.year}";
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

  // ================= DETAILS MODAL =================
  void _showShiftDetails(Map<String, dynamic> shift) {
    bool isSatellite = false;
    final mapController = MapController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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

                Text(
                  "${shift["client"]} - ${shift["site"]}",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _textColor,
                  ),
                ),

                const SizedBox(height: 12),
                _infoRow(
                  "Date",
                  "${_formatDate(shift["fromDate"])} → ${_formatDate(shift["toDate"])}",
                ),

                const SizedBox(height: 8),

                _infoRow("From", shift["from"]),
                _infoRow("To", shift["to"]),


                const SizedBox(height: 12),
                Text("Location",
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: _textColor)),

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
                        InkWell(
                          onTap: () => _openInMaps(shift["location"]),
                          child: FlutterMap(
                            mapController: mapController,
                            options: MapOptions(
                              initialCenter: shift["location"],
                              initialZoom: 15,
                            ),
                            children: [
                              if (!isSatellite)
                                TileLayer(
                                  urlTemplate:
                                  "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                                ),
                              if (isSatellite) ...[
                                TileLayer(
                                  urlTemplate: isSatellite
                                      ? "https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
                                      : "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                                ),
                              ],
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: shift["location"],
                                    width: 50,
                                    height: 50,
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Colors.red,
                                      size: 40,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // SATELLITE TOGGLE
                        Positioned(
                          top: 10,
                          right: 10,
                          child: FloatingActionButton(
                            mini: true,
                            backgroundColor: Colors.black87,
                            onPressed: () {
                              setModalState(() {
                                isSatellite = !isSatellite;
                              });
                            },
                            child: Icon(
                              isSatellite ? Icons.map : Icons.satellite,
                              color: Colors.white,
                            ),
                          ),
                        ),

                        // CENTER BUTTON
                        Positioned(
                          bottom: 10,
                          right: 10,
                          child: FloatingActionButton(
                            mini: true,
                            backgroundColor: Colors.black87,
                            onPressed: () {
                              mapController.move(shift["location"], 15);
                            },
                            child: const Icon(Icons.my_location,
                                color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Center(
                  child: Column(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            final prefs = await SharedPreferences.getInstance();
                            final userId = prefs.getInt('userId');
                            if (userId == null) {
                              AwesomeDialog(
                                context: context,
                                dialogType: DialogType.error,
                                title: 'Error',
                                desc: 'User not logged in',
                                btnOkOnPress: () {},
                              ).show();
                              return;
                            }
                            final api = ApiService();
                            // TODO: Put your API URL here
                            final response = await api.put(
                              'assignments/assign/${shift["assignmentId"]}',
                              {"userId": userId}, // ✅ this works with your ApiService.put
                            );


                            if (response.statusCode == 200) {
                              AwesomeDialog(
                                context: context,
                                dialogType: DialogType.success,
                                title: 'Done',
                                desc: 'You will be contacted by email for the details',
                                btnOkOnPress: () {},
                              ).show();
                            } else if (response.statusCode == 409) {
                              AwesomeDialog(
                                context: context,
                                dialogType: DialogType.warning,
                                title: 'Conflict',
                                desc: response.body, // shows backend message: Guard is already assigned...
                                btnOkOnPress: () {},
                              ).show();
                            } else {
                              AwesomeDialog(
                                context: context,
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
                        label: const Text(
                          "Take the shift",
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // ✅ Open in Google Maps / Apple Maps
                      ElevatedButton.icon(
                        onPressed: () => _openInMaps(shift["location"]),
                        icon: const Icon(Icons.map, color: Colors.white),
                        label: const Text(
                          "Open in Maps",
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // ✅ Checkpoint button (functionality can be added later)

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

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 100,
              child: Text("$label:",
                  style: TextStyle(color: _secondaryTextColor))),
          Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontWeight: FontWeight.w500, color: _textColor))),
        ],
      ),
    );
  }

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
            const Icon(Icons.work_outline,
                size: 32, color: Color(0xFF4F46E5)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                "${shift["client"]} - ${shift["site"]}",
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: _textColor),
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
