import 'package:flutter/material.dart';
import '../models/route_info.dart';
import '../models/route_indicators.dart';
import '../utils/helpers.dart';

class RouteList extends StatelessWidget {
  final List<RouteInfo> routes;
  final int chosenRoute;
  final Map<int, RouteIndicators> indicators;
  final Function(int index) onSelect;
  final Function(int index)? onPreview; // New callback for preview (chevron)
  final Widget modeSelector;
  final Set<String> selectedPollutants;

  const RouteList({
    super.key,
    required this.routes,
    required this.chosenRoute,
    required this.indicators,
    required this.onSelect,
    this.onPreview,
    required this.modeSelector,
    this.selectedPollutants = const {},
  });
  /// Get color for travel time based on DSS-calculated SI score ranking
  /// SI (Safety Index) comes from backend DSS calculation (riskScore)
  /// Green = lowest DSS score (safest), Yellow = second lowest, Red = highest DSS score (unsafe)
  /// Routes with the same DSS score get the same color
  Color _getTimeColor(double si, int index, int totalRoutes) {
    if (totalRoutes == 1) return Colors.green;
    
    // Get all DSS-calculated SI scores from indicators
    // These scores come from backend DSS (riskScore field)
    final allDssScores = indicators.values.map((e) => e.si).toList();
    
    // Remove duplicates and sort from lowest (safest) to highest (unsafe)
    final uniqueScores = allDssScores.toSet().toList()..sort((a, b) => a.compareTo(b));
    
    if (uniqueScores.isEmpty) return Colors.grey;
    
    // Find the rank of the current route's DSS score
    final rank = uniqueScores.indexOf(si);
    
    if (rank == -1) return Colors.grey;
    
    // If only one unique DSS score, all routes are green (safest)
    if (uniqueScores.length == 1) return Colors.green;
    
    // If two unique DSS scores: lowest = green, highest = yellow (second)
    if (uniqueScores.length == 2) {
      return rank == 0 ? Colors.green : const Color(0xFFF9A825); // Yellow for second lowest
    }
    
    // If three or more unique DSS scores:
    // - Lowest DSS score (rank 0) = green (safest route)
    // - Highest DSS score (last rank) = red (unsafe route)
    // - Second lowest and middle ranks = yellow
    if (rank == 0) {
      return Colors.green; // Safest - lowest DSS score
    } else if (rank == uniqueScores.length - 1) {
      return Colors.red; // Unsafe - highest DSS score
    } else {
      return const Color(0xFFF9A825); // Yellow - second lowest and middle DSS scores
    }
  }

  /// Format pollution avoidance text from selectedPollutants
  String _getPollutionAvoidanceText() {
    if (selectedPollutants.isEmpty) return "";
    
    final pollutants = selectedPollutants.toList()..sort();
    
    if (pollutants.length == 1) {
      return "Avoid ${pollutants[0]}";
    } else if (pollutants.length == 2) {
      return "Avoid ${pollutants[0]} and ${pollutants[1]}";
    } else {
      final first = pollutants.take(pollutants.length - 1).join(", ");
      final last = pollutants.last;
      return "Avoid $first, $last";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        modeSelector,
        const SizedBox(height: 16),

        ...routes.asMap().entries.map((entry) {
          final i = entry.key;
          final r = entry.value;

          // Indicators safe lookup
          final ind = indicators[i]!;
          final si = ind.si.clamp(0.0, 1.0);

          // Format arrival time
          final arrivalTime = formatArrivalTime(
            DateTime.now().add(Duration(seconds: r.durationSec))
          );

          // Get time color based on route ranking
          final timeColor = _getTimeColor(si, i, routes.length);
          
          // Get pollution avoidance text from selectedPollutants
          final pollutionText = _getPollutionAvoidanceText();
          
          // Format distance
          final distance = formatDistanceShort(r.distanceMeters);
          
          // Format duration (e.g., "2 min")
          final duration = formatDurationShort(r.durationSec);

          final isLast = i == routes.length - 1;
          
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onSelect(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: isLast ? null : Border(
                    bottom: BorderSide(
                      color: Colors.grey.shade200,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left: Travel time in colored text
                    SizedBox(
                      width: 90,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Time in one line (e.g., "2 min")
                          Text(
                            duration,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: timeColor,
                            ),
                          ),
                          const SizedBox(height: 6),
                          // "View more details" link
                          InkWell(
                            onTap: () => onSelect(i),
                            child: const Text(
                              "View more details",
                              style: TextStyle(
                                fontSize: 12,
                                decoration: TextDecoration.underline,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Center: Route details - three lines
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Line 1: Arrival time
                          Text(
                            "Arrive $arrivalTime",
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Line 2: Pollution avoidance (from selectedPollutants)
                          if (pollutionText.isNotEmpty) ...[
                            Text(
                              pollutionText,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
                          // Line 3: Distance
                          Text(
                            distance,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Right: Chevron icon (clickable for preview)
                    InkWell(
                      onTap: () {
                        if (onPreview != null) {
                          onPreview!(i);
                        } else {
                          onSelect(i); // Fallback to detail if no preview callback
                        }
                      },
                      child: const Icon(
                        Icons.chevron_right,
                        color: Colors.black87,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
