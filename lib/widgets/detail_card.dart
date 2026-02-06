import 'package:flutter/material.dart';
import '../models/route_info.dart';
import '../models/route_indicators.dart';
import '../models/safe_score.dart';
import '../utils/helpers.dart';

class DetailCard extends StatelessWidget {
  final RouteInfo route;
  final RouteIndicators ind;
  final SafeScore? score;
  final Widget modeSelector;

  final String originLabel;
  final String destinationLabel;
  final Set<String> selectedPollutants;

  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onStartRoute;

  const DetailCard({
    super.key,
    required this.route,
    required this.ind,
    required this.score,
    required this.modeSelector,
    required this.originLabel,
    required this.destinationLabel,
    this.selectedPollutants = const {},
    required this.onBack,
    required this.onNext,
    required this.onStartRoute,
  });

  // Calculate CRITIC point from pollution score
  double _calculateCriticPoint() {
    if (score == null) return 0.0;
    return (1.0 - score!.dp).clamp(0.0, 1.0);
  }

  // Get equation weights based on available data
  String _getEquation() {
    if (score == null) return "0.30 * Di + 0.30 * Dt + 0.30 * Dp + 0.10 * Dw";
    
    bool hasPollution = score!.dp != 0.5;
    bool hasWeather = score!.dw != 0.5;
    
    if (!hasPollution && !hasWeather) {
      return "0.50 * Di + 0.50 * Dt";
    } else if (hasWeather && !hasPollution) {
      return "0.45 * Di + 0.45 * Dt + 0.10 * Dw";
    } else if (hasPollution && !hasWeather) {
      return "0.30 * Di + 0.30 * Dt + 0.40 * Dp";
    } else {
      return "0.30 * Di + 0.30 * Dt + 0.30 * Dp + 0.10 * Dw";
    }
  }

  // Get equation calculation with actual values
  String _getEquationCalculation() {
    if (score == null) return "";
    
    bool hasPollution = score!.dp != 0.5;
    bool hasWeather = score!.dw != 0.5;
    
    if (!hasPollution && !hasWeather) {
      return "Final Score = (0.50 * ${score!.di.toStringAsFixed(3)}) + (0.50 * ${score!.dt.toStringAsFixed(3)})";
    } else if (hasWeather && !hasPollution) {
      return "Final Score = (0.45 * ${score!.di.toStringAsFixed(3)}) + (0.45 * ${score!.dt.toStringAsFixed(3)}) + (0.10 * ${score!.dw.toStringAsFixed(3)})";
    } else if (hasPollution && !hasWeather) {
      return "Final Score = (0.30 * ${score!.di.toStringAsFixed(3)}) + (0.30 * ${score!.dt.toStringAsFixed(3)}) + (0.40 * ${score!.dp.toStringAsFixed(3)})";
    } else {
      return "Final Score = (0.30 * ${score!.di.toStringAsFixed(3)}) + (0.30 * ${score!.dt.toStringAsFixed(3)}) + (0.30 * ${score!.dp.toStringAsFixed(3)}) + (0.10 * ${score!.dw.toStringAsFixed(3)})";
    }
  }

  // Get final score calculation result
  double _getFinalScore() {
    if (score == null) return 0.0;
    
    bool hasPollution = score!.dp != 0.5;
    bool hasWeather = score!.dw != 0.5;
    
    if (!hasPollution && !hasWeather) {
      return (0.50 * score!.di) + (0.50 * score!.dt);
    } else if (hasWeather && !hasPollution) {
      return (0.45 * score!.di) + (0.45 * score!.dt) + (0.10 * score!.dw);
    } else if (hasPollution && !hasWeather) {
      return (0.30 * score!.di) + (0.30 * score!.dt) + (0.40 * score!.dp);
    } else {
      return (0.30 * score!.di) + (0.30 * score!.dt) + (0.30 * score!.dp) + (0.10 * score!.dw);
    }
  }

