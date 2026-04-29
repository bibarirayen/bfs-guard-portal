// file: lib/screens/force_update_screen.dart
//
// Checks the backend for the minimum required app version.
// If the installed version is below the minimum, the user sees a
// full-screen "Please Update" page they cannot dismiss.
// If the check passes (or the server is unreachable), the app proceeds normally.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'login_screen.dart';

class ForceUpdateScreen extends StatefulWidget {
  const ForceUpdateScreen({super.key});

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen> {
  static const _bgColor   = Color(0xFF0F172A);
  static const _cardColor = Color(0xFF1E293B);
  static const _primary   = Color(0xFF4F46E5);
  static const _green     = Color(0xFF10B981);

  // Play Store and App Store URLs — update the iOS link with your App Store ID
  static const _androidUrl =
      'https://play.google.com/store/apps/details?id=com.blackfabricsecurity.crossplatformblackfabric';
  static const _iosUrl =
      'https://apps.apple.com/us/app/bfs-guard-portal/id6759178611';

  bool _checking = true;
  bool _needsUpdate = false;
  String _minVersion = '';
  String _currentVersion = '';

  @override
  void initState() {
    super.initState();
    _checkVersion();
  }

  // ── Compare two "major.minor.patch" strings.
  // Returns true when [current] is strictly less than [minimum].
  bool _isOutdated(String current, String minimum) {
    try {
      final c = current.split('.').map(int.parse).toList();
      final m = minimum.split('.').map(int.parse).toList();
      // Pad to same length
      while (c.length < 3) c.add(0);
      while (m.length < 3) m.add(0);
      for (int i = 0; i < 3; i++) {
        if (c[i] < m[i]) return true;
        if (c[i] > m[i]) return false;
      }
      return false; // equal → not outdated
    } catch (_) {
      return false; // parse error → let the user through
    }
  }

  Future<void> _checkVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      // version is e.g. "1.0.8" (without the build number)
      final current = info.version;

      final res = await http
          .get(Uri.parse('https://api.blackfabricsecurity.com/api/version'))
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final min  = body['minVersion']?.toString() ?? current;

        if (_isOutdated(current, min)) {
          setState(() {
            _needsUpdate    = true;
            _minVersion     = min;
            _currentVersion = current;
            _checking       = false;
          });
          return;
        }
      }
      // Either server OK and version fine, or server returned unexpected status →
      // proceed to the app.
      _proceed();
    } catch (_) {
      // Network error (offline, DNS fail, timeout, etc.) → fail open so guards
      // aren't locked out just because of a bad connection.
      _proceed();
    }
  }

  void _proceed() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _openStore() async {
    final url = Platform.isIOS ? _iosUrl : _androidUrl;
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // Fallback to browser if the store app can't be opened
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  @override
  Widget build(BuildContext context) {
    // While checking: show the splash with a loader
    if (_checking) {
      return Scaffold(
        backgroundColor: _bgColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.network(
                'https://reports.blackfabricsecurity.com/assets/img/Black-Fabric-Security-Light2x2.png',
                width: 160,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.security,
                  color: Colors.white54,
                  size: 80,
                ),
              ),
              const SizedBox(height: 40),
              const CircularProgressIndicator(color: _primary),
            ],
          ),
        ),
      );
    }

    // Force-update screen — cannot be dismissed, no back button
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _bgColor,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  Image.network(
                    'https://reports.blackfabricsecurity.com/assets/img/Black-Fabric-Security-Light2x2.png',
                    width: 140,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.security,
                      color: Colors.white54,
                      size: 80,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Update icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: _primary.withOpacity(0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: _primary.withOpacity(0.5), width: 2),
                    ),
                    child: const Icon(Icons.system_update_alt_rounded,
                        color: _primary, size: 38),
                  ),
                  const SizedBox(height: 24),

                  const Text(
                    'Update Required',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),

                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _cardColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(children: [
                      Text(
                        'A newer version of the app is required to continue. '
                        'Please update to version $_minVersion or later.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _versionBadge('Your version', _currentVersion,
                              Colors.red.shade400),
                          const Icon(Icons.arrow_forward_rounded,
                              color: Colors.white38, size: 18),
                          _versionBadge('Required', _minVersion, _green),
                        ],
                      ),
                    ]),
                  ),
                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _openStore,
                      icon: Icon(
                        Platform.isIOS
                            ? Icons.apple_rounded
                            : Icons.shop_rounded,
                        color: Colors.white,
                      ),
                      label: Text(
                        Platform.isIOS
                            ? 'Update on App Store'
                            : 'Update on Play Store',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Text(
                    'You cannot use the app until it is updated.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _versionBadge(String label, String version, Color color) {
    return Column(children: [
      Text(label,
          style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 11,
              fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(
          version,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    ]);
  }
}
