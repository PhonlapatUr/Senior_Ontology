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

  final VoidCallback onBack;
  final VoidCallback onNext;

  const DetailCard({
    super.key,
    required this.route,
    required this.ind,
    required this.score,
    required this.modeSelector,
    required this.originLabel,
    required this.destinationLabel,
    required this.onBack,
    required this.onNext,
  });

  // ---------------------- FORMULA ----------------------
  Widget _buildFormula(SafeScore? score) {
    if (score == null) return const Text("No score available.");

    return const Text("Si = 0.30(Di) + 0.30(Dt) + 0.30(Dp) + 0.10(Dw)");
  }

  // ---------------------- **API SCORE TABLE** ----------------------
  Widget _buildScoreTable(SafeScore? score) {
    if (score == null) {
      return const Text("No score available.");
    }

    final di = score.di;
    final dt = score.dt;
    final dp = score.dp;
    final dw = score.dw;
    final si = score.riskScore;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Table(
        columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1)},
        border: TableBorder.all(color: Colors.grey.shade300),
        children: [
          _row("Distance (Di)", di),
          _row("Time (Dt)", dt),
          _row("Pollution (Dp)", dp),
          _row("Weather (Dw)", dw),

          // Final score
          TableRow(
            decoration: BoxDecoration(color: Colors.blue.shade50),
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  "Final Score (Si)",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  si.toStringAsFixed(2),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  TableRow _row(String label, double v) {
    return TableRow(
      children: [
        Padding(padding: const EdgeInsets.all(12), child: Text(label)),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(v.toStringAsFixed(2), textAlign: TextAlign.right),
        ),
      ],
    );
  }

  // ---------------------- SECTIONS ----------------------
  Widget _routeDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        modeSelector,
        const Text(
          "Your route detail:",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 6),
        Text("Origin: $originLabel"),
        Text("Destination: $destinationLabel"),
        Text(
          "Estimate time: ${formatDuration(route.durationSec)} "
          "(${prettyKm(route.distanceMeters)})",
        ),
      ],
    );
  }

  Widget _pollutionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          "Pollution Considered:",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        SizedBox(height: 6),
        Text("PM2.5, PM10, O3, NO2, SO2, CO"),
      ],
    );
  }

  Widget _multiCriteriaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Multi-criteria decision making:",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 10),
        _buildFormula(score),
      ],
    );
  }

  // ---------------------- BUILD ----------------------
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(18),
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _routeDetailsSection(),
                    const SizedBox(height: 25),
                    _pollutionSection(),
                    const SizedBox(height: 25),
                    _multiCriteriaSection(),
                    const SizedBox(height: 16),

                    // 🔥 USE REAL API SCORE HERE
                    _buildScoreTable(score),

                    const SizedBox(height: 26),
                  ],
                ),
              ),
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton(onPressed: onBack, child: const Text("Back")),
                ElevatedButton(onPressed: onNext, child: const Text("Next")),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
