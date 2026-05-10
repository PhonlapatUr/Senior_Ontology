import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/route_request_item.dart';
import '../models/safe_score.dart';

class BackendService {
  final String baseUrl;
  BackendService(this.baseUrl);

  Future<Map<int, SafeScore>> scoreRoutes({
    required List<RouteRequestItem> routes,
    required int sampleStride,
    List<String>? focusPollutants,
    bool useOntology = false,
  }) async {
    final body = {
      "routes": routes.map((e) => e.toJson()).toList(),
      "sample_stride": sampleStride,
    };
    
    if (focusPollutants != null && focusPollutants.isNotEmpty) {
      body["focus_pollutants"] = focusPollutants;
    }
    
    if (useOntology) {
      body["use_ontology"] = true;
    }

    final res = await http.post(
      Uri.parse("$baseUrl/scoreRoutes"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(body),
    );

    if (res.statusCode != 200) {
      throw Exception("Backend error: ${res.statusCode} — ${res.body}");
    }

    final decoded = jsonDecode(res.body);

    final out = <int, SafeScore>{};

    for (final s in decoded["scores"]) {
      final i = int.tryParse(s["id"] ?? "0") ?? 0;
      out[i] = SafeScore.fromJson(s);
    }

    return out;
  }
}
