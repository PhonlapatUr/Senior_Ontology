import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/route_info.dart';
import '../utils/helpers.dart';

class NavOverlay extends StatelessWidget {
  final RouteInfo route;
  final LatLng? currentLocation;
  final LatLng? destination;
  final VoidCallback onExit;

  const NavOverlay({
    super.key,
    required this.route,
    required this.currentLocation,
    required this.destination,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final remainingMeters = currentLocation != null
        ? distanceRemainingAlongRoute(currentLocation!, route.points)
        : route.distanceMeters.toDouble();
    final totalMeters = route.distanceMeters > 0 ? route.distanceMeters.toDouble() : 1.0;
    final durationRemainingSec = (remainingMeters / totalMeters * route.durationSec).round();
    final instruction = (currentLocation != null && destination != null)
        ? directionTo(currentLocation!, destination!)
        : (route.points.isNotEmpty
            ? directionTo(
                currentLocation ?? route.points.first,
                route.points.last,
              )
            : "Follow the route");

    return Positioned(
      top: 24,
      left: 16,
      right: 16,
      child: Column(
        children: [
          // --------------------------------------------------
          // TOP DIRECTION BOX (live instruction from user position)
          // --------------------------------------------------
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.navigation, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    instruction,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // --------------------------------------------------
          // REMAINING DISTANCE & ETA
          // --------------------------------------------------
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${formatDuration(durationRemainingSec)} remaining • ${prettyKm(remainingMeters.round())}",
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF424242),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Total: ${formatDuration(route.durationSec)} (${prettyKm(route.distanceMeters)})",
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // --------------------------------------------------
          // EXIT NAVIGATION BUTTON
          // --------------------------------------------------
          ElevatedButton.icon(
            icon: const Icon(Icons.close, size: 20),
            label: const Text("Exit navigation"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: onExit,
          ),
        ],
      ),
    );
  }
}
