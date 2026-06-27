import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/notice_service.dart';

class ExecutiveNoticeScreen extends StatefulWidget {
  final List<NoticeItem> notices;
  final int              userId;
  /// Where to go after all notices are acknowledged.
  /// If null (triggered while already logged in), the screen simply pops.
  final Widget?          destination;

  const ExecutiveNoticeScreen({
    super.key,
    required this.notices,
    required this.userId,
    this.destination,
  });

  @override
  State<ExecutiveNoticeScreen> createState() => _ExecutiveNoticeScreenState();
}

class _ExecutiveNoticeScreenState extends State<ExecutiveNoticeScreen>
    with SingleTickerProviderStateMixin {

  final _noticeService = NoticeService();

  int  _current    = 0;
  bool _confirmed  = false;
  bool _submitting = false;

  late AnimationController _anim;
  late Animation<double>   _fadeAnim;

  // ─── theme ────────────────────────────────────────────────────────────────
  static const _bg       = Color(0xFF0B1628);
  static const _card     = Color(0xFF1E293B);
  static const _border   = Color(0xFF334155);
  static const _primary  = Color(0xFF1665C1);
  static const _accent   = Color(0xFF60A5FA);
  static const _text     = Colors.white;
  static const _subtext  = Color(0xFF94A3B8);

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();
  }

  @override
  void dispose() { _anim.dispose(); super.dispose(); }

  NoticeItem get _notice => widget.notices[_current];
  bool get _isLast => _current == widget.notices.length - 1;

  // ── Acknowledge current notice and advance ────────────────────────────────
  Future<void> _acknowledge() async {
    setState(() => _submitting = true);
    await _noticeService.acknowledgeNotice(_notice.id, widget.userId);
    setState(() => _submitting = false);

    if (_isLast) {
      if (!mounted) return;
      if (widget.destination != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => widget.destination!),
        );
      } else {
        Navigator.pop(context); // guard was already in-app; just dismiss
      }
    } else {
      setState(() { _current++; _confirmed = false; });
      _anim.reset();
      _anim.forward();
    }
  }

  // ── Attachment helpers ─────────────────────────────────────────────────────
  bool _isPdf(String url) => url.toLowerCase().endsWith('.pdf');

  List<String> get _images => _notice.attachmentUrls.where((u) => !_isPdf(u)).toList();
  List<String> get _pdfs   => _notice.attachmentUrls.where(_isPdf).toList();

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // block back button
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildBody()),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _card,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          // Shield logo
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _primary.withOpacity(0.15),
              border: Border.all(color: _accent.withOpacity(0.3)),
            ),
            child: const Icon(Icons.shield_outlined, color: _accent, size: 18),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Black Fabric Security',
                    style: TextStyle(color: _text, fontWeight: FontWeight.w800, fontSize: 13)),
                Text('Executive Notice',
                    style: TextStyle(color: _accent, fontSize: 10, fontWeight: FontWeight.w600,
                        letterSpacing: 0.8)),
              ],
            ),
          ),
          // Progress indicator
          if (widget.notices.length > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _primary.withOpacity(0.3)),
              ),
              child: Text(
                '${_current + 1} of ${widget.notices.length}',
                style: const TextStyle(color: _accent, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Label
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626).withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFDC2626).withOpacity(0.3)),
            ),
            child: const Text(
              '⚠️  ACTION REQUIRED',
              style: TextStyle(color: Color(0xFFFC8181), fontSize: 10,
                  fontWeight: FontWeight.w800, letterSpacing: 0.8),
            ),
          ),

          // Title
          Text(
            _notice.title,
            style: const TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w800,
                height: 1.3),
          ),
          const SizedBox(height: 6),

          // Meta
          Row(
            children: [
              const Icon(Icons.person_outline, color: _subtext, size: 13),
              const SizedBox(width: 4),
              Text(_notice.createdByName,
                  style: const TextStyle(color: _subtext, fontSize: 12)),
              const SizedBox(width: 10),
              const Icon(Icons.access_time, color: _subtext, size: 13),
              const SizedBox(width: 4),
              Text(_formatDate(_notice.createdAt),
                  style: const TextStyle(color: _subtext, fontSize: 12)),
            ],
          ),

          const SizedBox(height: 20),
          Divider(color: _border),
          const SizedBox(height: 16),

          // Content
          Text(
            _notice.content,
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 14.5, height: 1.65),
          ),

          // Image attachments
          if (_images.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('Attachments',
                style: TextStyle(color: _subtext, fontSize: 11,
                    fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            const SizedBox(height: 10),
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _openUrl(_images[i]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      _images[i],
                      height: 180, width: 240, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 240, height: 180, color: _card,
                        child: const Icon(Icons.broken_image, color: _subtext, size: 36),
                      ),
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : Container(
                              width: 240, height: 180, color: _card,
                              child: const Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2)),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],

          // PDF attachments
          if (_pdfs.isNotEmpty) ...[
            const SizedBox(height: 20),
            ..._pdfs.map((url) => GestureDetector(
              onTap: () => _openUrl(url),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf, color: Color(0xFFFC8181), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        url.split('/').last,
                        style: const TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.open_in_new, color: _subtext, size: 16),
                  ],
                ),
              ),
            )),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Footer (acknowledge section) ───────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: _card,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Checkbox
          GestureDetector(
            onTap: () => setState(() => _confirmed = !_confirmed),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: _confirmed ? _primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _confirmed ? _primary : _border, width: 2,
                    ),
                  ),
                  child: _confirmed
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : null,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'I have read and acknowledge this notice',
                    style: TextStyle(color: _text, fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Proceed button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: (_confirmed && !_submitting) ? _acknowledge : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                disabledBackgroundColor: _border,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _submitting
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(
                      _isLast ? 'Acknowledge & Continue' : 'Acknowledge & Next (${widget.notices.length - _current - 1} remaining)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) { return iso; }
  }
}
