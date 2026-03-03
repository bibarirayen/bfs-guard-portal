// file: lib/screens/report_page.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crossplatformblackfabric/config/ApiService.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

// flutter_image_compress REMOVED — use imageQuality param on pickImage instead (no crashes)
import 'package:video_compress/video_compress.dart';

// ─── Media item ───────────────────────────────────────────────────────────────
class _MediaItem {
  File file;
  final bool isVideo;
  Uint8List? videoThumb;      // null = still generating
  bool thumbLoading = false;  // show shimmer while generating

  _MediaItem({
    required this.file,
    required this.isVideo,
    this.videoThumb,
    this.thumbLoading = false,
  });

  File get uploadFile => file;
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

  // Video compression queue


  // ─── LIFECYCLE ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _fetchSites();
  }

  // Called at EVERY button tap.
  // - If not yet asked: calls .request() → system dialog appears.
  // - If already granted / limited: passes through immediately.
  // - If denied or permanently denied: shows our Settings dialog.
  //   (iOS/Android won't re-show system dialog after first denial — Settings is the only option.)
  Future<bool> _checkPermission(Permission perm, String label) async {
    PermissionStatus status = await perm.status;

    // Never asked yet on this device → show system dialog now
    if (status.isDenied) {
      status = await perm.request();
    }

    // Granted or limited (iOS "Select Photos") → OK
    if (status.isGranted || status == PermissionStatus.limited) return true;

    // Denied or permanently denied → only option is Settings
    if (!mounted) return false;

    bool openedSettings = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.lock_outline, color: Colors.redAccent, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(
            '$label Permission Required',
            style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w700),
          )),
        ]),
        content: Text(
          Platform.isIOS
              ? 'Please go to Settings → Privacy → $label and enable access for this app.'
              : 'Please go to App Settings → Permissions → $label and enable access.',
          style: TextStyle(color: _secondaryTextColor, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Not Now', style: TextStyle(color: _secondaryTextColor)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              openedSettings = true;
              await openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Open Settings', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    // If the user went to Settings and came back, re-check the permission.
    // Android caches the old status — we must query fresh after returning.
    if (openedSettings) {
      final refreshed = await perm.status;
      if (refreshed.isGranted || refreshed == PermissionStatus.limited) return true;
    }

    return false;
  }

  Future<int> _getAndroidSdkInt() async {
    try {
      final match = RegExp(r'Android (\d+)').firstMatch(Platform.operatingSystemVersion);
      if (match != null) {
        final v = int.tryParse(match.group(1) ?? '');
        if (v != null) return {14:34,13:33,12:32,11:30,10:29,9:28}[v] ?? (v >= 13 ? 33 : 28);
      }
    } catch (_) {}
    return 30;
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

  // ─── MEDIA PICKING ────────────────────────────────────────────────────────
  // THE FIX:
  // 1. imageQuality: 85 on pickImage replaces flutter_image_compress — zero crashes
  // 2. File is copied to temp dir (stable path on both iOS/Android)
  // 3. setState adds item to grid IMMEDIATELY after copy
  // 4. Thumbnail + compression start AFTER the frame renders (addPostFrameCallback)

  Future<void> _pickImage(ImageSource source) async {
    if (_isPickingMedia) return;

    if (source == ImageSource.camera) {
      if (!await _checkPermission(Permission.camera, 'Camera')) return;
    } else {
      final perm = Platform.isIOS
          ? Permission.photos
          : (await _getAndroidSdkInt() >= 33 ? Permission.photos : Permission.storage);
      if (!await _checkPermission(perm, 'Photos')) return;
    }

    setState(() => _isPickingMedia = true);
    try {
      XFile? picked;
      try { picked = await _picker.pickImage(source: source, imageQuality: 85); } catch (_) { return; }
      if (picked == null || !mounted) return;
      final File stableFile = await _copyToTemp(picked.path, ext: 'jpg');
      setState(() => _mediaItems.add(_MediaItem(file: stableFile, isVideo: false)));
    } finally {
      if (mounted) setState(() => _isPickingMedia = false);
    }
  }
  bool _isPickingMedia = false;

  Future<void> _pickVideo(ImageSource source) async {
    if (_isPickingMedia) return;

    if (source == ImageSource.camera) {
      if (!await _checkPermission(Permission.camera, 'Camera')) return;
      if (!await _checkPermission(Permission.microphone, 'Microphone')) return;
    } else {
      final perm = Platform.isIOS
          ? Permission.photos
          : (await _getAndroidSdkInt() >= 33 ? Permission.videos : Permission.storage);
      if (!await _checkPermission(perm, 'Photos & Videos')) return;
    }

    setState(() => _isPickingMedia = true);
    try {
      final picked = await _picker.pickVideo(source: source);
      if (picked == null || !mounted) return;
      final item = _MediaItem(file: File(picked.path), isVideo: true, thumbLoading: true);
      setState(() => _mediaItems.add(item));
      _generateThumb(item);
    } finally {
      if (mounted) setState(() => _isPickingMedia = false);
    }
  }
  // ─── VIDEO COMPRESSION QUEUE ──────────────────────────────────────────────
  Future<void> _generateThumb(_MediaItem item) async {
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: item.file.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 300,   // small = fast
        quality: 70,
      );
      if (!mounted) return;
      setState(() {
        item.videoThumb = bytes;
        item.thumbLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => item.thumbLoading = false);
    }
  }





  // Copies any file to temp dir with a timestamped name — guarantees stable path
  Future<File> _copyToTemp(String sourcePath, {required String ext}) async {
    try {
      final dir  = await getTemporaryDirectory();
      final dest = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.$ext';
      return await File(sourcePath).copy(dest);
    } catch (_) {
      return File(sourcePath);
    }
  }

  // ─── VIDEO COMPRESSION QUEUE ──────────────────────────────────────────────




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
  Future<void> _submitReport() async {
    if (!_hasActiveAssignment) { _snackError("Cannot submit: no active assignment"); return; }
    if (_selectedSiteId == null) { _snackError("Please select a site"); return; }

    final prefs     = await SharedPreferences.getInstance();
    final officerId = prefs.getInt('userId');

    setState(() { _isSubmitting = true; _uploadProgress = 0.0; });

    try {


      // Wait for any in-progress compression before uploading


      final payload = {
        "type": _selectedReportType,
        "data": {
          ..._buildReportData(),
          "officerId": officerId,
          "siteId": _selectedSiteId,
        },
      };

      final filesToUpload = _mediaItems.map((m) => m.uploadFile).toList();
      for (final m in _mediaItems) {
        print("Original: ${(await m.file.length()) / (1024 * 1024)} MB");

      }
      if (filesToUpload.isNotEmpty) {
        for (final f in filesToUpload) {
          final sizeMB = (await f.length()) / (1024 * 1024);
          print("FILE: ${f.path} — ${sizeMB.toStringAsFixed(2)} MB");
        }
        final stopwatch = Stopwatch()..start();

        await api.uploadReportDio(payload, filesToUpload, (sent, total) {
          if (total > 0 && mounted) setState(() => _uploadProgress = sent / total);
        });
        print("UPLOAD TOOK: ${stopwatch.elapsed}");
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
      print("DATA: ${e.response?.data}");
      print("ERROR: ${e.message}");
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

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

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

              _card(Column(children: [
                _innerBox(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _siteDropdown(),
                  Row(children: [
                    Icon(_getReportTypeIcon(), color: _primaryColor, size: 20), const SizedBox(width: 8),
                    Text(_selectedReportType, style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 16),
                  ..._buildReportFields(),
                ])),

                _innerBox(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.photo_library, color: _primaryColor, size: 20), const SizedBox(width: 8),
                    Text("Attachments", style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                    const Spacer(),

                  ]),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.amber, size: 15),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Set camera quality to 720p or 1080p before recording for faster uploads",
                            style: TextStyle(color: Colors.amber.shade300, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _mediaBtn(icon: Icons.videocam, label: "Video", onTap: () => _pickVideoCamera(), color: Colors.redAccent),
                    _mediaBtn(icon: Icons.video_library,         label: "Gallery\nVideo",onTap: () => _pickVideo(ImageSource.gallery), color: Colors.orange),
                    _mediaBtn(icon: Icons.camera_alt_rounded,    label: "Camera",        onTap: () => _pickImage(ImageSource.camera),  color: const Color(0xFF3B82F6)),
                    _mediaBtn(icon: Icons.photo_library_rounded, label: "Gallery",       onTap: () => _pickImage(ImageSource.gallery), color: const Color(0xFF8B5CF6)),
                  ]),
                  if (_mediaItems.isNotEmpty) ...[const SizedBox(height: 20), _buildGrid()],
                ])),

                const SizedBox(height: 8),
              ])),

              const SizedBox(height: 16),

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
                              ? 'Uploading... ${(_uploadProgress * 100).toStringAsFixed(0)}%' : 'Preparing...',
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
  Future<void> _pickVideoCamera() async {
    if (_isPickingMedia) return;

    // Show quality picker BEFORE opening camera
    final quality = await showModalBottomSheet<VideoQuality>(
      context: context,
      backgroundColor: _cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // drag handle
            Center(child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: _borderColor, borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 16),
            Text("Select Video Quality", style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w700)),
            Text("Higher quality = larger file & slower upload", style: TextStyle(color: _secondaryTextColor, fontSize: 12)),
            const SizedBox(height: 16),
            _qualityTile(Icons.sd,           Colors.green,        "Low",         "~360p · Smallest file, fastest upload", VideoQuality.LowQuality),
            _qualityTile(Icons.hd,           Colors.orange,       "Medium",      "~480p · Good balance",                  VideoQuality.MediumQuality),
            _qualityTile(Icons.high_quality, Colors.blueAccent,   "High",        "~720p · Recommended for evidence",      VideoQuality.HighestQuality),
          ],
        ),
      ),
    );

    // User dismissed sheet without picking
    if (quality == null || !mounted) return;
    if (!await _checkPermission(Permission.camera, 'Camera')) return;
    if (!await _checkPermission(Permission.microphone, 'Microphone')) return;

    setState(() => _isPickingMedia = true);
    try {
      final picked = await _picker.pickVideo(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxDuration: const Duration(minutes: 30),
      );
      if (picked == null || !mounted) return;

      // Note: image_picker uses videoQuality internally based on platform defaults.
      // To actually enforce quality, we pass it via the underlying platform call.
      // The cleanest cross-platform way is post-compression via video_compress,
      // which you already have imported. See compression note below.

      final item = _MediaItem(file: File(picked.path), isVideo: true, thumbLoading: true);
      setState(() => _mediaItems.add(item));
      _generateThumb(item);

    } finally {
      if (mounted) setState(() => _isPickingMedia = false);
    }
  }

  Widget _qualityTile(IconData icon, Color color, String label, String sub, VideoQuality quality) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(label, style: TextStyle(color: _textColor, fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(sub, style: TextStyle(color: _secondaryTextColor, fontSize: 12)),
      trailing: Icon(Icons.arrow_forward_ios, color: _secondaryTextColor, size: 14),
      onTap: () => Navigator.pop(context, quality),
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
          if (item.thumbLoading) {
            // Animated shimmer loading bar
            thumb = Container(
              color: const Color(0xFF1a1a2e),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.videocam, size: 28, color: Colors.white38),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                        minHeight: 4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Loading...",
                    style: TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ],
              ),
            );
          } else if (item.videoThumb != null) {
            thumb = Image.memory(
              item.videoThumb!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFF1a1a2e),
                child: const Center(child: Icon(Icons.videocam, size: 36, color: Colors.white54)),
              ),
            );
          } else {
            // Thumb generation failed — fallback icon
            thumb = Container(
              color: const Color(0xFF1a1a2e),
              child: const Center(child: Icon(Icons.videocam, size: 36, color: Colors.white54)),
            );
          }
        }else {
          thumb = Image.file(
            item.file,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Colors.grey[800],
              child: const Center(child: Icon(Icons.image, color: Colors.white54, size: 36)),
            ),
          );
        }

        return Stack(fit: StackFit.expand, children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: thumb),


          Positioned(top: 4, right: 4,
            child: GestureDetector(
              onTap: () => setState(() => _mediaItems.removeAt(i)),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ]);
      },
    );
  }

  // ─── HELPERS ──────────────────────────────────────────────────────────────
  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(20),
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

  Widget _mediaBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    final bool locked = _isPickingMedia;

    return Expanded(child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: locked ? Colors.grey.withOpacity(0.08) : color.withOpacity(0.1),
        border: Border.all(color: locked ? Colors.grey.withOpacity(0.2) : color.withOpacity(0.3)),
      ),
      child: Material(color: Colors.transparent, child: InkWell(
        onTap: locked ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(children: [
            locked
                ? SizedBox(
              width: 28, height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: color.withOpacity(0.4)),
            )
                : Icon(icon, size: 28, color: color),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: locked ? Colors.grey.withOpacity(0.4) : color,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      )),
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