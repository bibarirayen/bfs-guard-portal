import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
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

  Color get backgroundColor => _isDarkMode ? Color(0xFF0F172A) : Color(0xFFF8FAFC);
  Color get textColor => _isDarkMode ? Colors.white : Color(0xFF1E293B);
  Color get cardColor => _isDarkMode ? Color(0xFF1E293B) : Colors.white;
  Color get borderColor => _isDarkMode ? Color(0xFF334155) : Color(0xFFE2E8F0);
  Color get secondaryTextColor => _isDarkMode ? Colors.white : Colors.white;
  Color get primaryColor => _isDarkMode ? Color(0xFF4F46E5) : Color(0xFF3B82F6);
  Color get dangerColor => Color(0xFFEF4444);
  Color get warningColor => Color(0xFFF59E0B);

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
        setState(() {
          stops = data;
          loading = false;
        });
      } else {
        throw Exception('Failed to fetch stops');
      }
    } catch (e) {
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching stops: $e')),
      );
    }
  }

  Future<void> assignNfc(int stopId) async {
    final availability = await FlutterNfcKit.nfcAvailability;
    if (availability != NFCAvailability.available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('NFC is not available on this device')),
      );
      return;
    }

    setState(() => scanning = true);
    String? nfcTagId;

    try {
      NFCTag tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 20),
        iosMultipleTagMessage: 'Multiple tags detected. Present only one tag.',
        iosAlertMessage: 'Hold your iPhone near the NFC tag to assign it.',
      );

      nfcTagId = tag.id;
      await Future.delayed(const Duration(milliseconds: 150));

      await FlutterNfcKit.writeNDEFRecords([
        TextRecord(
          language: 'en',
          text: stopId.toString(),
        ),
      ]);

      await FlutterNfcKit.finish(iosAlertMessage: 'NFC tag assigned successfully!');

      final response = await apiService.post(
        'stops/$stopId/nfc',
        {'nfcTagId': nfcTagId},
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('NFC tag assigned successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Backend error: ${response.statusCode}');
      }
    } catch (e) {
      try {
        await FlutterNfcKit.finish(iosErrorMessage: 'Failed to assign NFC tag.');
      } catch (_) {}

      if (mounted) {
        String errorMsg = 'Error scanning/writing NFC. Please try again.';
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('session invalidated') || errStr.contains('500')) {
          errorMsg = 'NFC session lost. Hold the tag steady and try again.';
        } else if (errStr.contains('timeout')) {
          errorMsg = 'Timed out. Bring the tag closer and try again.';
        } else if (errStr.contains('user cancel') || errStr.contains('cancelled')) {
          errorMsg = 'Scan cancelled.';
        } else if (errStr.contains('tag connection lost')) {
          errorMsg = 'Tag moved away too quickly. Hold it steady and retry.';
        } else if (errStr.contains('ndef')) {
          errorMsg = 'This tag may not support NDEF. Try a different tag.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg)),
        );
      }
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  Future<void> resetNfc(int stopId) async {
    // Confirm before resetting
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor,
        title: Text('Reset NFC Tag', style: TextStyle(color: textColor)),
        content: Text(
          'This will erase the NFC tag data and unlink it from this stop. Hold the tag near your phone when ready.',
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('NFC is not available on this device')),
      );
      return;
    }

    setState(() => scanning = true);

    try {
      await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 20),
        iosMultipleTagMessage: 'Multiple tags detected. Present only one tag.',
        iosAlertMessage: 'Hold your iPhone near the NFC tag to reset it.',
      );

      await Future.delayed(const Duration(milliseconds: 150));

      // Write an empty Text record to overwrite existing data
      await FlutterNfcKit.writeNDEFRecords([
        TextRecord(
          language: 'en',
          text: '',
        ),
      ]);

      await FlutterNfcKit.finish(iosAlertMessage: 'NFC tag reset successfully!');

      // Clear nfcTagId in the backend (set to null)
      final response = await apiService.post(
        'stops/$stopId/nfc',
        {'nfcTagId': null},
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('NFC tag reset successfully!'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        throw Exception('Backend error: ${response.statusCode}');
      }
    } catch (e) {
      try {
        await FlutterNfcKit.finish(iosErrorMessage: 'Failed to reset NFC tag.');
      } catch (_) {}

      if (mounted) {
        String errorMsg = 'Error resetting NFC tag. Please try again.';
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('timeout')) {
          errorMsg = 'Timed out. Bring the tag closer and try again.';
        } else if (errStr.contains('user cancel') || errStr.contains('cancelled')) {
          errorMsg = 'Reset cancelled.';
        } else if (errStr.contains('tag connection lost')) {
          errorMsg = 'Tag moved away too quickly. Hold it steady and retry.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg)),
        );
      }
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        title: const Text(
          'Assign NFC Tags',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: dangerColor),
            onPressed: _logout,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: stops.length,
                  itemBuilder: (context, index) {
                    final stop = stops[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      color: cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                        side: BorderSide(color: borderColor),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            // Stop info
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    stop['name'] ?? 'Unnamed Stop',
                                    style: TextStyle(
                                      color: textColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Site: ${stop['siteName'] ?? '-'}',
                                    style: TextStyle(
                                        color: secondaryTextColor,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Assign button
                            ElevatedButton.icon(
                              onPressed: scanning
                                  ? null
                                  : () => assignNfc(stop['id']),
                              icon: const Icon(Icons.nfc, size: 16),
                              label: Text(
                                scanning ? '...' : 'Assign',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Reset button
                            ElevatedButton.icon(
                              onPressed: scanning
                                  ? null
                                  : () => resetNfc(stop['id']),
                              icon: const Icon(Icons.delete_outline,
                                  size: 16),
                              label: const Text(
                                'Reset',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 13),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: warningColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout, color: Colors.white),
                  label: const Text('Sign Out'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: dangerColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}