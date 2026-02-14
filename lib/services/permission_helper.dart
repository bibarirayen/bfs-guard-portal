// lib/services/permission_helper.dart

import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

class PermissionHelper {
  /// Request "Always" location permission for background tracking
  /// iOS requires a two-step process: first "When In Use", then "Always"
  static Future<bool> requestAlwaysLocationPermission(BuildContext? context) async {
    // First check current status
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.always) {
      print('✅ Already have "Always" location permission');
      return true;
    }
    
    // If permission is denied, request when-in-use first (iOS requirement)
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      
      if (permission == LocationPermission.denied) {
        print('❌ Location permission denied');
        return false;
      }
      
      if (permission == LocationPermission.deniedForever) {
        print('❌ Location permission permanently denied');
        if (context != null) {
          _showPermissionDeniedDialog(context);
        }
        return false;
      }
    }
    
    // Now we have at least "When In Use" permission
    // For iOS, request "Always" permission
    if (Platform.isIOS) {
      if (permission == LocationPermission.whileInUse) {
        // Request always permission using permission_handler
        PermissionStatus alwaysStatus = await Permission.locationAlways.request();
        
        if (alwaysStatus.isGranted) {
          print('✅ "Always" location permission granted');
          return true;
        } else if (alwaysStatus.isPermanentlyDenied) {
          print('❌ "Always" location permission permanently denied');
          if (context != null) {
            _showAlwaysPermissionDialog(context);
          }
          return false;
        } else {
          print('⚠️ "Always" permission not granted, but "While In Use" is available');
          if (context != null) {
            _showAlwaysPermissionDialog(context);
          }
          return false;
        }
      }
    } else {
      // Android - check if we have permission
      if (permission == LocationPermission.whileInUse || 
          permission == LocationPermission.always) {
        print('✅ Location permission granted');
        return true;
      }
    }
    
    return permission == LocationPermission.always;
  }

  /// Show dialog explaining that "Always" permission is required
  static void _showAlwaysPermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Permission Required'),
        content: const Text(
          'For accurate shift tracking and safety monitoring during your entire shift, '
          'please allow location access "Always" in your device settings.\n\n'
          'This ensures:\n'
          '• Continuous route tracking\n'
          '• Automatic safety alerts\n'
          '• Accurate shift reporting\n\n'
          'Tap "Open Settings" to change this.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Show dialog for permanently denied permissions
  static void _showPermissionDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'Location permission is required for shift tracking. '
          'Please enable it in your device settings.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Request microphone permission (for video recording)
  static Future<bool> requestMicrophonePermission(BuildContext? context) async {
    PermissionStatus status = await Permission.microphone.request();
    
    if (status.isGranted) {
      print('✅ Microphone permission granted');
      return true;
    } else if (status.isPermanentlyDenied) {
      print('❌ Microphone permission permanently denied');
      if (context != null) {
        _showMicrophonePermissionDialog(context);
      }
      return false;
    } else {
      print('⚠️ Microphone permission denied');
      return false;
    }
  }

  /// Show microphone permission dialog
  static void _showMicrophonePermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Microphone Permission Required'),
        content: const Text(
          'Microphone access is required to record videos with audio for incident reports. '
          'Please enable it in your device settings.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Request camera permission
  static Future<bool> requestCameraPermission(BuildContext? context) async {
    PermissionStatus status = await Permission.camera.request();
    
    if (status.isGranted) {
      print('✅ Camera permission granted');
      return true;
    } else if (status.isPermanentlyDenied) {
      print('❌ Camera permission permanently denied');
      if (context != null) {
        _showCameraPermissionDialog(context);
      }
      return false;
    } else {
      print('⚠️ Camera permission denied');
      return false;
    }
  }

  /// Show camera permission dialog
  static void _showCameraPermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Camera Permission Required'),
        content: const Text(
          'Camera access is required to capture photos and videos for reports. '
          'Please enable it in your device settings.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
