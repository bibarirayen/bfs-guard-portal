import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/counseling_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

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

  bool _isDarkMode = true;
  bool _loading = false;

  List<Map<String, dynamic>> _guards = [];
  int? _selectedGuardId;
  int? _supervisorId;
  List<File> _files = [];

  // -------- THEME --------
  Color get _backgroundColor =>
      _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _textColor =>
      _isDarkMode ? Colors.white : const Color(0xFF1E293B);
  Color get _cardColor =>
      _isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  Color get _borderColor =>
      _isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get _secondaryTextColor =>
      _isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
  Color get _primaryColor => const Color(0xFF4F46E5);
  Color get _accentColor => const Color(0xFF7C73FF);

  @override
  void initState() {
    super.initState();
    loadSupervisorAndGuards();
  }

  Future<void> loadSupervisorAndGuards() async {
    final prefs = await SharedPreferences.getInstance();
    _supervisorId = prefs.getInt('userId');

    try {
      final guards = await _service.getAllGuards();
      setState(() => _guards = guards);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text("Failed to load guards: $e"),
        ),
      );
    }
  }
  Future<bool> _requestPermissions(ImageSource source, {bool forVideo = false}) async {
    // iOS: image_picker handles permissions automatically
    if (Platform.isIOS) {
      return true; // Let image_picker handle iOS permissions
    }

    // Android: Manual permission handling
    PermissionStatus status;

    if (source == ImageSource.camera) {
      // Camera permission
      status = await Permission.camera.request();

      if (forVideo) {
        PermissionStatus micStatus = await Permission.microphone.request();
        if (!micStatus.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Please grant microphone permission to record videos"),
              backgroundColor: Colors.redAccent,
            ),
          );
          return false;
        }
      }
    } else {
      // Gallery permission
      if (await Permission.photos.isGranted || await Permission.storage.isGranted) {
        return true;
      }
      status = await Permission.photos.request();
    }

    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(forVideo
              ? "Please grant permission to access videos"
              : "Please grant permission to access images"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return false;
    }

    return true;
  }

  Future<void> pickImages() async {
    bool granted = await _requestPermissions(ImageSource.gallery);
    if (!granted) return;

    if (await Permission.photos.isPermanentlyDenied ||
        await Permission.storage.isPermanentlyDenied) {
      openAppSettings();
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickMultiImage();

    if (picked != null) {
      setState(() {
        _files.addAll(picked.map((e) => File(e.path)));
      });
    }
  }

  Future<void> pickVideo(ImageSource source) async {
    bool granted = await _requestPermissions(source, forVideo: true);
    if (!granted) return;

    final picker = ImagePicker();
    final picked = await picker.pickVideo(
      source: source,
      maxDuration: const Duration(minutes: 60),
    );

    if (picked != null) {
      setState(() {
        _files.add(File(picked.path));
      });
    }
  }

  Future<void> pickFiles() async {
    // kept for compatibility — delegates to pickImages
    await pickImages();
  }

  Future<void> submitStatement() async {
    if (_titleController.text.isEmpty ||
        _descriptionController.text.isEmpty ||
        _categoryController.text.isEmpty ||
        _selectedGuardId == null ||
        _supervisorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text("All fields are required"),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      Map<String, dynamic> payload = {
        "title": _titleController.text,
        "description": _descriptionController.text,
        "category": _categoryController.text,
        "supervisorId": _supervisorId,
        "guardId": _selectedGuardId,
      };

      final res = await _service.uploadStatement(payload, _files);

      if (res.statusCode == 200 || res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.greenAccent,
            content: Text("Statement uploaded successfully"),
          ),
        );

        _titleController.clear();
        _descriptionController.clear();
        _categoryController.clear();

        setState(() {
          _selectedGuardId = null;
          _files.clear();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text("Upload failed"),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text("Error: $e"),
        ),
      );
    }

    setState(() => _loading = false);
  }

  Widget _buildMediaButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: color.withOpacity(0.1),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _modernInput(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: _secondaryTextColor,
        fontWeight: FontWeight.w500,
      ),
      filled: true,
      fillColor: _isDarkMode ? const Color(0xFF2D3748) : Colors.grey[50],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _primaryColor, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Text(
                "Upload Counseling Statement",
                style: TextStyle(
                  color: _textColor,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: _cardColor,
                  border: Border.all(color: _borderColor),
                ),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _titleController,
                      decoration: _modernInput("Title"),
                      style: TextStyle(color: _textColor),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 4,
                      decoration: _modernInput("Description"),
                      style: TextStyle(color: _textColor),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _categoryController,
                      decoration: _modernInput("Category"),
                      style: TextStyle(color: _textColor),
                    ),
                    const SizedBox(height: 16),

                    DropdownButtonFormField<int>(
                      value: _selectedGuardId,
                      dropdownColor: _cardColor,
                      decoration: _modernInput("Select Guard"),
                      items: _guards.map((g) {
                        return DropdownMenuItem<int>(
                          value: g['id'],
                          child: Text(
                            "${g['firstName']} ${g['lastName']}",
                            style: TextStyle(color: _textColor),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setState(() => _selectedGuardId = val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Attachments
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: _cardColor,
                  border: Border.all(color: _borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.photo_library, color: _primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        "Attachments",
                        style: TextStyle(
                          color: _textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      "Upload images or videos for this counseling statement",
                      style: TextStyle(color: _secondaryTextColor, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildMediaButton(
                            icon: Icons.photo_library_rounded,
                            label: "Gallery\nImages",
                            color: _primaryColor,
                            onTap: pickImages,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMediaButton(
                            icon: Icons.video_library,
                            label: "Gallery\nVideo",
                            color: Colors.orange,
                            onTap: () => pickVideo(ImageSource.gallery),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMediaButton(
                            icon: Icons.videocam,
                            label: "Record\nVideo",
                            color: Colors.redAccent,
                            onTap: () => pickVideo(ImageSource.camera),
                          ),
                        ),
                      ],
                    ),
                    if (_files.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        "${_files.length} file${_files.length > 1 ? 's' : ''} selected",
                        style: TextStyle(color: _secondaryTextColor, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: _files.length,
                        itemBuilder: (context, index) {
                          final file = _files[index];
                          final ext = file.path.split('.').last.toLowerCase();
                          final isVideo = ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext);
                          return GestureDetector(
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => _LocalMediaFullScreenPage(file: file, isVideo: isVideo),
                            )),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: isVideo
                                      ? Container(
                                    color: Colors.black,
                                    child: const Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.play_circle_fill, color: Colors.white, size: 40),
                                        SizedBox(height: 4),
                                        Text('VIDEO', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  )
                                      : Image.file(
                                    file,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Colors.grey[800],
                                      child: const Icon(Icons.broken_image, color: Colors.white54),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 5,
                                  right: 5,
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => _files.removeAt(index)),
                                    child: const CircleAvatar(
                                      radius: 12,
                                      backgroundColor: Colors.red,
                                      child: Icon(Icons.close,
                                          size: 14, color: Colors.white),
                                    ),
                                  ),
                                )
                              ],
                            ),
                          );
                        },
                      ),
                    ]
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // Submit Button
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: [_primaryColor, _accentColor],
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _loading ? null : submitStatement,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: _loading
                          ? const CircularProgressIndicator(
                        color: Colors.white,
                      )
                          : const Text(
                        "Submit Statement",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen viewer for LOCAL files (picked from device)
// ─────────────────────────────────────────────────────────────────────────────
class _LocalMediaFullScreenPage extends StatefulWidget {
  final File file;
  final bool isVideo;

  const _LocalMediaFullScreenPage({required this.file, required this.isVideo});

  @override
  State<_LocalMediaFullScreenPage> createState() => _LocalMediaFullScreenPageState();
}

class _LocalMediaFullScreenPageState extends State<_LocalMediaFullScreenPage> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      _controller = VideoPlayerController.file(widget.file);
      await _controller!.initialize();
      setState(() => _initialized = true);
      _controller!.play();
    } catch (_) {
      setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.isVideo ? 'Video Preview' : 'Photo Preview',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Center(
        child: widget.isVideo ? _buildVideo() : _buildImage(),
      ),
      floatingActionButton: widget.isVideo && _initialized
          ? FloatingActionButton(
        backgroundColor: Colors.white24,
        onPressed: () => setState(() {
          _controller!.value.isPlaying
              ? _controller!.pause()
              : _controller!.play();
        }),
        child: Icon(
          _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
          color: Colors.white,
        ),
      )
          : null,
    );
  }

  Widget _buildImage() {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5.0,
      child: Image.file(
        widget.file,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 80),
      ),
    );
  }

  Widget _buildVideo() {
    if (_error) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
          SizedBox(height: 16),
          Text('Could not play video', style: TextStyle(color: Colors.white54)),
        ],
      );
    }
    if (!_initialized) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    return AspectRatio(
      aspectRatio: _controller!.value.aspectRatio,
      child: VideoPlayer(_controller!),
    );
  }
}