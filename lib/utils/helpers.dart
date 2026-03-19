import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';

String prettyKm(int m) => "${(m / 1000).toStringAsFixed(1)} km";

int isoSec(String iso) {
  if (!iso.endsWith("s")) return 0;
  return int.tryParse(iso.replaceAll("s", "")) ?? 0;
}

LatLng? parseLatLng(String t) {
  final m = RegExp(r'^\s*(-?\d+(\.\d+)?)\s*,\s*(-?\d+(\.\d+)?)').firstMatch(t);

  if (m != null) {
    return LatLng(double.parse(m.group(1)!), double.parse(m.group(3)!));
  }
  return null;
}

String formatHM(DateTime dt) {
  return "${dt.hour.toString().padLeft(2, '0')}:"
      "${dt.minute.toString().padLeft(2, '0')}";
}

String formatDuration(int sec) {
  int days = sec ~/ 86400;
  int hours = (sec % 86400) ~/ 3600;
  int mins = (sec % 3600) ~/ 60;

  if (hours == 0 && days == 0) {
    return "${mins}m";
  }

  if (days >= 1) {
    return "${days}d ${hours}h";
  }
  return "${hours}h ${mins}m";
}

String formatDurationShort(int sec) {
  int hours = sec ~/ 3600;
  int mins = (sec % 3600) ~/ 60;

  if (hours == 0) {
    return "${mins} min";
  }
  return "${hours}h ${mins} min";
}

String formatArrivalTime(DateTime dt) {
  int hour = dt.hour;
  int minute = dt.minute;
  String period = hour >= 12 ? "P.M." : "A.M.";
  
  if (hour == 0) {
    hour = 12;
  } else if (hour > 12) {
    hour = hour - 12;
  }
  
  return "$hour:${minute.toString().padLeft(2, '0')} $period";
}

String formatDistanceShort(int meters) {
  if (meters < 1000) {
    return "${meters} M";
  }
  return "${(meters / 1000).toStringAsFixed(1)} km";
}

/// Haversine distance in meters between two LatLng points.
double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const double R = 6371000; // Earth radius in meters
  final dLat = _toRad(lat2 - lat1);
  final dLng = _toRad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRad(lat1)) *
          math.cos(_toRad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return R * c;
}

double _toRad(double deg) => deg * math.pi / 180;

/// Returns remaining distance (meters) and segment index on the route from
/// [current] to destination along [routePoints].
/// [routePoints] must not be empty.
double distanceRemainingAlongRoute(LatLng current, List<LatLng> routePoints) {
  if (routePoints.isEmpty) return 0;
  if (routePoints.length == 1) {
    return _haversineMeters(
      current.latitude,
      current.longitude,
      routePoints[0].latitude,
      routePoints[0].longitude,
    );
  }
  double minDist = double.infinity;
  int closestIdx = 0;
  for (int i = 0; i < routePoints.length; i++) {
    final p = routePoints[i];
    final d = _haversineMeters(
      current.latitude,
      current.longitude,
      p.latitude,
      p.longitude,
    );
    if (d < minDist) {
      minDist = d;
      closestIdx = i;
    }
  }
  double remaining = 0;
  for (int i = closestIdx; i < routePoints.length - 1; i++) {
    final a = routePoints[i];
    final b = routePoints[i + 1];
    remaining += _haversineMeters(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
  }
  return remaining;
}

/// Minimum distance in meters from [point] to the route polyline (vertices only).
/// Used to detect when the user has gone off-route.
double distanceToRoute(LatLng point, List<LatLng> routePoints) {
  if (routePoints.isEmpty) return double.infinity;
  double minDist = double.infinity;
  for (final p in routePoints) {
    final d = _haversineMeters(
      point.latitude,
      point.longitude,
      p.latitude,
      p.longitude,
    );
    if (d < minDist) minDist = d;
  }
  return minDist;
}

/// Direction toward a point ahead on the route so the instruction updates as the user moves.
/// [metersAhead] is how far along the route to look for the "next" target (default 80m).
String directionToNextOnRoute(LatLng current, List<LatLng> routePoints, [double metersAhead = 80]) {
  if (routePoints.isEmpty) return "Follow the route";
  if (routePoints.length == 1) return directionTo(current, routePoints.first);
  double minDist = double.infinity;
  int closestIdx = 0;
  for (int i = 0; i < routePoints.length; i++) {
    final d = _haversineMeters(
      current.latitude, current.longitude,
      routePoints[i].latitude, routePoints[i].longitude,
    );
    if (d < minDist) {
      minDist = d;
      closestIdx = i;
    }
  }
  double dist = 0;
  int idx = closestIdx;
  while (idx < routePoints.length - 1 && dist < metersAhead) {
    dist += _haversineMeters(
      routePoints[idx].latitude, routePoints[idx].longitude,
      routePoints[idx + 1].latitude, routePoints[idx + 1].longitude,
    );
    idx++;
  }
  final target = routePoints[idx.clamp(0, routePoints.length - 1)];
  return directionTo(current, target);
}

/// Rough cardinal direction from [from] to [to] (e.g. "Head northeast").
String directionTo(LatLng from, LatLng to) {
  final latDiff = to.latitude - from.latitude;
  final lngDiff = to.longitude - from.longitude;
  if (latDiff.abs() < 1e-5 && lngDiff.abs() < 1e-5) return "You have arrived";
  final deg = (math.atan2(lngDiff, latDiff) * 180 / math.pi + 360) % 360;
  if (deg >= 337.5 || deg < 22.5) return "Head north";
  if (deg >= 22.5 && deg < 67.5) return "Head northeast";
  if (deg >= 67.5 && deg < 112.5) return "Head east";
  if (deg >= 112.5 && deg < 157.5) return "Head southeast";
  if (deg >= 157.5 && deg < 202.5) return "Head south";
  if (deg >= 202.5 && deg < 247.5) return "Head southwest";
  if (deg >= 247.5 && deg < 292.5) return "Head west";
  return "Head northwest";
}
