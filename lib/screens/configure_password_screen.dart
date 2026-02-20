import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_screen.dart';

class ConfigurePasswordScreen extends StatefulWidget {
  final int userId;
  const ConfigurePasswordScreen({required this.userId, super.key});

  @override
  State<ConfigurePasswordScreen> createState() => _ConfigurePasswordScreenState();
}

class _ConfigurePasswordScreenState extends State<ConfigurePasswordScreen> {
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmController = TextEditingController();

  // ✅ SMS consent state
  bool _smsConsentChecked = false;

  void _savePassword() async {
    final password = passwordController.text;
    final confirm = confirmController.text;

    if (password.isEmpty || confirm.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all fields")),
      );
      return;
    }

    if (password != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Passwords do not match")),
      );
      return;
    }

    // ✅ Block submission if consent not given
    if (!_smsConsentChecked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please agree to receive SMS alerts to continue."),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final response = await http.put(
      Uri.parse(
        "https://api.blackfabricsecurity.com/api/users/newpassword/${widget.userId}",
      ),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "password": password,
      }),
    );

    if (response.statusCode == 200) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('jwt');

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: ${response.body}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade50,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "Configure Your Password",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "New Password"),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Confirm Password"),
              ),
              const SizedBox(height: 30),

              // ─────────────────────────────────────────────────────────────
              // ✅ SMS CONSENT CHECKBOX (required before saving)
              // ─────────────────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _smsConsentChecked ? Colors.blue.shade400 : Colors.grey.shade300,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Opt-in description header
                    const Text(
                      "Emergency SMS Alert Consent",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "I agree to receive emergency security SMS alerts from Black Fabric Security regarding my protected account or monitored location. "
                          "Message frequency varies based on security activity. "
                          "Standard message and data rates may apply. "
                          "Reply STOP to opt out at any time. Reply HELP for assistance. "
                          "My mobile number will not be sold or shared for promotional or marketing purposes.",
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.5),
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1),
                    const SizedBox(height: 14),

                    // ✅ The actual consent checkbox row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _smsConsentChecked,
                            activeColor: Colors.blue.shade600,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            onChanged: (val) => setState(() => _smsConsentChecked = val ?? false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _smsConsentChecked = !_smsConsentChecked),
                            child: const Text(
                              "I agree to receive emergency SMS alerts from Black Fabric Security. "
                                  "Message frequency may vary. Standard message and data rates may apply. "
                                  "Reply STOP to opt out. Reply HELP for assistance. "
                                  "Your mobile information will not be sold or shared for marketing purposes.",
                              style: TextStyle(fontSize: 12, color: Color(0xFF374151), height: 1.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _savePassword,
                child: const Text("Save"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}