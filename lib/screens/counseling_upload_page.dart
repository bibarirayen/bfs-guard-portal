import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_compress/video_compress.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../services/counseling_service.dart';

/// Holds a media file + optional pre-generated video thumbnail bytes.
class _MediaItem {
  File file;
  final bool isVideo;
  Uint8List? videoThumb;
  bool thumbLoading;

  _MediaItem({
    required this.file,
    required this.isVideo,
    this.videoThumb,
    this.thumbLoading = false,
  });

  File get uploadFile => file;
}

class CounselingUploadPage extends StatefulWidget {
  const CounselingUploadPage({super.key});

  @override
  State<CounselingUploadPage> createState() => _CounselingUploadPageState();
}

class _CounselingUploadPageState extends State<CounselingUploadPage> {
  final _titleController       = TextEditingController();
  final _descriptionController = TextEditingController();
  final _categoryController    = TextEditingController();
  final _service               = CounselingService();
  final _picker                = ImagePicker();

  bool _isDarkMode = true;
  bool _loading    = false;
  double _uploadProgress = 0.0;

  List<Map<String, dynamic>> _guards = [];
  int? _selectedGuardId;
  int? _supervisorId;
  List<_MediaItem> _mediaItems = [];

  // ── Picking lock (blocks all buttons while OS picker is open / file loading) ──
  bool _isPickingMedia = false;
  bool _cancelRequested = false;

