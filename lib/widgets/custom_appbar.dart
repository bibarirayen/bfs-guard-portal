import 'package:flutter/material.dart';

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
    Color textColor = isDarkMode ? Colors.white : Colors.black;
    Color secondaryTextColor = isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
    Color cardColor = isDarkMode ? Color(0xFF1E293B) : Colors.white;
    Color borderColor = isDarkMode ? Color(0xFF334155) : Color(0xFFE2E8F0);

    return AppBar(
      centerTitle: false,
      elevation: 0,
      backgroundColor: Colors.transparent,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: textColor,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            "Security Guard Portal",
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      actions: [
        GestureDetector(
          onTap: () {
            if (onThemeChanged != null) {
              onThemeChanged!(!isDarkMode);
            }
          },
          child: Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Image.asset(
              isDarkMode
                  ? 'assets/applogo.png'
                  : 'assets/applogo.png',
              height: 28,
              width: 28,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ],

    );
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight);
}
