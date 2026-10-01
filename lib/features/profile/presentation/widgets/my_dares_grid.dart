import '../../../drafts/data/draft_repository.dart';
import '../../../drafts/data/capture_draft.dart';
import '../../../drafts/presentation/drafts_screen.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mooddare/models/post_model.dart';
import 'package:mooddare/features/feed/data/repositories/post_repository.dart';
import 'package:mooddare/features/feed/presentation/screens/post_details_screen.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mooddare/core/widgets/app_empty_state.dart';
import 'package:mooddare/core/branding/mood_wink.dart';

class MyDaresGrid extends StatefulWidget {
  final DraftRepository? drafts;
  final String userId;
  final PostRepository? repository;
  const MyDaresGrid({
    super.key,
    required this.userId,
    this.repository,
    this.drafts,
  });
  @override
  State<MyDaresGrid> createState() => _MyDaresGridState();
}

class _MyDaresGridState extends State<MyDaresGrid> {
  late PostRepository _repository = widget.repository ?? PostRepository();
  late Stream<List<PostModel>> _posts = _repository.getUserPosts(widget.userId);
  late Stream<List<CaptureDraft>> _drafts =
      widget.drafts?.watch(widget.userId) ?? Stream.value(<CaptureDraft>[]);
  final _thumbnails = <String, Future<String?>>{};
  Future<String?> _thumbnail(String url) async => VideoThumbnail.thumbnailFile(
    video: url,
    thumbnailPath: (await getTemporaryDirectory()).path,
    imageFormat: ImageFormat.JPEG,
    maxWidth: 240,
    quality: 75,
  );
  @override
  void didUpdateWidget(covariant MyDaresGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.repository != widget.repository ||
        oldWidget.drafts != widget.drafts) {
      _repository = widget.repository ?? PostRepository();
      _posts = _repository.getUserPosts(widget.userId);
      _drafts =
          widget.drafts?.watch(widget.userId) ?? Stream.value(<CaptureDraft>[]);
      _thumbnails.clear();
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CaptureDraft>>(
    key: ValueKey((widget.userId, widget.drafts)),
    stream: _drafts,
    builder: (context, drafts) => _buildGrid(drafts.data ?? []),
  );
  Widget _buildGrid(
    List<CaptureDraft> drafts,
  ) => StreamBuilder<List<PostModel>>(
    key: ValueKey(widget.userId),
    stream: _posts,
    builder: (context, snapshot) {
      if (snapshot.hasError && drafts.isEmpty) {
        return const AppEmptyState.error(
          title: 'Could not load moments',
          message: 'Check your connection and reopen your profile.',
        );
      }
      if (!snapshot.hasData && drafts.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      final posts = snapshot.data ?? [];
      if (posts.isEmpty && drafts.isEmpty) {
        return const AppEmptyState(
          illustration: MoodWink(
            size: 80,
            expression: MoodWinkExpression.smile,
          ),
          title: 'Your story starts here',
          message: 'Your shared dares will appear here.',
        );
      }
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: posts.length + (drafts.isEmpty ? 0 : 1),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: .8,
        ),
        itemBuilder: (context, i) {
          if (drafts.isNotEmpty && i == 0) {
            return Material(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  final store = widget.drafts;
                  final owner = widget.userId;
                  final posts = _repository;
                  if (store == null || store.currentUserId() != owner) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DraftsScreen(
                        repository: store,
                        ownerId: owner,
                        posts: posts,
                      ),
                    ),
                  );
                },
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.drafts_outlined, size: 28),
                        const SizedBox(height: 8),
                        Text(
                          'Drafts · ${drafts.length}',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Only you',
                          style: TextStyle(fontSize: 11, color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          final post = posts[i - (drafts.isEmpty ? 0 : 1)];
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Material(
              color: Colors.white10,
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        PostDetailsScreen(post: post, repository: _repository),
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
