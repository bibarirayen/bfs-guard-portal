// file: lib/pages/report_page.dart
import 'dart:convert';
import 'dart:io';
import 'package:crossplatformblackfabric/config/ApiService.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  bool _isDarkMode = true;

  // ─────────────────────────────────────────────────────────────────────────
  // PERMISSION HANDLERS
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> _requestPermissions(ImageSource source, {bool forVideo = false}) async {
    if (Platform.isIOS) {
      return await _requestPermissionsIOS(source, forVideo: forVideo);
    } else {
      return await _requestPermissionsAndroid(source, forVideo: forVideo);
    }
  }

  Future<bool> _requestPermissionsIOS(ImageSource source, {bool forVideo = false}) async {
    if (source == ImageSource.camera) {
      final camStatus = await Permission.camera.request();
      if (!camStatus.isGranted) {
        _showPermissionDeniedDialog(
          'Camera Permission Required',
          'Camera access is needed to take photos/videos for reports.',
          showSettings: true,
        );
        return false;
      }
      if (forVideo) {
        final micStatus = await Permission.microphone.request();
        if (!micStatus.isGranted) {
          _showPermissionDeniedDialog(
            'Microphone Permission Required',
            'Microphone access is required to record video with audio.\n\nGo to Settings → BFS Guard Portal → Microphone and enable it.',
            showSettings: true,
          );
          return false;
        }
      }
      return true;
    }

    final photoStatus = await Permission.photos.request();
    if (photoStatus.isDenied || photoStatus.isPermanentlyDenied) {
      _showPermissionDeniedDialog(
        'Photo Library Permission Required',
        'Photo library access is needed to select ${forVideo ? 'videos' : 'photos'} for reports.\n\nGo to Settings → BFS Guard Portal → Photos and set to "All Photos".',
        showSettings: true,
      );
      return false;
    }
    return true;
  }

  Future<bool> _requestPermissionsAndroid(ImageSource source, {bool forVideo = false}) async {
    if (source == ImageSource.camera) {
      final camStatus = await Permission.camera.request();
      if (!camStatus.isGranted) {
        if (camStatus.isPermanentlyDenied) {
          _showPermissionDeniedDialog('Camera Permission Blocked',
              'Camera permission is permanently blocked.\n\nOpen App Settings to enable it.',
              showSettings: true);
        } else {
          _snackError('Camera permission is required to take photos/videos.');
        }
        return false;
      }
      if (forVideo) {
        final micStatus = await Permission.microphone.request();
        if (!micStatus.isGranted) {
          if (micStatus.isPermanentlyDenied) {
            _showPermissionDeniedDialog('Microphone Permission Blocked',
                'Microphone permission is permanently blocked.\n\nOpen App Settings to enable it.',
                showSettings: true);
          } else {
            _snackError('Microphone permission is required to record videos.');
          }
          return false;
        }
      }
      return true;
    }

    final sdkVersion = await _getAndroidSdkVersion();
    if (sdkVersion >= 33) {
      final Permission perm = forVideo ? Permission.videos : Permission.photos;
      final status = await perm.request();
      if (!status.isGranted) {
        if (status.isPermanentlyDenied) {
          _showPermissionDeniedDialog(
              forVideo ? 'Video Permission Blocked' : 'Photo Permission Blocked',
              '${forVideo ? 'Video' : 'Photo'} permission is permanently blocked.\n\nOpen App Settings to enable it.',
              showSettings: true);
        } else {
          _snackError('${forVideo ? 'Video' : 'Photo'} library permission is required.');
        }
        return false;
      }
    } else {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        if (status.isPermanentlyDenied) {
          _showPermissionDeniedDialog('Storage Permission Blocked',
              'Storage permission is permanently blocked.\n\nOpen App Settings to enable it.',
              showSettings: true);
        } else {
          _snackError('Storage permission is required to access the gallery.');
        }
        return false;
      }
    }
    return true;
  }

  int? _cachedSdkVersion;
  Future<int> _getAndroidSdkVersion() async {
    if (_cachedSdkVersion != null) return _cachedSdkVersion!;
    try {
      final version = Platform.operatingSystemVersion;
      final match = RegExp(r'Android (\d+)').firstMatch(version);
      if (match != null) {
        final androidVer = int.tryParse(match.group(1) ?? '');
        if (androidVer != null) {
          final apiMap = {14: 34, 13: 33, 12: 32, 11: 30, 10: 29, 9: 28};
          _cachedSdkVersion = apiMap[androidVer] ?? (androidVer >= 13 ? 33 : 28);
          return _cachedSdkVersion!;
        }
      }
      _cachedSdkVersion = 30;
      return _cachedSdkVersion!;
    } catch (_) {
      _cachedSdkVersion = 30;
      return _cachedSdkVersion!;
    }
  }

  void _snackError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showPermissionDeniedDialog(String title, String message, {bool showSettings = false}) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.lock, color: Colors.redAccent, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w700))),
        ]),
        content: Text(message, style: TextStyle(color: _secondaryTextColor, fontSize: 14, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: _secondaryTextColor)),
          ),
          if (showSettings)
            ElevatedButton(
              onPressed: () { Navigator.pop(context); openAppSettings(); },
              style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Open Settings', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // THEME
  // ─────────────────────────────────────────────────────────────────────────
  Color get _backgroundColor => _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _textColor => _isDarkMode ? Colors.white : const Color(0xFF1E293B);
  Color get _cardColor => _isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  Color get _borderColor => _isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get _secondaryTextColor => _isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
  Color get _primaryColor => const Color(0xFF4F46E5);
  Color get _accentColor => _isDarkMode ? const Color(0xFF7C73FF) : const Color(0xFF6366F1);

  // ─────────────────────────────────────────────────────────────────────────
  // CONTROLLERS
  // ─────────────────────────────────────────────────────────────────────────
  final TextEditingController _clientController = TextEditingController();
  final TextEditingController _siteController = TextEditingController();
  final TextEditingController _officerController = TextEditingController();
  final TextEditingController _dateEnteredController = TextEditingController();

  final TextEditingController _incidentInternalIdController = TextEditingController();
  final TextEditingController _incidentDateTimeController = TextEditingController();
  final TextEditingController _incidentTypeController = TextEditingController();
  final TextEditingController _victimNameController = TextEditingController();
  final TextEditingController _victimContactController = TextEditingController();
  final TextEditingController _suspectNameController = TextEditingController();
  final TextEditingController _suspectContactController = TextEditingController();
  final TextEditingController _witnessNamesController = TextEditingController();
  final TextEditingController _incidentLocationController = TextEditingController();
  final TextEditingController _incidentSummaryController = TextEditingController();
  final TextEditingController _responderPoliceNamesController = TextEditingController();
  final TextEditingController _responderFireTruckController = TextEditingController();
  final TextEditingController _responderAmbulanceController = TextEditingController();
  final TextEditingController _incidentDetailsController = TextEditingController();
  final TextEditingController _incidentActionsController = TextEditingController();
  bool _policeCalled = false;

  final TextEditingController _dailyShiftStartNotesController = TextEditingController();
  final TextEditingController _dailyPostShiftController = TextEditingController();
  final TextEditingController _dailySpecialInstructionsController = TextEditingController();
  final TextEditingController _dailyPostItemsReceivedController = TextEditingController();
  final TextEditingController _dailyObservationsController = TextEditingController();
  final TextEditingController _dailyRelievingFirstController = TextEditingController();
  final TextEditingController _dailyRelievingLastController = TextEditingController();
  final TextEditingController _dailyAdditionalNotesController = TextEditingController();

  final TextEditingController _maintenanceTypeController = TextEditingController();
  final TextEditingController _maintenanceDetailsController = TextEditingController();
  final TextEditingController _maintenanceWhoNotifiedController = TextEditingController();
  bool _maintenanceEmailClient = false;

  final TextEditingController _violatorFirstController = TextEditingController();
  final TextEditingController _violatorLastController = TextEditingController();
  final TextEditingController _vehicleMakeController = TextEditingController();
  final TextEditingController _vehicleModelController = TextEditingController();
  final TextEditingController _vehicleLPController = TextEditingController();
  final TextEditingController _vehicleVINController = TextEditingController();
  final TextEditingController _vehicleColorController = TextEditingController();
  final TextEditingController _violationTypeController = TextEditingController();
  final TextEditingController _violationNumberController = TextEditingController();
  final TextEditingController _parkingLocationController = TextEditingController();
  final TextEditingController _parkingFineController = TextEditingController();
  final TextEditingController _parkingDetailsController = TextEditingController();
  bool _vehicleTowed = false;

  // ─────────────────────────────────────────────────────────────────────────
  // STATE
  // ─────────────────────────────────────────────────────────────────────────
  final List<File> _mediaFiles = [];
  String _selectedReportType = "Incident Report";
  final List<String> _reportTypes = [
    "Incident Report",
    "Daily Activity Report",
    "Maintenance Report",
    "Parking Violation Report",
  ];
  final api = ApiService();
  List<Map<String, dynamic>> _sites = [];
  bool _hasActiveAssignment = false;
  bool _isSubmitting = false;
  double _uploadProgress = 0.0;
  int? _selectedSiteId;
  final ImagePicker _picker = ImagePicker();

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────────────────────
  // RESET PAGE (called after successful submission)
  // ─────────────────────────────────────────────────────────────────────────
  void _resetPage() {
    setState(() {
      _mediaFiles.clear();
      _selectedReportType = "Incident Report";
      _policeCalled = false;
      _maintenanceEmailClient = false;
      _vehicleTowed = false;
      _uploadProgress = 0.0;
      _isSubmitting = false;
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

  // ─────────────────────────────────────────────────────────────────────────
  // IMAGE / VIDEO PICKING
  // ─────────────────────────────────────────────────────────────────────────
  Future<File> _compressImage(File file) async {
    final dir = await getTemporaryDirectory();
    final targetPath = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
    final XFile? compressedXFile = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path, targetPath, quality: 80, minWidth: 1280, minHeight: 1280,
      format: CompressFormat.jpeg,
    );
    if (compressedXFile == null) return file;
    return File(compressedXFile.path);
  }

  Future<void> _pickVideo(ImageSource source) async {
    final granted = await _requestPermissions(source, forVideo: true);
    if (!granted) return;
    try {
      final XFile? pickedFile = await _picker.pickVideo(
        source: source, maxDuration: const Duration(minutes: 60),
      );
      if (pickedFile == null) return;

      try {
        final fileSize = await pickedFile.length();
        final fileSizeMB = fileSize / (1024 * 1024);
        if (fileSizeMB > 1000) { _snackError('Video exceeds 1GB limit.'); return; }
      } catch (_) { /* Can't read size on large files on iOS — just proceed */ }

      final File videoFile = File(pickedFile.path);
      if (!await videoFile.exists()) { _snackError('Could not access the selected video.'); return; }
      setState(() => _mediaFiles.add(videoFile));
    } catch (e) {
      debugPrint('Video pick error: $e');
      final s = e.toString().toLowerCase();
      if (s.contains('permission') || s.contains('denied')) {
        _showPermissionDeniedDialog('Permission Required',
            'Please grant the required permission.', showSettings: true);
      } else if (!s.contains('cancel')) {
        _snackError('Could not load video. Please try again.');
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final granted = await _requestPermissions(source, forVideo: false);
    if (!granted) return;
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source, imageQuality: 85, maxWidth: 1920, maxHeight: 1920,
      );
      if (pickedFile == null) return;
      final File tempFile = File(pickedFile.path);
      if (!await tempFile.exists()) { _snackError('Could not access the selected image.'); return; }
      final File compressedFile = await _compressImage(tempFile);
      setState(() => _mediaFiles.add(compressedFile));
    } catch (e) {
      debugPrint('Image pick error: $e');
      final s = e.toString().toLowerCase();
      if (s.contains('permission') || s.contains('denied')) {
        _showPermissionDeniedDialog('Permission Required',
            'Please grant the required permission.', showSettings: true);
      } else if (!s.contains('cancel')) {
        _snackError('Error picking image. Please try again.');
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FETCH SITES
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _fetchSites() async {
    final prefs = await SharedPreferences.getInstance();
    int? guardId = prefs.getInt('userId');
    int? assignmentId = prefs.getInt('assignmentId');
    if (guardId == null) return;
    if (assignmentId == null) {
      setState(() { _hasActiveAssignment = false; _sites = []; });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.redAccent, content: Text("No assignment found!")));
      return;
    }
    try {
      final response = await api.get('assignments/shift/active-shift-sites/$guardId/$assignmentId');
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final site = decoded['site'];
        if (site != null) {
          setState(() { _sites = [site]; _hasActiveAssignment = true; _selectedSiteId = site['id']; });
        } else {
          setState(() { _sites = []; _hasActiveAssignment = false; });
        }
      } else if (response.statusCode == 404) {
        setState(() { _sites = []; _hasActiveAssignment = false; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text("No active Assignment found!", style: TextStyle(color: Colors.white))));
      } else {
        throw Exception("Failed to fetch sites");
      }
    } catch (e) {
      print("Error fetching sites: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text("Error fetching site: $e", style: const TextStyle(color: Colors.white))));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SUBMIT REPORT
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _submitReport() async {
    if (!_hasActiveAssignment) { _snackError("Cannot submit report: no active assignment"); return; }
    if (_selectedSiteId == null) { _snackError("Please select a site before submitting"); return; }

    final prefs = await SharedPreferences.getInstance();
    final int? officerId = prefs.getInt('userId');

    final payload = {
      "type": _selectedReportType,
      "data": {
        ..._buildReportData(),
        "officerId": officerId,
        "siteId": _selectedSiteId,
      },
    };

    setState(() { _isSubmitting = true; _uploadProgress = 0.0; });

    try {
      if (_mediaFiles.isNotEmpty) {
        // ✅ Dio streaming upload — streams from disk, no RAM overload
        await api.uploadReportDio(
          payload,
          _mediaFiles,
              (sent, total) {
            if (total > 0 && mounted) {
              setState(() => _uploadProgress = sent / total);
            }
          },
        );
      } else {
        // ✅ Normal JSON post when no files
        final response = await api.post('reports', payload);
        if (response.statusCode != 200 && response.statusCode != 201) {
          throw Exception("Failed: ${response.statusCode}");
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.greenAccent,
          content: Text("Report submitted successfully!", style: TextStyle(color: Colors.black)),
        ));
        // ✅ RESET PAGE after success
        _resetPage();
      }
    } on DioException catch (e) {
      final msg = e.response?.data?.toString() ?? e.message ?? 'Upload failed';
      _snackError("Upload failed: $msg");
    } catch (e) {
      _snackError("Error submitting report: $e");
    } finally {
      if (mounted) setState(() { _isSubmitting = false; _uploadProgress = 0.0; });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD REPORT DATA
  // ─────────────────────────────────────────────────────────────────────────
  Map<String, dynamic> _buildReportData() {
    switch (_selectedReportType) {
      case "Incident Report":
        return {
          "incidentInternalId": _incidentInternalIdController.text,
          "incidentDateTime": _incidentDateTimeController.text,
          "incidentType": _incidentTypeController.text,
          "victimName": _victimNameController.text,
          "victimContact": _victimContactController.text,
          "suspectName": _suspectNameController.text,
          "suspectContact": _suspectContactController.text,
          "witnessNames": _witnessNamesController.text,
          "incidentLocation": _incidentLocationController.text,
          "incidentSummary": _incidentSummaryController.text,
          "responderPoliceNames": _responderPoliceNamesController.text,
          "responderFireTruck": _responderFireTruckController.text,
          "responderAmbulance": _responderAmbulanceController.text,
          "incidentDetails": _incidentDetailsController.text,
          "incidentActions": _incidentActionsController.text,
          "policeCalled": _policeCalled,
        };
      case "Daily Activity Report":
        return {
          "dailyShiftStartNotes": _dailyShiftStartNotesController.text,
          "dailyPostShift": _dailyPostShiftController.text,
          "dailySpecialInstructions": _dailySpecialInstructionsController.text,
          "dailyPostItemsReceived": _dailyPostItemsReceivedController.text,
          "dailyObservations": _dailyObservationsController.text,
          "dailyRelievingFirst": _dailyRelievingFirstController.text,
          "dailyRelievingLast": _dailyRelievingLastController.text,
          "dailyAdditionalNotes": _dailyAdditionalNotesController.text,
        };
      case "Maintenance Report":
        return {
          "maintenanceType": _maintenanceTypeController.text,
          "maintenanceDetails": _maintenanceDetailsController.text,
          "maintenanceWhoNotified": _maintenanceWhoNotifiedController.text,
          "maintenanceEmailClient": _maintenanceEmailClient,
        };
      case "Parking Violation Report":
        return {
          "violatorFirst": _violatorFirstController.text,
          "violatorLast": _violatorLastController.text,
          "vehicleMake": _vehicleMakeController.text,
          "vehicleModel": _vehicleModelController.text,
          "vehicleLP": _vehicleLPController.text,
          "vehicleVIN": _vehicleVINController.text,
          "vehicleColor": _vehicleColorController.text,
          "violationType": _violationTypeController.text,
          "violationNumber": _violationNumberController.text,
          "parkingLocation": _parkingLocationController.text,
          "parkingFine": _parkingFineController.text,
          "parkingDetails": _parkingDetailsController.text,
          "vehicleTowed": _vehicleTowed,
        };
      default:
        return {};
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INPUT DECORATION
  // ─────────────────────────────────────────────────────────────────────────
  InputDecoration _modernInput(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: _secondaryTextColor, fontWeight: FontWeight.w500, fontSize: 14),
      filled: true,
      fillColor: _isDarkMode ? const Color(0xFF2D3748) : Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _borderColor, width: 1)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _borderColor, width: 1)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _primaryColor, width: 2)),
      hintStyle: TextStyle(color: _secondaryTextColor),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Report Type Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: _cardColor,
                        border: Border.all(color: _borderColor, width: 1),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(_isDarkMode ? 0.2 : 0.05), blurRadius: 15, offset: const Offset(0, 5))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.description, color: _primaryColor, size: 20),
                            const SizedBox(width: 8),
                            Text("Report Type", style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                          ]),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _selectedReportType,
                            decoration: _modernInput("Select Report Type"),
                            borderRadius: BorderRadius.circular(14),
                            dropdownColor: _cardColor,
                            icon: Icon(Icons.arrow_drop_down, color: _primaryColor),
                            items: _reportTypes.map((type) => DropdownMenuItem(value: type, child: Text(type, style: TextStyle(color: _textColor)))).toList(),
                            onChanged: (value) => setState(() => _selectedReportType = value!),
                            style: TextStyle(color: _textColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Form + Attachments
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: _cardColor,
                          border: Border.all(color: _borderColor, width: 1),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(_isDarkMode ? 0.2 : 0.05), blurRadius: 15, offset: const Offset(0, 5))],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              // Report fields
                              Container(
                                margin: const EdgeInsets.only(bottom: 20),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: _isDarkMode ? const Color(0xFF2D3748) : Colors.grey[50],
                                  border: Border.all(color: _borderColor, width: 1),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _siteDropdown(),
                                    Row(children: [
                                      Icon(_getReportTypeIcon(), color: _primaryColor, size: 20),
                                      const SizedBox(width: 8),
                                      Text(_selectedReportType, style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                                    ]),
                                    const SizedBox(height: 16),
                                    ..._buildReportFields(),
                                  ],
                                ),
                              ),

                              // Attachments
                              Container(
                                margin: const EdgeInsets.only(bottom: 20),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: _isDarkMode ? const Color(0xFF2D3748) : Colors.grey[50],
                                  border: Border.all(color: _borderColor, width: 1),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Icon(Icons.photo_library, color: _primaryColor, size: 20),
                                      const SizedBox(width: 8),
                                      Text("Attachments", style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                                    ]),
                                    const SizedBox(height: 16),
                                    Text("Upload images or videos related to the report", style: TextStyle(color: _secondaryTextColor, fontSize: 14)),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        _buildImageButton(icon: Icons.videocam, label: "Video", onTap: () => _pickVideo(ImageSource.camera), color: Colors.redAccent),
                                        _buildImageButton(icon: Icons.video_library, label: "Gallery Video", onTap: () => _pickVideo(ImageSource.gallery), color: Colors.orange),
                                        _buildImageButton(icon: Icons.camera_alt_rounded, label: "Camera", onTap: () => _pickImage(ImageSource.camera), color: const Color(0xFF3B82F6)),
                                        _buildImageButton(icon: Icons.photo_library_rounded, label: "Gallery", onTap: () => _pickImage(ImageSource.gallery), color: const Color(0xFF8B5CF6)),
                                      ],
                                    ),
                                    if (_mediaFiles.isNotEmpty) ...[
                                      const SizedBox(height: 20),
                                      _buildImageGrid(),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ✅ SUBMIT BUTTON WITH PROGRESS BAR
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          colors: [_primaryColor, _accentColor],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
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
                                ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _uploadProgress > 0
                                      ? 'Uploading... ${(_uploadProgress * 100).toStringAsFixed(0)}%'
                                      : 'Preparing...',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                                ),
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    // ✅ null = indeterminate spinner, value = real % progress
                                    value: _uploadProgress > 0 ? _uploadProgress : null,
                                    backgroundColor: Colors.white30,
                                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                    minHeight: 6,
                                  ),
                                ),
                              ],
                            )
                                : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.send_rounded, color: Colors.white, size: 22),
                                SizedBox(width: 12),
                                Text("Submit Report", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WIDGETS
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildImageButton({required IconData icon, required String label, required VoidCallback onTap, required Color color}) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: color.withOpacity(0.1),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(children: [
                Icon(icon, size: 28, color: color),
                const SizedBox(height: 8),
                Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12), textAlign: TextAlign.center),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: _mediaFiles.length,
      itemBuilder: (context, index) {
        File file = _mediaFiles[index];
        String ext = file.path.split('.').last.toLowerCase();
        Widget mediaWidget = ['mp4', 'mov', 'avi'].contains(ext)
            ? Container(color: Colors.black, child: const Center(child: Icon(Icons.play_circle_fill, size: 40, color: Colors.white)))
            : Image.file(file, fit: BoxFit.cover);
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(12), child: mediaWidget),
            Positioned(
              top: 6, right: 6,
              child: GestureDetector(
                onTap: () => setState(() => _mediaFiles.removeAt(index)),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))]),
                  child: const Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildReportFields() {
    switch (_selectedReportType) {
      case "Incident Report": return _incidentFields();
      case "Daily Activity Report": return _dailyFields();
      case "Maintenance Report": return _maintenanceFields();
      case "Parking Violation Report": return _parkingFields();
      default: return [];
    }
  }

  IconData _getReportTypeIcon() {
    switch (_selectedReportType) {
      case "Incident Report": return Icons.warning_amber_rounded;
      case "Daily Activity Report": return Icons.calendar_today;
      case "Maintenance Report": return Icons.build;
      case "Parking Violation Report": return Icons.local_parking;
      default: return Icons.description;
    }
  }

  Map<String, dynamic>? get _selectedSite {
    return _sites.firstWhere((s) => s['id'] == _selectedSiteId, orElse: () => {});
  }

  Widget _siteDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<Map<String, dynamic>>(
        value: _selectedSiteId == null ? null : _selectedSite,
        decoration: _modernInput("Select Site"),
        items: _sites.map((site) => DropdownMenuItem<Map<String, dynamic>>(value: site, child: Text(site['name']))).toList(),
        onChanged: _hasActiveAssignment ? (value) => setState(() => _selectedSiteId = value?['id']) : null,
        disabledHint: const Text("No active shift", style: TextStyle(color: Colors.redAccent)),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FIELD BUILDERS
  // ─────────────────────────────────────────────────────────────────────────
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
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: _isDarkMode ? const Color(0xFF374151) : Colors.grey[100]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.local_police, color: Colors.blueAccent, size: 20), const SizedBox(width: 8), Text("Emergency Services", style: TextStyle(color: _textColor, fontSize: 14, fontWeight: FontWeight.w600))]),
        const SizedBox(height: 12),
        Row(children: [
          Text("Police Called:", style: TextStyle(color: _textColor, fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          Switch(value: _policeCalled, onChanged: (v) => setState(() => _policeCalled = v), activeColor: Colors.blueAccent),
          Expanded(child: TextFormField(controller: _responderPoliceNamesController, decoration: _modernInput("Police Name(s) & Badge(s)"), style: TextStyle(color: _textColor))),
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
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: _isDarkMode ? const Color(0xFF374151) : Colors.grey[100]),
      child: Row(children: [
        const Icon(Icons.email, color: Colors.amber, size: 20),
        const SizedBox(width: 12),
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
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: _isDarkMode ? const Color(0xFF374151) : Colors.grey[100]),
      child: Row(children: [
        Expanded(child: TextFormField(controller: _parkingFineController, decoration: _modernInput("Fine"), style: TextStyle(color: _textColor))),
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

  Widget _single(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(controller: c, decoration: _modernInput(label), style: TextStyle(color: _textColor)),
  );

  Widget _multi(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(controller: c, maxLines: 4, decoration: _modernInput(label), style: TextStyle(color: _textColor)),
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