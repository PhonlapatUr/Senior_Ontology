import 'package:flutter/material.dart';
import '../models/route_info.dart';
import '../models/route_indicators.dart';
import '../utils/helpers.dart';

class RouteList extends StatelessWidget {
  final List<RouteInfo> routes;
  final int chosenRoute;
  final Map<int, RouteIndicators> indicators;
  final Function(int index) onSelect;
  final Function(int index)? onPreview;
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
    
    final allDssScores = indicators.values.map((e) => e.si).toList();
    
    final uniqueScores = allDssScores.toSet().toList()..sort((a, b) => a.compareTo(b));
    
    if (uniqueScores.isEmpty) return Colors.grey;
    
    final rank = uniqueScores.indexOf(si);
    
    if (rank == -1) return Colors.grey;
    
    if (uniqueScores.length == 1) return Colors.green;
    
    if (uniqueScores.length == 2) {
      return rank == 0 ? Colors.green : const Color(0xFFF9A825);
    }
    
    if (rank == 0) {
      return Colors.green;
    } else if (rank == uniqueScores.length - 1) {
      return Colors.red;
    } else {
      return const Color(0xFFF9A825);
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

          final ind = indicators[i]!;
          final si = ind.si.clamp(0.0, 1.0);

          final arrivalTime = formatArrivalTime(
            DateTime.now().add(Duration(seconds: r.durationSec))
          );

          final timeColor = _getTimeColor(si, i, routes.length);
          
          final pollutionText = _getPollutionAvoidanceText();
          
          final distance = formatDistanceShort(r.distanceMeters);
          
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
                    SizedBox(
                      width: 90,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            duration,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: timeColor,
                            ),
                          ),
                          const SizedBox(height: 6),
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

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Arrive $arrivalTime",
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
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

                    InkWell(
                      onTap: () {
                        if (onPreview != null) {
                          onPreview!(i);
                        } else {
                          onSelect(i);
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
