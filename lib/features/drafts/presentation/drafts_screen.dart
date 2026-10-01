import 'package:flutter/material.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/action_menu_label.dart';
import '../../../core/widgets/stable_popup_menu.dart';
import '../../feed/data/repositories/post_repository.dart';
import '../../feed/presentation/screens/preview_screen.dart';
import '../data/capture_draft.dart';
import '../data/draft_repository.dart';

class DraftsScreen extends StatefulWidget {
  final DraftRepository repository;
  final PostRepository? posts;
  final String ownerId;
  const DraftsScreen({
    super.key,
    required this.repository,
    required this.ownerId,
    this.posts,
  });
  @override
  State<DraftsScreen> createState() => _DraftsScreenState();
}

class _DraftsScreenState extends State<DraftsScreen> {
  late Stream<List<CaptureDraft>> _drafts = widget.repository.watch(
    widget.ownerId,
  );
  bool _opening = false;
  Future<void> _open(CaptureDraft draft) async {
    if (_opening || widget.repository.currentUserId() != widget.ownerId) return;
    setState(() => _opening = true);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewScreen(
            mediaFile: draft.mediaFile,
            mediaType: draft.mediaType,
            dareText: draft.dareText,
            moodId: draft.moodId,
            moodName: draft.moodName,
            weeklyDareId: draft.weeklyDareId,
            liveLens: draft.liveLens,
            draft: draft,
            drafts: widget.repository,
            repository: widget.posts,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _delete(CaptureDraft draft) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this draft?'),
        content: const Text(
          'This capture and its edits will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await widget.repository.delete(widget.ownerId, draft.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete the draft. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Drafts')),
    body: StreamBuilder<List<CaptureDraft>>(
      stream: _drafts,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppEmptyState.error(
            title: 'Could not load drafts',
            message: 'Sign in to the same account and check device storage.',
            actionLabel: 'Retry',
            onAction: () => setState(
              () => _drafts = widget.repository.watch(widget.ownerId),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final drafts = snapshot.data!;
        if (drafts.isEmpty) {
          return const AppEmptyState(
            icon: Icons.drafts_outlined,
            title: 'Room for your next moment',
            message: 'Save a capture as a draft to finish it later.',
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Only you · Saved on this device',
                style: TextStyle(color: Colors.white60),
              ),
            ),
            for (final draft in drafts)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.white.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    enabled: !_opening,
                    contentPadding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    leading: SizedBox(
                      width: 56,
                      height: 68,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: draft.mediaType == 'image'
                            ? Image.file(
                                draft.mediaFile,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.image_outlined),
                              )
                            : const ColoredBox(
                                color: Colors.white10,
                                child: Icon(Icons.videocam_outlined),
                              ),
                      ),
                    ),
                    title: Text(
                      draft.dareText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        if (draft.moodName != null) draft.moodName!,
                        draft.mediaType == 'image' ? 'Photo' : 'Video',
                      ].join(' · '),
                    ),
                    onTap: () => _open(draft),
                    trailing: StablePopupMenu<String>(
                      tooltip: 'Draft options',
                      enabled: !_opening,
                      onSelected: (_) => _delete(draft),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'delete',
                          child: ActionMenuLabel(
                            action: MenuAction.delete,
                            text: 'Delete draft',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
