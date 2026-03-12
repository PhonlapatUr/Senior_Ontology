import 'package:flutter/services.dart';

class OntologyService {
  static const String ontologyPath = 'ontology_fixed.ttl';

  /// Extract pollutant names from ontology file
  /// Returns list of pollutant names that are subclasses of :Pollutant
  static Future<List<String>> getPollutantsFromOntology() async {
    try {
      // Read the ontology file
      final String content = await rootBundle.loadString(ontologyPath);
      
      // Extract pollutant class names
      final List<String> pollutants = [];
      
      // Pattern to match pollutant class definitions
      // Look for lines like ":PM2.5 rdf:type owl:Class" or ":CO rdf:type owl:Class"
      final lines = content.split('\n');
      
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        
        // Match pollutant class definitions
        // Pattern: :POLLUTANT_NAME rdf:type owl:Class
        if (line.contains('rdf:type owl:Class') && 
            line.startsWith(':') && 
            !line.contains('Source') &&
            !line.contains('Restriction')) {
          
          // Extract the pollutant name
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
      
      // Filter to only include main pollutants (exclude PM parent class, include specific ones)
      final mainPollutants = pollutants.where((p) => 
        p == 'PM2.5' || 
        p == 'PM10' || 
        p == 'CO' || 
        p == 'NOx' || 
        p == 'NO2' || 
        p == 'O3' || 
        p == 'VOCs' || 
        p == 'SO2'
      ).toList();
      
      // Sort for consistent display
      mainPollutants.sort();
      
      return mainPollutants;
    } catch (e) {
      // Fallback to default pollutants if ontology can't be read
      return ['PM2.5', 'PM10', 'CO', 'NO2', 'O3', 'SO2', 'NOx', 'VOCs'];
    }
  }
  
  /// Check if a class is a pollutant (not a source)
  static bool _isPollutantClass(String name, String content) {
    // Check if it's defined as a subclass of Pollutant or has hasSource restrictions
    return content.contains(':$name') && 
           (content.contains(':$name rdf:type owl:Class') ||
            content.contains(':$name rdfs:subClassOf :Pollutant') ||
            content.contains(':$name rdfs:subClassOf :PM') ||
            content.contains(':$name rdfs:subClassOf :NOx'));
  }
  
  /// Convert ontology pollutant name to backend format
  /// e.g., "PM2.5" -> "pm2.5", "NO2" -> "no2"
  static String toBackendFormat(String ontologyName) {
    return ontologyName.toLowerCase();
  }
  
  /// Convert backend format to display name
  /// e.g., "pm2.5" -> "PM2.5", "no2" -> "NO2"
  static String toDisplayName(String backendName) {
    // Handle special cases
    if (backendName == 'pm2.5') return 'PM2.5';
    if (backendName == 'pm10') return 'PM10';
    if (backendName == 'no2') return 'NO2';
    if (backendName == 'o3') return 'O3';
    if (backendName == 'so2') return 'SO2';
    if (backendName == 'nox') return 'NOx';
    if (backendName == 'vocs') return 'VOCs';
    if (backendName == 'co') return 'CO';
    
    // Default: capitalize
    return backendName.toUpperCase();
  }
}
