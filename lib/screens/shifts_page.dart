import 'dart:convert';
import 'dart:io';

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

class _ShiftsPageState extends State<ShiftsPage>
    with SingleTickerProviderStateMixin {
  bool _isDarkMode = true;
  List<Map<String, dynamic>> _shifts = [];
  List<Map<String, dynamic>> _history = [];
  bool _loadingHistory = false;
  bool _showHistoryTab = false;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchShifts();
    _initHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    if (userId == null) return;

    final api = ApiService();
    try {
      final res = await api.get('assignments/open-shift-history?userId=$userId');
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        final list = data.map<Map<String, dynamic>>((a) {
          final shift    = a['shift']  ?? {};
          final site     = shift['site']   ?? {};
          final client   = shift['client'] ?? {};
          final guard    = a['guard'];

          final start = shift['startTime'] ?? '';
          final end   = shift['endTime']   ?? '';

          return {
            'assignmentId': a['id'],
            'client':    client['name'] ?? 'Unknown',
            'site':      site['name']   ?? 'Unknown',
            'fromDate':  a['fromDate']  ?? '',
            'toDate':    a['toDate']    ?? '',
            'from':      start,
            'to':        end,
            'openShift': a['openShift'] ?? false,
            'daysOfWeek': (a['daysOfWeek'] as List?)?.cast<String>() ?? [],
            'guardName': guard != null
                ? '${guard['firstName'] ?? ''} ${guard['lastName'] ?? ''}'.trim()
                : null,
            'postedByName':   a['postedByName'],
            'postedAt':       a['postedAt'],
            'acceptedByName': a['acceptedByName'],
            'acceptedAt':     a['acceptedAt'],
          };
        }).toList();

        if (mounted) {
          setState(() {
            _history = list;
            _showHistoryTab = true;
          });
        }
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AM/PM converter
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
    if (date.isEmpty) return '-';
    final d = DateTime.parse(date);
    return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Timestamp formatter: ISO → " on MM/DD/YYYY hh:mm AM"
  // ─────────────────────────────────────────────────────────────────────────
  String _formatTs(dynamic ts) {
    if (ts == null) return '';
    try {
      final d = DateTime.parse(ts.toString());
      final m  = d.month.toString().padLeft(2, '0');
      final dy = d.day.toString().padLeft(2, '0');
      int h = d.hour; final min = d.minute.toString().padLeft(2, '0');
      final period = h >= 12 ? 'PM' : 'AM';
      h = h % 12; if (h == 0) h = 12;
      return ' on $m/$dy/${d.year} $h:$min $period';
    } catch (_) { return ''; }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FETCH OPEN SHIFTS (Marketplace)
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _fetchShifts() async {
    final api = ApiService();
    try {
      final response = await api.get('assignments/OpenShift');
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        setState(() {
          _shifts = data.map<Map<String, dynamic>>((assignment) {
            final shift    = assignment['shift'];
            final client   = shift['client'];
            final site     = shift['site'];
            final fromDate = assignment['fromDate'] ?? '';
            final toDate   = assignment['toDate']   ?? '';
            final start    = shift['startTime']     ?? '';
            final end      = shift['endTime']       ?? '';

            int duration = 0;
            if (start.isNotEmpty && end.isNotEmpty) {
              final startDT = DateTime.parse('${assignment["fromDate"]}T$start');
              var endDT     = DateTime.parse('${assignment["fromDate"]}T$end');
              if (endDT.isBefore(startDT)) {
                endDT = endDT.add(const Duration(days: 1));
              }
              duration = endDT.difference(startDT).inHours;
            }

            return {
              'client':      client?['name'] ?? 'Unknown Client',
              'site':        site?['name']   ?? 'Unknown Site',
              'from':        start,
              'to':          end,
              'fromDate':    fromDate,
              'toDate':      toDate,
              'duration':    duration,
              'location': LatLng(
                (site?['latitude']  ?? 36.81897).toDouble(),
                (site?['longitude'] ?? 10.16579).toDouble(),
              ),
              'assignmentId': assignment['id'],
              'supervisorName':  assignment['supervisorName']  ?? '',
              'supervisorEmail': assignment['supervisorEmail'] ?? '',
              'supervisorPhone': assignment['supervisorPhone'] ?? '',
              'daysOfWeek': (assignment['daysOfWeek'] as List?)?.cast<String>() ?? [],
            };
          }).toList();
        });
      } else {
        throw Exception('Failed to load assignments');
      }
    } catch (e) {
      debugPrint('ERROR FETCHING ASSIGNMENTS: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // THEME
  // ─────────────────────────────────────────────────────────────────────────
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

  Future<void> _openInMaps(LatLng location) async {
    final lat = location.latitude;
    final lng = location.longitude;
    final Uri url;
    if (Platform.isIOS) {
      url = Uri.parse('https://maps.apple.com/?q=$lat,$lng&ll=$lat,$lng&z=15');
    } else {
      url = Uri.parse('https://maps.google.com/maps?q=$lat,$lng');
    }
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

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

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text('$label:', style: TextStyle(color: _secondaryTextColor)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontWeight: FontWeight.w500, color: _textColor)),
          ),
        ],
      ),
    );
  }

  Widget _copyableInfoRow(BuildContext ctx, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text('$label:', style: TextStyle(color: _secondaryTextColor)),
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

  // ─────────────────────────────────────────────────────────────────────────
  // DETAILS MODAL (Marketplace)
  // ─────────────────────────────────────────────────────────────────────────
  void _showShiftDetails(Map<String, dynamic> shift) {
    bool isSatellite = false;
    final mapController = MapController();

    final bool hasSupervisor = (shift['supervisorName'] as String).isNotEmpty ||
        (shift['supervisorEmail'] as String).isNotEmpty ||
        (shift['supervisorPhone'] as String).isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Center(
                      child: Container(
                        width: 50,
                        height: 5,
                        decoration: BoxDecoration(
                          color: _secondaryTextColor.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      children: [
                        Text(
                          '${shift["client"]} - ${shift["site"]}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _textColor,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _infoRow('Date',
                            '${_formatDate(shift["fromDate"])} → ${_formatDate(shift["toDate"])}'),
                        Builder(builder: (_) {
                          final days = (shift['daysOfWeek'] as List?)?.cast<String>() ?? [];
                          if (days.isEmpty || days.length == 7) return const SizedBox.shrink();
                          const labels = {
                            'MONDAY': 'Mon', 'TUESDAY': 'Tue', 'WEDNESDAY': 'Wed',
                            'THURSDAY': 'Thu', 'FRIDAY': 'Fri', 'SATURDAY': 'Sat', 'SUNDAY': 'Sun'
                          };
                          final readable = days.map((d) => labels[d] ?? d).join(', ');
                          return _infoRow('Recurring', readable);
                        }),
                        const SizedBox(height: 2),
                        _infoRow('From', _toAmPm(shift['from'])),
                        _infoRow('To',   _toAmPm(shift['to'])),
                        const SizedBox(height: 16),

                        // Supervisor section
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
                                    'Supervisor',
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
                                  'No supervisor assigned',
                                  style: TextStyle(
                                    color: _secondaryTextColor,
                                    fontStyle: FontStyle.italic,
                                    fontSize: 13,
                                  ),
                                )
                              else ...[
                                if ((shift['supervisorName'] as String).isNotEmpty)
                                  _infoRow('Name', shift['supervisorName']),
                                if ((shift['supervisorEmail'] as String).isNotEmpty)
                                  _copyableInfoRow(ctx, 'Email', shift['supervisorEmail']),
                                if ((shift['supervisorPhone'] as String).isNotEmpty)
                                  _copyableInfoRow(ctx, 'Phone', shift['supervisorPhone']),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Map
                        Text(
                          'Location',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _textColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 230,
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
                                    initialCenter: shift['location'],
                                    initialZoom: 15,
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate: isSatellite
                                          ? 'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                                          : 'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
                                      subdomains: const ['a', 'b', 'c'],
                                      userAgentPackageName:
                                      'com.blackfabricsecurity.crossplatformblackfabric',
                                    ),
                                    MarkerLayer(
                                      markers: [
                                        Marker(
                                          point: shift['location'],
                                          width: 50,
                                          height: 50,
                                          child: GestureDetector(
                                            onTap: () =>
                                                _openInMaps(shift['location']),
                                            child: const Icon(
                                                Icons.location_on,
                                                color: Colors.red,
                                                size: 40),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  child: FloatingActionButton(
                                    mini: true,
                                    heroTag: 'satellite_toggle',
                                    backgroundColor: Colors.black87,
                                    onPressed: () => setModalState(
                                            () => isSatellite = !isSatellite),
                                    child: Icon(
                                      isSatellite ? Icons.map : Icons.satellite,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 10,
                                  right: 10,
                                  child: FloatingActionButton(
                                    mini: true,
                                    heroTag: 'center_map',
                                    backgroundColor: Colors.black87,
                                    onPressed: () =>
                                        mapController.move(shift['location'], 15),
                                    child: const Icon(Icons.my_location,
                                        color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Take shift button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              try {
                                final prefs =
                                await SharedPreferences.getInstance();
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
                                final res = await api.put(
                                  'assignments/assign/${shift["assignmentId"]}',
                                  {'userId': userId},
                                );

                                if (res.statusCode == 200) {
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
                                } else if (res.statusCode == 409) {
                                  AwesomeDialog(
                                    context: ctx,
                                    dialogType: DialogType.warning,
                                    title: 'Conflict',
                                    desc: res.body,
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
                                debugPrint('ERROR SENDING REQUEST: $e');
                              }
                            },
                            icon: const Icon(Icons.send, color: Colors.white),
                            label: const Text('Take the shift',
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
                            onPressed: () => _openInMaps(shift['location']),
                            icon: const Icon(Icons.map, color: Colors.white),
                            label: const Text('Open in Maps',
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

                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHIFT CARD (Marketplace)
  // ─────────────────────────────────────────────────────────────────────────
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
                    '${shift["client"]} - ${shift["site"]}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: _textColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_toAmPm(shift["from"])} - ${_toAmPm(shift["to"])}',
                    style: TextStyle(fontSize: 12, color: _secondaryTextColor),
                  ),
                  Builder(builder: (_) {
                    final days = (shift['daysOfWeek'] as List?)?.cast<String>() ?? [];
                    if (days.isEmpty || days.length == 7) return const SizedBox.shrink();
                    const labels = {
                      'MONDAY': 'Mon', 'TUESDAY': 'Tue', 'WEDNESDAY': 'Wed',
                      'THURSDAY': 'Thu', 'FRIDAY': 'Fri', 'SATURDAY': 'Sat', 'SUNDAY': 'Sun'
                    };
                    final readable = days.map((d) => labels[d] ?? d).join(', ');
                    return Text(
                      '↺ $readable only',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF4F46E5), fontWeight: FontWeight.w600),
                    );
                  }),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 18, color: _secondaryTextColor),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HISTORY CARD
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHistoryCard(Map<String, dynamic> item) {
    final bool isTaken = item['guardName'] != null &&
        (item['guardName'] as String).isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isTaken
              ? const Color(0xFF22C55E).withOpacity(0.35)
              : _borderColor,
          width: isTaken ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isTaken
                  ? const Color(0xFF22C55E).withOpacity(0.12)
                  : _secondaryTextColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isTaken ? Icons.check_circle_outline : Icons.hourglass_empty,
              color: isTaken
                  ? const Color(0xFF22C55E)
                  : _secondaryTextColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item["client"]} — ${item["site"]}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _textColor,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_formatDate(item["fromDate"])} → ${_formatDate(item["toDate"])}  •  ${_toAmPm(item["from"])} – ${_toAmPm(item["to"])}',
                  style: TextStyle(fontSize: 12, color: _secondaryTextColor),
                ),
                const SizedBox(height: 6),
                // Posted by line
                if (item['postedByName'] != null && (item['postedByName'] as String).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Icon(Icons.upload_outlined, size: 13, color: _secondaryTextColor),
                        const SizedBox(width: 4),
                        Text(
                          'Posted by ${item["postedByName"]}${_formatTs(item["postedAt"])}',
                          style: TextStyle(fontSize: 11, color: _secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                if (isTaken)
                  Row(
                    children: [
                      const Icon(Icons.person, size: 14, color: Color(0xFF22C55E)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Taken by ${item["acceptedByName"] ?? item["guardName"]}${_formatTs(item["acceptedAt"])}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF22C55E),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    'Still open — no guard claimed yet',
                    style: TextStyle(
                      fontSize: 12,
                      color: _secondaryTextColor,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isTaken
                  ? const Color(0xFF22C55E).withOpacity(0.12)
                  : const Color(0xFFF59E0B).withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isTaken ? 'TAKEN' : 'OPEN',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: isTaken
                    ? const Color(0xFF22C55E)
                    : const Color(0xFFF59E0B),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Column(
        children: [
          // Tab bar
          Container(
            color: _isDarkMode ? const Color(0xFF1E293B) : Colors.white,
            child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF4F46E5),
              indicatorWeight: 3,
              labelColor: const Color(0xFF4F46E5),
              unselectedLabelColor: _secondaryTextColor,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: const [
                Tab(text: 'Marketplace'),
                Tab(text: 'My History'),
              ],
            ),
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // ── Marketplace ─────────────────────────────────────────────
                _shifts.isEmpty
                    ? Center(
                  child: Text(
                    'No open shifts available',
                    style: TextStyle(color: _secondaryTextColor, fontSize: 15),
                  ),
                )
                    : RefreshIndicator(
                  onRefresh: _fetchShifts,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _shifts.length,
                    itemBuilder: (context, i) =>
                        _buildShiftCard(_shifts[i]),
                  ),
                ),

                // ── History ─────────────────────────────────────────────────
                !_showHistoryTab
                    ? Center(
                  child: Text(
                    'History not available',
                    style: TextStyle(color: _secondaryTextColor, fontSize: 15),
                  ),
                )
                    : _history.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_toggle_off,
                          size: 48, color: _secondaryTextColor),
                      const SizedBox(height: 12),
                      Text(
                        'No open shift history yet',
                        style: TextStyle(
                            color: _secondaryTextColor, fontSize: 15),
                      ),
                    ],
                  ),
                )
                    : RefreshIndicator(
                  onRefresh: () async {
                    await _initHistory();
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _history.length,
                    itemBuilder: (context, i) =>
                        _buildHistoryCard(_history[i]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
