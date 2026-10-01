import 'package:flutter/material.dart';
import '../../core/widgets/app_empty_state.dart';
import '../../models/post_model.dart';
import '../feed/data/repositories/post_repository.dart';
import '../feed/presentation/screens/post_details_screen.dart';

class SharedMomentScreen extends StatefulWidget {
  final String postId;
  final PostRepository? repository;
  const SharedMomentScreen({super.key, required this.postId, this.repository});
  @override
  State<SharedMomentScreen> createState() => _SharedMomentScreenState();
}

class _SharedMomentScreenState extends State<SharedMomentScreen> {
  late final _repo = widget.repository ?? PostRepository();
  late final String? _owner;
  late Future<PostModel?> _post = _repo.getSharedPost(widget.postId);
  @override
  void initState() {
    super.initState();
    _owner = _repo.currentUserId;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PostModel?>(
    future: _post,
    builder: (context, snapshot) {
      if (snapshot.hasData && _repo.currentUserId == _owner) {
        return PostDetailsScreen(post: snapshot.data!, repository: _repo);
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Shared moment')),
        body: snapshot.connectionState != ConnectionState.done
            ? const Center(child: CircularProgressIndicator())
            : snapshot.hasError
            ? AppEmptyState.error(
                title: 'Could not open this moment',
                message: 'Check your connection and try again.',
                actionLabel: 'Retry',
                onAction: () => setState(() {
                  _post = _repo.getSharedPost(widget.postId);
                }),
              )
            : const AppEmptyState(
                icon: Icons.photo_outlined,
                title: 'Moment unavailable',
                message:
                    'It may have been deleted or is no longer available to you.',
              ),
      );
    },
  );
}
