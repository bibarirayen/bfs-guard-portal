import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/ApiService.dart';
import 'login_screen.dart';
import 'package:ndef/ndef.dart'; // add this import at the top

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
    // Check NFC availability first
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
      // STEP 1: Poll with iosAlertMessage — required on iOS 17+ to keep session alive
      NFCTag tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 20),
        iosMultipleTagMessage: 'Multiple tags detected. Present only one tag.',
        iosAlertMessage: 'Hold your iPhone near the NFC tag to assign it.',
      );

      nfcTagId = tag.id;

      // STEP 2: Small delay — iOS 18 needs breathing room after poll before write
      await Future.delayed(const Duration(milliseconds: 150));

      // STEP 3: Build a well-formed NDEF Text Record
      // iOS 18 strictly validates the TNF + type + payload structure.
      // A Text record (TNF=wellKnown, type=0x54) must have:
      //   payload[0] = status byte (bit7=0 for UTF-8, bits5-0 = lang code length)
      //   payload[1..n] = language code (e.g. 'en')
      //   payload[n+1..] = actual text
      final Uint8List langBytes = Uint8List.fromList(utf8.encode('en'));
      final Uint8List textBytes = Uint8List.fromList(utf8.encode(stopId.toString()));
      final Uint8List payload = Uint8List(1 + langBytes.length + textBytes.length);
      payload[0] = langBytes.length; // status byte: UTF-8 + lang length = 2
      payload.setRange(1, 1 + langBytes.length, langBytes);
      payload.setRange(1 + langBytes.length, payload.length, textBytes);
      await Future.delayed(const Duration(milliseconds: 150));

      // STEP 4: Write NDEF with proper TNF and type byte
      // ✅ CORRECT — proper TNF + raw byte 0x54
      await FlutterNfcKit.writeNDEFRecords([
        TextRecord(
          language: 'en',
          text: stopId.toString(),
        ),
      ]);

      // STEP 5: Finish with a success message (iOS shows native checkmark UI)
      await FlutterNfcKit.finish(iosAlertMessage: 'NFC tag assigned successfully!');

      // STEP 6: Save tag ID to backend
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
      // Always close the NFC session on error or iOS will stay in a hung state
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
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
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
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        title: Text(
                          stop['name'] ?? 'Unnamed Stop',
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          'Site: ${stop['siteName'] ?? '-'}',
                          style: TextStyle(color: secondaryTextColor),
                        ),
                        trailing: ElevatedButton.icon(
                          onPressed: scanning
                              ? null
                              : () => assignNfc(stop['id']),
                          icon: const Icon(Icons.nfc),
                          label: Text(
                            scanning ? 'Scanning...' : 'Add NFC',
                            style: const TextStyle(color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
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