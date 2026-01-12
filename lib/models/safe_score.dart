// models/safe_score.dart

class SafeScore {
  final String id;

  // Route decision values
  final double di;
  final double dt;
  final double dp;
  final double dw;

  // Final score from API
  final double riskScore;

  // Additional values
  final double avgHumidity;
  final int pointsSampled;
  final int pointsUsed;
  final String note;

  SafeScore({
    required this.id,
    required this.di,
    required this.dt,
    required this.dp,
    required this.dw,
    required this.riskScore,
    required this.avgHumidity,
    required this.pointsSampled,
    required this.pointsUsed,
    required this.note,
  });

  factory SafeScore.fromJson(Map<String, dynamic> json) {
    return SafeScore(
      id: json["id"],
      di: (json["di"] as num).toDouble(),
      dt: (json["dt"] as num).toDouble(),
      dp: (json["dp"] as num).toDouble(),
      dw: (json["dw"] as num).toDouble(),
      riskScore: (json["risk_score"] as num).toDouble(),

      avgHumidity: (json["avgHumidity"] as num).toDouble(),
      pointsSampled: json["points_sampled"] ?? json["pointsSampled"] ?? 0,
      pointsUsed: json["points_used"] ?? json["pointsUsed"] ?? 0,
      note: json["note"] ?? "",
    );
  }
}
