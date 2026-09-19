import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mooddare/models/post_model.dart';
import 'package:mooddare/features/feed/data/repositories/post_repository.dart';
import 'package:mooddare/features/feed/presentation/screens/post_details_screen.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mooddare/core/widgets/app_empty_state.dart';

class MyDaresGrid extends StatefulWidget {
  final String userId;
  const MyDaresGrid({super.key, required this.userId});
  @override
  State<MyDaresGrid> createState() => _MyDaresGridState();
}

class _MyDaresGridState extends State<MyDaresGrid> {
  late final _posts = PostRepository().getUserPosts(widget.userId);
  final _thumbnails = <String, Future<String?>>{};
  Future<String?> _thumbnail(String url) async => VideoThumbnail.thumbnailFile(
    video: url,
    thumbnailPath: (await getTemporaryDirectory()).path,
    imageFormat: ImageFormat.JPEG,
    maxWidth: 240,
    quality: 75,
  );
  @override
  Widget build(BuildContext context) => StreamBuilder<List<PostModel>>(
    stream: _posts,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const AppEmptyState(
          icon: Icons.cloud_off,
          title: 'Could not load moments',
          message: 'Check your connection and reopen your profile.',
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final posts = snapshot.data!;
      if (posts.isEmpty) {
        return const AppEmptyState(
          icon: Icons.photo_camera_back_outlined,
          title: 'Your story starts here',
          message: 'Your shared dares will appear here.',
        );
      }
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: posts.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: .8,
        ),
        itemBuilder: (context, i) {
          final post = posts[i];
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Material(
              color: Colors.white10,
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PostDetailsScreen(post: post),
                  ),
                ),
                child: post.mediaType == 'image'
                    ? Image.network(
                        post.mediaUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image_outlined),
                      )
                    : FutureBuilder<String?>(
                        future: _thumbnails.putIfAbsent(
                          post.mediaUrl,
                          () => _thumbnail(post.mediaUrl),
                        ),
                        builder: (context, thumbnail) => Stack(
                          fit: StackFit.expand,
                          children: [
                            if (thumbnail.hasData)
                              Image.file(
                                File(thumbnail.data!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const SizedBox(),
                              ),
                            const Center(
                              child: Icon(Icons.play_circle_outline, size: 32),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          );
        },
      );
    },
  );
}
