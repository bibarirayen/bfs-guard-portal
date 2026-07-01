import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notice_service.dart';
import 'notice_photo_viewer.dart';
import 'sop_pdf_viewer_page.dart';

class ExecutiveNoticesArchivePage extends StatefulWidget {
  const ExecutiveNoticesArchivePage({super.key});

  @override
  State<ExecutiveNoticesArchivePage> createState() => _ExecutiveNoticesArchivePageState();
}

class _ExecutiveNoticesArchivePageState extends State<ExecutiveNoticesArchivePage> {
  final _service = NoticeService();

  bool _loading = true;
  String? _error;
  int? _userId;
  List<NoticeArchiveItem> _notices = [];

  static const _bg     = Color(0xFF0B1628);
  static const _card   = Color(0xFF1E293B);
  static const _border = Color(0xFF334155);
  static const _accent = Color(0xFF60A5FA);
  static const _text   = Colors.white;
  static const _sub    = Color(0xFF94A3B8);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      _userId = prefs.getInt('userId');
      if (_userId == null) throw Exception('Not logged in');
      final data = await _service.getMyArchive(_userId!);
      if (mounted) setState(() { _notices = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Failed to load notices.'; _loading = false; });
    }
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) { return iso; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        foregroundColor: _text,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Executive Notices', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('Your notice archive', style: TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  color: _accent,
                  onRefresh: _load,
                  child: _notices.isEmpty ? _buildEmpty() : _buildList(),
                ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _notices.length,
      itemBuilder: (_, i) => _buildCard(_notices[i]),
    );
  }

  Widget _buildCard(NoticeArchiveItem notice) {
    final isRead = notice.acknowledged;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => _NoticeDetailPage(notice: notice)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isRead ? _border : const Color(0xFF1665C1).withOpacity(0.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: isRead
                    ? const Color(0xFF10B981).withOpacity(0.12)
                    : const Color(0xFF1665C1).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isRead ? Icons.check_circle_outline : Icons.notifications_outlined,
                color: isRead ? const Color(0xFF10B981) : _accent,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(notice.title,
                            style: const TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 13),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isRead
                              ? const Color(0xFF10B981).withOpacity(0.12)
                              : const Color(0xFFDC2626).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isRead ? 'Read' : 'Unread',
                          style: TextStyle(
                            color: isRead ? const Color(0xFF10B981) : const Color(0xFFFC8181),
                            fontSize: 10, fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(notice.content,
                      style: const TextStyle(color: _sub, fontSize: 12, height: 1.4),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.person_outline, color: _sub, size: 11),
                      const SizedBox(width: 3),
                      Text(notice.createdByName, style: const TextStyle(color: _sub, fontSize: 11)),
                      const SizedBox(width: 8),
                      const Icon(Icons.access_time, color: _sub, size: 11),
                      const SizedBox(width: 3),
                      Text(_formatDate(notice.createdAt), style: const TextStyle(color: _sub, fontSize: 11)),
                      if (notice.attachmentUrls.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.attach_file, color: _sub, size: 11),
                        const SizedBox(width: 2),
                        Text('${notice.attachmentUrls.length}',
                            style: const TextStyle(color: _sub, fontSize: 11)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: _sub, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.notifications_none, size: 56, color: _sub.withOpacity(0.4)),
              const SizedBox(height: 12),
              const Text('No executive notices yet.', style: TextStyle(color: _sub)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 48),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: _sub)),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accent),
            onPressed: _load,
            child: const Text('Retry', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ── Notice Detail ─────────────────────────────────────────────────────────────

class _NoticeDetailPage extends StatefulWidget {
  final NoticeArchiveItem notice;
  const _NoticeDetailPage({required this.notice});

  @override
  State<_NoticeDetailPage> createState() => _NoticeDetailPageState();
}

class _NoticeDetailPageState extends State<_NoticeDetailPage> {
  Map<String, String> _authHeaders = {};

  static const _bg      = Color(0xFF0B1628);
  static const _card    = Color(0xFF1E293B);
  static const _border  = Color(0xFF334155);
  static const _accent  = Color(0xFF60A5FA);
  static const _text    = Colors.white;
  static const _sub     = Color(0xFF94A3B8);
  static const _primary = Color(0xFF1665C1);

  @override
  void initState() {
    super.initState();
    _loadHeaders();
  }

  Future<void> _loadHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt') ?? '';
    if (token.isNotEmpty && mounted) {
      setState(() => _authHeaders = {'Authorization': 'Bearer $token'});
    }
  }

  bool _isPdf(String url) => url.toLowerCase().endsWith('.pdf');
  List<String> get _images => widget.notice.attachmentUrls.where((u) => !_isPdf(u)).toList();
  List<String> get _pdfs   => widget.notice.attachmentUrls.where(_isPdf).toList();

  void _openPhotoViewer(int index) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => NoticePhotoViewer(imageUrls: _images, initialIndex: index),
    ));
  }

  void _openPdf(String url) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SopPdfViewerPage(
        url: url,
        fileName: url.split('/').last,
        siteName: widget.notice.title,
      ),
    ));
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) { return iso; }
  }

  @override
  Widget build(BuildContext context) {
    final notice = widget.notice;
    final isRead = notice.acknowledged;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        foregroundColor: _text,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _primary.withOpacity(0.15),
                border: Border.all(color: _accent.withOpacity(0.3)),
              ),
              child: const Icon(Icons.shield_outlined, color: _accent, size: 15),
            ),
            const SizedBox(width: 8),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Executive Notice',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                Text('Black Fabric Security',
                    style: TextStyle(fontSize: 10, color: Colors.white54)),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12, top: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isRead
                  ? const Color(0xFF10B981).withOpacity(0.12)
                  : const Color(0xFFDC2626).withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isRead ? '✓ Read' : 'Unread',
              style: TextStyle(
                color: isRead ? const Color(0xFF10B981) : const Color(0xFFFC8181),
                fontSize: 11, fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Target badge
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: notice.targetType == 'ALL'
                    ? const Color(0xFF6366F1).withOpacity(0.12)
                    : const Color(0xFFF59E0B).withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: notice.targetType == 'ALL'
                      ? const Color(0xFF6366F1).withOpacity(0.3)
                      : const Color(0xFFF59E0B).withOpacity(0.3),
                ),
              ),
              child: Text(
                notice.targetType == 'ALL' ? '📢 All Guards' : '🎯 Selected Guards',
                style: TextStyle(
                  color: notice.targetType == 'ALL'
                      ? const Color(0xFF6366F1)
                      : const Color(0xFFF59E0B),
                  fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6,
                ),
              ),
            ),
            // Title
            Text(notice.title,
                style: const TextStyle(
                    color: _text, fontSize: 20, fontWeight: FontWeight.w800, height: 1.3)),
            const SizedBox(height: 8),
            // Meta
            Row(
              children: [
                const Icon(Icons.person_outline, color: _sub, size: 13),
                const SizedBox(width: 4),
                Text(notice.createdByName, style: const TextStyle(color: _sub, fontSize: 12)),
                const SizedBox(width: 10),
                const Icon(Icons.access_time, color: _sub, size: 13),
                const SizedBox(width: 4),
                Text(_formatDate(notice.createdAt),
                    style: const TextStyle(color: _sub, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 20),
            Divider(color: _border),
            const SizedBox(height: 16),
            // Content
            Text(notice.content,
                style: const TextStyle(
                    color: Color(0xFFCBD5E1), fontSize: 14.5, height: 1.65)),

            // ── Image attachments ────────────────────────────────────────
            if (_images.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  const Text('Photos',
                      style: TextStyle(color: _sub, fontSize: 11,
                          fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                  const SizedBox(width: 6),
                  Text('(${_images.length})',
                      style: const TextStyle(color: _sub, fontSize: 11)),
                  const Spacer(),
                  const Text('Tap to view · Pinch to zoom',
                      style: TextStyle(color: _sub, fontSize: 10)),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 130,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => _openPhotoViewer(i),
                    child: Hero(
                      tag: 'archive_img_${_images[i]}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Image.network(
                              _images[i],
                              height: 130, width: 130, fit: BoxFit.cover,
                              headers: _authHeaders,
                              errorBuilder: (_, __, ___) => Container(
                                width: 130, height: 130, color: _card,
                                child: const Icon(Icons.broken_image_outlined,
                                    color: _sub, size: 28),
                              ),
                              loadingBuilder: (_, child, progress) => progress == null
                                  ? child
                                  : Container(
                                      width: 130, height: 130, color: _card,
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                            color: _accent, strokeWidth: 2),
                                      ),
                                    ),
                            ),
                            Positioned(
                              bottom: 6, right: 6,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(Icons.zoom_in,
                                    color: Colors.white70, size: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],

            // ── PDF attachments ──────────────────────────────────────────
            if (_pdfs.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('Documents',
                  style: TextStyle(color: _sub, fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 0.6)),
              const SizedBox(height: 8),
              ..._pdfs.map((url) {
                final name = url.split('/').last;
                return GestureDetector(
                  onTap: () => _openPdf(url),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.picture_as_pdf,
                              color: Color(0xFFFC8181), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: const TextStyle(color: _text,
                                      fontSize: 13, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis),
                              const Text('Tap to open in-app viewer',
                                  style: TextStyle(color: _sub, fontSize: 11)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: _sub, size: 20),
                      ],
                    ),
                  ),
                );
              }),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
