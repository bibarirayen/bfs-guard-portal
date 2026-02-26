import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ndef/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/ApiService.dart';
import 'login_screen.dart';
import 'package:ndef/ndef.dart';

class NfcAssignPage extends StatefulWidget {
  const NfcAssignPage({super.key});

  @override
  State<NfcAssignPage> createState() => _NfcAssignPageState();
}

class _NfcAssignPageState extends State<NfcAssignPage> {
  final ApiService apiService = ApiService();
  List<Map<String, dynamic>> stops = [];
  bool loading = true;
  bool scanning = false;
  bool _isDarkMode = true;

  // ─── theme ───────────────────────────────────────────────────────────────
  Color get backgroundColor    => _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get textColor          => _isDarkMode ? Colors.white             : const Color(0xFF1E293B);
  Color get cardColor          => _isDarkMode ? const Color(0xFF1E293B)  : Colors.white;
  Color get borderColor        => _isDarkMode ? const Color(0xFF334155)  : const Color(0xFFE2E8F0);
  Color get secondaryTextColor => _isDarkMode ? Colors.grey[400]!        : Colors.grey[600]!;
  Color get primaryColor       => const Color(0xFF4F46E5);
  Color get dangerColor        => const Color(0xFFEF4444);
  Color get warningColor       => const Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    fetchStops();
  }

  Future<void> fetchStops() async {
    try {
      final response = await apiService.get('stops');
      if (response.statusCode == 200) {
        final data = List<Map<String, dynamic>>.from(jsonDecode(response.body));
        setState(() { stops = data; loading = false; });
      } else {
        throw Exception('Failed to fetch stops');
      }
    } catch (e) {
      setState(() => loading = false);
      _snack('Error fetching stops: $e', isError: true);
    }
  }

  Future<void> setCurrentLocation(int stopId) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) { _snack('Location services are disabled', isError: true); return; }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _snack('Location permission denied', isError: true);
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      final response = await apiService.put('stops/$stopId/location', {
        'latitude': position.latitude,
        'longitude': position.longitude,
      });

      if (response.statusCode == 200) {
        _snack('Stop location updated!');
        fetchStops();
      } else {
        _snack('Backend error: ${response.statusCode}', isError: true);
      }
    } catch (e) {
      _snack('Failed to get location: $e', isError: true);
    }
  }

  Future<void> assignNfc(int stopId) async {
    final availability = await FlutterNfcKit.nfcAvailability;
    if (availability != NFCAvailability.available) {
      _snack('NFC not available on this device', isError: true);
      return;
    }

    setState(() => scanning = true);
    String? nfcTagId;

    try {
      final tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 20),
        iosMultipleTagMessage: 'Multiple tags detected. Present only one tag.',
        iosAlertMessage: 'Hold your iPhone near the NFC tag to assign it.',
      );
      nfcTagId = tag.id;

      await FlutterNfcKit.writeNDEFRecords([
        TextRecord(language: 'en', text: stopId.toString()),
      ]);

      if (mounted) _snack('NFC tag assigned!');
    } catch (e) {
      String errMsg = 'Error scanning NFC tag.';
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('user cancel') || errStr.contains('cancelled')) {
        errMsg = 'Scan cancelled.';
      } else if (errStr.contains('timeout')) {
        errMsg = 'Timed out. Bring the tag closer.';
      } else if (errStr.contains('session invalidated')) {
        errMsg = 'NFC session lost. Try again.';
      } else if (errStr.contains('ndef')) {
        errMsg = 'Tag may not support NDEF.';
      }
      if (mounted) _snack(errMsg, isError: true);
    } finally {
      try { await FlutterNfcKit.finish(); } catch (_) {}
      if (mounted) setState(() => scanning = false);
    }

    if (nfcTagId != null) {
      try {
        final response = await apiService.post('stops/$stopId/nfc', {'nfcTagId': nfcTagId});
        if (response.statusCode != 200 && mounted) {
          _snack('Backend error: ${response.statusCode}', isError: true);
        }
      } catch (e) {
        if (mounted) _snack('Failed to save NFC tag: $e', isError: true);
      }
    }
  }

  Future<void> resetNfc(int stopId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Reset NFC Tag',
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        content: Text(
          'This will erase the NFC tag data and unlink it from this stop.',
          style: TextStyle(color: secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: secondaryTextColor)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: dangerColor),
            child: const Text('Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final availability = await FlutterNfcKit.nfcAvailability;
    if (availability != NFCAvailability.available) {
      _snack('NFC not available', isError: true);
      return;
    }

    setState(() => scanning = true);

    try {
      await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 20),
        iosAlertMessage: 'Hold your iPhone near the NFC tag to reset it.',
      );
      await Future.delayed(const Duration(milliseconds: 150));
      await FlutterNfcKit.writeNDEFRecords([TextRecord(language: 'en', text: '')]);
      await FlutterNfcKit.finish(iosAlertMessage: 'NFC tag reset successfully!');

      final response = await apiService.post('stops/$stopId/nfc', {'nfcTagId': null});
      if (response.statusCode == 200) {
        if (mounted) _snack('NFC tag reset!');
      } else {
        throw Exception('Backend error: ${response.statusCode}');
      }
    } catch (e) {
      try { await FlutterNfcKit.finish(iosErrorMessage: 'Failed to reset NFC tag.'); } catch (_) {}
      if (mounted) {
        String errorMsg = 'Error resetting NFC tag.';
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('timeout')) errorMsg = 'Timed out. Hold tag steady.';
        else if (errStr.contains('user cancel') || errStr.contains('cancelled')) errorMsg = 'Reset cancelled.';
        else if (errStr.contains('tag connection lost')) errorMsg = 'Tag moved away. Hold steady.';
        _snack(errorMsg, isError: true);
      }
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.nfc, color: primaryColor, size: 18),
            ),
            const SizedBox(width: 10),
            Text('Assign NFC Tags',
                style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
          ],
        ),
        actions: [
          // Theme toggle
          GestureDetector(
            onTap: () => setState(() => _isDarkMode = !_isDarkMode),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              child: Image.asset(
                'assets/applogo.png',
                height: 22,
                width: 22,
                color: _isDarkMode ? null : const Color(0xFF1E293B),
                colorBlendMode: _isDarkMode ? null : BlendMode.srcIn,
              ),
            ),
          ),
          // Logout
          Container(
            margin: const EdgeInsets.only(right: 12),
            child: IconButton(
              icon: Icon(Icons.logout_rounded, color: dangerColor),
              onPressed: _logout,
              tooltip: 'Sign Out',
            ),
          ),
        ],
      ),
      body: loading
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : Column(
        children: [
          // ── header stats bar ─────────────────────────────────────
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Icon(Icons.location_on_rounded,
                    color: primaryColor, size: 20),
                const SizedBox(width: 10),
                Text(
                  '${stops.length} checkpoint${stops.length != 1 ? 's' : ''} loaded',
                  style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14),
                ),
                const Spacer(),
                if (scanning)
                  Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            color: primaryColor, strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text('Scanning...',
                          style: TextStyle(
                              color: primaryColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
              ],
            ),
          ),

          // ── stop list ─────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: stops.length,
              itemBuilder: (context, index) {
                final stop = stops[index];
                final hasNfc = stop['nfcTagId'] != null &&
                    stop['nfcTagId'].toString().isNotEmpty;
                final hasGps = stop['latitude'] != null;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        // ── stop info ─────────────────────────────
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                stop['name'] ?? 'Unnamed Stop',
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                stop['siteName'] ?? '–',
                                style: TextStyle(
                                    color: secondaryTextColor,
                                    fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              // Status badges
                              Row(
                                children: [
                                  _badge(
                                    hasNfc ? 'NFC ✓' : 'No NFC',
                                    hasNfc
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFF475569),
                                  ),
                                  const SizedBox(width: 6),
                                  _badge(
                                    hasGps ? 'GPS ✓' : 'No GPS',
                                    hasGps
                                        ? const Color(0xFF3B82F6)
                                        : const Color(0xFF475569),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 10),

                        // ── action buttons (icon only, compact) ───
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _actionIconBtn(
                              icon: Icons.nfc_rounded,
                              color: primaryColor,
                              tooltip: 'Assign NFC',
                              onTap: scanning
                                  ? null
                                  : () => assignNfc(stop['id']),
                            ),
                            const SizedBox(width: 8),
                            _actionIconBtn(
                              icon: Icons.refresh_rounded,
                              color: warningColor,
                              tooltip: 'Reset NFC',
                              onTap: scanning
                                  ? null
                                  : () => resetNfc(stop['id']),
                            ),
                            const SizedBox(width: 8),
                            _actionIconBtn(
                              icon: Icons.my_location_rounded,
                              color: const Color(0xFF10B981),
                              tooltip: 'Set GPS',
                              onTap: () => setCurrentLocation(stop['id']),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // ── sign out button ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded,
                    color: Colors.white, size: 18),
                label: const Text('Sign Out',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: dangerColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── compact icon button ───────────────────────────────────────────────────
  Widget _actionIconBtn({
    required IconData icon,
    required Color color,
    required String tooltip,
    VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedOpacity(
          opacity: onTap == null ? 0.4 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.3), width: 1),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
        ),
      ),
    );
  }

  // ── status badge ──────────────────────────────────────────────────────────
  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}