  // ── Theme ──────────────────────────────────────────────────────────────────
  Color get _backgroundColor    => _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _textColor          => _isDarkMode ? Colors.white : const Color(0xFF1E293B);
  Color get _cardColor          => _isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  Color get _borderColor        => _isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get _secondaryTextColor => _isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
  Color get _primaryColor       => const Color(0xFF4F46E5);
  Color get _accentColor        => const Color(0xFF7C73FF);
  Color get _inputFill          => _isDarkMode ? const Color(0xFF2D3748) : Colors.grey.shade50;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    loadSupervisorAndGuards();
  }


  Future<bool> _checkPermission(Permission perm, String label) async {
    PermissionStatus status = await perm.status;
    if (status.isDenied) status = await perm.request();
    if (status.isGranted || status == PermissionStatus.limited) return true;
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

    // Re-check after returning from Settings — Android caches the old denied status.
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
    _titleController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  // ── Init ───────────────────────────────────────────────────────────────────
  Future<void> loadSupervisorAndGuards() async {
    final prefs = await SharedPreferences.getInstance();
    _supervisorId = prefs.getInt('userId');
    try {
      final guards = await _service.getAllGuards();
      if (mounted) setState(() => _guards = guards);
    } catch (e) {
      if (mounted) _snack('Failed to load guards: $e', color: Colors.redAccent);
    }
  }

  void _snack(String msg, {Color color = Colors.redAccent}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: color, content: Text(msg)),
    );
  }

  // ── Permissions ────────────────────────────────────────────────────────────


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

  // ── Copy to stable temp path ───────────────────────────────────────────────
  Future<File> _copyToTemp(String sourcePath, {required String ext}) async {
    try {
      final dir  = await getTemporaryDirectory();
      final dest = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.$ext';
      return await File(sourcePath).copy(dest);
    } catch (_) {
      return File(sourcePath);
    }
  }

  // ── Pick image — locked, stable path, imageQuality replaces flutter_image_compress ──
  Future<void> _pickImage(ImageSource source) async {
    if (_isPickingMedia || _loading) return;

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
      try {
        picked = await _picker.pickImage(source: source, imageQuality: 85);
      } catch (_) { return; }
      if (picked == null || !mounted) return;

      final File stableFile = await _copyToTemp(picked.path, ext: 'jpg');
      setState(() => _mediaItems.add(_MediaItem(file: stableFile, isVideo: false)));
    } finally {
      if (mounted) setState(() => _isPickingMedia = false);
    }
  }

  // ── Pick video from gallery — locked, shows immediately, thumb async ───────
  Future<void> _pickVideo(ImageSource source) async {
    if (_isPickingMedia || _loading) return;

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

  // ── Pick video from camera — quality sheet first, then locked ─────────────
  Future<void> _pickVideoCamera() async {
    if (_isPickingMedia || _loading) return;

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
            Center(child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: _borderColor, borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 16),
            Text("Select Video Quality", style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w700)),
            Text("Higher quality = larger file & slower upload", style: TextStyle(color: _secondaryTextColor, fontSize: 12)),
            const SizedBox(height: 16),
            _qualityTile(Icons.sd,           Colors.green,      "Low",    "~360p · Smallest file, fastest upload", VideoQuality.LowQuality),
            _qualityTile(Icons.hd,           Colors.orange,     "Medium", "~480p · Good balance",                  VideoQuality.MediumQuality),
            _qualityTile(Icons.high_quality, Colors.blueAccent, "High",   "~720p · Recommended for evidence",      VideoQuality.HighestQuality),
          ],
        ),
      ),
    );

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

  // ── Thumbnail generation (async, never blocks UI) ─────────────────────────


  Future<void> _generateThumb(_MediaItem item) async {
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: item.file.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 300,
        quality: 70,
      );
      if (!mounted) return;
      setState(() {
        item.videoThumb   = bytes;
        item.thumbLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => item.thumbLoading = false);
    }
  }

  // ── Submit ─────────────────────────────────────────────────────────────────
  Future<void> submitStatement() async {
    if (_loading) return;

    if (_titleController.text.isEmpty ||
        _descriptionController.text.isEmpty ||
        _categoryController.text.isEmpty ||
        _selectedGuardId == null ||
        _supervisorId == null) {
      _snack('All fields are required');
      return;
    }

    setState(() { _loading = true; _uploadProgress = 0.0; _cancelRequested = false; });

    try {
      final payload = {
        'title':        _titleController.text.trim(),
        'description':  _descriptionController.text.trim(),
        'category':     _categoryController.text.trim(),
        'supervisorId': _supervisorId,
        'guardId':      _selectedGuardId,
      };

      final List<File> files = _mediaItems.map((m) => m.uploadFile).toList();
      await _service.uploadStatementDio(payload, files, (sent, total) {
        if (total > 0 && mounted) setState(() => _uploadProgress = sent / total);
        if (_cancelRequested) throw Exception('Upload cancelled by user');
      });

      if (mounted) {
        _snack('Statement uploaded successfully', color: Colors.greenAccent);
        _titleController.clear();
        _descriptionController.clear();
        _categoryController.clear();
        setState(() { _selectedGuardId = null; _mediaItems.clear(); _uploadProgress = 0.0; });
      }
    } on DioException catch (e) {
      if (_cancelRequested) {
        if (mounted) _snack('Upload cancelled', color: Colors.orange);
      } else {
        _snack('Upload failed: \${e.response?.data ?? e.message}');
      }
    } catch (e) {
      if (_cancelRequested) {
        if (mounted) _snack('Upload cancelled', color: Colors.orange);
      } else {
        _snack('Error: \$e');
      }
    } finally {
      if (mounted) setState(() { _loading = false; _uploadProgress = 0.0; _cancelRequested = false; });
    }
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────
  InputDecoration _input(String label) => InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: _secondaryTextColor, fontWeight: FontWeight.w500),
    filled: true, fillColor: _inputFill,
    border:        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _borderColor)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _borderColor)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _primaryColor, width: 2)),
  );

  // Locked-aware media button — all four buttons grey + spinner when picking
  Widget _mediaButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final bool locked = _isPickingMedia || _loading;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color:  locked ? Colors.grey.withOpacity(0.08) : color.withOpacity(0.1),
          border: Border.all(color: locked ? Colors.grey.withOpacity(0.2) : color.withOpacity(0.3)),
        ),
        child: Material(color: Colors.transparent, child: InkWell(
          onTap: locked ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              locked
                  ? SizedBox(width: 26, height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: color.withOpacity(0.4)))
                  : Icon(icon, size: 26, color: color),
              const SizedBox(height: 6),
              Text(label, textAlign: TextAlign.center,
                  style: TextStyle(
                    color: locked ? Colors.grey.withOpacity(0.4) : color,
                    fontSize: 11, fontWeight: FontWeight.w600,
                  )),
            ]),
          ),
        )),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: _loading,
      child: Scaffold(
        backgroundColor: _backgroundColor,
        body: SafeArea(
          child: Stack(children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Upload Counseling Statement',
                    style: TextStyle(color: _textColor, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                _buildFormCard(),
                const SizedBox(height: 20),
                _buildAttachmentsCard(),
                const SizedBox(height: 30),
                _buildSubmitButton(),
                const SizedBox(height: 40),
              ]),
            ),

            if (_loading)
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
                        onPressed: () => setState(() => _cancelRequested = true),
                        icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 18),
                        label: const Text('Cancel Upload', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20), color: _cardColor, border: Border.all(color: _borderColor)),
      child: Column(children: [
        TextFormField(controller: _titleController, decoration: _input('Title'),
            style: TextStyle(color: _textColor)),
        const SizedBox(height: 16),
        TextFormField(controller: _descriptionController, maxLines: 4,
            decoration: _input('Description'), style: TextStyle(color: _textColor)),
        const SizedBox(height: 16),
        TextFormField(controller: _categoryController, decoration: _input('Category'),
            style: TextStyle(color: _textColor)),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          value: _selectedGuardId,
          dropdownColor: _cardColor,
          decoration: _input('Select Guard'),
          items: _guards.map((g) => DropdownMenuItem<int>(
            value: g['id'],
            child: Text('${g['firstName']} ${g['lastName']}', style: TextStyle(color: _textColor)),
          )).toList(),
          onChanged: _loading ? null : (val) => setState(() => _selectedGuardId = val),
        ),
      ]),
    );
  }

  Widget _buildAttachmentsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20), color: _cardColor, border: Border.all(color: _borderColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.photo_library, color: _primaryColor, size: 20),
          const SizedBox(width: 8),
          Text('Attachments', style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        const SizedBox(height: 8),
        // Tip banner — same style as report_page
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.withOpacity(0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, color: Colors.amber, size: 15),
            const SizedBox(width: 8),
            Expanded(child: Text(
              "Set camera quality to 720p or 1080p before recording for faster uploads",
              style: TextStyle(color: Colors.amber.shade300, fontSize: 12),
            )),
          ]),
        ),
        const SizedBox(height: 16),

        // 4 media buttons — locked together while any pick is in progress
        Row(children: [
          _mediaButton(icon: Icons.photo_library_rounded, label: 'Gallery\nPhoto',
              color: _primaryColor,                    onTap: () => _pickImage(ImageSource.gallery)),
          _mediaButton(icon: Icons.camera_alt_rounded,   label: 'Camera\nPhoto',
              color: const Color(0xFF3B82F6),           onTap: () => _pickImage(ImageSource.camera)),
          _mediaButton(icon: Icons.video_library,        label: 'Gallery\nVideo',
              color: Colors.orange,                     onTap: () => _pickVideo(ImageSource.gallery)),
          _mediaButton(icon: Icons.videocam,             label: 'Record\nVideo',
              color: Colors.redAccent,                  onTap: _pickVideoCamera),
        ]),

        if (_mediaItems.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('${_mediaItems.length} file${_mediaItems.length != 1 ? 's' : ''} selected',
              style: TextStyle(color: _secondaryTextColor, fontSize: 12)),
          const SizedBox(height: 8),
          _buildGrid(),
        ],
      ]),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
      itemCount: _mediaItems.length,
      itemBuilder: (_, i) {
        final item = _mediaItems[i];

        Widget thumb;
        if (item.isVideo) {
          if (item.thumbLoading) {
            thumb = Container(
              color: const Color(0xFF1a1a2e),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
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
                const Text("Loading...", style: TextStyle(color: Colors.white38, fontSize: 10)),
              ]),
            );
          } else if (item.videoThumb != null) {
            thumb = Stack(fit: StackFit.expand, children: [
              Image.memory(item.videoThumb!, fit: BoxFit.cover),
              const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 38,
                  shadows: [Shadow(blurRadius: 8, color: Colors.black54)])),
            ]);
          } else {
            thumb = Container(
              color: const Color(0xFF1a1a2e),
              child: const Center(child: Icon(Icons.videocam, color: Colors.white54, size: 36)),
            );
          }
        } else {
          thumb = Image.file(item.file, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.grey[800],
                child: const Center(child: Icon(Icons.image, color: Colors.white54, size: 36)),
              ));
        }

        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _LocalMediaFullScreen(file: item.file, isVideo: item.isVideo))),
          child: Stack(fit: StackFit.expand, children: [
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
          ]),
        );
      },
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: [_primaryColor, _accentColor]),
        boxShadow: [BoxShadow(color: _primaryColor.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _loading ? null : () async {
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
                  Text('Submit Statement',
                      style: TextStyle(color: _textColor, fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text(
                    'Are you sure you want to submit this counseling statement? This action cannot be undone.',
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
            if (confirmed == true) submitStatement();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              const Text('Submit Statement',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ])),
          ),
        ),
      ),
    );
  }
}

