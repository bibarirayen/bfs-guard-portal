import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/ApiService.dart';

class DispatchContactsPage extends StatefulWidget {
  const DispatchContactsPage({super.key});

  @override
  State<DispatchContactsPage> createState() => _DispatchContactsPageState();
}

class _DispatchContactsPageState extends State<DispatchContactsPage> {
  // ---------- THEME ----------
  final bool _isDarkMode = true;

  Color get _backgroundColor =>
      _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _cardColor =>
      _isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  Color get _borderColor =>
      _isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get _textColor =>
      _isDarkMode ? Colors.white : const Color(0xFF1E293B);
  Color get _secondaryTextColor =>
      _isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
  Color get _primaryColor => const Color(0xFF4F46E5);

  final api = ApiService();

  List<dynamic> _contacts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  // ================= FETCH =================
  Future<void> _fetchContacts() async {
    setState(() => _loading = true);

    try {
      final res = await api.get("dispatch");

      if (res.statusCode == 200) {
        setState(() {
          _contacts = jsonDecode(res.body);
          _loading = false;
        });
      } else {
        throw Exception("Failed to load dispatch contacts");
      }
    } catch (e) {
      debugPrint("Dispatch fetch error: $e");
      setState(() => _loading = false);
    }
  }

  // ================= COPY =================
  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$label copied"),
        backgroundColor: _primaryColor,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [


              Expanded(
                child: ListView.builder(
                  itemCount: _contacts.length,
                  itemBuilder: (_, i) {
                    final c = _contacts[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Name
                          Text(
                            c['name'] ?? '',
                            style: TextStyle(
                              color: _textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),

                          // Role
                          const SizedBox(height: 4),
                          Text(
                            c['role'] ?? '',
                            style: TextStyle(
                              color: _secondaryTextColor,
                            ),
                          ),

                          const Divider(height: 20),

                          // Phone
                          _copyRow(
                            icon: Icons.phone,
                            text: c['phone'] ?? '',
                            onCopy: () =>
                                _copy("Phone number", c['phone']),
                          ),

                          const SizedBox(height: 10),

                          // Email
                          _copyRow(
                            icon: Icons.email,
                            text: c['email'] ?? '',
                            onCopy: () =>
                                _copy("Email", c['email']),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= UI HELPERS =================
  Widget _copyRow({
    required IconData icon,
    required String text,
    required VoidCallback onCopy,
  }) {
    return Row(
      children: [
        Icon(icon, color: _primaryColor, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: _textColor),
          ),
        ),
        IconButton(
          icon: Icon(Icons.copy, color: _secondaryTextColor, size: 18),
          onPressed: onCopy,
        ),
      ],
    );
  }
}