  // ---------------------- **API SCORE TABLE** ----------------------
  Widget _buildScoreTable(SafeScore? score) {
    if (score == null) {
      return const Text("No score available.");
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2),
          1: FlexColumnWidth(1.5),
          2: FlexColumnWidth(1.5),
        },
        border: TableBorder.all(color: Colors.grey.shade300),
        children: [
          // Header row
          TableRow(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
            ),
            children: const [
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  "Value",
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  "Status",
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  "Normalized",
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          // Data rows
          _buildTableRow("Di: Distance", score.di),
          _buildTableRow("Dt: Time", score.dt),
          _buildTableRow("Dp: Pollution", score.dp),
          _buildTableRow("Dw: Weather", score.dw),
        ],
      ),
    );
  }

  TableRow _buildTableRow(String label, double value) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            "Valid",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            value.toStringAsFixed(3),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  void _showStartRouteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.directions, color: Colors.purple, size: 28),
              SizedBox(width: 12),
              Text(
                "Start Route?",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple,
                ),
              ),
            ],
          ),
          content: const Text(
            "Do you want to start navigation for this route?",
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                "Back",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                onStartRoute();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                "Start Route",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------------- BUILD ----------------------
  @override
  Widget build(BuildContext context) {
    final criticPoint = _calculateCriticPoint();
    final equation = _getEquation();
    final equationCalc = _getEquationCalculation();
    final finalScore = _getFinalScore();
    
    // Format selected pollutants
    String pollutionText = "None";
    if (selectedPollutants.isNotEmpty) {
      final pollutants = selectedPollutants.toList()..sort();
      pollutionText = pollutants.join(", ");
    }

    return Card(
      elevation: 12,
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      shadowColor: Colors.black.withOpacity(0.2),
      child: Container(
        padding: const EdgeInsets.all(20),
        height: 520,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.grey.shade50,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Route Details Section
                    modeSelector,
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Icon(Icons.route, color: Colors.blue.shade700, size: 24),
                        const SizedBox(width: 8),
                        const Text(
                          "Your route detail:",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200, width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.location_on, color: Colors.blue.shade700, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Origin: $originLabel",
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.location_on, color: Colors.red.shade700, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Destination: $destinationLabel",
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.access_time, color: Colors.orange.shade700, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                "Estimate time: ${formatDuration(route.durationSec)} "
                                "(${prettyKm(route.distanceMeters)})",
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Decision Support System Calculation Title
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blue.shade600, Colors.blue.shade400],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.calculate, color: Colors.white, size: 28),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "Decision Support System Calculation:",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Pollution Concerns
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200, width: 1),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Pollution Concerns:",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  pollutionText,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.grey.shade800,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  "(The pollution concerns will receive heavy weight more than other pollution.)",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // CRITIC point
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.purple.shade200, width: 1),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.analytics, color: Colors.purple.shade700, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "CRITIC point:",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  criticPoint.toStringAsFixed(4),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple.shade700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  "(The CRITIC point will focus on relationship between the pollutants)",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Real-time Factor Scores Table
                    Row(
                      children: [
                        Icon(Icons.table_chart, color: Colors.blue.shade700, size: 24),
                        const SizedBox(width: 8),
                        const Text(
                          "Real-time Factor Scores:",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildScoreTable(score),
                    const SizedBox(height: 24),

                    // Equation for Route Evaluation
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200, width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.functions, color: Colors.blue.shade700, size: 24),
                              const SizedBox(width: 8),
                              const Text(
                                "The equation for route evaluation:",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "(The equation will be selected based on valid values on your route.)",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Final Score = $equation",
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (equationCalc.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    equationCalc,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      "Final Score = ${finalScore.toStringAsFixed(3)}",
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Route Score Section
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.green.shade400, Colors.green.shade600],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.shade200,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.star, color: Colors.white, size: 28),
                              SizedBox(width: 12),
                              Text(
                                "Route Score:",
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: Text(
                              finalScore.toStringAsFixed(3),
                              style: const TextStyle(
                                fontSize: 56,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              "(Your route score is calculated based on pollution concerns, which affect the ontology score and the CRITIC score, as well as the DSS equation that is used to evaluate your route.)",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton(
                  onPressed: onBack,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    side: const BorderSide(color: Colors.purple, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "Back",
                    style: TextStyle(
                      color: Colors.purple,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _showStartRouteDialog(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: const Text(
                    "Next",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
