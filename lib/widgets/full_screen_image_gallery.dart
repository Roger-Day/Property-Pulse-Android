import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

/// Full-screen pinch-to-zoom image gallery (property detail, project detail, etc.).
class FullScreenImageGallery extends StatefulWidget {
  const FullScreenImageGallery({
    super.key,
    required this.imageUrls,
    required this.initialPage,
  });

  final List<String> imageUrls;
  final int initialPage;

  /// Pushes the gallery; no-op if [urls] is empty.
  static void open(BuildContext context, List<String> urls, int initialPage) {
    if (urls.isEmpty) return;
    final safe = initialPage.clamp(0, urls.length - 1);
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FullScreenImageGallery(
          imageUrls: urls,
          initialPage: safe,
        ),
      ),
    );
  }

  @override
  State<FullScreenImageGallery> createState() => _FullScreenImageGalleryState();
}

class _FullScreenImageGalleryState extends State<FullScreenImageGallery> {
  late final PageController _controller;
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
    _controller = PageController(initialPage: widget.initialPage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_page + 1} / ${widget.imageUrls.length}'),
      ),
      body: PhotoViewGallery.builder(
        pageController: _controller,
        itemCount: widget.imageUrls.length,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        onPageChanged: (index) => setState(() => _page = index),
        builder: (context, index) {
          return PhotoViewGalleryPageOptions(
            imageProvider:
                CachedNetworkImageProvider(widget.imageUrls[index]),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 2.5,
          );
        },
        loadingBuilder: (context, event) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        },
      ),
    );
  }
}
