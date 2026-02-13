class Stop {
  final int trajectoryStopId; // ✅ NEW
  final int stopId;           // ✅ REAL stop ID
  final String name;
  final double latitude;
  final double longitude;
  final double range;
  final String? description;
  final String verificationType;
  bool isScanned;

  Stop({
    required this.trajectoryStopId,
    required this.stopId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.range,
    this.description,
    required this.verificationType,
    this.isScanned = false,
  });

  factory Stop.fromJson(Map<String, dynamic> json) {
    return Stop(
      trajectoryStopId: json['trajectoryStopId'], // ✅
      stopId: json['id'],                     // ✅
      name: json['name'],
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      range: (json['range'] as num).toDouble(),
      description: json['description'],
      verificationType: json['verificationType'],
      isScanned: json['scanned'] ?? false,
    );
  }
}
