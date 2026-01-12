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
    return "${mins}m";
  }
  return "${hours}h ${mins}m";
}
