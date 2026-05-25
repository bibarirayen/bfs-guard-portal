// file: lib/screens/report_page.dart
import 'dart:async';
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
import 'package:device_info_plus/device_info_plus.dart';

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

// ─── DAR Observation entry ───────────────────────────────────────────────────
class _DarObservation {
  String type;
  String description;
  String time; // HST timestamp assigned when observation is created
  _DarObservation({this.type = '', this.description = '', this.time = ''});

  Map<String, dynamic> toJson() => {'type': type, 'description': description, 'time': time};
  factory _DarObservation.fromJson(Map<String, dynamic> j) =>
      _DarObservation(type: j['type'] ?? '', description: j['description'] ?? '', time: j['time'] ?? '');
}

// ─── Temperature entry ───────────────────────────────────────────────────────
class _TempEntry {
  String location; // 'Water Tank' or 'Water Heater'
  String degrees;  // temperature in °F
  String notes;    // optional notes
  String time;     // HST timestamp when added

  _TempEntry({this.location = '', this.degrees = '', this.notes = '', this.time = ''});

  Map<String, dynamic> toJson() =>
      {'location': location, 'degrees': degrees, 'notes': notes, 'time': time};

  factory _TempEntry.fromJson(Map<String, dynamic> j) => _TempEntry(
      location: j['location'] ?? '',
      degrees:  j['degrees']  ?? '',
      notes:    j['notes']    ?? '',
      time:     j['time']     ?? '');
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
  final TextEditingController _dailyRelievingFirstController     = TextEditingController();
  final TextEditingController _dailyRelievingLastController      = TextEditingController();
  final TextEditingController _dailyAdditionalNotesController    = TextEditingController();

  // Structured DAR observations list
  final List<_DarObservation> _darObservations = [];

  // Structured Temperature Report entries
  final List<_TempEntry> _tempEntries = [];

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
  // Per-report-type media buckets. Switching report types swaps which bucket
  // is shown/edited. Submitting a report only clears its own bucket — the
  // other types' attached media stay intact.
  final Map<String, List<_MediaItem>> _mediaByType = {
    "Incident Report": [],
    "Daily Activity Report": [],
    "Maintenance Report": [],
    "Parking Violation Report": [],
    "Temperature Report": [],
  };
  List<_MediaItem> get _mediaItems => _mediaByType[_selectedReportType]!;

  bool _isSubmitting    = false;
  double _uploadProgress = 0.0;
  bool _cancelRequested  = false;
  CancelToken? _cancelToken;
  bool _draftLoading     = false;  // suppresses saves while loading draft
  int? _activeSessionId;
  Timer? _darDraftSyncTimer;
  Timer? _darMediaSyncTimer;
  String _lastDarMediaSignature = '';

  String _selectedReportType = "Incident Report";
  static const String _darReportType = "Daily Activity Report";
  final List<String> _reportTypes = [
    "Incident Report", "Daily Activity Report",
    "Maintenance Report", "Parking Violation Report",
    "Temperature Report",
  ];

  // ─── Per-site draft scoping ───────────────────────────────────────────────────
  // Drafts are persisted under "<base>_s<siteId>" so a guard with multiple
  // sites can keep an in-progress DAR for site A and an Incident for site B
  // simultaneously. Submitting a report only clears its own (siteId, type)
  // bucket. When _selectedSiteId is null (no active site picked yet) the
  // legacy unsuffixed keys are used so existing drafts continue to load.
  String get _siteSuffix => _selectedSiteId == null ? '' : '_s$_selectedSiteId';
  String _k(String base) => '$base$_siteSuffix';
  // True until fetchSites sets the first site — any draft text loaded from
  // legacy unsuffixed keys is then carried over to the per-site bucket.
  bool _pendingLegacyMigration = true;

  // SharedPreferences key for the media list of a given report type.
  // Site-scoped so each (siteId, reportType) pair gets its own media bucket.
  String _mediaPrefsKey(String type) {
    final slug = type.toLowerCase().replaceAll(' ', '_');
    return 'draft_mediaPaths_$slug$_siteSuffix';
  }

  final api = ApiService();
  List<Map<String, dynamic>> _sites = [];
  bool _hasActiveAssignment = false;
  bool _canSubmitWithoutAssignment = false;
  int? _selectedSiteId;
  final ImagePicker _picker = ImagePicker();

  List<_MediaItem> get _darMediaItems => _mediaByType[_darReportType]!;
  bool get _canSyncDarDraft => _activeSessionId != null && _selectedSiteId != null;

  // Video compression queue


