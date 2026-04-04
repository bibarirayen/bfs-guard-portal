import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ndef/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/ApiService.dart';
import 'login_screen.dart';
import 'package:ndef/ndef.dart';

// ─── Main Page: Site list with client filter ──────────────────────────────────

class NfcAssignPage extends StatefulWidget {
  const NfcAssignPage({super.key});

  @override
  State<NfcAssignPage> createState() => _NfcAssignPageState();
}

class _NfcAssignPageState extends State<NfcAssignPage> {
  final ApiService apiService = ApiService();
  List<Map<String, dynamic>> allSites = [];
  List<Map<String, dynamic>> clients = [];
  int? selectedClientId;
  bool loading = true;
  bool _isDarkMode = true;

  // ─── theme ───────────────────────────────────────────────────────────────
  Color get backgroundColor    => _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get textColor          => _isDarkMode ? Colors.white             : const Color(0xFF1E293B);
  Color get cardColor          => _isDarkMode ? const Color(0xFF1E293B)  : Colors.white;
  Color get borderColor        => _isDarkMode ? const Color(0xFF334155)  : const Color(0xFFE2E8F0);
  Color get secondaryTextColor => _isDarkMode ? Colors.grey[400]!        : Colors.grey[600]!;
  Color get primaryColor       => const Color(0xFF4F46E5);
  Color get dangerColor        => const Color(0xFFEF4444);

