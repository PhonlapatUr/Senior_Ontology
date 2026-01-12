import 'package:flutter/material.dart';
import '../models/route_info.dart';
import '../utils/helpers.dart';

class NavOverlay extends StatelessWidget {
  final RouteInfo route;
  final VoidCallback onExit;

  const NavOverlay({super.key, required this.route, required this.onExit});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 24,
      left: 16,
      right: 16,
      child: Column(
        children: [
          // --------------------------------------------------
          // TOP DIRECTION BOX (Simple placeholder direction)
          // --------------------------------------------------
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6), // purple accent
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Text(
              "Head southeast",
              style: TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // --------------------------------------------------
          // EXIT NAVIGATION BUTTON
          // --------------------------------------------------
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: onExit,
            child: const Text(
              "Exit",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),

          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5), // light grey
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Text(
              "${formatDuration(route.durationSec)} "
              "(${prettyKm(route.distanceMeters)})",
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF424242),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
