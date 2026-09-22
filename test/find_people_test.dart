import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/core/branding/mood_wink.dart';
import 'package:mooddare/features/profile/data/social_repository.dart';
import 'package:mooddare/features/profile/presentation/screens/find_people_screen.dart';
import 'package:mooddare/models/user_model.dart';
import 'support/social_fakes.dart';
import 'support/search_history_fake.dart';

UserModel person(String id) =>
    UserModel(id: id, username: id, createdAt: Timestamp.now());

class SearchSocial extends MemorySocial {
  bool failBlocks = false;
  @override
  Stream<Set<String>> blocked() =>
      failBlocks ? Stream.error(StateError('Offline')) : super.blocked();
  final calls = <String>[];
  final pending = <Completer<PeoplePage>>[];
  @override
  Future<PeoplePage> searchPeople(String text, {DocumentSnapshot? after}) {
    calls.add(text);
    final result = Completer<PeoplePage>();
    pending.add(result);
    return result.future;
  }
}

void main() {
  test(
    'prefix search normalizes @ and case, paginates without gaps and avoids empty scans',
    () async {
      final db = FakeFirebaseFirestore();
      final repo = SocialRepository(firestore: db, auth: MockFirebaseAuth());
      for (var i = 0; i < 25; i++) {
        final name = 'alice${i.toString().padLeft(2, '0')}';
        await db.doc('users/$name').set({
          'username': name,
          'username_lower': name,
        });
      }
      await db.doc('users/bob').set({
        'username': 'bob',
        'username_lower': 'bob',
      });
      expect((await repo.searchPeople(' @ ')).users, isEmpty);
      final first = await repo.searchPeople(' @ALICE ');
      expect(first.users.length, 20);
      expect(first.next, isNotNull);
      final second = await repo.searchPeople('alice', after: first.next);
      expect(second.users.length, 5);
      expect(second.next, isNull);
      expect(
        {
          ...first.users.map((u) => u.id),
          ...second.users.map((u) => u.id),
        }.length,
        25,
      );
      expect((await repo.searchPeople('missing')).users, isEmpty);
    },
  );

  late SearchSocial repo;
  late MemorySearchHistory history;
  setUp(() {
    repo = SearchSocial();
    history = MemorySearchHistory();
  });
  tearDown(() => repo.changed.close());
  Future<void> open(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(),
            body: Text('Profile ${settings.arguments}'),
          ),
        ),
        home: FindPeopleScreen(repository: repo, recentSearches: history),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(const Duration(milliseconds: 301));
  }

  testWidgets(
    'mascot distinguishes discovery, loading, no results and errors',
    (tester) async {
      await open(tester, scale: 2);
      expect(
        tester.widget<MoodWink>(find.byType(MoodWink)).expression,
        MoodWinkExpression.wink,
      );
      await search(tester, 'missing');
      expect(find.byType(MoodWink), findsNothing);
      repo.pending.last.complete(const PeoplePage([]));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MoodWink>(find.byType(MoodWink)).expression,
        MoodWinkExpression.thinking,
      );
      expect(find.text('No matching people'), findsOneWidget);
      expect(
        find.text('Try another username or check the spelling.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await search(tester, 'offline');
      repo.pending.last.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MoodWink>(find.byType(MoodWink)).expression,
        MoodWinkExpression.error,
      );
      expect(find.text('Could not search people. Retry'), findsOneWidget);
      await tester.ensureVisible(find.text('Could not search people. Retry'));
      await tester.tap(find.text('Could not search people. Retry'));
      await tester.pump();
      expect(find.byType(MoodWink), findsNothing);
      repo.pending.last.complete(PeoplePage([person('alice')]));
      await tester.pumpAndSettle();
      expect(find.text('@alice'), findsOneWidget);
      expect(find.byType(MoodWink), findsNothing);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MoodWink>(find.byType(MoodWink)).expression,
        MoodWinkExpression.wink,
      );
    },
  );

  testWidgets(
    'debounces, ignores stale results, clears pending searches and safely disposes',
    (tester) async {
      await open(tester);
      expect(repo.calls, isEmpty);
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump(const Duration(milliseconds: 100));
      await search(tester, 'alice');
      expect(repo.calls, ['alice']);
      await search(tester, 'bob');
      repo.pending[1].complete(PeoplePage([person('bob')]));
      await tester.pumpAndSettle();
      repo.pending[0].complete(PeoplePage([person('alice')]));
      await tester.pumpAndSettle();
      expect(find.text('@bob'), findsOneWidget);
      expect(find.text('@alice'), findsNothing);
      await search(tester, 'charlie');
      await tester.tap(find.byTooltip('Clear search'));
      repo.pending[2].completeError(StateError('Offline'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Find your people'), findsOneWidget);
      expect(find.textContaining('Could not search'), findsNothing);
      await search(tester, 'dave');
      await tester.pumpWidget(const SizedBox());
      repo.pending[3].complete(PeoplePage([person('dave')]));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search retry, self/block exclusion, profile navigation and follow/unfollow',
    (tester) async {
      repo.blockedIds.add('hidden');
      await open(tester, scale: 2);
      await search(tester, '@a');
      repo.pending.last.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Could not search people. Retry'));
      await tester.pump();
      repo.pending.last.complete(
        PeoplePage([person('alice'), person('hidden'), person('viewer')]),
      );
      await tester.pumpAndSettle();
      expect(find.text('@hidden'), findsNothing);
      expect(find.text('@viewer'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();
      expect(repo.following['viewer'], contains('alice'));
      await tester.tap(find.text('Following'));
      await tester.pumpAndSettle();
      expect(repo.following['viewer'], isNot(contains('alice')));
      await tester.tap(find.text('@alice'));
      await tester.pumpAndSettle();
      expect(find.text('Profile alice'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      repo.blockedIds.add('alice');
      repo.changed.add(null);
      await tester.pumpAndSettle();
      expect(find.text('No matching people'), findsOneWidget);
    },
  );

  testWidgets('blocked-list errors hide search results until retry succeeds', (
    tester,
  ) async {
    repo.failBlocks = true;
    await open(tester);
    await search(tester, 'alice');
    repo.pending.last.complete(PeoplePage([person('alice')]));
    await tester.pumpAndSettle();
    expect(find.text('@alice'), findsNothing);
    repo.failBlocks = false;
    await tester.tap(find.text('Could not load blocked accounts. Retry'));
    await tester.pumpAndSettle();
    expect(find.text('@alice'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.enterText(find.byType(TextField), '@');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Clear search'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Clear search'), findsNothing);
  });

  testWidgets(
    'recent searches save submissions, replay, remove and clear without recording typing',
    (tester) async {
      history.values['viewer'] = ['bob', 'alice'];
      await open(tester);
      expect(find.text('Recent searches'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'bob'));
      await tester.pump();
      expect(repo.calls, ['bob']);
      repo.pending.last.complete(const PeoplePage([]));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove bob from recent searches'));
      await tester.pumpAndSettle();
      expect(history.values['viewer'], ['alice']);
      await tester.enterText(find.byType(TextField), 'char');
      await tester.pump(const Duration(milliseconds: 100));
      expect(history.values['viewer'], ['alice']);
      await tester.enterText(find.byType(TextField), '@CHARLIE');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(repo.calls.last, 'charlie');
      repo.pending.last.complete(const PeoplePage([]));
      await tester.pumpAndSettle();
      expect(history.values['viewer'], ['charlie', 'alice']);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();
      expect(history.values['viewer'], isEmpty);
      expect(find.text('Recent searches'), findsNothing);
    },
  );

  testWidgets(
    'history failures remain retryable and do not prevent searching',
    (tester) async {
      history.failLoad = true;
      await open(tester);
      expect(
        find.text('Could not load recent searches. Retry'),
        findsOneWidget,
      );
      history.failLoad = false;
      history.values['viewer'] = ['alice'];
      await tester.tap(find.text('Could not load recent searches. Retry'));
      await tester.pumpAndSettle();
      history.failSave = true;
      await tester.tap(find.widgetWithText(ListTile, 'alice'));
      await tester.pump();
      repo.pending.last.complete(const PeoplePage([]));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save recent searches on this device.'),
        findsOneWidget,
      );
      expect(find.text('No matching people'), findsOneWidget);
    },
  );

  testWidgets(
    'Show more appends results and keeps existing profiles after failure',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/a').set({'username_lower': 'a'});
      final cursor = await db.doc('users/a').get();
      await open(tester);
      await search(tester, 'a');
      repo.pending.last.complete(PeoplePage([person('a')], next: cursor));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show more'));
      await tester.pump();
      repo.pending.last.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('@a'), findsOneWidget);
      await tester.tap(find.text('Could not search people. Retry'));
      await tester.pump();
      repo.pending.last.complete(PeoplePage([person('a'), person('ab')]));
      await tester.pumpAndSettle();
      expect(find.text('@a'), findsOneWidget);
      expect(find.text('@ab'), findsOneWidget);
      expect(find.text('Show more'), findsNothing);
    },
  );
}
