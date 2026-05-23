// lib/widgets/navbar.dart
import 'package:flutter/material.dart';

class CustomNavbar extends StatelessWidget {
  final Function(int) onItemTapped;
  final int selectedIndex;
  /// Total unread chat messages — shows a red badge on the messages icon.
  final int unreadChatCount;

  const CustomNavbar({
    super.key,
    required this.onItemTapped,
    required this.selectedIndex,
    this.unreadChatCount = 0,
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
          // 1 - Chat / Conversations (with unread badge)
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: Icon(Icons.chat_bubble_outline_rounded,
                    color: selectedIndex == 2
                        ? Colors.white
                        : const Color(0xFF9299A1)),
                onPressed: () => onItemTapped(2),
              ),
              if (unreadChatCount > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Color(0xFF4F46E5),
                      shape: BoxShape.circle,
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 17, minHeight: 17),
                    child: Text(
                      unreadChatCount > 9 ? '9+' : '$unreadChatCount',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          // 2 - New Report (center button)
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF9299A1),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.add, color: Colors.white),
              onPressed: () => onItemTapped(10),
            ),
          ),
          // 3 - Patrols
          IconButton(
            icon: Icon(Icons.route,
                color: selectedIndex == 1 ? Colors.white : const Color(0xFF9299A1)),
            onPressed: () => onItemTapped(1),
          ),
          // 4 - Profile
          IconButton(
            icon: Icon(Icons.person,
                color: selectedIndex == 3 ? Colors.white : const Color(0xFF9299A1)),
            onPressed: () => onItemTapped(3),
          ),
        ],
      ),
    );
  }
}