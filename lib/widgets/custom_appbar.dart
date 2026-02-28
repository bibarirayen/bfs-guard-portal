import 'package:flutter/material.dart';

/// A stateful wrapper so the dark/light toggle persists correctly
/// when the appbar is rebuilt on any screen.
class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool isDarkMode;
  final ValueChanged<bool>? onThemeChanged;

  const CustomAppBar({
    super.key,
    required this.title,
    this.isDarkMode = true,
    this.onThemeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final Color textColor       = isDarkMode ? Colors.white           : const Color(0xFF1E293B);
    final Color subTextColor    = isDarkMode ? Colors.grey[400]!      : Colors.grey[600]!;
    final Color cardColor       = isDarkMode ? const Color(0xFF1E293B): Colors.white;
    final Color borderColor     = isDarkMode ? const Color(0xFF334155): const Color(0xFFE2E8F0);
    final Color bgColor         = isDarkMode ? const Color(0xFF0F172A): const Color(0xFFF8FAFC);

    return AppBar(
      centerTitle: false,
      elevation: 0,
      backgroundColor: bgColor,       // ← matches page background on every screen
      surfaceTintColor: Colors.transparent,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: textColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'Security Guard Portal',
            style: TextStyle(
              color: subTextColor,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Image.asset(
            'assets/tt.png',
            height: 28,
            width: 28,
            fit: BoxFit.contain,
          ),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}