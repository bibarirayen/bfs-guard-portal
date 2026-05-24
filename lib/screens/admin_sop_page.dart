import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/sop_service.dart';
import 'sop_pdf_viewer_page.dart';
import 'sop_web_viewer_page.dart';

/// Shown to supervisors and admins.
/// Lists all sites; tapping a site opens its SOP.
class AdminSopPage extends StatefulWidget {
  const AdminSopPage({super.key});

  @override
  State<AdminSopPage> createState() => _AdminSopPageState();
}

class _AdminSopPageState extends State<AdminSopPage> {
  final SopService _sopService = SopService();
  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _sites = [];
  List<Map<String, dynamic>> _filtered = [];
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSites();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadSites() async {
    try {
      final sites = await _sopService.getAllSitesWithSop();
      setState(() {
        _sites = sites;
        _filtered = sites;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load sites.';
        _loading = false;
      });
    }
  }

  void _filter(String term) {
    final q = term.toLowerCase();
    setState(() {
      _filtered = _sites.where((s) {
        final name = (s['name'] ?? '').toString().toLowerCase();
        final client = (s['clientName'] ?? '').toString().toLowerCase();
        return name.contains(q) || client.contains(q);
      }).toList();
    });
  }

  List<Map<String, dynamic>> _sopFilesFor(Map<String, dynamic> site) {
    final files = site['sopFiles'];
    if (files is List) {
      return files.map((file) => Map<String, dynamic>.from(file as Map)).toList();
    }

    final String? url = site['sopFileUrl']?.toString();
    if (url != null && url.isNotEmpty) {
      return [
        {
          'fileName': site['sopFileName'] ?? 'SOP Document',
          'fileUrl': url,
        }
      ];
    }
    return const [];
  }

  Future<void> _openFile(String url, {bool download = false, String? fileName, String? siteName}) async {
    final lower = (fileName ?? url).toLowerCase();
    final isPdf = lower.endsWith('.pdf');
    final isOffice = lower.endsWith('.pptx') || lower.endsWith('.ppt') ||
        lower.endsWith('.docx') || lower.endsWith('.doc');

    if (!download) {
      if (isPdf) {
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => SopPdfViewerPage(
            url: url,
            fileName: fileName ?? 'sop.pdf',
            siteName: siteName ?? '',
          ),
        ));
        return;
      }
      if (isOffice) {
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => SopWebViewerPage(
            fileUrl: url,
            fileName: fileName ?? 'sop',
            siteName: siteName ?? '',
          ),
        ));
        return;
      }
    }

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

  void _showSopSheet(Map<String, dynamic> site) {
    final files = _sopFilesFor(site);
    final String siteName = site['name'] ?? 'Site';

    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No SOP configured for $siteName'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    const Color accent = Color(0xFF6366F1);
    const Color card = Color(0xFF1E293B);

    showModalBottomSheet(
      context: context,
      backgroundColor: card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
              Text('${files.length} SOP file(s)',
              ),
            ),

              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, index) {
                    final file = files[index];
                    final fileName = file['fileName']?.toString() ?? 'SOP Document';
                    final fileUrl = file['fileUrl']?.toString() ?? '';
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.insert_drive_file_outlined,
                                  color: accent, size: 30),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(fileName,
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 14)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () {
                                Navigator.pop(context);
                                _openFile(fileUrl, fileName: fileName, siteName: siteName);
                              },
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('View SOP',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 15)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _openFile(url, fileName: name, siteName: siteName);
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('View SOP',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 10),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color bg = Color(0xFF0F172A);
    const Color card = Color(0xFF1E293B);
    const Color border = Color(0xFF334155);
    const Color accent = Color(0xFF6366F1);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        foregroundColor: Colors.white,
        title: const Text('SOP — All Sites',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: accent))
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.redAccent, size: 48),
                      const SizedBox(height: 12),
                      Text(_errorMessage!,
                          style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _errorMessage = null;
                          });
                          _loadSites();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Search bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                        controller: _search,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search sites...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon: const Icon(Icons.search,
                              color: Colors.white38),
                          filled: true,
                          fillColor: card,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: accent, width: 1.5),
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onChanged: _filter,
                      ),
                    ),

                    // Site list
                    Expanded(
                      child: _filtered.isEmpty
                          ? Center(
                              child: Text(
                                'No sites found.',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.4)),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              itemCount: _filtered.length,
                              itemBuilder: (_, i) {
                                final site = _filtered[i];
                                final sopFiles = _sopFilesFor(site);
                                final hasSop = sopFiles.isNotEmpty;
                                return GestureDetector(
                                  onTap: () => _showSopSheet(site),
                                  child: Container(
                                    margin:
                                        const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: card,
                                      borderRadius:
                                          BorderRadius.circular(14),
                                      border: Border.all(color: border),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: hasSop
                                                ? accent.withOpacity(0.15)
                                                : Colors.white
                                                    .withOpacity(0.05),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Icon(
                                            hasSop
                                                ? Icons
                                                    .insert_drive_file_outlined
                                                : Icons
                                                    .description_outlined,
                                            color: hasSop
                                                ? accent
                                                : Colors.white24,
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                site['name'] ?? '',
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    fontSize: 14),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                site['clientName'] ?? '',
                                                style: const TextStyle(
                                                    color: Colors.white54,
                                                    fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4),
                                          decoration: BoxDecoration(
                                            color: hasSop
                                                ? const Color(0xFF10B981)
                                                    .withOpacity(0.15)
                                                : Colors.white
                                                    .withOpacity(0.05),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            hasSop ? '${sopFiles.length} SOP' : 'No SOP',
                                            style: TextStyle(
                                              color: hasSop
                                                  ? const Color(0xFF10B981)
                                                  : Colors.white38,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Icon(
                                            Icons.arrow_forward_ios,
                                            size: 13,
                                            color: Colors.white24),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
