import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_compress/video_compress.dart';
import '../services/counseling_service.dart';

/// Holds a media file + optional pre-generated video thumbnail bytes.
class _MediaItem {
  File file;
  final bool isVideo;
  Uint8List? thumbnail;
  bool isCompressing;
  double compressionProgress; // 0.0 → 1.0
  File? compressedFile;
  bool compressionFailed;

  _MediaItem({required this.file, required this.isVideo, this.thumbnail})
      : isCompressing = false,
        compressionProgress = 0.0,
        compressionFailed = false;

  File get uploadFile => compressedFile ?? file;
}

class CounselingUploadPage extends StatefulWidget {
  const CounselingUploadPage({super.key});

  @override
  State<CounselingUploadPage> createState() => _CounselingUploadPageState();
}

class _CounselingUploadPageState extends State<CounselingUploadPage> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _categoryController = TextEditingController();
  final _service = CounselingService();
  final _picker = ImagePicker();

  bool _isDarkMode = true;
  bool _loading = false;
  double _uploadProgress = 0.0;

  List<Map<String, dynamic>> _guards = [];
  int? _selectedGuardId;
  int? _supervisorId;
  List<_MediaItem> _mediaItems = [];

  // Tracks background compression futures: index → Future<File>
  final Map<int, Future<File>> _pendingCompressions = {};

  // ── Theme ──────────────────────────────────────────────────────────────────
  Color get _backgroundColor => _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _textColor => _isDarkMode ? Colors.white : const Color(0xFF1E293B);
  Color get _cardColor => _isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  Color get _borderColor => _isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get _secondaryTextColor => _isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
  Color get _primaryColor => const Color(0xFF4F46E5);
  Color get _accentColor => const Color(0xFF7C73FF);
  Color get _inputFill => _isDarkMode ? const Color(0xFF2D3748) : Colors.grey.shade50;

  @override
  void initState() {
    super.initState();
    loadSupervisorAndGuards();
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

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _snack(String msg, {Color color = Colors.redAccent}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: color, content: Text(msg)),
    );
  }

  // ── Image compression ─────────────────────────────────────────────────────
  // iOS  → HEIC (hardware encoder, ~10× faster than JPEG, same visual quality)
  // Android → JPEG quality 82, cap at 1280px on the longest side.
  // minWidth/minHeight = 0 so small images are never upscaled.
  Future<File> _compressImage(File file) async {
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final bool useHeic = Platform.isIOS;
    final String ext = useHeic ? 'heic' : 'jpg';
    final target = '${dir.path}/$ts.$ext';

    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      target,
      quality: 82,
      minWidth: 0,
      minHeight: 0,
      format: useHeic ? CompressFormat.heic : CompressFormat.jpeg,
    );
    return result == null ? file : File(result.path);
  }

  // ── Video compression queue ───────────────────────────────────────────────
  // Queued so multiple picked videos compress one-at-a-time (video_compress is single-threaded)
  final List<({_MediaItem item, int index})> _compressionQueue = [];
  bool _compressionRunning = false;

  void _queueVideoCompression(_MediaItem item, int index) {
    if (!mounted) return;
    setState(() {
      item.isCompressing = true;
      item.compressionProgress = 0.01;
    });
    _compressionQueue.add((item: item, index: index));
    if (!_compressionRunning) _runCompressionQueue();
  }

  Future<void> _runCompressionQueue() async {
    _compressionRunning = true;
    while (_compressionQueue.isNotEmpty) {
      final job = _compressionQueue.removeAt(0);
      await _doCompressVideo(job.item, job.index);
    }
    _compressionRunning = false;
  }

  Future<void> _doCompressVideo(_MediaItem item, int index) async {
    Subscription? sub;
    try {
      sub = VideoCompress.compressProgress$.subscribe((progress) {
        if (mounted && index < _mediaItems.length) {
          setState(() => _mediaItems[index].compressionProgress = (progress / 100.0).clamp(0.01, 0.99));
        }
      });

      final MediaInfo? info = await VideoCompress.compressVideo(
        item.file.path,
        quality: VideoQuality.Res960x540Quality,
        deleteOrigin: false,
        includeAudio: true,
        frameRate: 30,
      );

      if (mounted && index < _mediaItems.length) {
        setState(() {
          _mediaItems[index].compressedFile = info?.file;
          _mediaItems[index].isCompressing = false;
          _mediaItems[index].compressionProgress = 1.0;
          // Update the pending compression future to resolved
        });
        _pendingCompressions.remove(index);
      }
    } catch (_) {
      if (mounted && index < _mediaItems.length) {
        setState(() {
          _mediaItems[index].isCompressing = false;
          _mediaItems[index].compressionFailed = true;
          _mediaItems[index].compressionProgress = 0.0;
        });
        _pendingCompressions.remove(index);
      }
    } finally {
      sub?.unsubscribe();
    }
  }


  // ── Permissions ────────────────────────────────────────────────────────────

  Future<bool> _requestPermissions(ImageSource source, {bool forVideo = false}) async {
    if (Platform.isIOS) return true;

    if (source == ImageSource.camera) {
      if (!(await Permission.camera.request()).isGranted) {
        _snack('Camera permission required');
        return false;
      }
      if (forVideo && !(await Permission.microphone.request()).isGranted) {
        _snack('Microphone permission required for video');
        return false;
      }
      return true;
    }

    // Gallery
    if (await Permission.photos.isGranted || await Permission.storage.isGranted) return true;
    final s = await Permission.photos.request();
    if (!s.isGranted) {
      _snack(forVideo ? 'Video library permission required' : 'Photo library permission required');
      return false;
    }
    return true;
  }

  // ── Pick image ─────────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    if (_loading) return;
    if (!await _requestPermissions(source)) return;

    try {
      final XFile? picked = await _picker.pickImage(source: source);
      if (picked == null) return;

      final File rawFile = File(picked.path);
      final item = _MediaItem(file: rawFile, isVideo: false);
      final int itemIndex = _mediaItems.length;
      // Show immediately in grid
      setState(() => _mediaItems.add(item));

      // Compress in background — swaps file silently when done.
      final Future<File> compressionFuture = _compressImage(rawFile);
      _pendingCompressions[itemIndex] = compressionFuture;
      compressionFuture.then((compressed) {
        _pendingCompressions.remove(itemIndex);
        if (mounted && itemIndex < _mediaItems.length) {
          setState(() => _mediaItems[itemIndex].file = compressed);
        }
      }).catchError((_) { _pendingCompressions.remove(itemIndex); });
    } catch (e) {
      if (!e.toString().toLowerCase().contains('cancel')) _snack('Could not load image');
    }
  }

  // ── Pick video ─────────────────────────────────────────────────────────────

  Future<void> _pickVideo(ImageSource source) async {
    if (_loading) return;
    if (!await _requestPermissions(source, forVideo: true)) return;

    try {
      final XFile? picked = await _picker.pickVideo(source: source, maxDuration: const Duration(minutes: 60));
      if (picked == null) return;

      final File rawFile = File(picked.path);
      final item = _MediaItem(file: rawFile, isVideo: true);
      final int itemIndex = _mediaItems.length;
      // Show immediately in grid — no blocking
      setState(() => _mediaItems.add(item));

      // Generate thumbnail in background
      VideoCompress.getByteThumbnail(rawFile.path, quality: 50).then((bytes) {
        if (mounted && bytes != null && itemIndex < _mediaItems.length) {
          setState(() => _mediaItems[itemIndex].thumbnail = bytes);
        }
      }).catchError((_) {});

      // Compress in background via queue — buttons stay active
      // Use a completer so submitStatement can await it if needed
      final completer = Completer<File>();
      _pendingCompressions[itemIndex] = completer.future;
      _queueVideoCompression(item, itemIndex);
      // Resolve completer when compression finishes (polled in submitStatement)
    } catch (e) {
      if (!e.toString().toLowerCase().contains('cancel')) _snack('Could not load video');
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

    setState(() { _loading = true; _uploadProgress = 0.0; });

    try {
      // If background compressions are still running, wait for them first.
      if (_mediaItems.any((m) => m.isCompressing)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Finishing video compression, please wait a moment...'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 60),
          ));
        }
        final deadline = DateTime.now().add(const Duration(minutes: 5));
        while (_mediaItems.any((m) => m.isCompressing)) {
          if (DateTime.now().isAfter(deadline)) break;
          await Future.delayed(const Duration(milliseconds: 300));
        }
        if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
      }
      _pendingCompressions.clear();

      final payload = {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'category': _categoryController.text.trim(),
        'supervisorId': _supervisorId,
        'guardId': _selectedGuardId,
      };

      final List<File> files = _mediaItems.map((m) => m.uploadFile).toList();
      await _service.uploadStatementDio(payload, files, (sent, total) {
        if (total > 0 && mounted) setState(() => _uploadProgress = sent / total);
      });

      if (mounted) {
        _snack('Statement uploaded successfully', color: Colors.greenAccent);
        _titleController.clear();
        _descriptionController.clear();
        _categoryController.clear();
        _pendingCompressions.clear();
        setState(() { _selectedGuardId = null; _mediaItems.clear(); _uploadProgress = 0.0; });
      }
    } on DioException catch (e) {
      _snack('Upload failed: ${e.response?.data ?? e.message}');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() { _loading = false; _uploadProgress = 0.0; });
    }
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────

  InputDecoration _input(String label) => InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: _secondaryTextColor, fontWeight: FontWeight.w500),
    filled: true, fillColor: _inputFill,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _borderColor)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _borderColor)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _primaryColor, width: 2)),
  );

  Widget _mediaButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: _loading ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: color.withOpacity(0.1),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 26, color: color),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Block all interaction while loading/picking
    return AbsorbPointer(
      absorbing: _loading,
      child: Scaffold(
        backgroundColor: _backgroundColor,
        body: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Text('Upload Counseling Statement',
                        style: TextStyle(color: _textColor, fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),

                    // Form card
                    _buildFormCard(),
                    const SizedBox(height: 20),

                    // Attachments card
                    _buildAttachmentsCard(),
                    const SizedBox(height: 30),

                    // Submit button
                    _buildSubmitButton(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),

              // Full-screen loading overlay while submitting
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
                      ]),
                    ),
                  ),
                ),
            ],
          ),
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
        Text('Tap any thumbnail to preview it full-screen',
            style: TextStyle(color: _secondaryTextColor, fontSize: 12)),
        const SizedBox(height: 16),

        // Picker buttons
        Row(children: [
          _mediaButton(icon: Icons.photo_library_rounded, label: 'Gallery\nPhoto',
              color: _primaryColor, onTap: () => _pickImage(ImageSource.gallery)),
          const SizedBox(width: 8),
          _mediaButton(icon: Icons.camera_alt_rounded, label: 'Camera\nPhoto',
              color: const Color(0xFF3B82F6), onTap: () => _pickImage(ImageSource.camera)),
          const SizedBox(width: 8),
          _mediaButton(icon: Icons.video_library, label: 'Gallery\nVideo',
              color: Colors.orange, onTap: () => _pickVideo(ImageSource.gallery)),
          const SizedBox(width: 8),
          _mediaButton(icon: Icons.videocam, label: 'Record\nVideo',
              color: Colors.redAccent, onTap: () => _pickVideo(ImageSource.camera)),
        ]),

        if (_mediaItems.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('${_mediaItems.length} file${_mediaItems.length != 1 ? 's' : ''} selected',
              style: TextStyle(color: _secondaryTextColor, fontSize: 12)),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
            itemCount: _mediaItems.length,
            itemBuilder: (_, i) {
              final item = _mediaItems[i];

              Widget mediaWidget;
              if (item.isVideo) {
                mediaWidget = item.thumbnail != null
                    ? Stack(fit: StackFit.expand, children: [
                  Image.memory(item.thumbnail!, fit: BoxFit.cover),
                  const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.play_circle_fill, color: Colors.white, size: 38, shadows: [Shadow(blurRadius: 8, color: Colors.black54)]),
                    SizedBox(height: 4),
                    Text('VIDEO', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
                  ])),
                ])
                    : Container(color: Colors.black,
                    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.play_circle_fill, color: Colors.white, size: 38),
                      SizedBox(height: 4),
                      Text('VIDEO', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
                    ]));
              } else {
                mediaWidget = Image.file(item.file, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: _borderColor,
                        child: Icon(Icons.broken_image, color: _secondaryTextColor)));
              }

              return GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _LocalMediaFullScreen(file: item.file, isVideo: item.isVideo))),
                child: Stack(fit: StackFit.expand, children: [
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: mediaWidget),

                  // Compression progress bar
                  if (item.isVideo && item.isCompressing)
                    Positioned(bottom: 0, left: 0, right: 0,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            color: Colors.black54,
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Center(child: Text(
                              '${(item.compressionProgress * 100).toStringAsFixed(0)}%',
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

                  // Compression done badge
                  if (item.isVideo && !item.isCompressing && item.compressedFile != null)
                    Positioned(bottom: 6, left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(color: Colors.green.withOpacity(0.85), borderRadius: BorderRadius.circular(6)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.check, size: 9, color: Colors.white),
                          SizedBox(width: 2),
                          Text('960p', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),

                  // Failed badge (uploads raw)
                  if (item.isVideo && item.compressionFailed)
                    Positioned(bottom: 6, left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(color: Colors.orange.withOpacity(0.85), borderRadius: BorderRadius.circular(6)),
                        child: const Text('raw', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                      ),
                    ),

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
          ),
        ],
      ]),
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
          onTap: _loading ? null : submitStatement,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                const Text('Submit Statement',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen viewer for LOCAL files
// ─────────────────────────────────────────────────────────────────────────────
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
      appBar: AppBar(backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(widget.isVideo ? 'Video Preview' : 'Photo Preview',
              style: const TextStyle(color: Colors.white))),
      body: Center(child: widget.isVideo ? _video() : _image()),
      floatingActionButton: widget.isVideo && _ready
          ? FloatingActionButton(backgroundColor: Colors.white24,
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