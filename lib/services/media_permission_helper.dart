import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// Result of a media permission check.
enum MediaPermissionResult {
  granted,    // Full access — proceed normally
  limited,    // iOS "Limited" — picker works but only shows selected photos
  denied,     // Denied this session — show snackbar
  permanentlyDenied, // Must go to Settings
}

/// Single source of truth for all gallery/camera permission logic.
/// Handles:
///   - iOS "Limited Photos" (PermissionStatus.limited) — lets the picker
///     open but warns the user they may not see all photos
///   - Android 13+ granular media permissions (photos vs videos vs both)
///   - Never re-shows a system dialog when permission is already granted/limited
class MediaPermissionHelper {

  /// Check & request gallery permission for picking IMAGES.
  static Future<MediaPermissionResult> requestGalleryPhoto() async {
    if (Platform.isIOS) return _requestIosPhotos();
    return _requestAndroidMedia(needPhotos: true, needVideos: false);
  }

  /// Check & request gallery permission for picking VIDEOS.
  static Future<MediaPermissionResult> requestGalleryVideo() async {
    if (Platform.isIOS) return _requestIosPhotos(); // iOS uses same .photos permission for video too
    return _requestAndroidMedia(needPhotos: false, needVideos: true);
  }

  /// Check & request camera permission.
  static Future<MediaPermissionResult> requestCamera() async {
    final status = await Permission.camera.status;
    if (status.isGranted) return MediaPermissionResult.granted;
    if (status.isPermanentlyDenied) return MediaPermissionResult.permanentlyDenied;

    final result = await Permission.camera.request();
    if (result.isGranted) return MediaPermissionResult.granted;
    if (result.isPermanentlyDenied) return MediaPermissionResult.permanentlyDenied;
    return MediaPermissionResult.denied;
  }

  /// Check & request microphone permission (for video recording with audio).
  static Future<MediaPermissionResult> requestMicrophone() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return MediaPermissionResult.granted;
    if (status.isPermanentlyDenied) return MediaPermissionResult.permanentlyDenied;

    final result = await Permission.microphone.request();
    if (result.isGranted) return MediaPermissionResult.granted;
    if (result.isPermanentlyDenied) return MediaPermissionResult.permanentlyDenied;
    return MediaPermissionResult.denied;
  }

  // ─── iOS ────────────────────────────────────────────────────────────────────

  static Future<MediaPermissionResult> _requestIosPhotos() async {
    // Check FIRST — avoid re-showing the system dialog if already granted/limited
    final current = await Permission.photos.status;

    if (current.isGranted) return MediaPermissionResult.granted;

    // ⚠️ KEY FIX: iOS "limited" means the user chose "Select Photos".
    // image_picker CAN open the gallery in this state, so we allow it
    // but return `limited` so the caller can show a hint.
    if (current == PermissionStatus.limited) return MediaPermissionResult.limited;

    if (current.isPermanentlyDenied) return MediaPermissionResult.permanentlyDenied;

    // Only request the system dialog if truly denied (not yet asked)
    if (current.isDenied) {
      final result = await Permission.photos.request();
      if (result.isGranted) return MediaPermissionResult.granted;
      if (result == PermissionStatus.limited) return MediaPermissionResult.limited;
      if (result.isPermanentlyDenied) return MediaPermissionResult.permanentlyDenied;
      return MediaPermissionResult.denied;
    }

    return MediaPermissionResult.denied;
  }

  // ─── Android ────────────────────────────────────────────────────────────────

  static Future<MediaPermissionResult> _requestAndroidMedia({
    required bool needPhotos,
    required bool needVideos,
  }) async {
    final sdk = await _getAndroidSdk();

    if (sdk >= 33) {
      // Android 13+ uses granular permissions
      final perms = <Permission>[];
      if (needPhotos) perms.add(Permission.photos);
      if (needVideos) perms.add(Permission.videos);

      for (final perm in perms) {
        var status = await perm.status;
        // Treat permanentlyDenied same as denied — let caller decide to open Settings.
        // Re-querying after openAppSettings() is the caller's responsibility.
        if (status.isPermanentlyDenied) return MediaPermissionResult.permanentlyDenied;

        if (!status.isGranted) {
          status = await perm.request();
          if (status.isPermanentlyDenied) return MediaPermissionResult.permanentlyDenied;
          if (!status.isGranted) return MediaPermissionResult.denied;
        }
      }
      return MediaPermissionResult.granted;

    } else {
      // Android < 13 uses legacy READ_EXTERNAL_STORAGE
      var status = await Permission.storage.status;
      if (status.isGranted) return MediaPermissionResult.granted;
      if (status.isPermanentlyDenied) return MediaPermissionResult.permanentlyDenied;

      final result = await Permission.storage.request();
      if (result.isGranted) return MediaPermissionResult.granted;
      if (result.isPermanentlyDenied) return MediaPermissionResult.permanentlyDenied;
      return MediaPermissionResult.denied;
    }
  }

  static int? _cachedSdk;
  static Future<int> _getAndroidSdk() async {
    if (_cachedSdk != null) return _cachedSdk!;
    try {
      final match = RegExp(r'Android (\d+)').firstMatch(Platform.operatingSystemVersion);
      if (match != null) {
        final v = int.tryParse(match.group(1) ?? '');
        if (v != null) {
          _cachedSdk = {14: 34, 13: 33, 12: 32, 11: 30, 10: 29, 9: 28}[v] ?? (v >= 13 ? 33 : 28);
          return _cachedSdk!;
        }
      }
    } catch (_) {}
    return _cachedSdk = 30;
  }
}