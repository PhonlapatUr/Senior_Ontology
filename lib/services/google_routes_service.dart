import 'dart:convert';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/route_info.dart';
import '../models/travel_time.dart';
import '../utils/helpers.dart';

class GoogleRoutesService {
  final String apiKey;

  GoogleRoutesService(this.apiKey);
  Future<int> getDuration({
    required LatLng origin,
    required LatLng dest,
    required String mode,
  }) async {
    const url = "https://routes.googleapis.com/directions/v2:computeRoutes";

    final r = await http.post(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask": "routes.duration",
      },
      body: jsonEncode({
        "origin": {
          "location": {
            "latLng": {
              "latitude": origin.latitude,
              "longitude": origin.longitude,
            },
          },
        },
        "destination": {
          "location": {
            "latLng": {"latitude": dest.latitude, "longitude": dest.longitude},
          },
        },
        "travelMode": mode,
      }),
    );

    if (r.statusCode != 200) return 0;

    final rt = jsonDecode(r.body)["routes"];
    if (rt == null || rt.isEmpty) return 0;

    return isoSec(rt[0]["duration"]);
  }

  Future<List<RouteInfo>> getRoutes({
    required LatLng origin,
    required LatLng dest,
    required String mode,
  }) async {
    const url = "https://routes.googleapis.com/directions/v2:computeRoutes";

    final r = await http.post(
      Uri.parse(url),
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask":
            "routes.polyline.encodedPolyline,"
            "routes.distanceMeters,"
            "routes.duration,"
            "routes.routeLabels",
      },
      body: jsonEncode({
        "origin": {
          "location": {
            "latLng": {
              "latitude": origin.latitude,
              "longitude": origin.longitude,
            },
          },
        },
        "destination": {
          "location": {
            "latLng": {"latitude": dest.latitude, "longitude": dest.longitude},
          },
        },
        "travelMode": mode,
        "computeAlternativeRoutes": true,
      }),
    );

    if (r.statusCode != 200) return [];

    final data = jsonDecode(r.body)["routes"] ?? [];
    final list = <RouteInfo>[];

    for (final rt in data) {
      final enc = rt["polyline"]["encodedPolyline"];

      final points = PolylinePoints()
          .decodePolyline(enc)
          .map((e) => LatLng(e.latitude, e.longitude))
          .toList();

      list.add(
        RouteInfo(
          points: points,
          encodedPolyline: enc,
          distanceMeters: rt["distanceMeters"],
          durationSec: isoSec(rt["duration"]),
          label: (rt["routeLabels"] as List?)?.first ?? "",
        ),
      );
    }

    return list;
  }

  Future<Map<String, TravelTime>> getTravelTimes(
    LatLng origin,
    LatLng dest,
  ) async {
    final modes = ["DRIVE", "WALK"];
    final result = <String, TravelTime>{};

    for (final m in modes) {
      final sec = await getDuration(origin: origin, dest: dest, mode: m);
      result[m] = TravelTime(m, sec);
    }

    return result;
  }
}
