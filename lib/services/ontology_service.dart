import 'package:flutter/services.dart';

class OntologyService {
  static const String ontologyPath = 'ontology_fixed.ttl';
  static Future<List<String>> getPollutantsFromOntology() async {
    try {
      final String content = await rootBundle.loadString(ontologyPath);
      final List<String> pollutants = [];
      final lines = content.split('\n');
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.contains('rdf:type owl:Class') &&
            line.startsWith(':') &&
            !line.contains('Source') &&
            !line.contains('Restriction')) {
          final match = RegExp(r':(\w+(?:\.\d+)?)').firstMatch(line);
          if (match != null) {
            final name = match.group(1);
            if (name != null &&
                !pollutants.contains(name) &&
                _isPollutantClass(name, content)) {
              pollutants.add(name);
            }
          }
        }
      }
      final mainPollutants = pollutants
          .where(
            (p) =>
                p == 'PM2.5' ||
                p == 'PM10' ||
                p == 'CO' ||
                p == 'NOx' ||
                p == 'NO2' ||
                p == 'O3' ||
                p == 'VOCs' ||
                p == 'SO2',
          )
          .toList();
      mainPollutants.sort();

      return mainPollutants;
    } catch (e) {
      return ['PM2.5', 'PM10', 'CO', 'NO2', 'O3', 'SO2', 'NOx', 'VOCs'];
    }
  }

  static bool _isPollutantClass(String name, String content) {
    return content.contains(':$name') &&
        (content.contains(':$name rdf:type owl:Class') ||
            content.contains(':$name rdfs:subClassOf :Pollutant') ||
            content.contains(':$name rdfs:subClassOf :PM') ||
            content.contains(':$name rdfs:subClassOf :NOx'));
  }

  static String toBackendFormat(String ontologyName) {
    return ontologyName.toLowerCase();
  }

  static String toDisplayName(String backendName) {
    if (backendName == 'pm2.5') return 'PM2.5';
    if (backendName == 'pm10') return 'PM10';
    if (backendName == 'no2') return 'NO2';
    if (backendName == 'o3') return 'O3';
    if (backendName == 'so2') return 'SO2';
    if (backendName == 'nox') return 'NOx';
    if (backendName == 'vocs') return 'VOCs';
    if (backendName == 'co') return 'CO';
    return backendName.toUpperCase();
  }
}
