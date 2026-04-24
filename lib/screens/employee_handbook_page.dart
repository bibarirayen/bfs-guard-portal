import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/employee_handbook_service.dart';
import 'sop_pdf_viewer_page.dart';
import 'sop_web_viewer_page.dart';

/// Shows the Employee Handbook list — accessible to ALL users (guards, supervisors, admins).
class EmployeeHandbookPage extends StatefulWidget {
  const EmployeeHandbookPage({super.key});

  @override
  State<EmployeeHandbookPage> createState() => _EmployeeHandbookPageState();
}

class _EmployeeHandbookPageState extends State<EmployeeHandbookPage> {
  final EmployeeHandbookService _service = EmployeeHandbookService();
  final TextEditingController _search = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];

  // ── Design tokens ─────────────────────────────────────────────
  static const Color _bg = Color(0xFF0F172A);
  static const Color _card = Color(0xFF1E293B);
  static const Color _border = Color(0xFF334155);
  static const Color _accent = Color(0xFF6366F1);
  static const Color _text = Colors.white;
  static const Color _sub = Color(0xFF94A3B8);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _service.getAll();
      if (!mounted) return;
      setState(() {
        _all = data;
        _filtered = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load handbook documents.';
        _loading = false;
      });
    }
  }

  void _filter(String term) {
    final q = term.toLowerCase();
    setState(() {
      _filtered = _all.where((e) {
        return (e['displayName'] ?? '').toString().toLowerCase().contains(q);
      }).toList();
    });
  }

  Future<void> _openFile(String url, {String? fileName}) async {
    final lower = (fileName ?? url).toLowerCase();
    final isPdf = lower.endsWith('.pdf');
    final isOffice = lower.endsWith('.pptx') || lower.endsWith('.ppt') ||
        lower.endsWith('.docx') || lower.endsWith('.doc');

    if (isPdf) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SopPdfViewerPage(
            url: url,
            fileName: fileName ?? 'document.pdf',
            siteName: 'Employee Handbook',
          ),
        ),
      );
      return;
    }

    if (isOffice) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SopWebViewerPage(
            fileUrl: url,
            fileName: fileName ?? 'document',
            siteName: 'Employee Handbook',
          ),
        ),
      );
      return;
    }

    // Fallback: open in external browser
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open file')),
        );
      }
    }
  }

  String _extLabel(String url) {
    final m = RegExp(r'\.([a-zA-Z0-9]+)$').firstMatch(url);
    return m != null ? m.group(1)!.toUpperCase() : 'FILE';
  }

  Color _extColor(String url) {
    final ext = (_extLabel(url)).toLowerCase();
    if (ext == 'pdf') return const Color(0xFFEF4444);
    if (ext == 'pptx' || ext == 'ppt') return const Color(0xFFF59E0B);
    if (ext == 'docx' || ext == 'doc') return const Color(0xFF3B82F6);
    return const Color(0xFF64748B);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        foregroundColor: _text,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Employee Handbook',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('Company documents & policies',
                style: TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _error != null
              ? _buildError()
              : Column(
                  children: [
                    _buildSearchBar(),
                    Expanded(child: _buildList()),
                  ],
                ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _search,
        onChanged: _filter,
        style: const TextStyle(color: _text),
        decoration: InputDecoration(
          hintText: 'Search documents...',
          hintStyle: const TextStyle(color: _sub),
          prefixIcon: const Icon(Icons.search, color: _sub),
          filled: true,
          fillColor: _card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 56, color: _sub.withOpacity(0.5)),
            const SizedBox(height: 12),
            const Text('No documents available.', style: TextStyle(color: _sub)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _accent,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filtered.length,
        itemBuilder: (ctx, i) => _buildCard(_filtered[i]),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> entry) {
    final name = entry['displayName'] ?? 'Document';
    final url = entry['storedFileName'] ?? entry['fileUrl'] ?? '';
    final fileUrl = entry['fileUrl'] ?? '';
    final ext = _extLabel(url);
    final color = _extColor(url);

    return GestureDetector(
      onTap: () => _openFile(fileUrl, fileName: entry['storedFileName']),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            // Extension badge
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              alignment: Alignment.center,
              child: Text(ext,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 11)),
            ),
            const SizedBox(width: 14),
            // Title
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: _text,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('Tap to open', style: TextStyle(color: _sub, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: _sub),
          ],
        ),
      ),
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
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _load();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
