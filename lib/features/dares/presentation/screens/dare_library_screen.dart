import 'package:flutter/material.dart';
import 'package:mooddare/core/branding/mood_wink.dart';
import 'package:mooddare/core/widgets/app_empty_state.dart';
import 'package:mooddare/features/profile/data/social_repository.dart';
import 'package:mooddare/models/user_model.dart';
import '../../data/repositories/dare_library_repository.dart';
import '../../data/repositories/dares_repository.dart';
import '../widgets/dare_actions.dart';

class DareInboxScreen extends StatelessWidget {
  final DareLibraryRepository? repository;
  final SocialRepository? social;
  const DareInboxScreen({super.key, this.repository, this.social});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Dare inbox')),
    body: DareLibraryList(inbox: true, repository: repository, social: social),
  );
}

class DareInboxButton extends StatefulWidget {
  final DareLibraryRepository? repository;
  final SocialRepository? social;
  const DareInboxButton({super.key, this.repository, this.social});
  @override
  State<DareInboxButton> createState() => _DareInboxButtonState();
}

class _DareInboxButtonState extends State<DareInboxButton> {
  late final _repo = widget.repository ?? DareLibraryRepository();
  late final _unread = _repo.hasUnread();
  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: _unread,
    builder: (context, snapshot) => IconButton(
      tooltip: 'Dare inbox',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              DareInboxScreen(repository: _repo, social: widget.social),
        ),
      ),
      icon: Badge(
        isLabelVisible: snapshot.data == true,
        child: const Icon(Icons.inbox_outlined),
      ),
    ),
  );
}

/// Saved dares are private. Incoming dares are retained until dismissed.
class DareLibraryList extends StatefulWidget {
  final bool inbox;
  final DareLibraryRepository? repository;
  final SocialRepository? social;
  final DaresRepository? catalog;
  final Widget Function(DarePrompt)? cameraBuilder;
  const DareLibraryList({
    super.key,
    this.inbox = false,
    this.repository,
    this.social,
    this.catalog,
    this.cameraBuilder,
  });
  @override
  State<DareLibraryList> createState() => _DareLibraryListState();
}

class _DareLibraryListState extends State<DareLibraryList> {
  late final _repo = widget.repository ?? DareLibraryRepository();
  late final _social = widget.social ?? SocialRepository();
  int _limit = 40;
  late Stream<List<DareEntry>> _entries = _load();
  late Stream<Set<String>> _blocked = widget.inbox
      ? _social.blocked()
      : Stream.value(<String>{});
  Stream<List<DareEntry>> _load() =>
      widget.inbox ? _repo.inbox(limit: _limit) : _repo.saved(limit: _limit);
  @override
  Widget build(BuildContext context) => StreamBuilder<Set<String>>(
    stream: _blocked,
    builder: (context, blocks) => StreamBuilder<List<DareEntry>>(
      stream: _entries,
      builder: (context, snapshot) {
        if (snapshot.hasError || blocks.hasError) {
          return AppEmptyState.error(
            title: 'Couldn’t load dares',
            message: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: () => setState(() {
              _entries = _load();
              _blocked = widget.inbox
                  ? _social.blocked()
                  : Stream.value(<String>{});
            }),
          );
        }
        if (!snapshot.hasData || !blocks.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snapshot.data!
            .where((d) => !blocks.data!.contains(d.senderId))
            .toList();
        final more = snapshot.data!.length >= _limit;
        if (entries.isEmpty && !more) {
          return AppEmptyState(
            illustration: MoodWink(
              size: 80,
              expression: widget.inbox
                  ? MoodWinkExpression.smile
                  : MoodWinkExpression.thinking,
            ),
            title: widget.inbox
                ? 'A dare could be on its way'
                : 'Keep a little inspiration',
            message: widget.inbox
                ? 'Dares from mutual followers will arrive here.'
                : 'Bookmark a dare to try it another day. Only you can see your saved dares.',
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = !widget.inbox && constraints.maxWidth >= 340
                ? 2
                : 1;
            // Rows size to their content, including large accessibility text.
            final rows = (entries.length / columns).ceil();
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: rows + (more ? 1 : 0),
              itemBuilder: (context, row) {
                if (row == rows) {
                  return TextButton(
                    onPressed: () => setState(() {
                      _limit += 40;
                      _entries = _load();
                    }),
                    child: const Text('Load more dares'),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var col = 0; col < columns; col++) ...[
                        if (col > 0) const SizedBox(width: 12),
                        Expanded(
                          child: row * columns + col < entries.length
                              ? _DareTile(
                                  key: ValueKey(
                                    entries[row * columns + col].id,
                                  ),
                                  entry: entries[row * columns + col],
                                  repository: _repo,
                                  social: _social,
                                  catalog: widget.catalog,
                                  cameraBuilder: widget.cameraBuilder,
                                )
                              : const SizedBox(),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    ),
  );
}

class _DareTile extends StatefulWidget {
  final DareEntry entry;
  final DareLibraryRepository repository;
  final SocialRepository social;
  final DaresRepository? catalog;
  final Widget Function(DarePrompt)? cameraBuilder;
  const _DareTile({
    super.key,
    required this.entry,
    required this.repository,
    required this.social,
    this.catalog,
    this.cameraBuilder,
  });
  @override
  State<_DareTile> createState() => _DareTileState();
}

class _DareTileState extends State<_DareTile> {
  late final Future<List<UserModel>>? _sender = widget.entry.senderId == null
      ? null
      : widget.social.people({widget.entry.senderId!});
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_sender != null)
            FutureBuilder<List<UserModel>>(
              future: _sender,
              builder: (_, snapshot) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  snapshot.data?.isNotEmpty == true
                      ? 'From @${snapshot.data!.first.username ?? 'member'}'
                      : 'From a MoodDare member',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.prompt.moodName ?? 'A little challenge',
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ),
              if (entry.senderId == null)
                SaveDareButton(
                  prompt: entry.prompt,
                  repository: widget.repository,
                )
              else
                IconButton(
                  tooltip: 'Dismiss dare',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            await widget.repository.dismiss(entry.id);
                          } catch (_) {
                            if (context.mounted) {
                              dareMessage(
                                context,
                                'Could not dismiss this dare. Please try again.',
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            entry.prompt.text,
            style: const TextStyle(
              fontSize: 17,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (entry.senderId == null)
            TryDareButton(
              prompt: entry.prompt,
              label: 'Try it',
              catalog: widget.catalog,
              cameraBuilder: widget.cameraBuilder,
            )
          else
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            await widget.repository.markOpened(entry.id);
                            if (!context.mounted) return;
                            await openDareCamera(
                              context,
                              entry.prompt,
                              catalog: widget.catalog,
                              cameraBuilder: widget.cameraBuilder,
                            );
                          } catch (e) {
                            if (context.mounted) {
                              dareMessage(
                                context,
                                e is StateError
                                    ? e.message.toString()
                                    : 'Could not open this dare. Please try again.',
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  child: Text(_busy ? 'Opening…' : 'Try it'),
                ),
                SaveDareButton(
                  prompt: entry.prompt,
                  repository: widget.repository,
                ),
                if (!entry.opened)
                  const Text(
                    'New',
                    style: TextStyle(color: Color(0xFFC5B4FF), fontSize: 12),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
