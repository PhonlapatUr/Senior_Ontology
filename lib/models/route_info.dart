import 'package:google_maps_flutter/google_maps_flutter.dart';

class RouteInfo {
  final List<LatLng> points;
  final String encodedPolyline;
  final int distanceMeters;
  final int durationSec;
  final String label;

  RouteInfo({
    required this.points,
    required this.encodedPolyline,
    required this.distanceMeters,
    required this.durationSec,
    required this.label,
  });
}
