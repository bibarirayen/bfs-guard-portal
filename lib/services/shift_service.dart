import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/ApiService.dart';
import '../models/AssignmentTrajectory.dart';
import '../models/Stop.dart';
import '../models/Trajectory.dart';
import '../models/shift_models.dart';

class ShiftService {
  final ApiService _api = ApiService();

  Future<int> getGuardId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('userId');
    debugPrint("GUARD ID FROM PREFS: $id");

    if (id == null) throw Exception("Not logged in");
    return id;
  }
  Future<List<Trajectory>> getTrajectoriesByAssignment(int assignmentId) async {
    final res = await ApiService().get("shift/getTrajects/$assignmentId");

    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((e) => Trajectory.fromJson(e)).toList();
    } else {
      throw Exception("Failed to load trajectories");
    }
  }
  Future<List<Stop>> getStops(int assignmentTrajectoryId) async {
    final res =
    await _api.get("assignment-trajectories/$assignmentTrajectoryId");

    if (res.statusCode == 200) {
      final List<dynamic> data = jsonDecode(res.body);

      return data.map((e) => Stop.fromJson(e)).toList();
    } else {
      throw Exception("Failed to load stops");
    }
  }


  Future<void> sendStopScan({
    required int assignmentTrajectoryId,
    required int trajectoryStopId,
    required int stopId,
    required double distance,
    required int accuracy,
    required bool isLate,
    required int lateMinutes,
  }) async {
    final response = await ApiService().post(
      "assignment-trajectories/$assignmentTrajectoryId/scan",
      {
        'trajectoryStopId': trajectoryStopId, // ✅ REQUIRED
        'stopId': stopId,
        'distanceFeet': distance,
        'accuracyPercent': accuracy,
        'isLate': isLate,
        'lateMinutes': lateMinutes,
      },
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception("Scan failed: ${response.body}");
    }
  }


  Future<List<AssignmentTrajectory>> getAssignmentTrajectories(int assignmentId) async {
    final res = await _api.get("assignment-trajectories/assignment/$assignmentId");
    print('getAssignmentTrajectories response: ${res.body}');

    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data
          .map((e) => AssignmentTrajectory.fromJson(e))
          .toList();
    } else {
      throw Exception("Failed to load assignment trajectories");
    }
  }

  Future<void> startAssignment(int assignmentId) async {
    final res = await _api.post("assignment-trajectories/start-assignment/$assignmentId", {});
    if (res.statusCode != 200) {
      throw Exception("Failed to start assignment: ${res.body}");
    }
  }
  Future<void> startTrajectory(int assignmentTrajectoryId) async {
    final res = await _api.post("assignment-trajectories/start/$assignmentTrajectoryId", {});
    if (res.statusCode != 200) {
      throw Exception("Failed to start trajectory: ${res.body}");
    }
  }
  Future<void> completeTrajectory(int assignmentTrajectoryId) async {
    final res = await _api.post("assignment-trajectories/complete/$assignmentTrajectoryId", {});
    if (res.statusCode != 200) {
      throw Exception("Failed to complete trajectory: ${res.body}");
    }
  }


  Future<List<ShiftTrajectory>> getActiveTrajectories() async {
    final guardId = await getGuardId();

    final res =
    await _api.get('shift/active/$guardId');

    if (res.statusCode == 204) return [];

    if (res.statusCode != 200) {
      throw Exception('Failed to load shift');
    }

    final shift = ShiftResponse.fromJson(jsonDecode(res.body));
    print(shift);
    return shift.trajectories;
  }
}