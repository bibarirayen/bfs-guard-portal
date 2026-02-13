class AssignmentTrajectory {
  final int id;
  final int trajectoryId;
  final String name;
  final String description;
  final int duration;

  bool isActive;
  bool isDone;
  bool isFailed;

  DateTime? startedAt;
  DateTime? completedAt;
  DateTime? expiresAt;

  String? instanceKey;

  AssignmentTrajectory({
    required this.id,
    required this.trajectoryId,
    required this.name,
    required this.description,
    required this.duration,
    this.isActive = false,
    this.isDone = false,
    this.isFailed = false,
    this.startedAt,
    this.completedAt,
    this.expiresAt,
    this.instanceKey,
  });

  factory AssignmentTrajectory.fromJson(Map<String, dynamic> json) {
    return AssignmentTrajectory(
      id: json['id'],
      trajectoryId: json['trajectory']['id'],
      name: json['trajectory']['name'] ?? '',
      description: json['trajectory']['description'] ?? '',
      duration: json['trajectory']['totalDuration'] ?? 0,
      isActive: json['isActive'] ?? false,
      isDone: json['isDone'] ?? false,
      isFailed: json['isFailed'] ?? false,
      startedAt: json['startedAt'] != null
          ? DateTime.parse(json['startedAt'])
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'])
          : null,
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'])
          : null,
      instanceKey: '${json['id']}',
    );
  }
}
