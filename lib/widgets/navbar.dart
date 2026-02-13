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
      // Use margin to control the distance from the bottom
      margin: const EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 20, // <-- Change this value to move the navbar up/down
      ),
      height: 60,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
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
          IconButton(
            icon: Icon(
              Icons.home_rounded,
              color: selectedIndex == 0 ? Colors.white : Color(0xFF9299A1),
            ),
            onPressed: () => onItemTapped(0),
          ),
          IconButton(
            icon: Icon(
              Icons.description,
              color: selectedIndex == 1 ? Colors.white : Color(0xFF9299A1),
            ),
            onPressed: () => onItemTapped(1),
          ),
          Container(
            decoration: BoxDecoration(
              color: Color(0xFF9299A1),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.add, color: Colors.white),
              onPressed: () => onItemTapped(2),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.route,
              color: selectedIndex == 3 ? Colors.white : Color(0xFF9299A1),
            ),
            onPressed: () => onItemTapped(3),
          ),
          IconButton(
            icon: Icon(
              Icons.person,
              color: selectedIndex == 4 ? Colors.white : Color(0xFF9299A1),
            ),
            onPressed: () => onItemTapped(4),
          ),
        ],
      ),
    );
  }
}
