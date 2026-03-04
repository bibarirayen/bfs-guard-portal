// lib/widgets/navbar.dart
// CHANGE: Added chat icon at index 5 (between route and profile)
import 'package:flutter/material.dart';

class CustomNavbar extends StatelessWidget {
  final Function(int) onItemTapped;
  final int selectedIndex;

  const CustomNavbar({
    super.key,
    required this.onItemTapped,
    required this.selectedIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 20,
      ),
      height: 60,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // 0 - Dashboard
          IconButton(
            icon: Icon(Icons.home_rounded,
                color: selectedIndex == 0 ? Colors.white : const Color(0xFF9299A1)),
            onPressed: () => onItemTapped(0),
          ),
          // 1 - Reports
          IconButton(
            icon: Icon(Icons.description,
                color: selectedIndex == 1 ? Colors.white : const Color(0xFF9299A1)),
            onPressed: () => onItemTapped(1),
          ),
          // 2 - New Report (center button)
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF9299A1),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.add, color: Colors.white),
              onPressed: () => onItemTapped(2),
            ),
          ),
          // 3 - Patrols
          IconButton(
            icon: Icon(Icons.route,
                color: selectedIndex == 3 ? Colors.white : const Color(0xFF9299A1)),
            onPressed: () => onItemTapped(3),
          ),
          // 4 - Chat  ← NEW
          IconButton(
            icon: Icon(Icons.chat_bubble_outline_rounded,
                color: selectedIndex == 4 ? Colors.white : const Color(0xFF9299A1)),
            onPressed: () => onItemTapped(4),
          ),
          // 5 - Profile
          IconButton(
            icon: Icon(Icons.person,
                color: selectedIndex == 5 ? Colors.white : const Color(0xFF9299A1)),
            onPressed: () => onItemTapped(5),
          ),
        ],
      ),
    );
  }
}