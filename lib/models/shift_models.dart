class ShiftResponse {
  final List<ShiftTrajectory> trajectories;

  ShiftResponse({required this.trajectories});

  factory ShiftResponse.fromJson(Map<String, dynamic> json) {
    return ShiftResponse(
      trajectories: (json['shiftTrajectories'] as List)
          .map((e) => ShiftTrajectory.fromJson(e))
          .toList(),
    );
  }
}

class ShiftTrajectory {
  final String name;
  final int orderIndex;
  final int timeGapMinutes;

  ShiftTrajectory({
    required this.name,
    required this.orderIndex,
    required this.timeGapMinutes,
  });

  factory ShiftTrajectory.fromJson(Map<String, dynamic> json) {
    return ShiftTrajectory(
      name: json['trajectoryName'],
      orderIndex: json['trajectoryOrder'],
      timeGapMinutes: json['breakMinutes'],
    );
  }
}
