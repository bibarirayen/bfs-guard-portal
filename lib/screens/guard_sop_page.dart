import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/sop_service.dart';
import 'sop_pdf_viewer_page.dart';
import 'sop_web_viewer_page.dart';

/// Shown to guards during an active shift.
/// Displays the SOP for their current active site.
class GuardSopPage extends StatefulWidget {
  final int siteId;
  final String siteName;

  const GuardSopPage({
    super.key,
    required this.siteId,
    required this.siteName,
  });

  @override
  State<GuardSopPage> createState() => _GuardSopPageState();
}

class _GuardSopPageState extends State<GuardSopPage> {
  final SopService _sopService = SopService();
  bool _loading = true;
  String? _errorMessage;
  String? _sopFileName;
  String? _sopFileUrl;

  @override
  void initState() {
    super.initState();
    _loadSop();
  }

  Future<void> _loadSop() async {
    try {
      final sop = await _sopService.getSop(widget.siteId);
      setState(() {
        _sopFileName = sop?['sopFileName'];
        _sopFileUrl = sop?['sopFileUrl'];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load SOP. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _openFile({bool download = false}) async {
    if (_sopFileUrl == null) return;

    final lower = (_sopFileName ?? _sopFileUrl!).toLowerCase();
    final isPdf = lower.endsWith('.pdf');
    final isOffice = lower.endsWith('.pptx') || lower.endsWith('.ppt') ||
        lower.endsWith('.docx') || lower.endsWith('.doc');

    if (!download) {
      if (isPdf) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => SopPdfViewerPage(
            url: _sopFileUrl!,
            fileName: _sopFileName ?? 'sop.pdf',
            siteName: widget.siteName,
          ),
        ));
        return;
      }
      if (isOffice) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => SopWebViewerPage(
            fileUrl: _sopFileUrl!,
            fileName: _sopFileName ?? 'sop',
            siteName: widget.siteName,
          ),
        ));
        return;
      }
    }

    // Download or unsupported type: open in external app
    final url = Uri.parse(_sopFileUrl!);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open file')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color accent = Color(0xFF6366F1);
    const Color bg = Color(0xFF0F172A);
    const Color card = Color(0xFF1E293B);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        foregroundColor: Colors.white,
        title: const Text('SOP', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: accent))
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                      const SizedBox(height: 12),
                      Text(_errorMessage!,
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() { _loading = true; _errorMessage = null; });
                          _loadSop();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Site name banner
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: accent.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on, color: accent, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.siteName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      if (_sopFileUrl == null) ...[
                        // No SOP configured
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.description_outlined,
                                    size: 72,
                                    color: Colors.white.withOpacity(0.2)),
                                const SizedBox(height: 16),
                                const Text(
                                  'No SOP available for this site.',
                                  style: TextStyle(color: Colors.white60, fontSize: 16),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Contact your supervisor or admin.',
                                  style: TextStyle(color: Colors.white38, fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        // File card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: accent.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                        Icons.insert_drive_file_outlined,
                                        color: accent,
                                        size: 28),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      _sopFileName ?? 'SOP Document',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              // View button
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: accent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  onPressed: () => _openFile(),
                                  icon: const Icon(Icons.open_in_new),
                                  label: const Text('View SOP',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}
