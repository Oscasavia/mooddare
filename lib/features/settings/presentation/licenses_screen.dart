import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mooddare/core/widgets/app_empty_state.dart';

/// Keeps the bundled notices intact while presenting them in the app's theme.
class LicensesScreen extends StatefulWidget {
  final Stream<LicenseEntry> Function()? loadLicenses;
  const LicensesScreen({super.key, this.loadLicenses});

  @override
  State<LicensesScreen> createState() => _LicensesScreenState();
}

class _LicensesScreenState extends State<LicensesScreen> {
  late Future<Map<String, List<LicenseEntry>>> _licenses = _load();
  String _query = '';

  Future<Map<String, List<LicenseEntry>>> _load() async {
    final packages = <String, List<LicenseEntry>>{};
    final stream = widget.loadLicenses?.call() ?? LicenseRegistry.licenses;
    await for (final entry in stream) {
      for (final package in entry.packages.toSet()) {
        (packages[package] ??= []).add(entry);
      }
    }
    return packages;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Licenses')),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: FutureBuilder<Map<String, List<LicenseEntry>>>(
            future: _licenses,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return AppEmptyState.error(
                  title: 'Could not load licenses',
                  message: 'Please try again.',
                  actionLabel: 'Try again',
                  onAction: () => setState(() {
                    _licenses = _load();
                  }),
                );
              }
              final packages = snapshot.data!;
              final names =
                  packages.keys
                      .where((name) => name.toLowerCase().contains(_query))
                      .toList()
                    ..sort(
                      (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                    );
              return CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Built with a little help',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Thanks to the people behind the software that helps power MoodDare. Explore their licenses and acknowledgments below.',
                            style: TextStyle(
                              color: Colors.white60,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextField(
                            onChanged: (value) => setState(
                              () => _query = value.trim().toLowerCase(),
                            ),
                            onTapOutside: (_) =>
                                FocusManager.instance.primaryFocus?.unfocus(),
                            decoration: const InputDecoration(
                              hintText: 'Search licenses',
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (names.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No matching licenses',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white60),
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    sliver: SliverList.builder(
                      itemCount: names.length,
                      itemBuilder: (context, index) {
                        final name = names[index];
                        final entries = packages[name]!;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            title: Text(name),
                            subtitle: Text(
                              '${entries.length} ${entries.length == 1 ? 'notice' : 'notices'}',
                              style: const TextStyle(color: Colors.white60),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: Colors.white38,
                            ),
                            onTap: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => _LicenseDetails(
                                    name: name,
                                    entries: entries,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _LicenseDetails extends StatelessWidget {
  final String name;
  final List<LicenseEntry> entries;
  const _LicenseDetails({required this.name, required this.entries});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(name)),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SelectionArea(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              itemCount: entries.length,
              itemBuilder: (context, index) => Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final paragraph in entries[index].paragraphs)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: 16,
                            left: paragraph.indent > 0
                                ? paragraph.indent.clamp(0, 4) * 12.0
                                : 0,
                          ),
                          child: Text(
                            paragraph.text,
                            textAlign:
                                paragraph.indent ==
                                    LicenseParagraph.centeredIndent
                                ? TextAlign.center
                                : TextAlign.start,
                            style: const TextStyle(
                              color: Colors.white70,
                              height: 1.6,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
