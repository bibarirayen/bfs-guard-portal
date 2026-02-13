class Trajectory {
  final int id;
  final String name;
  final String description;
  final int duration;
  bool isActive = false; // default
  String? instanceKey;

  Trajectory({
    required this.id,
    required this.duration,

    required this.name,
    required this.description,
  });

  factory Trajectory.fromJson(Map<String, dynamic> json) {
    return Trajectory(
      id: json['id'],
      name: json['name'],
      duration: json['duration'],
      description: json['description'] ?? '',
    );
  }
}
