import 'package:flutter/material.dart';
import '../models/route_info.dart';
import '../models/safe_score.dart';
import '../utils/helpers.dart';

class DSSCalculationScreen extends StatelessWidget {
  final RouteInfo route;
  final SafeScore? score;
  final String originLabel;
  final String destinationLabel;
  final Set<String> selectedPollutants;
  final Widget modeSelector;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const DSSCalculationScreen({
    super.key,
    required this.route,
    required this.score,
    required this.originLabel,
    required this.destinationLabel,
    required this.selectedPollutants,
    required this.modeSelector,
    required this.onBack,
    required this.onNext,
  });

  // Calculate CRITIC point from pollution score
  double _calculateCriticPoint() {
    if (score == null) return 0.0;
    // CRITIC point is the pollution score (1 - dp gives us the pollution risk)
    // The higher the dp, the lower the pollution risk, so CRITIC = 1 - dp
    return (1.0 - score!.dp).clamp(0.0, 1.0);
  }

  // Get equation weights based on available data
  String _getEquation() {
    if (score == null) return "0.30 * Di + 0.30 * Dt + 0.30 * Dp + 0.10 * Dw";
    
    // Check if pollution and weather data are available
    bool hasPollution = score!.dp != 0.5; // 0.5 is the neutral/default value
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

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation Bar
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: onBack,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: TextEditingController(text: originLabel.isEmpty ? "Your Location" : originLabel),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: TextEditingController(text: destinationLabel),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.swap_vert),
                              onPressed: () {},
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        modeSelector,
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Main Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Decision Support System Calculation Title
                    const Text(
                      "Decision Support System Calculation:",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Pollution Concerns
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("• ", style: TextStyle(fontSize: 16)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Pollution Concerns:",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                pollutionText,
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                "(The pollution concerns will receive heavy weight more than other pollution.)",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // CRITIC point
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("• ", style: TextStyle(fontSize: 16)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "CRITIC point:",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                criticPoint.toStringAsFixed(4),
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                "(The CRITIC point will focus on relationship between the pollutants)",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Real-time Factor Scores Table
                    const Text(
                      "Real-time Factor Scores:",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
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
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                          // Di: Distance
                          _buildTableRow(
                            "Di: Distance",
                            score?.di ?? 0.0,
                          ),
                          // Dt: Time
                          _buildTableRow(
                            "Dt: Time",
                            score?.dt ?? 0.0,
                          ),
                          // Dp: Pollution
                          _buildTableRow(
                            "Dp: Pollution",
                            score?.dp ?? 0.0,
                          ),
                          // Dw: Weather
                          _buildTableRow(
                            "Dw: Weather",
                            score?.dw ?? 0.0,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Equation for Route Evaluation
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("• ", style: TextStyle(fontSize: 16)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "The equation for route evaluation:",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.blue,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                "(The equation will be selected based on valid values on your route.)",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Final Score = $equation",
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontFamily: 'monospace',
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
                                Text(
                                  "Final Score = ${finalScore.toStringAsFixed(3)}",
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Route Score Section
                    const Text(
                      "Route Score:",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      finalScore.toStringAsFixed(3),
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "(Your route score is calculated based on pollution concerns, which affect the ontology score and the CRITIC score, as well as the DSS equation that is used to evaluate your route.)",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Next Button
            Container(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade300,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "Next",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TableRow _buildTableRow(String label, double value) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(label),
        ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            "Valid",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.green),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            value.toStringAsFixed(3),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
