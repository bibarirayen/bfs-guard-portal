import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:crossplatformblackfabric/screens/home_screen.dart';
import '../config/ApiService.dart';
import '../services/HeartbeatService.dart';
import 'configure_password_screen.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';

import 'nfcassignpage.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController emailController    = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool _obscurePassword  = true;
  bool _isLoading        = false;
  bool _rememberMe       = true;

  late AnimationController _animController;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  // ─── theme ───────────────────────────────────────────────────────────────
  static const Color _bg      = Color(0xFF0F172A);
  static const Color _card    = Color(0xFF1E293B);
  static const Color _border  = Color(0xFF334155);
  static const Color _primary = Color(0xFF4F46E5);
  static const Color _text    = Colors.white;
  static const Color _subtext = Color(0xFF94A3B8);

  // ─── SharedPreferences keys ──────────────────────────────────────────────
  static const _kEmail      = 'saved_email';
  static const _kPassword   = 'saved_password';
  static const _kRememberMe = 'remember_me';

  @override
  void initState() {
    super.initState();
    _initFirebaseMessaging();
    _loadSavedCredentials();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(
        parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
        parent: _animController, curve: Curves.easeOut));

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs      = await SharedPreferences.getInstance();
    final remember   = prefs.getBool(_kRememberMe) ?? true;
    final savedEmail = prefs.getString(_kEmail) ?? '';
    final savedPass  = prefs.getString(_kPassword) ?? '';

    if (remember && savedEmail.isNotEmpty) {
      setState(() {
        _rememberMe = true;
        emailController.text    = savedEmail;
        passwordController.text = savedPass;
      });
    } else {
      setState(() => _rememberMe = remember);
    }
  }

  Future<void> _saveCredentials(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString(_kEmail,    email);
      await prefs.setString(_kPassword, password);
      await prefs.setBool(_kRememberMe, true);
    } else {
      await prefs.remove(_kEmail);
      await prefs.remove(_kPassword);
      await prefs.setBool(_kRememberMe, false);
    }
  }

  Future<void> _initFirebaseMessaging() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    final token = await messaging.getToken();
    if (token != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcmToken', token);
    }
  }

  void _login() async {
    final email    = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showSnack('Please fill in all fields', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('https://api.blackfabricsecurity.com/api/users/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['firstTime'] == true) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ConfigurePasswordScreen(userId: data['id']),
            ),
          );
          return;
        }

        if (data['token'] != null) {
          await _saveCredentials(email, password);

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('jwt',       data['token']);
          await prefs.setInt('userId',       data['user']['id']);
          await prefs.setString('userEmail', data['user']['email']);

          HeartbeatService().startHeartbeat(data['user']['id']);

          final fcmToken = prefs.getString('fcmToken');
          if (fcmToken != null) {
            await ApiService().updateFcmToken(data['user']['id'], fcmToken);
          }

          final roles   = List<String>.from(data['user']['roles'] ?? []);
          final isAdmin = roles.any((r) =>
          r.toLowerCase() == 'admin' ||
              r.toLowerCase() == 'full admin');

          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
              isAdmin ? const NfcAssignPage() : const HomeScreen(),
            ),
          );
        }
      }
      else if (response.statusCode == 401) {
        _showSnack('Invalid password', isError: true);
      }
      else if (response.statusCode == 403) {
        _showSnack('Account is deactivated. Contact administrator.', isError: true);
      }else if (response.statusCode == 404) {
        _showSnack('User not found', isError: true);
      } else {
        _showSnack('Error: ${response.body}', isError: true);
      }
    } catch (e) {
      _showSnack('Connection error. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 60),

                  // ── Logo ─────────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: _border),
                      boxShadow: [
                        BoxShadow(
                          color: _primary.withOpacity(0.15),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/cropped-Black-Fabric-Security-Main.png',
                      height: 90,
                      fit: BoxFit.contain,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Title ─────────────────────────────────────────────────
                  const Text(
                    'BFS Guard Portal',
                    style: TextStyle(
                      color: _text,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Sign in to your account',
                    style: TextStyle(
                        color: _subtext,
                        fontSize: 14,
                        fontWeight: FontWeight.w400),
                  ),

                  const SizedBox(height: 40),

                  // ── Form card ─────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: _border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // Email
                        const Text('Email address',
                            style: TextStyle(
                                color: _subtext,
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(height: 8),
                        _buildTextField(
                          controller: emailController,
                          hint: 'you@gmail.com',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                        ),

                        const SizedBox(height: 20),

                        // Password
                        const Text('Password',
                            style: TextStyle(
                                color: _subtext,
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(height: 8),
                        _buildTextField(
                          controller: passwordController,
                          hint: '••••••••',
                          icon: Icons.lock_outline,
                          obscure: _obscurePassword,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: _subtext,
                              size: 20,
                            ),
                            onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── Remember me toggle ────────────────────────────
                        GestureDetector(
                          onTap: () =>
                              setState(() => _rememberMe = !_rememberMe),
                          child: Row(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: _rememberMe
                                      ? _primary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: _rememberMe
                                        ? _primary
                                        : const Color(0xFF475569),
                                    width: 1.5,
                                  ),
                                ),
                                child: _rememberMe
                                    ? const Icon(Icons.check,
                                    color: Colors.white, size: 13)
                                    : null,
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Remember my credentials',
                                style: TextStyle(
                                  color: _subtext,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ── Sign In button ────────────────────────────────
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primary,
                              disabledBackgroundColor:
                              _primary.withOpacity(0.5),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                                : const Text(
                              'Sign In',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Footer ────────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _border),
                    ),
                    child: Column(
                      children: [

                        // Brand name row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Black Fabric Security LLC',
                              style: TextStyle(
                                color: _text,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),
                        const Divider(color: _border, height: 1),
                        const SizedBox(height: 16),

                        // Links row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildFooterLink(
                              Icons.language_outlined,
                              'Website',
                              'https://blackfabricsecurity.com/',
                            ),
                            Container(width: 1, height: 32, color: _border),
                            _buildFooterLink(
                              Icons.contact_page_outlined,
                              'Contact',
                              'https://blackfabricsecurity.com/contact-us/',
                            ),
                            Container(width: 1, height: 32, color: _border),
                            _buildFooterLink(
                              Icons.email_outlined,
                              'Email',
                              'mailto:admin@blackfabricsecurity.com',
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),
                        const Divider(color: _border, height: 1),
                        const SizedBox(height: 12),

                        // Copyright
                        Text(
                          '© ${DateTime.now().year} Black Fabric Security LLC.\nAll rights reserved.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _subtext,
                            fontSize: 11,
                            height: 1.7,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooterLink(IconData icon, String label, String url) {
    return GestureDetector(
      onTap: () => _launchUrl(url),
      child: Column(
        children: [
          Icon(icon, color: _subtext, size: 22),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(
              color: _subtext,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: _text, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
        const TextStyle(color: Color(0xFF475569), fontSize: 14),
        prefixIcon: Icon(icon, color: _subtext, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFF0F172A),
        contentPadding:
        const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primary, width: 1.5),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border),
        ),
      ),
    );
  }
}