  // ─── LIFECYCLE ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _attachDraftListeners();
    _loadDraft();
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
      final info = await DeviceInfoPlugin().androidInfo;
      return info.version.sdkInt;
    } catch (_) {}
    return 30;
  }

  @override
  void dispose() {
    _darDraftSyncTimer?.cancel();
    _darMediaSyncTimer?.cancel();
    _removeDraftListeners();
    for (final c in [
      _clientController, _siteController, _officerController, _dateEnteredController,
      _incidentInternalIdController, _incidentDateTimeController, _incidentTypeController,
      _victimNameController, _victimContactController, _suspectNameController,
      _suspectContactController, _witnessNamesController, _incidentLocationController,
      _incidentSummaryController, _responderPoliceNamesController, _responderFireTruckController,
      _responderAmbulanceController, _incidentDetailsController, _incidentActionsController,
      _dailyShiftStartNotesController, _dailyPostShiftController, _dailySpecialInstructionsController,
      _dailyPostItemsReceivedController, _dailyRelievingFirstController,
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
    final submittedType = _selectedReportType;
    _clearDraft();
    setState(() {
      // Only clear media for the type that was just submitted — other types
      // keep their attached photos/videos.
      _mediaByType[submittedType]?.clear();
      _uploadProgress  = 0.0;
      _isSubmitting    = false;
      _cancelRequested = false;
      // Only reset the type back to Incident if we just submitted an Incident Report,
      // otherwise keep the current type so the other drafts stay selected.
      if (submittedType == _selectedReportType) {
        _selectedReportType = "Incident Report";
      }
    });

    // Only clear controllers for the report type that was submitted
    if (submittedType == 'Incident Report') {
      for (final c in [
        _incidentInternalIdController, _incidentDateTimeController, _incidentTypeController,
        _victimNameController, _victimContactController, _suspectNameController,
        _suspectContactController, _witnessNamesController, _incidentLocationController,
        _incidentSummaryController, _responderPoliceNamesController, _responderFireTruckController,
        _responderAmbulanceController, _incidentDetailsController, _incidentActionsController,
      ]) { c.clear(); }
      setState(() { _policeCalled = false; });
    } else if (submittedType == 'Daily Activity Report') {
      for (final c in [
        _dailyShiftStartNotesController, _dailyPostShiftController,
        _dailySpecialInstructionsController, _dailyPostItemsReceivedController,
        _dailyRelievingFirstController, _dailyRelievingLastController,
        _dailyAdditionalNotesController,
      ]) { c.clear(); }
      setState(() { _darObservations.clear(); });
    } else if (submittedType == 'Maintenance Report') {
      for (final c in [
        _maintenanceTypeController, _maintenanceDetailsController,
        _maintenanceWhoNotifiedController,
      ]) { c.clear(); }
      setState(() { _maintenanceEmailClient = false; });
    } else if (submittedType == 'Parking Violation Report') {
      for (final c in [
        _violatorFirstController, _violatorLastController, _vehicleMakeController,
        _vehicleModelController, _vehicleLPController, _vehicleVINController,
        _vehicleColorController, _violationTypeController, _violationNumberController,
        _parkingLocationController, _parkingFineController, _parkingDetailsController,
      ]) { c.clear(); }
      setState(() { _vehicleTowed = false; });
    } else if (submittedType == 'Temperature Report') {
      setState(() { _tempEntries.clear(); });
    }
  }

  // ─── DRAFT SAVE / LOAD ────────────────────────────────────────────────────
  // The draft is saved to SharedPreferences on every keystroke and every toggle.
  // It survives: app close, logout, and report-type switches.
  // It is cleared only after a successful submission.

  List<TextEditingController> get _allControllers => [
    _clientController, _siteController, _officerController, _dateEnteredController,
    _incidentInternalIdController, _incidentDateTimeController, _incidentTypeController,
    _victimNameController, _victimContactController, _suspectNameController,
    _suspectContactController, _witnessNamesController, _incidentLocationController,
    _incidentSummaryController, _responderPoliceNamesController, _responderFireTruckController,
    _responderAmbulanceController, _incidentDetailsController, _incidentActionsController,
    _dailyShiftStartNotesController, _dailyPostShiftController, _dailySpecialInstructionsController,
    _dailyPostItemsReceivedController, _dailyRelievingFirstController,
    _dailyRelievingLastController, _dailyAdditionalNotesController,
    _maintenanceTypeController, _maintenanceDetailsController, _maintenanceWhoNotifiedController,
    _violatorFirstController, _violatorLastController, _vehicleMakeController, _vehicleModelController,
    _vehicleLPController, _vehicleVINController, _vehicleColorController, _violationTypeController,
    _violationNumberController, _parkingLocationController, _parkingFineController, _parkingDetailsController,
  ];

  void _attachDraftListeners() {
    for (final c in _allControllers) {
      c.addListener(_saveDraft);
    }
  }

  void _removeDraftListeners() {
    for (final c in _allControllers) {
      c.removeListener(_saveDraft);
    }
  }

  /// Synchronous wrapper — called by text-controller listeners.
  void _saveDraft() {
    if (_draftLoading) return;
    _doSaveDraft();
  }

  Future<void> _doSaveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k('draft_selectedReportType'), _selectedReportType);
    // Incident Report fields
    await prefs.setString(_k('draft_incidentInternalId'),   _incidentInternalIdController.text);
    await prefs.setString(_k('draft_incidentDateTime'),     _incidentDateTimeController.text);
    await prefs.setString(_k('draft_incidentType'),         _incidentTypeController.text);
    await prefs.setString(_k('draft_victimName'),           _victimNameController.text);
    await prefs.setString(_k('draft_victimContact'),        _victimContactController.text);
    await prefs.setString(_k('draft_suspectName'),          _suspectNameController.text);
    await prefs.setString(_k('draft_suspectContact'),       _suspectContactController.text);
    await prefs.setString(_k('draft_witnessNames'),         _witnessNamesController.text);
    await prefs.setString(_k('draft_incidentLocation'),     _incidentLocationController.text);
    await prefs.setString(_k('draft_incidentSummary'),      _incidentSummaryController.text);
    await prefs.setString(_k('draft_responderPoliceNames'), _responderPoliceNamesController.text);
    await prefs.setString(_k('draft_responderFireTruck'),   _responderFireTruckController.text);
    await prefs.setString(_k('draft_responderAmbulance'),   _responderAmbulanceController.text);
    await prefs.setString(_k('draft_incidentDetails'),      _incidentDetailsController.text);
    await prefs.setString(_k('draft_incidentActions'),      _incidentActionsController.text);
    await prefs.setBool(_k('draft_policeCalled'),           _policeCalled);
    // Daily Activity Report fields
    await prefs.setString(_k('draft_dailyShiftStartNotes'),     _dailyShiftStartNotesController.text);
    await prefs.setString(_k('draft_dailyPostShift'),           _dailyPostShiftController.text);
    await prefs.setString(_k('draft_dailySpecialInstructions'), _dailySpecialInstructionsController.text);
    await prefs.setString(_k('draft_dailyPostItemsReceived'),   _dailyPostItemsReceivedController.text);
    await prefs.setString(_k('draft_dailyRelievingFirst'),      _dailyRelievingFirstController.text);
    await prefs.setString(_k('draft_dailyRelievingLast'),       _dailyRelievingLastController.text);
    await prefs.setString(_k('draft_dailyAdditionalNotes'),     _dailyAdditionalNotesController.text);
    await prefs.setString(_k('draft_darObservations'),
        jsonEncode(_darObservations.map((o) => o.toJson()).toList()));
    // Temperature Report fields
    await prefs.setString(_k('draft_tempEntries'),
        jsonEncode(_tempEntries.map((e) => e.toJson()).toList()));
    // Maintenance Report fields
    await prefs.setString(_k('draft_maintenanceType'),        _maintenanceTypeController.text);
    await prefs.setString(_k('draft_maintenanceDetails'),     _maintenanceDetailsController.text);
    await prefs.setString(_k('draft_maintenanceWhoNotified'), _maintenanceWhoNotifiedController.text);
    await prefs.setBool(_k('draft_maintenanceEmailClient'),   _maintenanceEmailClient);
    // Parking Violation Report fields
    await prefs.setString(_k('draft_violatorFirst'),    _violatorFirstController.text);
    await prefs.setString(_k('draft_violatorLast'),     _violatorLastController.text);
    await prefs.setString(_k('draft_vehicleMake'),      _vehicleMakeController.text);
    await prefs.setString(_k('draft_vehicleModel'),     _vehicleModelController.text);
    await prefs.setString(_k('draft_vehicleLP'),        _vehicleLPController.text);
    await prefs.setString(_k('draft_vehicleVIN'),       _vehicleVINController.text);
    await prefs.setString(_k('draft_vehicleColor'),     _vehicleColorController.text);
    await prefs.setString(_k('draft_violationType'),    _violationTypeController.text);
    await prefs.setString(_k('draft_violationNumber'),  _violationNumberController.text);
    await prefs.setString(_k('draft_parkingLocation'),  _parkingLocationController.text);
    await prefs.setString(_k('draft_parkingFine'),      _parkingFineController.text);
    await prefs.setString(_k('draft_parkingDetails'),   _parkingDetailsController.text);
    await prefs.setBool(_k('draft_vehicleTowed'),       _vehicleTowed);
    // Save attached media file paths PER (siteId, report type) so each bucket
    // keeps its own attachments.
    for (final entry in _mediaByType.entries) {
      await prefs.setStringList(
        _mediaPrefsKey(entry.key),
        entry.value.map((m) => '${m.isVideo ? 'v' : 'i'}:${m.file.path}').toList(),
      );
    }

    if (_selectedReportType == _darReportType) {
      _scheduleDarDraftSync();
      _scheduleDarMediaSync();
    }
  }

  Future<void> _loadDraft() async {
    _draftLoading = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final type = prefs.getString(_k('draft_selectedReportType'));
      if (type != null && _reportTypes.contains(type)) {
        if (mounted) setState(() => _selectedReportType = type);
      }
      // Text fields (setting .text does NOT trigger rebuild, setState not needed)
      _incidentInternalIdController.text   = prefs.getString(_k('draft_incidentInternalId'))   ?? '';
      _incidentDateTimeController.text     = prefs.getString(_k('draft_incidentDateTime'))     ?? '';
      _incidentTypeController.text         = prefs.getString(_k('draft_incidentType'))         ?? '';
      _victimNameController.text           = prefs.getString(_k('draft_victimName'))           ?? '';
      _victimContactController.text        = prefs.getString(_k('draft_victimContact'))        ?? '';
      _suspectNameController.text          = prefs.getString(_k('draft_suspectName'))          ?? '';
      _suspectContactController.text       = prefs.getString(_k('draft_suspectContact'))       ?? '';
      _witnessNamesController.text         = prefs.getString(_k('draft_witnessNames'))         ?? '';
      _incidentLocationController.text     = prefs.getString(_k('draft_incidentLocation'))     ?? '';
      _incidentSummaryController.text      = prefs.getString(_k('draft_incidentSummary'))      ?? '';
      _responderPoliceNamesController.text = prefs.getString(_k('draft_responderPoliceNames')) ?? '';
      _responderFireTruckController.text   = prefs.getString(_k('draft_responderFireTruck'))   ?? '';
      _responderAmbulanceController.text   = prefs.getString(_k('draft_responderAmbulance'))   ?? '';
      _incidentDetailsController.text      = prefs.getString(_k('draft_incidentDetails'))      ?? '';
      _incidentActionsController.text      = prefs.getString(_k('draft_incidentActions'))      ?? '';
      _dailyShiftStartNotesController.text     = prefs.getString(_k('draft_dailyShiftStartNotes'))     ?? '';
      _dailyPostShiftController.text           = prefs.getString(_k('draft_dailyPostShift'))           ?? '';
      _dailySpecialInstructionsController.text = prefs.getString(_k('draft_dailySpecialInstructions')) ?? '';
      _dailyPostItemsReceivedController.text   = prefs.getString(_k('draft_dailyPostItemsReceived'))   ?? '';
      _dailyRelievingFirstController.text      = prefs.getString(_k('draft_dailyRelievingFirst'))      ?? '';
      _dailyRelievingLastController.text       = prefs.getString(_k('draft_dailyRelievingLast'))       ?? '';
      _dailyAdditionalNotesController.text     = prefs.getString(_k('draft_dailyAdditionalNotes'))     ?? '';
      // Restore structured DAR observations
      final obsJson = prefs.getString(_k('draft_darObservations'));
      if (mounted) {
        setState(() {
          _darObservations.clear();
          if (obsJson != null) {
            try {
              final decoded = jsonDecode(obsJson) as List;
              _darObservations.addAll(decoded.map(
                  (e) => _DarObservation.fromJson(e as Map<String, dynamic>)));
            } catch (_) {}
          }
        });
      }
      // Restore structured temperature entries
      final tempJson = prefs.getString(_k('draft_tempEntries'));
      if (mounted) {
        setState(() {
          _tempEntries.clear();
          if (tempJson != null) {
            try {
              final decoded = jsonDecode(tempJson) as List;
              _tempEntries.addAll(decoded.map(
                  (e) => _TempEntry.fromJson(e as Map<String, dynamic>)));
            } catch (_) {}
          }
        });
      }
      _maintenanceTypeController.text        = prefs.getString(_k('draft_maintenanceType'))        ?? '';
      _maintenanceDetailsController.text     = prefs.getString(_k('draft_maintenanceDetails'))     ?? '';
      _maintenanceWhoNotifiedController.text = prefs.getString(_k('draft_maintenanceWhoNotified')) ?? '';
      _violatorFirstController.text    = prefs.getString(_k('draft_violatorFirst'))   ?? '';
      _violatorLastController.text     = prefs.getString(_k('draft_violatorLast'))    ?? '';
      _vehicleMakeController.text      = prefs.getString(_k('draft_vehicleMake'))     ?? '';
      _vehicleModelController.text     = prefs.getString(_k('draft_vehicleModel'))    ?? '';
      _vehicleLPController.text        = prefs.getString(_k('draft_vehicleLP'))       ?? '';
      _vehicleVINController.text       = prefs.getString(_k('draft_vehicleVIN'))      ?? '';
      _vehicleColorController.text     = prefs.getString(_k('draft_vehicleColor'))    ?? '';
      _violationTypeController.text    = prefs.getString(_k('draft_violationType'))   ?? '';
      _violationNumberController.text  = prefs.getString(_k('draft_violationNumber')) ?? '';
      _parkingLocationController.text  = prefs.getString(_k('draft_parkingLocation')) ?? '';
      _parkingFineController.text      = prefs.getString(_k('draft_parkingFine'))     ?? '';
      _parkingDetailsController.text   = prefs.getString(_k('draft_parkingDetails'))  ?? '';
      // Boolean toggles
      if (mounted) {
        setState(() {
          _policeCalled           = prefs.getBool(_k('draft_policeCalled'))           ?? false;
          _maintenanceEmailClient = prefs.getBool(_k('draft_maintenanceEmailClient')) ?? false;
          _vehicleTowed           = prefs.getBool(_k('draft_vehicleTowed'))           ?? false;
        });
      }
      // Restore attached media files PER (siteId, report type) bucket.
      // Also handles a one-time legacy migration of the old non-suffixed
      // 'draft_mediaPaths' bucket onto the saved selected type so users with
      // older drafts don't lose previously attached media on first run.
      if (_selectedSiteId == null) {
        final legacy = prefs.getStringList('draft_mediaPaths');
        if (legacy != null) {
          await prefs.setStringList(_mediaPrefsKey(_selectedReportType), legacy);
          await prefs.remove('draft_mediaPaths');
        }
      }
      for (final type in _mediaByType.keys) {
        final paths    = prefs.getStringList(_mediaPrefsKey(type)) ?? [];
        final restored = <_MediaItem>[];
        for (final p in paths) {
          if (p.length < 3) continue;
          final isVideo = p.startsWith('v:');
          final path    = p.substring(2);
          final file    = File(path);
          if (await file.exists()) {
            final item = _MediaItem(file: file, isVideo: isVideo, thumbLoading: isVideo);
            restored.add(item);
            if (isVideo) _generateThumb(item);
          }
        }
        if (restored.isNotEmpty) {
          _mediaByType[type]!.addAll(restored);
        }
      }
      await _hydrateDarDraftFromServerIfNeeded();
      if (_canSyncDarDraft && !_isDarDraftEmptyLocally()) {
        _scheduleDarDraftSync();
        _scheduleDarMediaSync(force: true);
      } else {
        _lastDarMediaSignature = _currentDarMediaSignature();
      }
      if (mounted) setState(() {});
    } finally {
      _draftLoading = false;
    }
  }

  /// Switches the active draft scope to a different site. Called both from
  /// the site dropdown's onChanged AND from `_fetchSites` once the active
  /// assignment resolves to a site. Persists current state under the OLD
  /// site suffix, clears all in-memory state, swaps the suffix, and reloads.
  ///
  /// On the very first transition (null → newId), if no per-site draft
  /// already exists for newId, the current legacy-loaded controller text is
  /// migrated into the per-site bucket so existing drafts aren't lost.
  Future<void> _swapSite(int? newId) async {
    if (_selectedSiteId == newId) return;

    final prefs = await SharedPreferences.getInstance();
    final wasLegacy = _selectedSiteId == null && _pendingLegacyMigration;

    if (wasLegacy && newId != null) {
      // Does the destination site already have a saved draft?
      final hasPerSite =
          prefs.containsKey('draft_selectedReportType_s$newId');
      if (hasPerSite) {
        // Per-site draft exists → discard legacy text in controllers and
        // load the per-site draft as-is.
        _draftLoading = true;
        setState(() {
          for (final c in _allControllers) c.clear();
          _darObservations.clear();
          _tempEntries.clear();
          _policeCalled = false;
          _maintenanceEmailClient = false;
          _vehicleTowed = false;
          for (final list in _mediaByType.values) list.clear();
          _selectedSiteId = newId;
        });
        _pendingLegacyMigration = false;
        await _loadDraft();
        return;
      }
      // No per-site draft yet → keep current controller text, just save it
      // under the new site's suffix.
      setState(() => _selectedSiteId = newId);
      _pendingLegacyMigration = false;
      await _doSaveDraft();
      // Cleanup: drop the now-orphaned legacy unsuffixed keys to prevent
      // re-migration on subsequent launches.
      await _clearLegacyUnsuffixedDraft(prefs);
      return;
    }

    // Normal swap: persist current state under OLD suffix, clear, load NEW.
    if (!_draftLoading) await _doSaveDraft();
    _draftLoading = true;
    setState(() {
      for (final c in _allControllers) c.clear();
      _darObservations.clear();
      _tempEntries.clear();
      _policeCalled = false;
      _maintenanceEmailClient = false;
      _vehicleTowed = false;
      for (final list in _mediaByType.values) list.clear();
      _selectedSiteId = newId;
    });
    await _loadDraft();
  }

  /// Removes the pre-multi-site (unsuffixed) draft keys after a successful
  /// migration so subsequent app launches don't re-load stale legacy text.
  Future<void> _clearLegacyUnsuffixedDraft(SharedPreferences prefs) async {
    const legacyKeys = [
      'draft_selectedReportType',
      'draft_incidentInternalId', 'draft_incidentDateTime', 'draft_incidentType',
      'draft_victimName', 'draft_victimContact', 'draft_suspectName',
      'draft_suspectContact', 'draft_witnessNames', 'draft_incidentLocation',
      'draft_incidentSummary', 'draft_responderPoliceNames',
      'draft_responderFireTruck', 'draft_responderAmbulance',
      'draft_incidentDetails', 'draft_incidentActions', 'draft_policeCalled',
      'draft_dailyShiftStartNotes', 'draft_dailyPostShift',
      'draft_dailySpecialInstructions', 'draft_dailyPostItemsReceived',
      'draft_dailyRelievingFirst', 'draft_dailyRelievingLast',
      'draft_dailyAdditionalNotes', 'draft_darObservations',
      'draft_maintenanceType', 'draft_maintenanceDetails',
      'draft_maintenanceWhoNotified', 'draft_maintenanceEmailClient',
      'draft_violatorFirst', 'draft_violatorLast', 'draft_vehicleMake',
      'draft_vehicleModel', 'draft_vehicleLP', 'draft_vehicleVIN',
      'draft_vehicleColor', 'draft_violationType', 'draft_violationNumber',
      'draft_parkingLocation', 'draft_parkingFine', 'draft_parkingDetails',
      'draft_vehicleTowed',
      'draft_mediaPaths',
      'draft_mediaPaths_incident_report',
      'draft_mediaPaths_daily_activity_report',
      'draft_mediaPaths_maintenance_report',
      'draft_mediaPaths_parking_violation_report',
      'draft_tempEntries',
      'draft_mediaPaths_temperature_report',
    ];
    for (final k in legacyKeys) {
      await prefs.remove(k);
    }
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();

    // Keys shared across all report types (media is per-type, not shared)
    const sharedKeys = ['draft_selectedReportType'];

    // Keys specific to each report type
    const keysByType = <String, List<String>>{
      'Incident Report': [
        'draft_incidentInternalId', 'draft_incidentDateTime', 'draft_incidentType',
        'draft_victimName', 'draft_victimContact', 'draft_suspectName', 'draft_suspectContact',
        'draft_witnessNames', 'draft_incidentLocation', 'draft_incidentSummary',
        'draft_responderPoliceNames', 'draft_responderFireTruck', 'draft_responderAmbulance',
        'draft_incidentDetails', 'draft_incidentActions', 'draft_policeCalled',
      ],
      'Daily Activity Report': [
        'draft_dailyShiftStartNotes', 'draft_dailyPostShift', 'draft_dailySpecialInstructions',
        'draft_dailyPostItemsReceived', 'draft_dailyRelievingFirst', 'draft_dailyRelievingLast',
        'draft_dailyAdditionalNotes', 'draft_darObservations',
      ],
      'Maintenance Report': [
        'draft_maintenanceType', 'draft_maintenanceDetails', 'draft_maintenanceWhoNotified',
        'draft_maintenanceEmailClient',
      ],
      'Parking Violation Report': [
        'draft_violatorFirst', 'draft_violatorLast', 'draft_vehicleMake', 'draft_vehicleModel',
        'draft_vehicleLP', 'draft_vehicleVIN', 'draft_vehicleColor', 'draft_violationType',
        'draft_violationNumber', 'draft_parkingLocation', 'draft_parkingFine',
        'draft_parkingDetails', 'draft_vehicleTowed',
      ],
      'Temperature Report': [
        'draft_tempEntries',
      ],
    };

    // Only clear the keys for the (current site, report type just submitted),
    // plus shared keys, plus that type's own per-site media bucket. Other
    // types' media (and other sites' drafts entirely) stay intact.
    final keysToRemove = [
      ...sharedKeys.map(_k),
      ...((keysByType[_selectedReportType] ?? const <String>[]).map(_k)),
      _mediaPrefsKey(_selectedReportType),
    ];
    for (final k in keysToRemove) {
      await prefs.remove(k);
    }
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
      // Camera permission is required to access the camera hardware.
      if (!await _checkPermission(Permission.camera, 'Camera')) return;
    }
    // Gallery picking:
    // - Android 13+: image_picker uses the system Photo Picker → NO permission needed.
    // - Android ≤ 12: READ_EXTERNAL_STORAGE (maxSdkVersion="32") handles it at OS level.
    // - iOS: image_picker shows its own system dialog on first use, BUT if the user
    //   previously denied access it returns null silently. We check manually so we
    //   can show the "go to Settings" dialog in that case.
    if (source == ImageSource.gallery && Platform.isIOS) {
      if (!await _checkPermission(Permission.photos, 'Photos')) return;
    }

    setState(() => _isPickingMedia = true);
    try {
      // Gallery → multi-select (system picker lets the user tap many photos).
      // Camera → single shot (no multi-shot at the OS level).
      if (source == ImageSource.gallery) {
        List<XFile> pickedList;
        try {
          pickedList = await _picker.pickMultiImage(imageQuality: 85);
        } catch (_) {
          return;
        }
        if (pickedList.isEmpty || !mounted) return;
        // Respect the server-side cap of 20 files per upload.
        const maxFiles = 20;
        final remaining = maxFiles - _mediaItems.length;
        if (remaining <= 0) {
          _snackError('Maximum of $maxFiles attachments reached.');
          return;
        }
        final toAdd = pickedList.take(remaining).toList();
        if (toAdd.length < pickedList.length) {
          _snackError('Only the first ${toAdd.length} photos were added (max $maxFiles).');
        }
        for (final picked in toAdd) {
          final File stableFile = await _copyToTemp(picked.path, ext: 'jpg');
          if (!mounted) return;
          setState(() => _mediaItems.add(_MediaItem(file: stableFile, isVideo: false)));
        }
        _doSaveDraft();
      } else {
        XFile? picked;
        try { picked = await _picker.pickImage(source: source, imageQuality: 85); } catch (_) { return; }
        if (picked == null || !mounted) return;
        if (_mediaItems.length >= 20) {
          _snackError('Maximum of 20 attachments reached.');
          return;
        }
        final File stableFile = await _copyToTemp(picked.path, ext: 'jpg');
        setState(() => _mediaItems.add(_MediaItem(file: stableFile, isVideo: false)));
        _doSaveDraft();
      }
    } finally {
      if (mounted) setState(() => _isPickingMedia = false);
    }
  }
  bool _isPickingMedia = false;

  Future<void> _pickVideo(ImageSource source) async {
    if (_isPickingMedia) return;

    if (source == ImageSource.camera) {
      // Camera + microphone permissions required for recording.
      if (!await _checkPermission(Permission.camera, 'Camera')) return;
      if (!await _checkPermission(Permission.microphone, 'Microphone')) return;
    }
    // Gallery picking:
    // - Android 13+: image_picker uses the system Photo Picker → NO permission needed.
    // - Android ≤ 12: READ_EXTERNAL_STORAGE (maxSdkVersion="32") handles it at OS level.
    // - iOS: check manually so we can show "go to Settings" if previously denied.
    if (source == ImageSource.gallery && Platform.isIOS) {
      if (!await _checkPermission(Permission.photos, 'Photos & Videos')) return;
    }

    setState(() => _isPickingMedia = true);
    try {
      final picked = await _picker.pickVideo(source: source);
      if (picked == null || !mounted) return;
      if (_mediaItems.length >= 20) {
        _snackError('Maximum of 20 attachments reached.');
        return;
      }
      final item = _MediaItem(file: File(picked.path), isVideo: true, thumbLoading: true);
      setState(() => _mediaItems.add(item));
      _generateThumb(item);
      _doSaveDraft();
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




  // ─── EMPTY REPORT GUARD ───────────────────────────────────────────────────
  /// Returns true when every text field for the current report type is blank.
  bool _isReportEmpty() {
    switch (_selectedReportType) {
      case "Incident Report":
        return [
          _incidentInternalIdController, _incidentDateTimeController,
          _incidentTypeController, _victimNameController, _victimContactController,
          _suspectNameController, _suspectContactController, _witnessNamesController,
          _incidentLocationController, _incidentSummaryController,
          _responderPoliceNamesController, _responderFireTruckController,
          _responderAmbulanceController, _incidentDetailsController,
          _incidentActionsController,
        ].every((c) => c.text.trim().isEmpty);
      case "Daily Activity Report":
        return _darObservations.isEmpty &&
            [
              _dailyShiftStartNotesController, _dailyPostShiftController,
              _dailySpecialInstructionsController, _dailyPostItemsReceivedController,
              _dailyRelievingFirstController, _dailyRelievingLastController,
              _dailyAdditionalNotesController,
            ].every((c) => c.text.trim().isEmpty);
      case "Maintenance Report":
        return [
          _maintenanceTypeController,
          _maintenanceDetailsController,
          _maintenanceWhoNotifiedController,
        ].every((c) => c.text.trim().isEmpty);
      case "Parking Violation Report":
        return [
          _violatorFirstController, _violatorLastController,
          _vehicleMakeController, _vehicleModelController,
          _vehicleLPController, _vehicleVINController, _vehicleColorController,
          _violationTypeController, _violationNumberController,
          _parkingLocationController, _parkingFineController,
          _parkingDetailsController,
        ].every((c) => c.text.trim().isEmpty);
      case "Temperature Report":
        return _tempEntries.isEmpty;
      default:
        return true;
    }
  }

  void _showEmptyReportDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 26),
          const SizedBox(width: 10),
          Text('Report is Empty',
              style: TextStyle(
                  color: _textColor, fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        content: Text(
          'Your report has nothing in it yet.\n\nPlease fill in at least one field before submitting. You cannot send a blank report.',
          style: TextStyle(color: _secondaryTextColor, height: 1.6),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Got it',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ─── FETCH SITES ──────────────────────────────────────────────────────────
  Future<void> _fetchSites() async {
    final prefs      = await SharedPreferences.getInstance();
    final guardId    = prefs.getInt('userId');
    int? assignmentId = prefs.getInt('assignmentId');
    if (guardId == null) return;

    try {
      final dashboardResponse = await api.get('assignments/dashboard-mobile/$guardId');
      if (dashboardResponse.statusCode == 200) {
        final dashboardData = jsonDecode(dashboardResponse.body) as Map<String, dynamic>;
        final rawSessionId = dashboardData['sessionId'];
        final rawAssignmentId = dashboardData['assignmentId'];
        _activeSessionId = rawSessionId is num ? rawSessionId.toInt() : int.tryParse('${rawSessionId ?? ''}');
        if (_activeSessionId != null) {
          await prefs.setInt('sessionId', _activeSessionId!);
        } else {
          await prefs.remove('sessionId');
        }
        if (assignmentId == null && rawAssignmentId is num) {
          assignmentId = rawAssignmentId.toInt();
          await prefs.setInt('assignmentId', assignmentId!);
        }
      }
    } catch (_) {}

    final userResponse = await api.get('users/$guardId');
    final userData = userResponse.statusCode == 200
        ? jsonDecode(userResponse.body) as Map<String, dynamic>
        : <String, dynamic>{};
    final roles = List<String>.from(userData['roles'] ?? const []);
    final isSupervisor = roles.any((role) => role.toLowerCase() == 'supervisor');
    final isAdmin = roles.any((role) {
      final normalized = role.toLowerCase();
      return normalized == 'admin' || normalized == 'full admin';
    });

    if (assignmentId == null) {
      _activeSessionId = null;
      await prefs.remove('sessionId');
      if (isSupervisor || isAdmin) {
        await _loadSitesForRoleWithoutAssignment(guardId, isSupervisor: isSupervisor, isAdmin: isAdmin);
      } else {
        setState(() {
          _hasActiveAssignment = false;
          _canSubmitWithoutAssignment = false;
          _sites = [];
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(backgroundColor: Colors.redAccent, content: Text("You don't have an active assignment right now. Please contact your supervisor.")));
      }
      return;
    }
    try {
      final response = await api.get('assignments/shift/active-shift-sites/$guardId/$assignmentId');
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        // Multi-site support: use 'sites' array if present, fall back to single 'site'
        final sitesRaw = decoded['sites'];
        if (sitesRaw != null && sitesRaw is List && sitesRaw.isNotEmpty) {
          final siteList = List<Map<String, dynamic>>.from(sitesRaw);
          setState(() {
            _sites = siteList;
            _hasActiveAssignment = true;
            _canSubmitWithoutAssignment = isSupervisor || isAdmin;
          });
          // Auto-pick when there's only one site so the draft scope locks in.
          if (siteList.length == 1) {
            await _swapSite((siteList[0]['id'] as num).toInt());
          }
        } else {
          final site = decoded['site'];
          if (site != null) {
            setState(() {
              _sites = [Map<String, dynamic>.from(site as Map)];
              _hasActiveAssignment = true;
              _canSubmitWithoutAssignment = isSupervisor || isAdmin;
            });
            await _swapSite((site['id'] as num).toInt());
          } else {
            if (isSupervisor || isAdmin) {
              await _loadSitesForRoleWithoutAssignment(guardId, isSupervisor: isSupervisor, isAdmin: isAdmin);
            } else {
              setState(() {
                _sites = [];
                _hasActiveAssignment = false;
                _canSubmitWithoutAssignment = false;
              });
            }
          }
        }
      } else {
        if (isSupervisor || isAdmin) {
          await _loadSitesForRoleWithoutAssignment(guardId, isSupervisor: isSupervisor, isAdmin: isAdmin);
        } else {
          setState(() {
            _sites = [];
            _hasActiveAssignment = false;
            _canSubmitWithoutAssignment = false;
          });
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text("You don't have an active shift right now. Please start your shift before submitting a report.", style: TextStyle(color: Colors.white))));
        }
      }
    } catch (e) {
      if (mounted) _snackError(ApiService.friendlyError(e));
    }
  }

  Future<void> _loadSitesForRoleWithoutAssignment(int userId, {required bool isSupervisor, required bool isAdmin}) async {
    _activeSessionId = null;
    final response = await api.get('sites');
    if (response.statusCode != 200) {
      setState(() {
        _hasActiveAssignment = false;
        _canSubmitWithoutAssignment = false;
        _sites = [];
      });
      return;
    }

    final List decoded = jsonDecode(response.body) as List;
    final roleSites = decoded
        .map((site) => Map<String, dynamic>.from(site as Map))
        .where((site) {
          if (isAdmin) return true;
          final supervisorIds = List<dynamic>.from(site['supervisorIds'] ?? const []);
          return supervisorIds.any((id) => (id as num).toInt() == userId);
        })
        .toList();

    setState(() {
      _sites = roleSites;
      _hasActiveAssignment = false;
      _canSubmitWithoutAssignment = isSupervisor || isAdmin;
    });

    if (roleSites.length == 1) {
      await _swapSite((roleSites.first['id'] as num).toInt());
    } else if (_selectedSiteId != null && !roleSites.any((site) => site['id'] == _selectedSiteId)) {
      await _swapSite(null);
    }
  }

  // ─── SUBMIT ───────────────────────────────────────────────────────────────
  Future<void> _submitReport() async {
    if (_isReportEmpty() && _mediaItems.isEmpty) { _showEmptyReportDialog(); return; }
    if (!_hasActiveAssignment && !_canSubmitWithoutAssignment) { _snackError("You don't have an active assignment right now. Please contact your supervisor."); return; }
    if (_selectedSiteId == null) { _snackError("Please select a site before submitting."); return; }

    // Temperature Report validation — location and temperature are required per entry
    if (_selectedReportType == 'Temperature Report') {
      for (int i = 0; i < _tempEntries.length; i++) {
        final e = _tempEntries[i];
        if (e.location.trim().isEmpty) {
          _snackError("Reading ${i + 1}: Please select a location (Water Tank or Water Heater).");
          return;
        }
        if (e.degrees.trim().isEmpty) {
          _snackError("Reading ${i + 1}: Please enter a temperature.");
          return;
        }
      }
    }

    final prefs     = await SharedPreferences.getInstance();
    final officerId = prefs.getInt('userId');

    _cancelToken = CancelToken();
    setState(() { _isSubmitting = true; _uploadProgress = 0.0; _cancelRequested = false; });

    try {


      // Wait for any in-progress compression before uploading


      final payload = {
        "type": _selectedReportType,
        "data": {
          ..._buildReportData(),
          "officerId": officerId,
          "siteId": _selectedSiteId,
          if (_selectedReportType == _darReportType && _activeSessionId != null) "sessionId": _activeSessionId,
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
        }, cancelToken: _cancelToken);
        print("UPLOAD TOOK: ${stopwatch.elapsed}");
      } else {
        final response = await api.post('reports', payload);
        if (response.statusCode != 200 && response.statusCode != 201) {
          throw Exception("status:${response.statusCode}");
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
      if (_cancelRequested || e.type == DioExceptionType.cancel) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Upload cancelled.'), backgroundColor: Colors.orange));
      } else {
        _snackError(ApiService.friendlyError(e, statusCode: e.response?.statusCode));
      }
    } catch (e) {
      if (_cancelRequested) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Upload cancelled.'), backgroundColor: Colors.orange));
      } else {
        _snackError(ApiService.friendlyError(e));
      }
    } finally {
      if (mounted) setState(() { _isSubmitting = false; _uploadProgress = 0.0; _cancelRequested = false; });
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
        "dailyObservations":        jsonEncode(_darObservations.map((o) => o.toJson()).toList()),
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
      case "Temperature Report": return {
        "tempEntries": jsonEncode(_tempEntries.map((e) => e.toJson()).toList()),
      };
      default: return {};
    }
  }

  Map<String, dynamic> _buildDarDraftData() {
    return {
      "dailyShiftStartNotes": _dailyShiftStartNotesController.text,
      "dailyPostShift": _dailyPostShiftController.text,
      "dailySpecialInstructions": _dailySpecialInstructionsController.text,
      "dailyPostItemsReceived": _dailyPostItemsReceivedController.text,
      "dailyObservations": jsonEncode(_darObservations.map((o) => o.toJson()).toList()),
      "dailyRelievingFirst": _dailyRelievingFirstController.text,
      "dailyRelievingLast": _dailyRelievingLastController.text,
      "dailyAdditionalNotes": _dailyAdditionalNotesController.text,
    };
  }

  Future<void> _hydrateDarDraftFromServerIfNeeded() async {
    if (!_canSyncDarDraft || !_isDarDraftEmptyLocally()) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final officerId = prefs.getInt('userId');
    if (officerId == null) {
      return;
    }

    try {
      final response = await api.get(
        'dar-drafts/session/$_activeSessionId/site/$_selectedSiteId/officer/$officerId',
      );
      if (response.statusCode != 200) {
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final rawData = decoded['data'];
      final data = rawData is Map<String, dynamic>
          ? rawData
          : Map<String, dynamic>.from(rawData as Map? ?? const {});
      final observationsJson = data['dailyObservations']?.toString() ?? '[]';

      _draftLoading = true;
      _dailyShiftStartNotesController.text = data['dailyShiftStartNotes']?.toString() ?? '';
      _dailyPostShiftController.text = data['dailyPostShift']?.toString() ?? '';
      _dailySpecialInstructionsController.text = data['dailySpecialInstructions']?.toString() ?? '';
      _dailyPostItemsReceivedController.text = data['dailyPostItemsReceived']?.toString() ?? '';
      _dailyRelievingFirstController.text = data['dailyRelievingFirst']?.toString() ?? '';
      _dailyRelievingLastController.text = data['dailyRelievingLast']?.toString() ?? '';
      _dailyAdditionalNotesController.text = data['dailyAdditionalNotes']?.toString() ?? '';
      if (mounted) {
        setState(() {
          _darObservations.clear();
          try {
            final decodedObservations = jsonDecode(observationsJson) as List<dynamic>;
            _darObservations.addAll(decodedObservations.map(
              (entry) => _DarObservation.fromJson(Map<String, dynamic>.from(entry as Map)),
            ));
          } catch (_) {}
        });
      }
      _draftLoading = false;
      await _doSaveDraft();
    } catch (_) {
      _draftLoading = false;
    }
  }

  bool _isDarDraftEmptyLocally() {
    return _darMediaItems.isEmpty &&
        _darObservations.isEmpty &&
        [
          _dailyShiftStartNotesController,
          _dailyPostShiftController,
          _dailySpecialInstructionsController,
          _dailyPostItemsReceivedController,
          _dailyRelievingFirstController,
          _dailyRelievingLastController,
          _dailyAdditionalNotesController,
        ].every((controller) => controller.text.trim().isEmpty);
  }

  String _currentDarMediaSignature() {
    return _darMediaItems.map((item) => item.uploadFile.path).join('|');
  }

  void _scheduleDarDraftSync() {
    if (!_canSyncDarDraft) {
      return;
    }
    _darDraftSyncTimer?.cancel();
    _darDraftSyncTimer = Timer(const Duration(seconds: 1), () {
      _syncDarDraftToServer();
    });
  }

  void _scheduleDarMediaSync({bool force = false}) {
    if (!_canSyncDarDraft) {
      return;
    }
    final signature = _currentDarMediaSignature();
    if (!force && signature == _lastDarMediaSignature) {
      return;
    }
    _darMediaSyncTimer?.cancel();
    _darMediaSyncTimer = Timer(const Duration(milliseconds: 600), () {
      _syncDarMediaToServer(expectedSignature: signature);
    });
  }

  Future<void> _syncDarDraftToServer() async {
    if (!_canSyncDarDraft) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final officerId = prefs.getInt('userId');
    if (officerId == null) {
      return;
    }

    try {
      await api.put(
        'dar-drafts/session/$_activeSessionId/site/$_selectedSiteId/officer/$officerId',
        _buildDarDraftData(),
      );
    } catch (_) {}
  }

  Future<void> _syncDarMediaToServer({String? expectedSignature}) async {
    if (!_canSyncDarDraft) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final officerId = prefs.getInt('userId');
    if (officerId == null) {
      return;
    }

    final signature = _currentDarMediaSignature();
    if (expectedSignature != null && expectedSignature != signature) {
      return;
    }

    try {
      if (_darMediaItems.isEmpty) {
        await api.delete('dar-drafts/session/$_activeSessionId/site/$_selectedSiteId/officer/$officerId/media');
      } else {
        await api.uploadDarDraftMediaDio(
          _activeSessionId!,
          _selectedSiteId!,
          officerId,
          _darMediaItems.map((item) => item.uploadFile).toList(),
          (_, __) {},
        );
      }
      _lastDarMediaSignature = signature;
    } catch (_) {}
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

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Stack(children: [
      AbsorbPointer(
        absorbing: _isSubmitting,
        child: Scaffold(
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
                      onChanged: (v) { setState(() => _selectedReportType = v!); _doSaveDraft(); },
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
                        onTap: _isSubmitting ? null : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            barrierDismissible: false,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: _cardColor,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                              content: Column(mainAxisSize: MainAxisSize.min, children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: _primaryColor.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.send_rounded, color: _primaryColor, size: 36),
                                ),
                                const SizedBox(height: 16),
                                Text('Submit Report',
                                    style: TextStyle(color: _textColor, fontSize: 18, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 10),
                                Text(
                                  'Are you sure you want to submit this $_selectedReportType? This action cannot be undone.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: _secondaryTextColor, fontSize: 14, height: 1.5),
                                ),
                              ]),
                              actions: [
                                Row(children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          side: BorderSide(color: _borderColor),
                                        ),
                                      ),
                                      child: Text('Cancel', style: TextStyle(color: _secondaryTextColor, fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _primaryColor,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        elevation: 0,
                                      ),
                                      child: const Text('Submit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                    ),
                                  ),
                                ]),
                              ],
                            ),
                          );
                          if (confirmed == true) _submitReport();
                        },
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
        ),
      ),

      // overlay is outside AbsorbPointer — cancel button receives taps
      if (_isSubmitting)
        Container(
          color: Colors.black54,
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _borderColor),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  _uploadProgress > 0
                      ? 'Uploading... ${(_uploadProgress * 100).toStringAsFixed(0)}%'
                      : 'Preparing...',
                  style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _uploadProgress > 0 ? _uploadProgress : null,
                    backgroundColor: _borderColor,
                    valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 12),
                Text('Please wait, do not close the app',
                    style: TextStyle(color: _secondaryTextColor, fontSize: 12)),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () {
                    _cancelToken?.cancel('Upload cancelled by user');
                    setState(() => _cancelRequested = true);
                  },
                  icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 18),
                  label: const Text('Cancel Upload', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ),
        ),
    ]),
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
      _doSaveDraft();

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
              onTap: () { setState(() => _mediaItems.removeAt(i)); _doSaveDraft(); },
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
      case "Temperature Report":        return _tempFields();
      default: return [];
    }
  }

  IconData _getReportTypeIcon() {
    switch (_selectedReportType) {
      case "Incident Report":           return Icons.warning_amber_rounded;
      case "Daily Activity Report":     return Icons.calendar_today;
      case "Maintenance Report":        return Icons.build;
      case "Parking Violation Report":  return Icons.local_parking;
      case "Temperature Report":        return Icons.thermostat;
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
      onChanged: _sites.isNotEmpty
          ? (v) => _swapSite((v?['id'] as num?)?.toInt())
          : null,
      disabledHint: const Text("No sites available", style: TextStyle(color: Colors.redAccent)),
    ),
  );

  Future<void> _pickIncidentDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.dark(primary: _primaryColor),
        ),
        child: child!,
      ),
    );
    if (pickedDate == null) return;
    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.dark(primary: _primaryColor),
        ),
        child: child!,
      ),
    );
    if (pickedTime == null) return;
    final hour   = pickedTime.hourOfPeriod == 0 ? 12 : pickedTime.hourOfPeriod;
    final minute = pickedTime.minute.toString().padLeft(2, '0');
    final ampm   = pickedTime.period == DayPeriod.am ? 'AM' : 'PM';
    final formatted =
        '${pickedDate.month.toString().padLeft(2, '0')}/'
        '${pickedDate.day.toString().padLeft(2, '0')}/'
        '${pickedDate.year} '
        '$hour:$minute $ampm';
    setState(() => _incidentDateTimeController.text = formatted);
    _doSaveDraft();
  }

  List<Widget> _incidentFields() => [
    Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(children: [
        Expanded(
          child: TextFormField(
            controller: _incidentInternalIdController,
            decoration: _modernInput("Internal Display ID"),
            style: TextStyle(color: _textColor),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: _pickIncidentDateTime,
            child: AbsorbPointer(
              child: TextFormField(
                controller: _incidentDateTimeController,
                readOnly: true,
                decoration: _modernInput("Date & Time").copyWith(
                  suffixIcon: Icon(Icons.calendar_today, color: _primaryColor, size: 18),
                ),
                style: TextStyle(color: _textColor),
              ),
            ),
          ),
        ),
      ]),
    ),
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
          Switch(value: _policeCalled, onChanged: (v) { setState(() => _policeCalled = v); _doSaveDraft(); }, activeColor: Colors.blueAccent),
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
    _single(_dailyPostItemsReceivedController, "Post Items Received (phone, keys)"),
    _buildDarObservationsSection(),
    _rowTwo(_dailyRelievingFirstController, "Relieving Officer - First Name", _dailyRelievingLastController, "Relieving Officer - Last Name"),
    _multi(_dailyAdditionalNotesController, "Additional Notes"),
  ];

  List<Widget> _maintenanceFields() => [
    _single(_maintenanceTypeController, "Maintenance Type (e.g. Lights Out)"),
    _multi(_maintenanceDetailsController, "Problem Details"),
    _single(_maintenanceWhoNotifiedController, "Who has been notified"),
  ];

  // ─── TEMPERATURE REPORT ───────────────────────────────────────────────────
  static const List<String> _tempLocations = ['Water Tank', 'Water Heater'];

  List<Widget> _tempFields() => [_buildTempSection()];

  Widget _buildTempSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Temperature Readings",
                style: TextStyle(color: _textColor, fontWeight: FontWeight.w600, fontSize: 14),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _tempEntries.add(_TempEntry(time: _hawaiiTimeNow()));
                  });
                  _doSaveDraft();
                },
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text("Add"),
                style: TextButton.styleFrom(foregroundColor: _primaryColor),
              ),
            ],
          ),
          if (_tempEntries.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: _isDarkMode ? const Color(0xFF2D3748) : Colors.grey[50],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _borderColor),
              ),
              child: Text(
                'No readings added yet. Tap "Add" to record one.',
                style: TextStyle(color: _secondaryTextColor, fontSize: 13),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _tempEntries.length,
              itemBuilder: (context, index) {
                final entry = _tempEntries[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _isDarkMode ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _borderColor),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: badge + time + delete
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.teal.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Reading ${index + 1}",
                                    style: const TextStyle(color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                                if (entry.time.isNotEmpty)
                                  Text(entry.time,
                                      style: TextStyle(color: _secondaryTextColor, fontSize: 10)),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              setState(() => _tempEntries.removeAt(index));
                              _doSaveDraft();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.close, color: Colors.redAccent, size: 16),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Location dropdown
                      DropdownButtonFormField<String>(
                        value: entry.location.isNotEmpty ? entry.location : null,
                        hint: Text("Select location", style: TextStyle(color: _secondaryTextColor, fontSize: 14)),
                        dropdownColor: _cardColor,
                        style: TextStyle(color: _textColor, fontSize: 14),
                        decoration: _modernInput("Location").copyWith(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                        items: _tempLocations
                            .map((t) => DropdownMenuItem(value: t, child: Text(t, style: TextStyle(color: _textColor))))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _tempEntries[index].location = val);
                            _doSaveDraft();
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // Temperature input
                      TextFormField(
                        initialValue: entry.degrees,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: TextStyle(color: _textColor, fontSize: 14),
                        decoration: _modernInput("Temperature (°F)"),
                        onChanged: (val) {
                          _tempEntries[index].degrees = val;
                          _doSaveDraft();
                        },
                      ),
                      const SizedBox(height: 12),
                      // Notes (optional)
                      TextFormField(
                        initialValue: entry.notes,
                        maxLines: 3,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        style: TextStyle(color: _textColor, fontSize: 14),
                        decoration: _modernInput("Notes (optional)"),
                        onChanged: (val) {
                          _tempEntries[index].notes = val;
                          _doSaveDraft();
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

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
          Switch(value: _vehicleTowed, onChanged: (v) { setState(() => _vehicleTowed = v); _doSaveDraft(); }, activeColor: Colors.redAccent),
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
    child: TextFormField(controller: c, maxLines: 4, keyboardType: TextInputType.multiline, textInputAction: TextInputAction.newline, decoration: _modernInput(l), style: TextStyle(color: _textColor)),
  );
  Widget _rowTwo(TextEditingController c1, String l1, TextEditingController c2, String l2) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(children: [
      Expanded(child: TextFormField(controller: c1, decoration: _modernInput(l1), style: TextStyle(color: _textColor))),
      const SizedBox(width: 12),
      Expanded(child: TextFormField(controller: c2, decoration: _modernInput(l2), style: TextStyle(color: _textColor))),
    ]),
  );

  /// Returns the current date/time in Hawaii Standard Time (UTC-10, no DST).
  static String _hawaiiTimeNow() {
    final hst = DateTime.now().toUtc().subtract(const Duration(hours: 10));
    final h   = hst.hour;
    final m   = hst.minute.toString().padLeft(2, '0');
    final ampm = h >= 12 ? 'PM' : 'AM';
    final h12  = h % 12 == 0 ? 12 : h % 12;
    return '${hst.month}/${hst.day}/${hst.year} $h12:$m $ampm HST';
  }

  // ── Observation types — update this list when the client provides full set ──
  static const List<String> _observationTypes = [
    'General notes',
    'Light fixture',
    'Doors',
    'Gate',
    'Windows',
    'Electrical',
    'Leaks',
    'Unauthorized parking',
    'Alarm system',
    'Security cameras',
    'Fire extinguisher',
    'Emergency exit',
    'Fence/perimeter',
    'Trash/debris',
    'Flooring',
    'Appliances',
    'Stairs/railing',
    'Sewer smell',
    'Exposed wiring',
    'Mold',
    'Pests',
    'General cleanliness',
    'Elevator',
    'Pool',
    'Other',
  ];

  Widget _buildDarObservationsSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Observations",
                style: TextStyle(
                  color: _textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _darObservations.add(_DarObservation(time: _hawaiiTimeNow()));
                  });
                  _doSaveDraft();
                },
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text("Add"),
                style: TextButton.styleFrom(foregroundColor: _primaryColor),
              ),
            ],
          ),
          if (_darObservations.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: _isDarkMode ? const Color(0xFF2D3748) : Colors.grey[50],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _borderColor),
              ),
              child: Text(
                "No observations added yet. Tap \"Add\" to add one.",
                style: TextStyle(color: _secondaryTextColor, fontSize: 13),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _darObservations.length,
              itemBuilder: (context, index) {
                final obs = _darObservations[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _isDarkMode ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top row: index badge + delete button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _primaryColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Observation ${index + 1}",
                                  style: TextStyle(
                                    color: _accentColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (obs.time.isNotEmpty)
                                  Text(
                                    obs.time,
                                    style: TextStyle(
                                      color: _secondaryTextColor,
                                      fontSize: 10,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              setState(() => _darObservations.removeAt(index));
                              _doSaveDraft();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.close, color: Colors.redAccent, size: 16),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Type dropdown
                      DropdownButtonFormField<String>(
                        value: obs.type.isNotEmpty ? obs.type : null,
                        hint: Text("Select type", style: TextStyle(color: _secondaryTextColor, fontSize: 14)),
                        dropdownColor: _cardColor,
                        style: TextStyle(color: _textColor, fontSize: 14),
                        decoration: _modernInput("Observation Type").copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                        items: _observationTypes.map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t, style: TextStyle(color: _textColor)),
                        )).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _darObservations[index].type = val);
                            _doSaveDraft();
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // Description
                      TextFormField(
                        initialValue: obs.description,
                        maxLines: 3,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        style: TextStyle(color: _textColor, fontSize: 14),
                        decoration: _modernInput("Description"),
                        onChanged: (val) {
                          _darObservations[index].description = val;
                          _doSaveDraft();
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}