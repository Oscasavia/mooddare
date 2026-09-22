import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/branding/mood_wink.dart';
import 'package:mooddare/features/profile/presentation/widgets/my_dares_grid.dart';
import 'package:mooddare/features/profile/presentation/screens/connections_screen.dart';
import 'package:mooddare/models/post_model.dart';
import 'package:mooddare/models/user_model.dart';
import 'entry_polish_test.dart' show mount;
import 'moments_test.dart' show openFeed;
import 'support/moments_fakes.dart';
import 'support/social_fakes.dart';

class ProfileStates extends MemoryPosts {
  ProfileStates() : super([]);
  final changes = StreamController<List<PostModel>>();
  @override
  Stream<List<PostModel>> getUserPosts(String uid) => changes.stream;
}

void main() {
  testWidgets('profile smile follows empty results and is replaced by errors', (
    tester,
  ) async {
    final repo = ProfileStates();
    addTearDown(repo.changes.close);
    addTearDown(repo.commentChanges.close);
    repo.changes.add([]);
    await mount(
      tester,
      Scaffold(
        body: MyDaresGrid(userId: 'viewer', repository: repo),
      ),
      size: const Size(320, 480),
      scale: 2,
    );
    expect(find.text('Your story starts here'), findsOneWidget);
    expect(
      tester.widget<MoodWink>(find.byType(MoodWink)).expression,
      MoodWinkExpression.smile,
    );
    repo.changes.addError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MoodWink>(find.byType(MoodWink)).expression,
      MoodWinkExpression.error,
    );
    repo.changes.add([]);
    await tester.pumpAndSettle();
    expect(
      tester.widget<MoodWink>(find.byType(MoodWink)).expression,
      MoodWinkExpression.smile,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty feed uses a smile on a narrow screen with large text', (
    tester,
  ) async {
    final repo = MemoryPosts([]);
    addTearDown(repo.commentChanges.close);
    await openFeed(tester, repo, size: const Size(320, 640), textScale: 2);
    expect(find.text('The first moment could be yours'), findsOneWidget);
    expect(
      tester.widget<MoodWink>(find.byType(MoodWink)).expression,
      MoodWinkExpression.smile,
    );
    expect(tester.takeException(), isNull);
  });

  for (final followers in [true, false]) {
    testWidgets(
      '${followers ? 'followers' : 'following'} smile transitions to people and thinking search',
      (tester) async {
        final repo = MemorySocial();
        addTearDown(repo.changed.close);
        await mount(
          tester,
          ConnectionsScreen(
            userId: 'viewer',
            followers: followers,
            repository: repo,
          ),
          size: const Size(320, 640),
          scale: 2,
        );
        expect(
          tester.widget<MoodWink>(find.byType(MoodWink)).expression,
          MoodWinkExpression.smile,
        );
        repo.users['alice'] = UserModel(
          id: 'alice',
          username: 'alice',
          createdAt: Timestamp.now(),
        );
        (followers ? repo.followers : repo.following)['viewer'] = {'alice'};
        repo.changed.add(null);
        await tester.pumpAndSettle();
        expect(find.byType(MoodWink), findsNothing);
        expect(find.text('@alice'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'missing');
        await tester.pumpAndSettle();
        expect(
          tester.widget<MoodWink>(find.byType(MoodWink)).expression,
          MoodWinkExpression.thinking,
        );
        await tester.enterText(find.byType(TextField), 'alice');
        await tester.pumpAndSettle();
        expect(find.byType(MoodWink), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'friendly expressions preserve the icon silhouette and original eye shapes',
    () {
      final open = MoodWinkGeometry.path(0);
      for (final expression in [
        MoodWinkExpression.smile,
        MoodWinkExpression.talking,
      ]) {
        final face = MoodWinkGeometry.path(1, expression: expression);
        expect(face.getBounds(), open.getBounds());
        for (var y = 0; y < 100; y++) {
          for (var x = 0; x < 100; x++) {
            final point = Offset(x + .5, y + .5);
            // Only the mouth may change. This also guards the outline and eyes.
            if (y < 58 ||
                y > 87 ||
                x < 30 ||
                x > 76 ||
                expression == MoodWinkExpression.smile) {
              expect(face.contains(point), open.contains(point));
            }
          }
        }
      }
    },
  );
}
