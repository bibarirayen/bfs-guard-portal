import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/ApiService.dart';
import 'login_screen.dart';

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
      setState(() {
        loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching stops: $e')),
      );
    }
  }

  Future<void> assignNfc(int stopId) async {
    setState(() {
      scanning = true;
    });

    try {
      // 1️⃣ Poll the NFC tag
      NFCTag tag = await FlutterNfcKit.poll(timeout: const Duration(seconds: 10));
      String nfcTagId = tag.id;

      // 2️⃣ Prepare stopId as NDEF payload (UTF-8)
      Uint8List payload = Uint8List.fromList(utf8.encode(stopId.toString()));

      // 3️⃣ Write as NDEF record
      await FlutterNfcKit.writeNDEFRecords([
        NDEFRecord(
          type: Uint8List.fromList(utf8.encode('T')), // "T" = text record
          payload: payload,
        ),
      ]);

      // 4️⃣ Finish NFC session
      await FlutterNfcKit.finish();

      // 5️⃣ Send NFC ID to backend
      final response = await apiService.post(
        'stops/$stopId/nfc',
        {'nfcTagId': nfcTagId},
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('NFC tag assigned successfully!')),
        );
      } else {
        throw Exception('Failed to save NFC tag');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error scanning/writing NFC: $e')),
      );
    } finally {
      setState(() {
        scanning = false;
      });
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
        title: const Text('Assign NFC Tags',
          style: const TextStyle(
            color: Colors.white, // AppBar title is white
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
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                          onPressed: scanning ? null : () => assignNfc(stop['id']),
                          icon: const Icon(Icons.nfc),

                          label: Text(scanning ? 'Scanning...' : 'Add NFC',
                            style: const TextStyle(color: Colors.white), // Button text white
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Logout Section
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _logout,
                  icon: Icon(Icons.logout, color: Colors.white),
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
