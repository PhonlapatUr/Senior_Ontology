import 'package:flutter/material.dart';
import '../models/route_info.dart';
import '../models/route_indicators.dart';
import '../utils/helpers.dart';

class RouteList extends StatelessWidget {
  final List<RouteInfo> routes;
  final int chosenRoute;
  final Map<int, RouteIndicators> indicators;
  final Function(int index) onSelect;
  final Widget modeSelector;

  const RouteList({
    super.key,
    required this.routes,
    required this.chosenRoute,
    required this.indicators,
    required this.onSelect,
    required this.modeSelector,
  });

  Color _siColor(double si) {
    // si range expected 0.0 → 1.0
    if (si <= 0.25) return Colors.green.shade200;
    if (si <= 0.50) return Colors.yellow.shade200;
    if (si <= 0.75) return Colors.orange.shade200;
    return Colors.red.shade200;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        modeSelector,
        const SizedBox(height: 12),

        ...routes.asMap().entries.map((entry) {
          final i = entry.key;
          final r = entry.value;

          // Indicators safe lookup
          final ind = indicators[i]!;
          final si = ind.si.clamp(0.0, 1.0);

          final formattedArrival = (() {
            final t = DateTime.now().add(Duration(seconds: r.durationSec));
            return "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
          })();

          final selected = i == chosenRoute;

          return InkWell(
            onTap: () => onSelect(i),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFEDE7FF) : _siColor(si),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF8B5CF6)
                      : Colors.transparent,
                  width: selected ? 2 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: const Color(0xFF8B5CF6).withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // --------------------------------------------------------
                  // Left Column: Duration and SI score
                  // --------------------------------------------------------
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatDuration(r.durationSec),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "SI: ${si.toStringAsFixed(2)}",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black.withOpacity(0.75),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Details",
                        style: TextStyle(
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                          color: Color(0xFF8B5CF6),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(width: 20),

                  // --------------------------------------------------------
                  // Middle Column: Arrival time and distance
                  // --------------------------------------------------------
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Arrival: $formattedArrival",
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF424242),
                          ),
                        ),
                        Text(
                          prettyKm(r.distanceMeters),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF616161),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Icon(Icons.chevron_right, color: Color(0xFF8B5CF6)),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
