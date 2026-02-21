import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/report.dart';
import '../services/report.service.dart';

class ReportListPage extends StatefulWidget {
  const ReportListPage({super.key});

  @override
  State<ReportListPage> createState() => _ReportListPageState();
}

class _ReportListPageState extends State<ReportListPage> {
  final ReportService _service = ReportService();
  bool loading = true;
  List<Report> reports = [];
  bool _isDarkMode = true;

  Color get _backgroundColor => _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _textColor => _isDarkMode ? Colors.white : const Color(0xFF1E293B);
  Color get _cardColor => _isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  Color get _borderColor => _isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get _secondaryTextColor => _isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
  Color get _iconColor => _isDarkMode ? const Color(0xFF64B5F6) : const Color(0xFF2196F3);

  @override
  void initState() {
    super.initState();
    fetchReports();
  }

  bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm');
  }

  Widget _buildVideoThumbnail() {
    return Container(
      width: 110,
      height: 110,
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.videocam, color: Colors.white54, size: 32),
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('VIDEO',
                  style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
            ),
          ),
          const Icon(Icons.play_circle_fill, color: Colors.white, size: 40),
        ],
      ),
    );
  }

  void _openMediaFullScreen(String url, bool isVideo) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MediaFullScreenPage(url: url, isVideo: isVideo),
      ),
    );
  }

  Future<void> fetchReports() async {
    try {
      final data = await _service.getReports();
      setState(() {
        reports = data;
        loading = false;
      });
    } catch (e) {
      setState(() => loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Failed to load reports'), backgroundColor: _cardColor),
        );
      }
    }
  }

  void openReportDetails(Report report) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            controller: controller,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 50,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _secondaryTextColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(report.type,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _textColor)),
                Divider(color: _borderColor),
                _infoRow("Date", report.dateEntered),
                _infoRow("Client", report.client),
                _infoRow("Site", report.site),
                _infoRow("Officer", report.officer),
                const SizedBox(height: 12),
                Text("Details", style: TextStyle(fontWeight: FontWeight.bold, color: _textColor)),
                ...report.raw.entries
                    .where((e) => !['id', 'type', 'client', 'site', 'officer', 'images', 'dateEntered']
                    .contains(e.key))
                    .map((e) => _infoRow(e.key.replaceAll('_', ' '), e.value.toString())),
                if (report.images.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text("Media", style: TextStyle(fontWeight: FontWeight.bold, color: _textColor)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 110,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: report.images.length,
                      itemBuilder: (_, i) {
                        final url = report.images[i];
                        final isVideo = _isVideoUrl(url);
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => _openMediaFullScreen(url, isVideo),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: isVideo
                                  ? _buildVideoThumbnail()
                                  : Image.network(
                                url,
                                width: 110,
                                height: 110,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 110,
                                  height: 110,
                                  color: _borderColor,
                                  child: Center(
                                    child: Icon(Icons.broken_image, color: _secondaryTextColor),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text("$label:", style: TextStyle(color: _secondaryTextColor, fontSize: 14)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                style: TextStyle(fontWeight: FontWeight.w500, color: _textColor, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(Report report) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: _borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(_isDarkMode ? 0.1 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => openReportDetails(report),
          borderRadius: BorderRadius.circular(15),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.description, color: _iconColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(report.type,
                          style: TextStyle(
                              color: _textColor, fontSize: 16, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                          "${report.site ?? 'No Site'} • ${report.dateEntered ?? 'No Date'}",
                          style: TextStyle(color: _secondaryTextColor, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      if (report.client != null && report.client!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text("Client: ${report.client!}",
                            style: TextStyle(color: _secondaryTextColor, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, size: 16, color: _secondaryTextColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String value, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: _cardColor,
        border: Border.all(color: _borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 16, color: color),
              ),
              const Spacer(),
              Text(value,
                  style: TextStyle(color: _textColor, fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: _secondaryTextColor, fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: _cardColor,
                  border: Border.all(color: _borderColor, width: 1),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _iconColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.description, size: 32, color: _iconColor),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Reports",
                              style: TextStyle(
                                  color: _textColor, fontSize: 20, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(
                              "${reports.length} report${reports.length != 1 ? 's' : ''} found",
                              style: TextStyle(color: _secondaryTextColor, fontSize: 14)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Stats
              Row(
                children: [
                  Expanded(
                      child: _buildStatCard(
                          reports.length.toString(), "Total Reports", Icons.description, _iconColor)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _buildStatCard(
                          reports
                              .where((r) => r.dateEntered != null && r.dateEntered!.isNotEmpty)
                              .length
                              .toString(),
                          "With Date",
                          Icons.calendar_today,
                          const Color(0xFF10B981))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _buildStatCard(
                          reports.where((r) => r.images.isNotEmpty).length.toString(),
                          "With Media",
                          Icons.photo,
                          const Color(0xFFF59E0B))),
                ],
              ),

              const SizedBox(height: 20),

              // Refresh
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: fetchReports,
                  icon: const Icon(Icons.refresh, size: 20),
                  label: const Text("Refresh Reports",
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _cardColor,
                    foregroundColor: _textColor,
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(color: _borderColor, width: 1),
                    ),
                    elevation: 0,
                  ),
                ),
              ),

              const SizedBox(height: 25),

              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text("All Reports",
                    style: TextStyle(
                        color: _textColor, fontSize: 18, fontWeight: FontWeight.w700)),
              ),

              const SizedBox(height: 12),

              if (loading)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: CircularProgressIndicator(color: _iconColor),
                  ),
                )
              else if (reports.isEmpty)
                Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: _cardColor,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: _borderColor, width: 1),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.inbox_outlined, size: 64, color: _secondaryTextColor),
                      const SizedBox(height: 16),
                      Text("No reports found",
                          style: TextStyle(
                              color: _textColor, fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text("Create your first report or check your connection",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _secondaryTextColor, fontSize: 14)),
                    ],
                  ),
                )
              else
                Column(children: reports.map((r) => _buildReportCard(r)).toList()),

              const SizedBox(height: 90),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen viewer — network URLs from backend
// ─────────────────────────────────────────────────────────────────────────────
class _MediaFullScreenPage extends StatefulWidget {
  final String url;
  final bool isVideo;

  const _MediaFullScreenPage({required this.url, required this.isVideo});

  @override
  State<_MediaFullScreenPage> createState() => _MediaFullScreenPageState();
}

class _MediaFullScreenPageState extends State<_MediaFullScreenPage> {
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
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
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
        title: Text(widget.isVideo ? 'Video' : 'Photo',
            style: const TextStyle(color: Colors.white)),
      ),
      body: Center(child: widget.isVideo ? _buildVideo() : _buildImage()),
      floatingActionButton: widget.isVideo && _initialized
          ? FloatingActionButton(
        backgroundColor: Colors.white24,
        onPressed: () => setState(() {
          _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
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
      child: Image.network(
        widget.url,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
        const Icon(Icons.broken_image, color: Colors.white54, size: 80),
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
          Text('Could not load video', style: TextStyle(color: Colors.white54)),
        ],
      );
    }
    if (!_initialized) return const CircularProgressIndicator(color: Colors.white);
    return AspectRatio(
      aspectRatio: _controller!.value.aspectRatio,
      child: VideoPlayer(_controller!),
    );
  }
}