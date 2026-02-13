import 'package:shared_preferences/shared_preferences.dart';

class ActiveTrajectManager {
  static const _key = 'activeTrajectIds'; // now storing a list

  /// Get all active traject instance keys
  static Future<List<String>> getActiveTrajects() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }
  static Future<void> clearAllActiveTrajects() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key); // or however you store the list
  }

  /// Check if a specific instance is active
  static Future<bool> isActive(String instanceKey) async {
    final active = await getActiveTrajects();
    return active.contains(instanceKey);
  }

  /// Add a new active traject instance
  static Future<void> addActiveTraject(String instanceKey) async {
    final prefs = await SharedPreferences.getInstance();
    final active = await getActiveTrajects();
    if (!active.contains(instanceKey)) {
      active.add(instanceKey);
      await prefs.setStringList(_key, active);
    }
  }

  /// Remove a specific active traject instance
  static Future<void> removeActiveTraject(String instanceKey) async {
    final prefs = await SharedPreferences.getInstance();
    final active = await getActiveTrajects();
    active.remove(instanceKey);
    await prefs.setStringList(_key, active);
  }

  /// Clear all active trajects
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
