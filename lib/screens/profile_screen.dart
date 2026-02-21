import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/ApiService.dart';
import '../services/HeartbeatService.dart';
import '../services/LiveLocationService.dart';
import 'login_screen.dart';
import 'dart:convert'; // <-- Add this at the top

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String name = '';
  String email = '';
  String phone = '';
  String username = '';
  String profileImage = '';
  bool _isLoading = true;



  final api = ApiService();
  bool _isDarkMode = true;

  @override
  void initState() {
    super.initState();
    _loadProfile(); // fetch the profile as soon as the screen is created
  }
  // Theme colors getters (matching HomeScreen)
  Color get backgroundColor => _isDarkMode ? Color(0xFF0F172A) : Color(0xFFF8FAFC);
  Color get textColor => _isDarkMode ? Colors.white : Color(0xFF1E293B);
  Color get cardColor => _isDarkMode ? Color(0xFF1E293B) : Colors.white;
  Color get borderColor => _isDarkMode ? Color(0xFF334155) : Color(0xFFE2E8F0);
  Color get secondaryTextColor => _isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
  Color get primaryColor => _isDarkMode ? Color(0xFF4F46E5) : Color(0xFF3B82F6);
  Color get successColor => Color(0xFF10B981);
  Color get warningColor => Color(0xFFF59E0B);
  Color get dangerColor => Color(0xFFEF4444);
  Future<void> _loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt');
      final userId = prefs.getInt('userId');
      if (token == null || userId == null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        return;
      }

      // Call backend
      final response = await api.get('users/profile/$userId'); // This is Response
      final data = jsonDecode(response.body); // Now data is Map<String, dynamic>
      print(data);
      setState(() {
        name = "${data['firstName'] ?? ''} ${data['lastName'] ?? ''}";
        email = data['email'] ?? '';
        phone = data['phone'] ?? '';
        username = data['username'] ?? '';
        profileImage = data['profileImage'] ?? '';
        _isLoading = false;
      });
    } catch (e) {
      print('Profile load error: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();

    // 🚨 STOP ALL BACKGROUND SERVICES
    LiveLocationService().stopTracking();
    HeartbeatService().stopHeartbeat();

    await prefs.clear();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }


  void _openEditProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');

    if (userId == null) return;

    final nameController = TextEditingController(text: name);
    final emailController = TextEditingController(text: email);
    final phoneController = TextEditingController(text: phone);
    final usernameController = TextEditingController(text: username);
    final passwordController = TextEditingController(); // empty for new password

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  'Edit Profile',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildTextField('Full Name', nameController),
              _buildTextField('Email', emailController),
              _buildTextField('Phone', phoneController),
              _buildTextField('Username', usernameController),
              _buildTextField('New Password', passwordController),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(16),
                  ),
                  onPressed: () async {
                    try {
                      Map<String, dynamic> body = {
                        "firstName": nameController.text.split(' ').first,
                        "lastName": nameController.text.split(' ').length > 1
                            ? nameController.text.split(' ').sublist(1).join(' ')
                            : '',
                        "email": emailController.text,
                        "phone": phoneController.text,
                        "username": usernameController.text,
                      };

                      if (passwordController.text.isNotEmpty) {
                        body["password"] = passwordController.text;
                      }

                      // Call backend PUT /profile/{id}
                      final response = await api.put('users/profile/$userId', body);

                      if (response.statusCode == 200) {
                        final updatedUser = jsonDecode(response.body);

                        // Update state
                        setState(() {
                          name = "${updatedUser['firstName'] ?? ''} ${updatedUser['lastName'] ?? ''}";
                          email = updatedUser['email'] ?? '';
                          phone = updatedUser['phone'] ?? '';
                          username = updatedUser['username'] ?? '';
                        });

                        // Optionally update SharedPreferences if needed
                        await prefs.setString('userEmail', updatedUser['email'] ?? '');

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Profile updated successfully!'),
                            backgroundColor: successColor,
                          ),
                        );

                        Navigator.pop(context);
                      } else {
                        final error = jsonDecode(response.body);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to update profile: ${error['message'] ?? 'Unknown error'}'),
                            backgroundColor: dangerColor,
                          ),
                        );
                      }
                    } catch (e) {
                      print('Update profile error: $e');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('An error occurred while updating profile'),
                          backgroundColor: dangerColor,
                        ),
                      );
                    }
                  },
                  child: const Text(
                    'Save Changes',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 15),
            ],
          ),
        ),
      ),
    );
  }



  Widget _buildTextField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        style: TextStyle(color: textColor),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: secondaryTextColor),
          filled: true,
          fillColor: cardColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primaryColor),
          ),
        ),
      ),
    );
  }

  Future<void> _contactAdmin() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'admin@blackfabricsecurity.com',
      query: 'subject=Support Request&body=Hello Admin,',
    );
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not launch email app'),
          backgroundColor: cardColor,
        ),
      );
    }
  }

  Widget _buildInfoRow(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: secondaryTextColor,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: secondaryTextColor, size: 20),
        ],
      ),
    );
  }

  Widget _buildActionButton(String text, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: secondaryTextColor),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
        child: SingleChildScrollView(
          physics: BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Header ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: cardColor,
                  border: Border.all(color: borderColor, width: 1),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: primaryColor.withOpacity(0.3),
                          width: 3,
                        ),
                        gradient: LinearGradient(
                          colors: [primaryColor, Color(0xFF7C73FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(40),
                        child: profileImage.isNotEmpty
                            ? ClipRRect(
                          borderRadius: BorderRadius.circular(40),
                          child: Image.network(
                            profileImage,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withOpacity(0.1),
                                ),
                                child: Icon(Icons.person, size: 40, color: Colors.white),
                              );
                            },
                          ),
                        )
                            : Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.1),
                          ),
                          child: Icon(Icons.person, size: 40, color: Colors.white),
                        ),


                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: primaryColor.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.security, size: 14, color: primaryColor),
                                const SizedBox(width: 6),
                                Text(
                                  'Security Guard',
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 25),

              // --- Personal Info Title ---
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  "Personal Information",
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              _buildInfoRow('Full Name', name, Icons.person, primaryColor),
              _buildInfoRow('Email', email, Icons.email, Colors.blue),
              _buildInfoRow('Phone', phone, Icons.phone, Colors.green),
              _buildInfoRow('Username', username, Icons.account_circle, Colors.orange),


              const SizedBox(height: 25),

              // --- Actions Title ---
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  "Account Actions",
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // --- Action Buttons ---
              _buildActionButton(
                'Edit Profile',
                Icons.edit,
                primaryColor,
                _openEditProfile,
              ),
              _buildActionButton(
                'Contact Support',
                Icons.support_agent,
                Color(0xFF3B82F6),
                _contactAdmin,
              ),

              const SizedBox(height: 25),

              // --- Logout Section ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  color: dangerColor.withOpacity(0.1),
                  border: Border.all(color: dangerColor.withOpacity(0.3), width: 1),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: dangerColor.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.logout, color: dangerColor, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Account Security',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Sign out from this device',
                                style: TextStyle(
                                  color: secondaryTextColor,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _logout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: dangerColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.logout, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              'Sign Out',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 90), // Padding for bottom nav
            ],
          ),
        ),
      ),
    );
  }
}