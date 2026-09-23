import 'package:flutter/material.dart';
import 'package:mooddare/core/branding/mood_wink.dart';
import 'package:mooddare/core/widgets/app_empty_state.dart';
import 'package:mooddare/features/profile/data/social_repository.dart';
import 'package:mooddare/models/user_model.dart';
import '../../data/repositories/dare_library_repository.dart';

Future<void> showSendDare(
  BuildContext context,
  DarePrompt prompt, {
  DareLibraryRepository? repository,
  SocialRepository? social,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) =>
      SendDareSheet(prompt: prompt, repository: repository, social: social),
);

class SendDareSheet extends StatefulWidget {
  final DarePrompt prompt;
  final DareLibraryRepository? repository;
  final SocialRepository? social;
  const SendDareSheet({
    super.key,
    required this.prompt,
    this.repository,
    this.social,
  });
  @override
  State<SendDareSheet> createState() => _SendDareSheetState();
}

class _SendDareSheetState extends State<SendDareSheet> {
  late final _repo = widget.repository ?? DareLibraryRepository();
  late final _social = widget.social ?? SocialRepository();
  late Stream<List<UserModel>> _people = _load();
  Stream<List<UserModel>> _load() => _social.mutuals().asyncMap(_social.people);
  final _search = TextEditingController();
  final _sent = <String>{};
  String? _sending, _failed;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: StreamBuilder<List<UserModel>>(
        stream: _people,
        builder: (context, snapshot) {
          final query = _search.text.trim().toLowerCase().replaceFirst(
            RegExp(r'^@'),
            '',
          );
          final users = (snapshot.data ?? <UserModel>[])
              .where(
                (u) => '${u.username ?? ''} ${u.name ?? ''}'
                    .toLowerCase()
                    .contains(query),
              )
              .toList();
          return CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Send a dare',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'A little challenge for someone who follows you back.',
                        style: TextStyle(color: Colors.white60),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: 'Search mutual followers',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              if (snapshot.hasError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppEmptyState.error(
                    title: 'Couldn’t load people',
                    message: 'Please try again.',
                    actionLabel: 'Retry',
                    onAction: () => setState(() => _people = _load()),
                  ),
                )
              else if (!snapshot.hasData)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (users.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppEmptyState(
                    illustration: const MoodWink(
                      size: 72,
                      expression: MoodWinkExpression.thinking,
                    ),
                    title: query.isEmpty
                        ? 'Better with a friend'
                        : 'No matching people',
                    message: query.isEmpty
                        ? 'When you follow each other, you can send dares here.'
                        : 'Try a different name.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  sliver: SliverList.builder(
                    itemCount: users.length,
                    itemBuilder: (context, index) => _recipient(users[index]),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );

  Widget _recipient(UserModel user) {
    final sent = _sent.contains(user.id);
    final identity = Row(
      children: [
        CircleAvatar(
          radius: 18,
          foregroundImage: user.photoUrl?.isNotEmpty == true
              ? NetworkImage(user.photoUrl!)
              : null,
          onForegroundImageError: user.photoUrl?.isNotEmpty == true
              ? (_, _) {}
              : null,
          child: const Icon(Icons.person_outline),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '@${user.username ?? 'member'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    final button = TextButton(
      onPressed: _sending != null || sent
          ? null
          : () async {
              setState(() {
                _sending = user.id;
                _failed = null;
              });
              try {
                await _repo.send(widget.prompt, user.id);
                if (!mounted) return;
                setState(() => _sent.add(user.id));
              } catch (_) {
                if (mounted) setState(() => _failed = user.id);
              } finally {
                if (mounted) setState(() => _sending = null);
              }
            },
      child: Text(
        sent
            ? 'Sent'
            : _sending == user.id
            ? 'Sending…'
            : 'Send',
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_failed == user.id)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Could not send. Check your connection and that you still follow each other.',
                style: TextStyle(color: Color(0xFFF0A6AE)),
              ),
            ),
          MediaQuery.textScalerOf(context).scale(16) > 23
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [identity, button],
                )
              : Row(
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: 8),
                    button,
                  ],
                ),
        ],
      ),
    );
  }
}
