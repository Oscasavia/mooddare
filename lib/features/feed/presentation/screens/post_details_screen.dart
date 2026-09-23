import 'package:mooddare/features/dares/data/repositories/dare_library_repository.dart';
// lib/features/feed/presentation/screens/post_details_screen.dart
import 'package:flutter/material.dart';
import 'package:mooddare/models/post_model.dart';
import 'package:mooddare/features/feed/presentation/widgets/dare_proof_card.dart';
import '../../data/repositories/post_repository.dart';

class PostDetailsScreen extends StatelessWidget {
  final DareLibraryRepository? dareLibrary;
  final PostModel post;
  final PostRepository? repository;
  final VoidCallback? onHidden;
  const PostDetailsScreen({
    super.key,
    required this.post,
    this.dareLibrary,
    this.repository,
    this.onHidden,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DareProofCard(
        post: post,
        dareLibrary: dareLibrary,
        repository: repository,
        onHidden: onHidden,
        isFullScreen: true,
        isActive: true,
      ),
    );
  }
}