  List<Map<String, dynamic>> get filteredSites {
    if (selectedClientId == null) return allSites;
    return allSites
        .where((s) => s['clientId'] != null &&
            (s['clientId'] as num).toInt() == selectedClientId)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final results = await Future.wait([
        apiService.get('clients'),
        apiService.get('sites'),
      ]);
      final clientsRes = results[0];
      final sitesRes = results[1];
      if (clientsRes.statusCode == 200 && sitesRes.statusCode == 200) {
        setState(() {
          clients = List<Map<String, dynamic>>.from(jsonDecode(clientsRes.body));
          allSites = List<Map<String, dynamic>>.from(jsonDecode(sitesRes.body));
          loading = false;
        });
      } else {
        throw Exception('Failed to load data');
      }
    } catch (e) {
      setState(() => loading = false);
      _snack('Error loading data: $e', isError: true);
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
    final sites = filteredSites;
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
                'assets/tt.png',
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
                // ── client filter ─────────────────────────────────────
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: selectedClientId,
                      isExpanded: true,
                      dropdownColor: cardColor,
                      style: TextStyle(color: textColor, fontSize: 14),
                      icon: Icon(Icons.expand_more_rounded,
                          color: secondaryTextColor),
                      hint: Text('All Clients',
                          style:
                              TextStyle(color: secondaryTextColor, fontSize: 14)),
                      items: [
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text('All Clients',
                              style: TextStyle(color: secondaryTextColor)),
                        ),
                        ...clients.map((c) => DropdownMenuItem<int?>(
                              value: c['id'] != null
                                  ? (c['id'] as num).toInt()
                                  : null,
                              child: Text(c['name'] ?? 'Unnamed',
                                  style: TextStyle(color: textColor)),
                            )),
                      ],
                      onChanged: (v) => setState(() => selectedClientId = v),
                    ),
                  ),
                ),

                // ── stats bar ─────────────────────────────────────────
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.business_rounded,
                          color: primaryColor, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        '${sites.length} site${sites.length != 1 ? 's' : ''}',
                        style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 14),
                      ),
                    ],
                  ),
                ),

                // ── sites list ────────────────────────────────────────
                Expanded(
                  child: sites.isEmpty
                      ? Center(
                          child: Text('No sites found',
                              style: TextStyle(
                                  color: secondaryTextColor, fontSize: 14)),
                        )
                      : ListView.builder(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: sites.length,
                          itemBuilder: (context, index) {
                            final site = sites[index];
                            return GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => _SiteStopsPage(
                                    siteId: (site['id'] as num).toInt(),
                                    siteName: site['name'] ?? 'Site',
                                    isDarkMode: _isDarkMode,
                                  ),
                                ),
                              ),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color:
                                              primaryColor.withOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                            Icons.location_city_rounded,
                                            color: primaryColor,
                                            size: 20),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              site['name'] ?? 'Unnamed Site',
                                              style: TextStyle(
                                                  color: textColor,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (site['clientName'] != null) ...[
                                              const SizedBox(height: 3),
                                              Text(
                                                site['clientName'],
                                                style: TextStyle(
                                                    color: secondaryTextColor,
                                                    fontSize: 12),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.chevron_right_rounded,
                                          color: secondaryTextColor, size: 20),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

// ─── Site Stops Page ──────────────────────────────────────────────────────────

class _SiteStopsPage extends StatefulWidget {
  final int siteId;
  final String siteName;
  final bool isDarkMode;

  const _SiteStopsPage({
    required this.siteId,
    required this.siteName,
    required this.isDarkMode,
  });

  @override
  State<_SiteStopsPage> createState() => _SiteStopsPageState();
}

class _SiteStopsPageState extends State<_SiteStopsPage> {
  final ApiService apiService = ApiService();
  List<Map<String, dynamic>> stops = [];
  bool loading = true;
  bool scanning = false;
  late bool _isDarkMode;

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
    _isDarkMode = widget.isDarkMode;
    _fetchStops();
  }

  Future<void> _fetchStops() async {
    try {
      final response = await apiService.get('stops/site/${widget.siteId}');
      if (response.statusCode == 200) {
        final data =
            List<Map<String, dynamic>>.from(jsonDecode(response.body));
        setState(() {
          stops = data;
          loading = false;
        });
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
      if (!serviceEnabled) {
        _snack('Location services are disabled', isError: true);
        return;
      }

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
        _fetchStops();
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
        final response =
            await apiService.post('stops/$stopId/nfc', {'nfcTagId': nfcTagId});
        if (response.statusCode == 409 && mounted) {
          final body = jsonDecode(response.body);
          final conflictStopName = body['stopName'] ?? 'another stop';
          final confirm = await _showConflictModal(conflictStopName);
          if (confirm == true && mounted) {
            final forceResponse = await apiService.post(
              'stops/$stopId/nfc',
              {'nfcTagId': nfcTagId, 'force': 'true'},
            );
            if (forceResponse.statusCode == 200 && mounted) {
              _snack('NFC tag reassigned!');
              _fetchStops();
            } else if (mounted) {
              _snack('Backend error: ${forceResponse.statusCode}',
                  isError: true);
            }
          }
        } else if (response.statusCode == 200 && mounted) {
          _snack('NFC tag assigned!');
          _fetchStops();
        } else if (mounted) {
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Reset NFC Tag',
            style:
                TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        content: Text(
          'This will erase the NFC tag data and unlink it from this stop.',
          style: TextStyle(color: secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text('Cancel', style: TextStyle(color: secondaryTextColor)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: dangerColor),
            child: const Text('Reset',
                style: TextStyle(color: Colors.white)),
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
      await FlutterNfcKit.writeNDEFRecords(
          [TextRecord(language: 'en', text: '')]);
      await FlutterNfcKit.finish(
          iosAlertMessage: 'NFC tag reset successfully!');

      final response =
          await apiService.post('stops/$stopId/nfc', {'nfcTagId': null});
      if (response.statusCode == 200) {
        if (mounted) _snack('NFC tag reset!');
      } else {
        throw Exception('Backend error: ${response.statusCode}');
      }
    } catch (e) {
      try {
        await FlutterNfcKit.finish(
            iosErrorMessage: 'Failed to reset NFC tag.');
      } catch (_) {}
      if (mounted) {
        String errorMsg = 'Error resetting NFC tag.';
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('timeout')) {
          errorMsg = 'Timed out. Hold tag steady.';
        } else if (errStr.contains('user cancel') ||
            errStr.contains('cancelled')) {
          errorMsg = 'Reset cancelled.';
        } else if (errStr.contains('tag connection lost')) {
          errorMsg = 'Tag moved away. Hold steady.';
        }
        _snack(errorMsg, isError: true);
      }
    } finally {
      if (mounted) setState(() => scanning = false);
    }
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

  Future<bool?> _showConflictModal(String conflictStopName) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: warningColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.warning_amber_rounded,
                  color: warningColor, size: 22),
            ),
            const SizedBox(width: 12),
            Text('Tag Already Assigned',
                style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This NFC tag is already assigned to:',
                style: TextStyle(color: secondaryTextColor, fontSize: 13)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: warningColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: warningColor.withOpacity(0.3)),
              ),
              child: Text(conflictStopName,
                  style: TextStyle(
                      color: warningColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ),
            const SizedBox(height: 12),
            Text('Do you want to reassign it to this stop instead?',
                style: TextStyle(color: secondaryTextColor, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text('Cancel', style: TextStyle(color: secondaryTextColor)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: warningColor,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Reassign',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: textColor, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
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
            Expanded(
              child: Text(
                widget.siteName,
                style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: () => setState(() => _isDarkMode = !_isDarkMode),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              child: Image.asset(
                'assets/tt.png',
                height: 22,
                width: 22,
                color: _isDarkMode ? null : const Color(0xFF1E293B),
                colorBlendMode: _isDarkMode ? null : BlendMode.srcIn,
              ),
            ),
          ),
        ],
      ),
      body: loading
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : Column(
              children: [
                // ── stats bar ─────────────────────────────────────────
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
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
                        '${stops.length} checkpoint${stops.length != 1 ? 's' : ''}',
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

                // ── stops list ────────────────────────────────────────
                Expanded(
                  child: stops.isEmpty
                      ? Center(
                          child: Text('No checkpoints for this site',
                              style: TextStyle(
                                  color: secondaryTextColor, fontSize: 14)),
                        )
                      : ListView.builder(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
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
                                    // ── stop info ─────────────────────
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                          const SizedBox(height: 6),
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

                                    // ── action buttons ────────────────
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
                                          onTap: () =>
                                              setCurrentLocation(stop['id']),
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