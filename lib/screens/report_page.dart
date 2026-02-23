// file: lib/screens/report_page.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crossplatformblackfabric/config/ApiService.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';
import 'package:video_compress/video_compress.dart';
import 'package:ffmpeg_kit_flutter_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min/return_code.dart';

// ─── Media item ───────────────────────────────────────────────────────────────
// Tracks the file through its lifecycle:
//   raw file picked → compression running in background → compressed file ready
// When Submit is pressed, we upload whichever file is ready (compressed if done,
// raw if compression somehow failed) and wait for the upload before firing email.
class _MediaItem {
  File file;           // starts as raw, swapped to compressed when done
  final bool isVideo;
  Uint8List? thumbnail;

  // Compression state
  bool isCompressing;
  bool compressionFailed;
  double compressionProgress; // 0.0 → 1.0

  // Set once compression finishes
  File? compressedFile;

  _MediaItem({required this.file, required this.isVideo, this.thumbnail})
      : isCompressing = false,
        compressionFailed = false,
        compressionProgress = 0.0;

  // The file we'll actually upload — compressed version if available, else raw
  File get uploadFile => compressedFile ?? file;

  bool get isReady => !isCompressing; // ready to upload even if compression failed (uploads raw)
}

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});
  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  bool _isDarkMode = true;

  // ─── THEME ────────────────────────────────────────────────────────────────
  Color get _backgroundColor => _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _textColor       => _isDarkMode ? Colors.white : const Color(0xFF1E293B);
  Color get _cardColor       => _isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  Color get _borderColor     => _isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get _secondaryTextColor => _isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
  Color get _primaryColor    => const Color(0xFF4F46E5);
  Color get _accentColor     => _isDarkMode ? const Color(0xFF7C73FF) : const Color(0xFF6366F1);

  // ─── CONTROLLERS ──────────────────────────────────────────────────────────
  final TextEditingController _clientController               = TextEditingController();
  final TextEditingController _siteController                 = TextEditingController();
  final TextEditingController _officerController              = TextEditingController();
  final TextEditingController _dateEnteredController          = TextEditingController();
  final TextEditingController _incidentInternalIdController   = TextEditingController();
  final TextEditingController _incidentDateTimeController     = TextEditingController();
  final TextEditingController _incidentTypeController         = TextEditingController();
  final TextEditingController _victimNameController           = TextEditingController();
  final TextEditingController _victimContactController        = TextEditingController();
  final TextEditingController _suspectNameController          = TextEditingController();
  final TextEditingController _suspectContactController       = TextEditingController();
  final TextEditingController _witnessNamesController         = TextEditingController();
  final TextEditingController _incidentLocationController     = TextEditingController();
  final TextEditingController _incidentSummaryController      = TextEditingController();
  final TextEditingController _responderPoliceNamesController = TextEditingController();
  final TextEditingController _responderFireTruckController   = TextEditingController();
  final TextEditingController _responderAmbulanceController   = TextEditingController();
  final TextEditingController _incidentDetailsController      = TextEditingController();
  final TextEditingController _incidentActionsController      = TextEditingController();
  bool _policeCalled = false;

  final TextEditingController _dailyShiftStartNotesController    = TextEditingController();
  final TextEditingController _dailyPostShiftController          = TextEditingController();
  final TextEditingController _dailySpecialInstructionsController = TextEditingController();
  final TextEditingController _dailyPostItemsReceivedController  = TextEditingController();
  final TextEditingController _dailyObservationsController       = TextEditingController();
  final TextEditingController _dailyRelievingFirstController     = TextEditingController();
  final TextEditingController _dailyRelievingLastController      = TextEditingController();
  final TextEditingController _dailyAdditionalNotesController    = TextEditingController();

  final TextEditingController _maintenanceTypeController        = TextEditingController();
  final TextEditingController _maintenanceDetailsController     = TextEditingController();
  final TextEditingController _maintenanceWhoNotifiedController = TextEditingController();
  bool _maintenanceEmailClient = false;

  final TextEditingController _violatorFirstController    = TextEditingController();
  final TextEditingController _violatorLastController     = TextEditingController();
  final TextEditingController _vehicleMakeController      = TextEditingController();
  final TextEditingController _vehicleModelController     = TextEditingController();
  final TextEditingController _vehicleLPController        = TextEditingController();
  final TextEditingController _vehicleVINController       = TextEditingController();
  final TextEditingController _vehicleColorController     = TextEditingController();
  final TextEditingController _violationTypeController    = TextEditingController();
  final TextEditingController _violationNumberController  = TextEditingController();
  final TextEditingController _parkingLocationController  = TextEditingController();
  final TextEditingController _parkingFineController      = TextEditingController();
  final TextEditingController _parkingDetailsController   = TextEditingController();
  bool _vehicleTowed = false;

  // ─── STATE ────────────────────────────────────────────────────────────────
  final List<_MediaItem> _mediaItems = [];
  bool _isPickingMedia  = false;
  bool _isSubmitting    = false;
  double _uploadProgress = 0.0;

  String _selectedReportType = "Incident Report";
  final List<String> _reportTypes = [
    "Incident Report", "Daily Activity Report",
    "Maintenance Report", "Parking Violation Report",
  ];

  final api = ApiService();
  List<Map<String, dynamic>> _sites = [];
  bool _hasActiveAssignment = false;
  int? _selectedSiteId;
  final ImagePicker _picker = ImagePicker();

  // ─── LIFECYCLE ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _fetchSites();
  }

  @override
  void dispose() {
    for (final c in [
      _clientController, _siteController, _officerController, _dateEnteredController,
      _incidentInternalIdController, _incidentDateTimeController, _incidentTypeController,
      _victimNameController, _victimContactController, _suspectNameController,
      _suspectContactController, _witnessNamesController, _incidentLocationController,
      _incidentSummaryController, _responderPoliceNamesController, _responderFireTruckController,
      _responderAmbulanceController, _incidentDetailsController, _incidentActionsController,
      _dailyShiftStartNotesController, _dailyPostShiftController, _dailySpecialInstructionsController,
      _dailyPostItemsReceivedController, _dailyObservationsController, _dailyRelievingFirstController,
      _dailyRelievingLastController, _dailyAdditionalNotesController, _maintenanceTypeController,
      _maintenanceDetailsController, _maintenanceWhoNotifiedController, _violatorFirstController,
      _violatorLastController, _vehicleMakeController, _vehicleModelController, _vehicleLPController,
      _vehicleVINController, _vehicleColorController, _violationTypeController,
      _violationNumberController, _parkingLocationController, _parkingFineController,
      _parkingDetailsController,
    ]) { c.dispose(); }
    super.dispose();
  }

  void _resetPage() {
    setState(() {
      _mediaItems.clear();
      _selectedReportType = "Incident Report";
      _policeCalled        = false;
      _maintenanceEmailClient = false;
      _vehicleTowed        = false;
      _uploadProgress      = 0.0;
      _isSubmitting        = false;
      _isPickingMedia      = false;
    });
    for (final c in [
      _clientController, _siteController, _officerController, _dateEnteredController,
      _incidentInternalIdController, _incidentDateTimeController, _incidentTypeController,
      _victimNameController, _victimContactController, _suspectNameController,
      _suspectContactController, _witnessNamesController, _incidentLocationController,
      _incidentSummaryController, _responderPoliceNamesController, _responderFireTruckController,
      _responderAmbulanceController, _incidentDetailsController, _incidentActionsController,
      _dailyShiftStartNotesController, _dailyPostShiftController, _dailySpecialInstructionsController,
      _dailyPostItemsReceivedController, _dailyObservationsController, _dailyRelievingFirstController,
      _dailyRelievingLastController, _dailyAdditionalNotesController, _maintenanceTypeController,
      _maintenanceDetailsController, _maintenanceWhoNotifiedController, _violatorFirstController,
      _violatorLastController, _vehicleMakeController, _vehicleModelController, _vehicleLPController,
      _vehicleVINController, _vehicleColorController, _violationTypeController,
      _violationNumberController, _parkingLocationController, _parkingFineController,
      _parkingDetailsController,
    ]) { c.clear(); }
  }

  // ─── PERMISSIONS ──────────────────────────────────────────────────────────
  Future<bool> _requestPermissions(ImageSource source, {bool forVideo = false}) async {
    if (Platform.isIOS) return _requestPermissionsIOS(source, forVideo: forVideo);
    return _requestPermissionsAndroid(source, forVideo: forVideo);
  }

  Future<bool> _requestPermissionsIOS(ImageSource source, {bool forVideo = false}) async {
    if (source == ImageSource.camera) {
      if (!(await Permission.camera.request()).isGranted) {
        _showPermissionDeniedDialog('Camera Permission Required',
            'Camera access is needed to take photos/videos for reports.', showSettings: true);
        return false;
      }
      if (forVideo && !(await Permission.microphone.request()).isGranted) {
        _showPermissionDeniedDialog('Microphone Permission Required',
            'Microphone access is required to record video with audio.', showSettings: true);
        return false;
      }
      return true;
    }
    final status = await Permission.photos.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      _showPermissionDeniedDialog('Photo Library Permission Required',
          'Go to Settings → BFS Guard Portal → Photos → "All Photos".', showSettings: true);
      return false;
    }
    return true;
  }

  Future<bool> _requestPermissionsAndroid(ImageSource source, {bool forVideo = false}) async {
    if (source == ImageSource.camera) {
      if (!(await Permission.camera.request()).isGranted) {
        _snackError('Camera permission is required.'); return false;
      }
      if (forVideo && !(await Permission.microphone.request()).isGranted) {
        _snackError('Microphone permission is required.'); return false;
      }
      return true;
    }
    final sdk = await _getAndroidSdkVersion();
    final perm = sdk >= 33 ? (forVideo ? Permission.videos : Permission.photos) : Permission.storage;
    final status = await perm.request();
    if (!status.isGranted) {
      status.isPermanentlyDenied
          ? _showPermissionDeniedDialog('Permission Blocked', 'Open App Settings to enable.', showSettings: true)
          : _snackError('Permission is required.');
      return false;
    }
    return true;
  }

  int? _cachedSdkVersion;
  Future<int> _getAndroidSdkVersion() async {
    if (_cachedSdkVersion != null) return _cachedSdkVersion!;
    try {
      final match = RegExp(r'Android (\d+)').firstMatch(Platform.operatingSystemVersion);
      if (match != null) {
        final v = int.tryParse(match.group(1) ?? '');
        if (v != null) {
          _cachedSdkVersion = {14:34,13:33,12:32,11:30,10:29,9:28}[v] ?? (v >= 13 ? 33 : 28);
          return _cachedSdkVersion!;
        }
      }
    } catch (_) {}
    return _cachedSdkVersion = 30;
  }

  void _snackError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating));
  }

  void _showPermissionDeniedDialog(String title, String msg, {bool showSettings = false}) {
    if (!mounted) return;
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: _cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        const Icon(Icons.lock, color: Colors.redAccent, size: 22), const SizedBox(width: 8),
        Expanded(child: Text(title, style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w700))),
      ]),
      content: Text(msg, style: TextStyle(color: _secondaryTextColor, fontSize: 14, height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: _secondaryTextColor))),
        if (showSettings) ElevatedButton(
          onPressed: () { Navigator.pop(context); openAppSettings(); },
          style: ElevatedButton.styleFrom(backgroundColor: _primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          child: const Text('Open Settings', style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
  }

  // ─── VIDEO COMPRESSION ────────────────────────────────────────────────────
  // Runs in background the moment a video is picked.
  // Target: 720p, ~40–80 MB for a 2-minute clip (vs 400 MB raw).
  // This runs while the guard fills the form — by Submit time it's usually done.
  Future<void> _compressVideoInBackground(_MediaItem item, int index) async {
    if (!mounted) return;
    setState(() {
      item.isCompressing = true;
      item.compressionProgress = 0.01;
    });

    try {
      File compressed;

      if (Platform.isAndroid) {
        compressed = await _compressAndroid(item.file, index);
      } else {
        compressed = await _compressIOS(item.file, index);
      }

      if (mounted && index < _mediaItems.length) {
        setState(() {
          _mediaItems[index].compressedFile  = compressed;
          _mediaItems[index].isCompressing   = false;
          _mediaItems[index].compressionProgress = 1.0;
        });
      }
    } catch (_) {
      // Compression failed — we'll just upload the raw file. No crash.
      if (mounted && index < _mediaItems.length) {
        setState(() {
          _mediaItems[index].isCompressing      = false;
          _mediaItems[index].compressionFailed  = true;
          _mediaItems[index].compressionProgress = 0.0;
        });
      }
    }
  }

  Future<File> _compressAndroid(File file, int index) async {
    final dir = await getTemporaryDirectory();
    final ts  = DateTime.now().millisecondsSinceEpoch;
    final out = '${dir.path}/${ts}_720p.mp4';

    // h264_mediacodec = Android hardware encoder (MediaCodec API)
    // Hardware encoding is 10–20x faster than software (libx264)
    // scale=1280:720 → 720p, keeps aspect ratio, pads with black if needed
    // b:v 1500k → ~1.5 Mbps — sharp at 720p, good for playback and email links
    // movflags +faststart → browser/email can play before fully downloaded
    final hwCmd =
        '-i "${file.path}" '
        '-c:v h264_mediacodec '
        '-b:v 1500k '
        '-vf "scale=\'if(gt(iw,ih),1280,-2)\':\'if(gt(iw,ih),-2,1280)\'" '
        '-c:a aac -b:a 96k '
        '-movflags +faststart '
        '"$out"';

    final session  = await FFmpegKit.execute(hwCmd);
    final rc       = await session.getReturnCode();

    if (ReturnCode.isSuccess(rc)) {
      final f = File(out);
      if (await f.exists()) {
        _updateCompressionProgress(index, 0.95);
        return f;
      }
    }

    // Software fallback (older devices without hardware encoder)
    final swOut = '${dir.path}/${ts}_720p_sw.mp4';
    final swCmd =
        '-i "${file.path}" '
        '-c:v libx264 -preset veryfast -crf 26 '
        '-vf "scale=\'if(gt(iw,ih),1280,-2)\':\'if(gt(iw,ih),-2,1280)\'" '
        '-c:a aac -b:a 96k '
        '-movflags +faststart '
        '"$swOut"';

    final swSession = await FFmpegKit.execute(swCmd);
    if (ReturnCode.isSuccess(await swSession.getReturnCode())) {
      final f = File(swOut);
      if (await f.exists()) return f;
    }

    return file; // upload raw as absolute last resort
  }

  Future<File> _compressIOS(File file, int index) async {
    // VideoCompress uses AVFoundation hardware encoder on iOS — very fast
    await VideoCompress.cancelCompression();

    // Subscribe to compression progress to update UI
    final sub = VideoCompress.compressProgress$.subscribe((progress) {
      _updateCompressionProgress(index, progress / 100.0);
    });

    try {
      final info = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.Res1280x720Quality, // 720p
        deleteOrigin: false,
        includeAudio: true,
        frameRate: 30,
      );
      return info?.file ?? file;
    } finally {
      sub.unsubscribe();
    }
  }

  void _updateCompressionProgress(int index, double progress) {
    if (mounted && index < _mediaItems.length) {
      setState(() => _mediaItems[index].compressionProgress = progress.clamp(0.0, 1.0));
    }
  }

  // ─── IMAGE COMPRESSION ────────────────────────────────────────────────────
  Future<File> _compressImage(File file) async {
    final dir    = await getTemporaryDirectory();
    final ts     = DateTime.now().millisecondsSinceEpoch;
    final useHeic = Platform.isIOS;
    final target  = '${dir.path}/$ts.${useHeic ? 'heic' : 'jpg'}';
    final result  = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path, target,
      quality: 82, minWidth: 0, minHeight: 0,
      format: useHeic ? CompressFormat.heic : CompressFormat.jpeg,
    );
    return result != null ? File(result.path) : file;
  }

  // ─── MEDIA PICKING ────────────────────────────────────────────────────────
  Future<void> _pickVideo(ImageSource source) async {
    if (_isPickingMedia) return;
    if (!await _requestPermissions(source, forVideo: true)) return;
    setState(() => _isPickingMedia = true);

    try {
      // No maxDuration — accept 30 seconds to 5 minutes or anything
      final XFile? picked = await _picker.pickVideo(source: source);
      setState(() => _isPickingMedia = false);
      if (picked == null) return;

      final raw   = File(picked.path);
      final item  = _MediaItem(file: raw, isVideo: true);
      final index = _mediaItems.length;
      setState(() => _mediaItems.add(item));

      // Generate thumbnail (fast, display only)
      VideoCompress.getByteThumbnail(raw.path, quality: 50).then((bytes) {
        if (mounted && bytes != null && index < _mediaItems.length) {
          setState(() => _mediaItems[index].thumbnail = bytes);
        }
      }).catchError((_) {});

      // START COMPRESSION IMMEDIATELY in background
      // By the time the guard finishes filling the form this is likely done
      _compressVideoInBackground(item, index);

    } catch (e) {
      setState(() => _isPickingMedia = false);
      final s = e.toString().toLowerCase();
      if (s.contains('permission') || s.contains('denied')) {
        _showPermissionDeniedDialog('Permission Required', 'Please grant the required permission.', showSettings: true);
      } else if (!s.contains('cancel')) {
        _snackError('Could not load video. Please try again.');
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_isPickingMedia) return;
    if (!await _requestPermissions(source)) return;
    setState(() => _isPickingMedia = true);

    try {
      final XFile? picked = await _picker.pickImage(source: source);
      setState(() => _isPickingMedia = false);
      if (picked == null) return;

      final raw = File(picked.path);
      if (!await raw.exists()) { _snackError('Could not access the selected image.'); return; }

      final item  = _MediaItem(file: raw, isVideo: false);
      final index = _mediaItems.length;
      setState(() => _mediaItems.add(item));

      // Compress image in background (< 1s), swap file when done
      _compressImage(raw).then((compressed) {
        if (mounted && index < _mediaItems.length) {
          setState(() {
            _mediaItems[index].file = compressed;
            _mediaItems[index].compressionProgress = 1.0;
          });
        }
      }).catchError((_) {});

    } catch (e) {
      setState(() => _isPickingMedia = false);
      final s = e.toString().toLowerCase();
      if (s.contains('permission') || s.contains('denied')) {
        _showPermissionDeniedDialog('Permission Required', 'Please grant the required permission.', showSettings: true);
      } else if (!s.contains('cancel')) {
        _snackError('Error picking image. Please try again.');
      }
    }
  }

  // ─── FETCH SITES ──────────────────────────────────────────────────────────
  Future<void> _fetchSites() async {
    final prefs      = await SharedPreferences.getInstance();
    final guardId    = prefs.getInt('userId');
    final assignmentId = prefs.getInt('assignmentId');
    if (guardId == null) return;
    if (assignmentId == null) {
      setState(() { _hasActiveAssignment = false; _sites = []; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.redAccent, content: Text("No assignment found!")));
      return;
    }
    try {
      final response = await api.get('assignments/shift/active-shift-sites/$guardId/$assignmentId');
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final site    = decoded['site'];
        if (site != null) {
          setState(() { _sites = [site]; _hasActiveAssignment = true; _selectedSiteId = site['id']; });
        } else {
          setState(() { _sites = []; _hasActiveAssignment = false; });
        }
      } else {
        setState(() { _sites = []; _hasActiveAssignment = false; });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text("No active Assignment found!", style: TextStyle(color: Colors.white))));
      }
    } catch (e) {
      if (mounted) _snackError("Error fetching site: $e");
    }
  }

  // ─── SUBMIT ───────────────────────────────────────────────────────────────
  // Strategy:
  //   1. If any video is still compressing → show a brief "finishing compression"
  //      message and wait for it. This is usually < 5 seconds since compression
  //      started the moment the video was picked.
  //   2. Upload all files (compressed videos + images) with real progress bar.
  //   3. Save report to DB + fire client email — all in one server round-trip.
  Future<void> _submitReport() async {
    if (!_hasActiveAssignment) { _snackError("Cannot submit: no active assignment"); return; }
    if (_selectedSiteId == null) { _snackError("Please select a site"); return; }

    final prefs     = await SharedPreferences.getInstance();
    final officerId = prefs.getInt('userId');

    setState(() { _isSubmitting = true; _uploadProgress = 0.0; });

    try {
      // ── Step 1: Wait for any still-compressing videos ──────────────────
      final stillCompressing = _mediaItems.where((m) => m.isCompressing).toList();
      if (stillCompressing.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              'Almost ready — finishing compression of '
                  '${stillCompressing.length} video${stillCompressing.length > 1 ? 's' : ''}...',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 30),
          ));
        }

        // Poll until all compression is done (max 3 minutes)
        final deadline = DateTime.now().add(const Duration(minutes: 3));
        while (_mediaItems.any((m) => m.isCompressing)) {
          if (DateTime.now().isAfter(deadline)) break; // safety — upload raw
          await Future.delayed(const Duration(milliseconds: 300));
        }

        if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
      }

      // ── Step 2: Collect files to upload ───────────────────────────────
      final payload = {
        "type": _selectedReportType,
        "data": {
          ..._buildReportData(),
          "officerId": officerId,
          "siteId": _selectedSiteId,
        },
      };

      final filesToUpload = _mediaItems.map((m) => m.uploadFile).toList();

      if (filesToUpload.isNotEmpty) {
        // Upload + save report + trigger email — single request
        await api.uploadReportDio(
          payload,
          filesToUpload,
              (sent, total) {
            if (total > 0 && mounted) {
              setState(() => _uploadProgress = sent / total);
            }
          },
        );
      } else {
        final response = await api.post('reports', payload);
        if (response.statusCode != 200 && response.statusCode != 201) {
          throw Exception("Server error: ${response.statusCode}");
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.greenAccent,
          content: Text("Report submitted successfully!", style: TextStyle(color: Colors.black)),
        ));
        _resetPage();
      }

    } on DioException catch (e) {
      _snackError("Upload failed: ${e.response?.data?.toString() ?? e.message}");
    } catch (e) {
      _snackError("Error submitting report: $e");
    } finally {
      if (mounted) setState(() { _isSubmitting = false; _uploadProgress = 0.0; });
    }
  }

  // ─── REPORT DATA ──────────────────────────────────────────────────────────
  Map<String, dynamic> _buildReportData() {
    switch (_selectedReportType) {
      case "Incident Report": return {
        "incidentInternalId": _incidentInternalIdController.text,
        "incidentDateTime":   _incidentDateTimeController.text,
        "incidentType":       _incidentTypeController.text,
        "victimName":         _victimNameController.text,
        "victimContact":      _victimContactController.text,
        "suspectName":        _suspectNameController.text,
        "suspectContact":     _suspectContactController.text,
        "witnessNames":       _witnessNamesController.text,
        "incidentLocation":   _incidentLocationController.text,
        "incidentSummary":    _incidentSummaryController.text,
        "responderPoliceNames": _responderPoliceNamesController.text,
        "responderFireTruck": _responderFireTruckController.text,
        "responderAmbulance": _responderAmbulanceController.text,
        "incidentDetails":    _incidentDetailsController.text,
        "incidentActions":    _incidentActionsController.text,
        "policeCalled":       _policeCalled,
      };
      case "Daily Activity Report": return {
        "dailyShiftStartNotes":     _dailyShiftStartNotesController.text,
        "dailyPostShift":           _dailyPostShiftController.text,
        "dailySpecialInstructions": _dailySpecialInstructionsController.text,
        "dailyPostItemsReceived":   _dailyPostItemsReceivedController.text,
        "dailyObservations":        _dailyObservationsController.text,
        "dailyRelievingFirst":      _dailyRelievingFirstController.text,
        "dailyRelievingLast":       _dailyRelievingLastController.text,
        "dailyAdditionalNotes":     _dailyAdditionalNotesController.text,
      };
      case "Maintenance Report": return {
        "maintenanceType":         _maintenanceTypeController.text,
        "maintenanceDetails":      _maintenanceDetailsController.text,
        "maintenanceWhoNotified":  _maintenanceWhoNotifiedController.text,
        "maintenanceEmailClient":  _maintenanceEmailClient,
      };
      case "Parking Violation Report": return {
        "violatorFirst":   _violatorFirstController.text,
        "violatorLast":    _violatorLastController.text,
        "vehicleMake":     _vehicleMakeController.text,
        "vehicleModel":    _vehicleModelController.text,
        "vehicleLP":       _vehicleLPController.text,
        "vehicleVIN":      _vehicleVINController.text,
        "vehicleColor":    _vehicleColorController.text,
        "violationType":   _violationTypeController.text,
        "violationNumber": _violationNumberController.text,
        "parkingLocation": _parkingLocationController.text,
        "parkingFine":     _parkingFineController.text,
        "parkingDetails":  _parkingDetailsController.text,
        "vehicleTowed":    _vehicleTowed,
      };
      default: return {};
    }
  }

  // ─── INPUT DECORATION ─────────────────────────────────────────────────────
  InputDecoration _modernInput(String label) => InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: _secondaryTextColor, fontWeight: FontWeight.w500, fontSize: 14),
    filled: true,
    fillColor: _isDarkMode ? const Color(0xFF2D3748) : Colors.grey[50],
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border:         OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _borderColor)),
    enabledBorder:  OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _borderColor)),
    focusedBorder:  OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _primaryColor, width: 2)),
    hintStyle:      TextStyle(color: _secondaryTextColor),
  );

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final anyCompressing = _mediaItems.any((m) => m.isCompressing);

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

              // ── Report Type ──────────────────────────────────────────────
              _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.description, color: _primaryColor, size: 20), const SizedBox(width: 8),
                  Text("Report Type", style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedReportType,
                  decoration: _modernInput("Select Report Type"),
                  borderRadius: BorderRadius.circular(14),
                  dropdownColor: _cardColor,
                  icon: Icon(Icons.arrow_drop_down, color: _primaryColor),
                  items: _reportTypes.map((t) => DropdownMenuItem(value: t,
                      child: Text(t, style: TextStyle(color: _textColor)))).toList(),
                  onChanged: (v) => setState(() => _selectedReportType = v!),
                  style: TextStyle(color: _textColor),
                ),
              ])),
              const SizedBox(height: 20),

              // ── Form + Attachments ───────────────────────────────────────
              _card(Column(children: [
                // Form fields
                _innerBox(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _siteDropdown(),
                  Row(children: [
                    Icon(_getReportTypeIcon(), color: _primaryColor, size: 20), const SizedBox(width: 8),
                    Text(_selectedReportType, style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 16),
                  ..._buildReportFields(),
                ])),

                // Attachments
                _innerBox(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.photo_library, color: _primaryColor, size: 20), const SizedBox(width: 8),
                    Text("Attachments", style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    // Live compression badge
                    if (anyCompressing)
                      _badge(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(width: 10, height: 10,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.deepPurpleAccent)),
                          const SizedBox(width: 6),
                          const Text('Compressing', style: TextStyle(color: Colors.deepPurpleAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                        ]),
                        color: Colors.deepPurpleAccent,
                      ),
                  ]),
                  const SizedBox(height: 6),
                  Text("Videos auto-compress to 720p while you fill the form",
                      style: TextStyle(color: _secondaryTextColor, fontSize: 12)),
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _mediaBtn(icon: Icons.videocam,            label: "Video",    onTap: () => _pickVideo(ImageSource.camera),  color: Colors.redAccent),
                    _mediaBtn(icon: Icons.video_library,       label: "Gallery\nVideo", onTap: () => _pickVideo(ImageSource.gallery), color: Colors.orange),
                    _mediaBtn(icon: Icons.camera_alt_rounded,  label: "Camera",   onTap: () => _pickImage(ImageSource.camera),  color: const Color(0xFF3B82F6)),
                    _mediaBtn(icon: Icons.photo_library_rounded, label: "Gallery", onTap: () => _pickImage(ImageSource.gallery), color: const Color(0xFF8B5CF6)),
                  ]),
                  if (_mediaItems.isNotEmpty) ...[const SizedBox(height: 20), _buildGrid()],
                ])),

                const SizedBox(height: 8),
              ])),

              const SizedBox(height: 16),

              // ── Submit ────────────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(colors: [_primaryColor, _accentColor],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  boxShadow: [BoxShadow(color: _primaryColor.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isSubmitting ? null : _submitReport,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      alignment: Alignment.center,
                      child: _isSubmitting
                          ? Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          _uploadProgress > 0
                              ? 'Uploading... ${(_uploadProgress * 100).toStringAsFixed(0)}%'
                              : anyCompressing ? 'Finishing compression...' : 'Preparing...',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _uploadProgress > 0 ? _uploadProgress : null,
                            backgroundColor: Colors.white30,
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                            minHeight: 6,
                          ),
                        ),
                      ])
                          : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.send_rounded, color: Colors.white, size: 22),
                        SizedBox(width: 12),
                        Text("Submit Report", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5)),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ]),
          ),
        )),
      ),
    );
  }

  // ─── GRID ─────────────────────────────────────────────────────────────────
  Widget _buildGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: _mediaItems.length,
      itemBuilder: (context, i) {
        final item = _mediaItems[i];

        Widget thumb;
        if (item.isVideo) {
          thumb = item.thumbnail != null
              ? Stack(fit: StackFit.expand, children: [
            Image.memory(item.thumbnail!, fit: BoxFit.cover),
            const Center(child: Icon(Icons.play_circle_fill, size: 36, color: Colors.white,
                shadows: [Shadow(blurRadius: 8, color: Colors.black54)])),
          ])
              : Container(color: Colors.black87,
              child: const Center(child: Icon(Icons.play_circle_fill, size: 40, color: Colors.white)));
        } else {
          thumb = Image.file(item.file, fit: BoxFit.cover);
        }

        return Stack(fit: StackFit.expand, children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: thumb),

          // Compression progress bar (purple, only for videos)
          if (item.isVideo && item.isCompressing)
            Positioned(bottom: 0, left: 0, right: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(color: Colors.black54, padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Center(child: Text(
                      '${(item.compressionProgress * 100).toStringAsFixed(0)}% compressed',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
                    )),
                  ),
                  LinearProgressIndicator(
                    value: item.compressionProgress > 0 ? item.compressionProgress : null,
                    backgroundColor: Colors.black45,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.deepPurpleAccent),
                    minHeight: 4,
                  ),
                ]),
              ),
            ),

          // Compression done checkmark
          if (item.isVideo && !item.isCompressing && item.compressedFile != null)
            Positioned(bottom: 6, left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.85), borderRadius: BorderRadius.circular(8)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check, size: 10, color: Colors.white),
                  SizedBox(width: 3),
                  Text('720p', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),

          // Compression failed badge (will upload raw)
          if (item.isVideo && item.compressionFailed)
            Positioned(bottom: 6, left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.85), borderRadius: BorderRadius.circular(8)),
                child: const Text('raw', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
              ),
            ),

          // Delete button
          Positioned(top: 6, right: 6,
            child: GestureDetector(
              onTap: () => setState(() => _mediaItems.removeAt(i)),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)]),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        ]);
      },
    );
  }

  // ─── SMALL HELPERS ────────────────────────────────────────────────────────
  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(20),
    margin: const EdgeInsets.only(bottom: 0),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20), color: _cardColor,
      border: Border.all(color: _borderColor),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(_isDarkMode ? 0.2 : 0.05), blurRadius: 15, offset: const Offset(0, 5))],
    ),
    child: child,
  );

  Widget _innerBox(Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: _isDarkMode ? const Color(0xFF2D3748) : Colors.grey[50],
      border: Border.all(color: _borderColor),
    ),
    child: child,
  );

  Widget _badge({required Widget child, required Color color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.4)),
    ),
    child: child,
  );

  Widget _mediaBtn({required IconData icon, required String label, required VoidCallback onTap, required Color color}) {
    return Expanded(child: Opacity(
      opacity: _isPickingMedia ? 0.4 : 1.0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16),
            color: color.withOpacity(0.1), border: Border.all(color: color.withOpacity(0.3))),
        child: Material(color: Colors.transparent, child: InkWell(
          onTap: _isPickingMedia ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(children: [
              Icon(icon, size: 28, color: color), const SizedBox(height: 8),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11), textAlign: TextAlign.center),
            ]),
          ),
        )),
      ),
    ));
  }

  List<Widget> _buildReportFields() {
    switch (_selectedReportType) {
      case "Incident Report":           return _incidentFields();
      case "Daily Activity Report":     return _dailyFields();
      case "Maintenance Report":        return _maintenanceFields();
      case "Parking Violation Report":  return _parkingFields();
      default: return [];
    }
  }

  IconData _getReportTypeIcon() {
    switch (_selectedReportType) {
      case "Incident Report":           return Icons.warning_amber_rounded;
      case "Daily Activity Report":     return Icons.calendar_today;
      case "Maintenance Report":        return Icons.build;
      case "Parking Violation Report":  return Icons.local_parking;
      default: return Icons.description;
    }
  }

  Map<String, dynamic>? get _selectedSite =>
      _sites.firstWhere((s) => s['id'] == _selectedSiteId, orElse: () => {});

  Widget _siteDropdown() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<Map<String, dynamic>>(
      value: _selectedSiteId == null ? null : _selectedSite,
      decoration: _modernInput("Select Site"),
      items: _sites.map((s) => DropdownMenuItem<Map<String, dynamic>>(value: s,
          child: Text(s['name']))).toList(),
      onChanged: _hasActiveAssignment ? (v) => setState(() => _selectedSiteId = v?['id']) : null,
      disabledHint: const Text("No active shift", style: TextStyle(color: Colors.redAccent)),
    ),
  );

  List<Widget> _incidentFields() => [
    _rowTwo(_incidentInternalIdController, "Internal Display ID", _incidentDateTimeController, "Date & Time"),
    _single(_incidentTypeController, "Incident Type (or 'Other')"),
    _rowTwo(_victimNameController, "Victim Name(s)", _victimContactController, "Victim Contact Info"),
    _rowTwo(_suspectNameController, "Suspect Name(s)", _suspectContactController, "Suspect Contact Info"),
    _single(_witnessNamesController, "Witness Name(s) & Contact"),
    _single(_incidentLocationController, "Incident Location"),
    _multi(_incidentSummaryController, "Incident Summary"),
    const SizedBox(height: 16),
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
          color: _isDarkMode ? const Color(0xFF374151) : Colors.grey[100]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.local_police, color: Colors.blueAccent, size: 20),
          const SizedBox(width: 8),
          Text("Emergency Services", style: TextStyle(color: _textColor, fontSize: 14, fontWeight: FontWeight.w600))]),
        const SizedBox(height: 12),
        Row(children: [
          Text("Police Called:", style: TextStyle(color: _textColor, fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          Switch(value: _policeCalled, onChanged: (v) => setState(() => _policeCalled = v), activeColor: Colors.blueAccent),
          Expanded(child: TextFormField(controller: _responderPoliceNamesController,
              decoration: _modernInput("Police Name(s) & Badge(s)"), style: TextStyle(color: _textColor))),
        ]),
        const SizedBox(height: 12),
        _rowTwo(_responderFireTruckController, "Fire Truck #", _responderAmbulanceController, "Ambulance #"),
      ]),
    ),
    _multi(_incidentDetailsController, "Details (Who, What, When, etc.)"),
    _multi(_incidentActionsController, "Officer Actions"),
  ];

  List<Widget> _dailyFields() => [
    _single(_dailyShiftStartNotesController, "Shift Start Notes / Post"),
    _single(_dailyPostShiftController, "Post/Shift (e.g. Swingshift)"),
    _single(_dailySpecialInstructionsController, "Special Instructions"),
    _single(_dailyPostItemsReceivedController, "Post Items Received (phone, keys)"),
    _multi(_dailyObservationsController, "Observations (time / comment list)"),
    _rowTwo(_dailyRelievingFirstController, "Relieving Officer - First Name", _dailyRelievingLastController, "Relieving Officer - Last Name"),
    _multi(_dailyAdditionalNotesController, "Additional Notes"),
  ];

  List<Widget> _maintenanceFields() => [
    _single(_maintenanceTypeController, "Maintenance Type (e.g. Lights Out)"),
    _multi(_maintenanceDetailsController, "Problem Details"),
    _single(_maintenanceWhoNotifiedController, "Who has been notified"),
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
          color: _isDarkMode ? const Color(0xFF374151) : Colors.grey[100]),
      child: Row(children: [
        const Icon(Icons.email, color: Colors.amber, size: 20), const SizedBox(width: 12),
        Text("Email Client:", style: TextStyle(color: _textColor, fontWeight: FontWeight.w500)),
        const SizedBox(width: 12),
        Switch(value: _maintenanceEmailClient, onChanged: (v) => setState(() => _maintenanceEmailClient = v), activeColor: Colors.amber),
      ]),
    ),
  ];

  List<Widget> _parkingFields() => [
    _rowTwo(_violatorFirstController, "Violator First Name", _violatorLastController, "Violator Last Name"),
    _rowTwo(_vehicleMakeController, "Vehicle Make", _vehicleModelController, "Vehicle Model"),
    _rowTwo(_vehicleLPController, "LP # (Plate)", _vehicleVINController, "VIN"),
    _single(_vehicleColorController, "Vehicle Color"),
    _single(_violationTypeController, "Violation Type"),
    _rowTwo(_violationNumberController, "Violation #", _parkingLocationController, "Location"),
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
          color: _isDarkMode ? const Color(0xFF374151) : Colors.grey[100]),
      child: Row(children: [
        Expanded(child: TextFormField(controller: _parkingFineController,
            decoration: _modernInput("Fine"), style: TextStyle(color: _textColor))),
        const SizedBox(width: 20),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Vehicle Towed?", style: TextStyle(color: _textColor, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Switch(value: _vehicleTowed, onChanged: (v) => setState(() => _vehicleTowed = v), activeColor: Colors.redAccent),
        ]),
      ]),
    ),
    _multi(_parkingDetailsController, "Detail Description"),
  ];

  Widget _single(TextEditingController c, String l) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(controller: c, decoration: _modernInput(l), style: TextStyle(color: _textColor)),
  );
  Widget _multi(TextEditingController c, String l) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(controller: c, maxLines: 4, decoration: _modernInput(l), style: TextStyle(color: _textColor)),
  );
  Widget _rowTwo(TextEditingController c1, String l1, TextEditingController c2, String l2) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(children: [
      Expanded(child: TextFormField(controller: c1, decoration: _modernInput(l1), style: TextStyle(color: _textColor))),
      const SizedBox(width: 12),
      Expanded(child: TextFormField(controller: c2, decoration: _modernInput(l2), style: TextStyle(color: _textColor))),
    ]),
  );
}