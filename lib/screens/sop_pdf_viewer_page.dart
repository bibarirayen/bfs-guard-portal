import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Downloads a PDF from [url] and renders it natively inside the app.
/// Works for both guards (single SOP) and admins (any SOP).
class SopPdfViewerPage extends StatefulWidget {
  final String url;
  final String fileName;
  final String siteName;

  const SopPdfViewerPage({
    super.key,
    required this.url,
    required this.fileName,
    required this.siteName,
  });

  @override
  State<SopPdfViewerPage> createState() => _SopPdfViewerPageState();
}

class _SopPdfViewerPageState extends State<SopPdfViewerPage> {
  bool _loading = true;
  String? _localPath;
  String? _errorMessage;
  int _totalPages = 0;
  int _currentPage = 0;

  static const Color _accent = Color(0xFF6366F1);
  static const Color _bg = Color(0xFF0F172A);
  static const Color _card = Color(0xFF1E293B);

  @override
  void initState() {
    super.initState();
    _downloadAndLoad();
  }

  Future<void> _downloadAndLoad() async {
    File? tempFile;
    try {
      final dir = await getTemporaryDirectory();
      // Cache key is the URL hash — if the file is re-uploaded the URL changes,
      // which busts the cache and forces a fresh download.
      final urlHash = widget.url.hashCode.abs().toString();
      final ext = widget.fileName.contains('.')
          ? widget.fileName.substring(widget.fileName.lastIndexOf('.'))
          : '.pdf';
      final cachedFile = File('${dir.path}/sop_$urlHash$ext');
      tempFile = File('${dir.path}/sop_${urlHash}_tmp$ext');

      if (!await cachedFile.exists()) {
        // Download to a temp file first, then rename atomically on success.
        // This prevents a failed/interrupted download from leaving a corrupt
        // cached file that would cause "not in PDF format" on the next open.
        if (await tempFile.exists()) await tempFile.delete();
        await Dio().download(widget.url, tempFile.path);
        await tempFile.rename(cachedFile.path);
        tempFile = null; // rename succeeded — nothing to clean up
      }

      setState(() {
        _localPath = cachedFile.path;
        _loading = false;
      });
    } catch (e) {
      // Remove any partial download so the next retry fetches a fresh copy.
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
      }
      setState(() {
        _errorMessage = 'Failed to load PDF.\nCheck your connection and try again.';
        _loading = false;
      });
    }
  }

  Future<void> _download() async {
    final uri = Uri.parse(widget.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.siteName,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            Text(widget.fileName,
                style: const TextStyle(fontSize: 11, color: Colors.white54),
                overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          if (!_loading && _errorMessage == null)
            Text(
              '$_currentPage / $_totalPages',
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: _accent),
                  SizedBox(height: 16),
                  Text('Loading SOP...',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.redAccent, size: 52),
                        const SizedBox(height: 14),
                        Text(_errorMessage!,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: Colors.white),
                          onPressed: () {
                            setState(() {
                              _loading = true;
                              _errorMessage = null;
                              _localPath = null;
                            });
                            _downloadAndLoad();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : PDFView(
                  filePath: _localPath!,
                  enableSwipe: true,
                  swipeHorizontal: false,
                  autoSpacing: true,
                  pageFling: true,
                  defaultPage: 0,
                  fitPolicy: FitPolicy.BOTH,
                  onRender: (pages) {
                    setState(() {
                      _totalPages = pages ?? 0;
                      _currentPage = 1;
                    });
                  },
                  onPageChanged: (page, total) {
                    setState(() {
                      _currentPage = (page ?? 0) + 1;
                      _totalPages = total ?? 0;
                    });
                  },
                  onError: (error) {
                    setState(() {
                      _errorMessage = 'Could not render PDF: $error';
                    });
                  },
                ),
    );
  }
}