// ── Full-screen viewer for local files ────────────────────────────────────────
class _LocalMediaFullScreen extends StatefulWidget {
  final File file;
  final bool isVideo;
  const _LocalMediaFullScreen({required this.file, required this.isVideo});

  @override
  State<_LocalMediaFullScreen> createState() => _LocalMediaFullScreenState();
}

class _LocalMediaFullScreenState extends State<_LocalMediaFullScreen> {
  VideoPlayerController? _ctrl;
  bool _ready = false, _error = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      _ctrl = VideoPlayerController.file(widget.file);
      await _ctrl!.initialize();
      setState(() => _ready = true);
      _ctrl!.play();
    } catch (_) { setState(() => _error = true); }
  }

  @override
  void dispose() { _ctrl?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.isVideo ? 'Video Preview' : 'Photo Preview',
            style: const TextStyle(color: Colors.white)),
      ),
      body: Center(child: widget.isVideo ? _video() : _image()),
      floatingActionButton: widget.isVideo && _ready
          ? FloatingActionButton(
          backgroundColor: Colors.white24,
          onPressed: () => setState(() =>
          _ctrl!.value.isPlaying ? _ctrl!.pause() : _ctrl!.play()),
          child: Icon(_ctrl!.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white))
          : null,
    );
  }

  Widget _image() => InteractiveViewer(minScale: 0.5, maxScale: 5,
      child: Image.file(widget.file, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 80)));

  Widget _video() {
    if (_error) return const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
      SizedBox(height: 16),
      Text('Could not play video', style: TextStyle(color: Colors.white54)),
    ]);
    if (!_ready) return const CircularProgressIndicator(color: Colors.white);
    return AspectRatio(aspectRatio: _ctrl!.value.aspectRatio, child: VideoPlayer(_ctrl!));
  }
}