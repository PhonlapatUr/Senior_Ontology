import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class GeocodeService {
  final String apiKey;

  GeocodeService(this.apiKey);

  Future<LatLng?> geocode(String query) async {
    final url =
        "https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(query)}&key=$apiKey";

    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) return null;

    final data = jsonDecode(r.body);
    if (data["status"] != "OK") return null;

    final loc = data["results"][0]["geometry"]["location"];
    return LatLng(loc["lat"], loc["lng"]);
  }
}
