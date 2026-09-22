import 'package:flutter/material.dart';
import 'package:mooddare/features/feed/data/repositories/post_repository.dart';
import 'package:mooddare/features/user/data/repositories/user_repository.dart';
import 'package:mooddare/models/user_model.dart';
import 'package:mooddare/core/widgets/app_empty_state.dart';

class BlockedAccountsScreen extends StatefulWidget {
  const BlockedAccountsScreen({super.key});
  @override
  State<BlockedAccountsScreen> createState() => _BlockedAccountsScreenState();
}

class _BlockedAccountsScreenState extends State<BlockedAccountsScreen> {
  final _repo = PostRepository();
  late final _blocked = _repo.blockedAuthors();
  final _profiles = <String, Future<UserModel?>>{};
  String? _busy;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Blocked accounts')),
    body: StreamBuilder<Set<String>>(
      stream: _blocked,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const AppEmptyState.error(
            title: 'Could not load accounts',
            message: 'Check your connection and reopen this page.',
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final ids = snapshot.data!.toList();
        if (ids.isEmpty) {
          return const AppEmptyState(
            icon: Icons.block,
            title: 'No blocked accounts',
            message: 'You can block an account from the menu on their moment.',
          );
        }
        return ListView.builder(
          itemCount: ids.length,
          itemBuilder: (context, index) {
            final id = ids[index];
            return FutureBuilder<UserModel?>(
              future: _profiles.putIfAbsent(
                id,
                () => UserRepository().getUserModel(id),
              ),
              builder: (context, user) => ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(
                  user.data?.username == null
                      ? 'MoodDare member'
                      : '@${user.data!.username}',
                ),
                trailing: TextButton(
                  onPressed: _busy != null
                      ? null
                      : () async {
                          setState(() => _busy = id);
                          try {
                            await _repo.unblockAuthor(id);
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Could not unblock. Please try again.',
                                  ),
                                ),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _busy = null);
                          }
                        },
                  child: Text(_busy == id ? 'Unblocking…' : 'Unblock'),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
