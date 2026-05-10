import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/route_info.dart';
import '../utils/helpers.dart';
import '../utils/debug_log.dart';

class NavOverlay extends StatelessWidget {
  final RouteInfo route;
  final LatLng? currentLocation;
  final LatLng? destination;
  final VoidCallback onExit;
  final VoidCallback? onResetToFirstPage;
  final VoidCallback? onRecenter;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onCompassTap;
  final VoidCallback? onRouteOptionsTap;

  const NavOverlay({
    super.key,
    required this.route,
    required this.currentLocation,
    required this.destination,
    required this.onExit,
    this.onResetToFirstPage,
    this.onRecenter,
    this.onZoomIn,
    this.onZoomOut,
    this.onCompassTap,
    this.onRouteOptionsTap,
  });

  @override
  Widget build(BuildContext context) {
    final remainingMeters = currentLocation != null
        ? distanceRemainingAlongRoute(currentLocation!, route.points)
        : route.distanceMeters.toDouble();
    final totalMeters = route.distanceMeters > 0 ? route.distanceMeters.toDouble() : 1.0;
    final durationRemainingSec = (remainingMeters / totalMeters * route.durationSec).round();
    // Instruction updates as user moves: direction toward next part of route (not just destination)
    final instruction = (currentLocation != null && route.points.isNotEmpty)
        ? directionToNextOnRoute(currentLocation!, route.points, 80)
        : (route.points.isNotEmpty
            ? directionTo(
                currentLocation ?? route.points.first,
                route.points.last,
              )
            : "Follow the route");
    final eta = DateTime.now().add(Duration(seconds: durationRemainingSec));
    debugLog(
      'nav_overlay.dart:build',
      'navigation overlay computed values',
      runId: 'initial',
      hypothesisId: 'H1',
      data: {
        'remainingMeters': remainingMeters,
        'durationRemainingSec': durationRemainingSec,
        'hasCurrentLocation': currentLocation != null,
        'isNear200m': remainingMeters <= 200.0,
      },
    );

    const teal = Color(0xFF00796B);
    final mq = MediaQuery.of(context);
    final width = mq.size.width;
    final padding = mq.padding;
    final horizontalInset = (width * 0.04).clamp(12.0, 20.0);
    final instructionFontSize = (width * 0.038).clamp(13.0, 18.0);

    return Stack(
      children: [
        // TOP-LEFT: Instruction box (↑ toward ...) – responsive
        Positioned(
          top: padding.top + 12,
          left: horizontalInset,
          right: horizontalInset,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: (width * 0.04).clamp(12.0, 20.0),
              vertical: (mq.size.height * 0.016).clamp(10.0, 18.0),
            ),
            decoration: BoxDecoration(
              color: teal,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  Icons.arrow_upward,
                  color: Colors.white,
                  size: (instructionFontSize * 1.6).clamp(22.0, 30.0),
                ),
                SizedBox(width: (width * 0.025).clamp(8.0, 14.0)),
                Expanded(
                  child: Text(
                    "toward $instruction",
                    style: TextStyle(
                      fontSize: instructionFontSize,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: onResetToFirstPage ?? onExit,
                  borderRadius: BorderRadius.circular(16),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, color: Colors.white, size: 22),
                  ),
                ),
              ],
            ),
          ),
        ),

        // RIGHT: Map controls – responsive inset
        Positioned(
          top: padding.top + 94,
          right: horizontalInset,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onCompassTap != null)
                _MapControlButton(icon: Icons.explore, onTap: onCompassTap!),
              if (onCompassTap != null) const SizedBox(height: 8),
              if (onZoomIn != null)
                _MapControlButton(icon: Icons.add, onTap: onZoomIn!),
              if (onZoomIn != null) const SizedBox(height: 4),
              if (onZoomOut != null)
                _MapControlButton(icon: Icons.remove, onTap: onZoomOut!),
              if (onZoomOut != null && onRouteOptionsTap != null) const SizedBox(height: 8),
              if (onRouteOptionsTap != null)
                _MapControlButton(
                  icon: Icons.alt_route,
                  onTap: onRouteOptionsTap!,
                ),
            ],
          ),
        ),

        // BOTTOM: Dark bar – time (green + clock + leaf), distance, ETA, route options, Exit, Re-center
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              horizontalInset,
              14,
              horizontalInset,
              14 + padding.bottom,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.82),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  // Left: time (green), distance & ETA – responsive font size
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: (width * 0.045).clamp(14.0, 20.0),
                              color: Colors.green.shade300,
                            ),
                            SizedBox(width: (width * 0.015).clamp(4.0, 8.0)),
                            Text(
                              formatDurationShort(durationRemainingSec),
                              style: TextStyle(
                                fontSize: (width * 0.045).clamp(14.0, 20.0),
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade300,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              prettyKm(remainingMeters.round()),
                              style: TextStyle(
                                fontSize: (width * 0.032).clamp(11.0, 14.0),
                                color: Colors.white70,
                              ),
                            ),
                            SizedBox(width: (width * 0.03).clamp(8.0, 14.0)),
                            Text(
                              formatHM(eta),
                              style: TextStyle(
                                fontSize: (width * 0.032).clamp(11.0, 14.0),
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Exit button (red)
                  Material(
                    color: Colors.red.shade600,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: onExit,
                      borderRadius: BorderRadius.circular(10),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        child: Text(
                          "Exit",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Re-center: triangle + "Re-center"
                  if (onRecenter != null)
                    Material(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: onRecenter,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
                              const SizedBox(width: 6),
                              const Text("Re-center",
                                  style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;

  const _MapControlButton({required this.icon, required this.onTap, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey.shade900,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Icon(icon, color: iconColor ?? Colors.white, size: 24),
        ),
      ),
    );
  }
}
