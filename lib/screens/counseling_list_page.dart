import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/counseling_service.dart';

class CounselingListPage extends StatefulWidget {
  const CounselingListPage({super.key});

  @override
  State<CounselingListPage> createState() => _CounselingListPageState();
}

class _CounselingListPageState extends State<CounselingListPage> {
  final _service = CounselingService();
  bool _loading = true;
  List<Map<String, dynamic>> _statements = [];
  bool _isDarkMode = true;

  // ── Theme ──────────────────────────────────────────────────────────────────
  Color get _backgroundColor => _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _cardColor => _isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  Color get _textColor => _isDarkMode ? Colors.white : const Color(0xFF1E293B);
  Color get _secondaryTextColor => _isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
  Color get _borderColor => _isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get _primaryColor => const Color(0xFF4F46E5);

  @override
  void initState() {
    super.initState();
    fetchStatements();
  }

  Future<void> fetchStatements() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getAllStatements();
      if (mounted) setState(() => _statements = data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') || lower.endsWith('.mov') ||
        lower.endsWith('.avi') || lower.endsWith('.mkv') || lower.endsWith('.webm');
  }

  String _getSiteName(dynamic site) {
    if (site is Map && site.containsKey('name')) return site['name'];
    if (site is int) return 'Site ID: $site';
    return 'No Site';
  }

  String _getPersonName(dynamic person) {
    if (person is Map && person.containsKey('firstName') && person.containsKey('lastName')) {
      return '${person['firstName']} ${person['lastName']}';
    }
    if (person is int) return 'ID: $person';
    return '-';
  }

  // ── Bottom sheet ───────────────────────────────────────────────────────────

  void _showDetails(Map<String, dynamic> statement) {
    final rawMedia = statement['mediaUrls'];
    final List<String> mediaUrls = rawMedia is List
        ? rawMedia.map((e) => e.toString()).toList()
        : [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Drag handle
            Center(child: Container(
              width: 50, height: 5,
              decoration: BoxDecoration(color: _secondaryTextColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10)),
            )),
            const SizedBox(height: 16),

            Text(statement['title'] ?? 'No Title',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _textColor)),
            const SizedBox(height: 12),

            _infoRow('Supervisor', _getPersonName(statement['supervisor'])),
            _infoRow('Guard', _getPersonName(statement['guard'])),
            _infoRow('Category', statement['category'] ?? '-'),
            _infoRow('Site', _getSiteName(statement['site'])),
            _infoRow('Date', statement['createdAt'] ?? '-'),
            _infoRow('Status', statement['status'] ?? '-'),

            const SizedBox(height: 12),
            Text('Description', style: TextStyle(fontWeight: FontWeight.bold, color: _textColor)),
            const SizedBox(height: 8),
            Text(statement['description'] ?? 'No description',
                style: TextStyle(color: _textColor, height: 1.5)),

            if (mediaUrls.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Media (${mediaUrls.length})',
                  style: TextStyle(fontWeight: FontWeight.bold, color: _textColor)),
              const SizedBox(height: 10),
              SizedBox(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: mediaUrls.length,
                  itemBuilder: (_, i) {
                    final url = mediaUrls[i];
                    final isVideo = _isVideoUrl(url);
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => _NetworkMediaFullScreen(url: url, isVideo: isVideo))),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: isVideo
                              ? _videoThumbnail()
                              : Image.network(url, width: 120, height: 120, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 120, height: 120,
                                color: _borderColor,
                                child: Icon(Icons.broken_image, color: _secondaryTextColor),
                              )),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 30),
          ]),
        ),
      ),
    );
  }

  Widget _videoThumbnail() {
    return Container(
      width: 120, height: 120, color: Colors.black,
      child: Stack(alignment: Alignment.center, children: [
        const Icon(Icons.videocam, color: Colors.white38, size: 30),
        const Icon(Icons.play_circle_fill, color: Colors.white, size: 44),
        Positioned(bottom: 4, left: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
            child: const Text('VIDEO', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 100, child: Text('$label:', style: TextStyle(color: _secondaryTextColor, fontSize: 14))),
        Expanded(child: Text(value, style: TextStyle(fontWeight: FontWeight.w500, color: _textColor, fontSize: 14))),
      ]),
    );
  }

  // ── Card ───────────────────────────────────────────────────────────────────

  Widget _buildCard(Map<String, dynamic> s) {
    final rawMedia = s['mediaUrls'];
    final mediaCount = rawMedia is List ? rawMedia.length : 0;

    return GestureDetector(
      onTap: () => _showDetails(s),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _borderColor),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(_isDarkMode ? 0.1 : 0.05),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.description_outlined, size: 26, color: _primaryColor),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s['title'] ?? 'No Title',
                style: TextStyle(fontWeight: FontWeight.bold, color: _textColor, fontSize: 15),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(_getSiteName(s['site']),
                style: TextStyle(color: _secondaryTextColor, fontSize: 13),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (mediaCount > 0) ...[
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.photo_library_outlined, size: 13, color: _primaryColor),
                const SizedBox(width: 4),
                Text('$mediaCount media file${mediaCount != 1 ? 's' : ''}',
                    style: TextStyle(color: _primaryColor, fontSize: 12, fontWeight: FontWeight.w500)),
              ]),
            ],
          ])),
          Icon(Icons.arrow_forward_ios, size: 16, color: _secondaryTextColor),
        ]),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _primaryColor))
          : _statements.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.inbox_outlined, size: 64, color: _secondaryTextColor),
        const SizedBox(height: 16),
        Text('No statements found', style: TextStyle(color: _textColor, fontSize: 16)),
      ]))
          : RefreshIndicator(
        onRefresh: fetchStatements,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _statements.length,
          itemBuilder: (_, i) => _buildCard(_statements[i]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen viewer for NETWORK URLs (from backend)
// ─────────────────────────────────────────────────────────────────────────────
class _NetworkMediaFullScreen extends StatefulWidget {
  final String url;
  final bool isVideo;
  const _NetworkMediaFullScreen({required this.url, required this.isVideo});

  @override
  State<_NetworkMediaFullScreen> createState() => _NetworkMediaFullScreenState();
}

class _NetworkMediaFullScreenState extends State<_NetworkMediaFullScreen> {
  VideoPlayerController? _ctrl;
  bool _ready = false, _error = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
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
          title: Text(widget.isVideo ? 'Video' : 'Photo',
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
      child: Image.network(widget.url, fit: BoxFit.contain,
          loadingBuilder: (_, child, progress) => progress == null ? child
              : const CircularProgressIndicator(color: Colors.white),
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 80)));

  Widget _video() {
    if (_error) return const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
      SizedBox(height: 16),
      Text('Could not load video', style: TextStyle(color: Colors.white54)),
    ]);
    if (!_ready) return const CircularProgressIndicator(color: Colors.white);
    return AspectRatio(aspectRatio: _ctrl!.value.aspectRatio, child: VideoPlayer(_ctrl!));
  }
}