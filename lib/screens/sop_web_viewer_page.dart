import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Renders PPTX, DOCX, and other Office files using Microsoft Office Online Viewer.
/// Also used as a fallback for any file type not handled by SopPdfViewerPage.
class SopWebViewerPage extends StatefulWidget {
  final String fileUrl;
  final String fileName;
  final String siteName;

  const SopWebViewerPage({
    super.key,
    required this.fileUrl,
    required this.fileName,
    required this.siteName,
  });

  /// Builds the Office Online embed URL for a given public file URL.
  static String officeViewerUrl(String fileUrl) {
    return 'https://view.officeapps.live.com/op/embed.aspx?src='
        '${Uri.encodeComponent(fileUrl)}';
  }

  @override
  State<SopWebViewerPage> createState() => _SopWebViewerPageState();
}

class _SopWebViewerPageState extends State<SopWebViewerPage> {
  late final WebViewController _controller;
  bool _loading = true;

  static const Color _accent = Color(0xFF6366F1);
  static const Color _bg = Color(0xFF0F172A);
  static const Color _card = Color(0xFF1E293B);

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) => setState(() => _loading = false),
        onWebResourceError: (error) => setState(() => _loading = false),
      ))
      ..loadRequest(
        Uri.parse(SopWebViewerPage.officeViewerUrl(widget.fileUrl)),
      );
  }

  Future<void> _download() async {
    final uri = Uri.parse(widget.fileUrl);
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
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            Text(widget.fileName,
                style:
                    const TextStyle(fontSize: 11, color: Colors.white54),
                overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Download',
            icon: const Icon(Icons.download_outlined),
            onPressed: _download,
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: _accent),
                  SizedBox(height: 14),
                  Text('Loading document...',
                      style:
                          TextStyle(color: Colors.white54, fontSize: 13)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
