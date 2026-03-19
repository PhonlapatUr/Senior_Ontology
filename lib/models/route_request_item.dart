class RouteRequestItem {
  final String id;
  final String encodedPolyline;
  final int distanceMeters;
  final int durationSeconds;

  RouteRequestItem({
    required this.id,
    required this.encodedPolyline,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  Map<String, dynamic> toJson() => {
    "id": id,
    "encodedPolyline": encodedPolyline,
    "distanceMeters": distanceMeters,
    "durationSeconds": durationSeconds,
  };
}
