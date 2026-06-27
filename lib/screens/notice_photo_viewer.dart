import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NoticePhotoViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int          initialIndex;

  const NoticePhotoViewer({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  @override
  State<NoticePhotoViewer> createState() => _NoticePhotoViewerState();
}

class _NoticePhotoViewerState extends State<NoticePhotoViewer> {
  late PageController _pageController;
  late int _current;
  Map<String, String> _headers = {};

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _loadHeaders();
    // Show status bar as dark while viewer is open
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  }

  Future<void> _loadHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt') ?? '';
    if (token.isNotEmpty && mounted) {
      setState(() => _headers = {'Authorization': 'Bearer $token'});
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.55),
        elevation: 0,
        foregroundColor: Colors.white,
        title: widget.imageUrls.length > 1
            ? Text(
                '${_current + 1} / ${widget.imageUrls.length}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: PhotoViewGallery.builder(
        pageController: _pageController,
        itemCount: widget.imageUrls.length,
        onPageChanged: (i) => setState(() => _current = i),
        scrollPhysics: const BouncingScrollPhysics(),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        builder: (context, index) {
          return PhotoViewGalleryPageOptions(
            imageProvider: NetworkImage(
              widget.imageUrls[index],
              headers: _headers,
            ),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 4.0,
            initialScale: PhotoViewComputedScale.contained,
            heroAttributes: PhotoViewHeroAttributes(
              tag: 'notice_img_${widget.imageUrls[index]}',
            ),
            errorBuilder: (_, __, ___) => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image_outlined, color: Colors.white38, size: 52),
                  SizedBox(height: 12),
                  Text('Could not load image',
                      style: TextStyle(color: Colors.white38, fontSize: 13)),
                ],
              ),
            ),
          );
        },
        loadingBuilder: (_, __) => const Center(
          child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
        ),
      ),
      // Dot indicator at bottom when multiple photos
      bottomNavigationBar: widget.imageUrls.length > 1
          ? Container(
              color: Colors.black.withOpacity(0.55),
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.imageUrls.length, (i) {
                  final active = i == _current;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width:  active ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active ? Colors.white : Colors.white38,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            )
          : null,
    );
  }
}
