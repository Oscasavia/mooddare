import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/core/widgets/mooddare_wordmark.dart';
import 'package:mooddare/features/auth/data/repositories/auth_repository.dart';
import 'package:mooddare/features/auth/presentation/screens/auth_form_screen.dart';
import 'package:mooddare/features/auth/presentation/screens/welcome_screen.dart';
import 'package:mooddare/features/auth/presentation/widgets/welcome_artwork.dart';
import 'package:mooddare/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:mooddare/features/user/data/repositories/user_repository.dart';
import 'package:mooddare/models/user_model.dart';
import 'moments_test.dart' show openFeed;
import 'support/moments_fakes.dart';

class EntryAuth implements AuthRepository {
  int googleCalls = 0;
  Completer<UserCredential?>? pending;
  bool fail = false;
  @override
  Future<UserCredential?> signInWithGoogle() async {
    googleCalls++;
    if (fail) throw FirebaseAuthException(code: 'network-request-failed');
    return pending == null ? null : await pending!.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Implement instead of constructing Firebase services in widget tests.
class ProfileMemory implements UserRepository {
  bool failLoad = false, failSave = false, missing = false;
  int saves = 0;
  Future<void>? loadGate, saveGate;
  String? savedName, savedUsername, savedBio;
  @override
  Future<UserModel?> getUserModel(String uid) async {
    await loadGate;
    if (failLoad) throw StateError('Offline');
    if (missing) return null;
    return UserModel(
      id: uid,
      username: 'moodfriend',
      name: 'Mood Friend',
      bio: 'Hello there',
      createdAt: Timestamp.now(),
    );
  }

  @override
  Future<void> saveProfile({
    required String username,
    String? name,
    String? bio,
    File? imageFile,
  }) async {
    saves++;
    savedUsername = username;
    savedName = name;
    savedBio = bio;
    await saveGate;
    if (failSave) {
      throw const FormatException('That username is already taken.');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  double scale = 1,
  Size size = const Size(320, 700),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
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
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> profile(
  WidgetTester tester,
  ProfileMemory repo, {
  double scale = 1,
}) async {
  await mount(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            final saved = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    EditProfileScreen(repository: repo, userId: 'viewer'),
              ),
            );
            if (context.mounted && saved == true) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Saved profile')));
            }
          },
          child: const Text('Edit'),
        ),
      ),
    ),
    scale: scale,
  );
  await tester.tap(find.text('Edit'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'welcome has two working entry options and original artwork at scale $scale',
      (tester) async {
        await mount(tester, const WelcomeScreen(), scale: scale);
        expect(find.text('Explore as a guest'), findsNothing);
        expect(find.text('📸'), findsNothing);
        expect(find.byType(WelcomeArtwork), findsOneWidget);
        expect(find.byType(MoodDareWordmark), findsOneWidget);
        final brandRect = tester.getRect(find.byType(MoodDareWordmark));
        final headlineRect = tester.getRect(
          find.text('A little dare.\nA great story.'),
        );
        expect(brandRect.left, closeTo(headlineRect.left, .1));
        expect(brandRect.width, lessThanOrEqualTo(180));
        expect(find.text('MOODDARE'), findsNothing);
        expect(find.text('A little dare.\nA great story.'), findsOneWidget);
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.byType(OutlinedButton), findsNothing);
        for (final signup in [true, false]) {
          final action = find.text(
            signup ? 'Get started' : 'Already a member? Sign in',
          );
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(
            tester.widget<AuthFormScreen>(find.byType(AuthFormScreen)).signUp,
            signup,
          );
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final signup in [false, true]) {
    testWidgets(
      'Google logo loads and button works in ${signup ? 'signup' : 'login'} without email validation',
      (tester) async {
        final repo = EntryAuth()..pending = Completer<UserCredential?>();
        await mount(tester, AuthFormScreen(signUp: signup, repository: repo));
        final button = find.byKey(const ValueKey('google_sign_in'));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        final logo = tester.widget<Image>(
          find.descendant(of: button, matching: find.byType(Image)),
        );
        expect(
          (logo.image as AssetImage).assetName,
          'assets/branding/google-g.png',
        );
        await tester.runAsync(
          () => precacheImage(logo.image, tester.element(button)),
        );
        expect(find.byIcon(Icons.login), findsNothing);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pump();
        expect(repo.googleCalls, 1);
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        expect(find.text('Enter a valid email'), findsNothing);
        repo.pending!.complete(null);
        await tester.pumpAndSettle();
        expect(find.byType(AuthFormScreen), findsOneWidget);
        repo.fail = true;
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(
          find.text('Check your internet connection and try again.'),
          findsOneWidget,
        );
        expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      },
    );
  }
  testWidgets(
    'top Save validates, preserves failed edits, blocks duplicate saves and returns success',
    (tester) async {
      final repo = ProfileMemory()..failSave = true;
      await profile(tester, repo);
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('profile_save'));
      expect(
        find.descendant(of: find.byType(AppBar), matching: save),
        findsOneWidget,
      );
      expect(find.text('Save changes'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'bad name!',
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.saves, 0);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'newname',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Display name'),
        'Updated Name',
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('That username is already taken.'), findsOneWidget);
      expect(find.text('newname'), findsOneWidget);
      repo.failSave = false;
      final gate = Completer<void>();
      repo.saveGate = gate.future;
      await tester.tap(save);
      await tester.pump();
      expect(tester.widget<TextButton>(save).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(repo.saves, 2);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsNothing);
      expect(find.text('Saved profile'), findsOneWidget);
      expect(repo.savedName, 'Updated Name');
      expect(repo.savedUsername, 'newname');
      expect(repo.savedBio, 'Hello there');
    },
  );
  testWidgets(
    'Save is disabled during initial load and failed/missing profile, and load can retry',
    (tester) async {
      final gate = Completer<void>();
      final repo = ProfileMemory()
        ..failLoad = true
        ..loadGate = gate.future;
      await profile(tester, repo);
      final save = find.byKey(const ValueKey('profile_save'));
      expect(tester.widget<TextButton>(save).onPressed, isNull);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Could not load your profile'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(tester.widget<TextButton>(save).onPressed, isNull);
      repo.failLoad = false;
      repo.missing = true;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(save).onPressed, isNull);
      repo.missing = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('moodfriend'), findsOneWidget);
      expect(tester.widget<TextButton>(save).onPressed, isNotNull);
    },
  );
  testWidgets(
    'top Save remains visible above keyboard on narrow phone with large text',
    (tester) async {
      await profile(tester, ProfileMemory(), scale: 2);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final bio = find.widgetWithText(TextFormField, 'A little about you');
      await tester.ensureVisible(bio);
      await tester.pumpAndSettle();
      final save = tester.getRect(find.byKey(const ValueKey('profile_save')));
      expect(save.top, greaterThanOrEqualTo(0));
      expect(save.bottom, lessThan(150));
      expect(save.right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'mood search trims and ignores case; only selecting a result changes feed',
    (tester) async {
      final repo = MemoryPosts([
        moment('happy', moodId: 'happy', moodName: 'Happy'),
        moment('calm', moodId: 'calm', moodName: 'Calm'),
      ]);
      await openFeed(tester, repo);
      await tester.tap(find.byTooltip('Filter by mood'));
      await tester.pumpAndSettle();
      final reads = repo.reads;
      await tester.enterText(
        find.byKey(const ValueKey('mood_filter_search')),
        '  hApP  ',
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Happy'), findsOneWidget);
      expect(find.text('Calm'), findsNothing);
      expect(find.text('All moods'), findsOneWidget);
      expect(repo.reads, reads);
      await tester.tap(find.widgetWithText(ListTile, 'Happy'));
      await tester.pumpAndSettle();
      expect(repo.selectedMood, 'happy');
      await tester.tap(find.byTooltip('Filter by mood'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('mood_filter_search')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Happy'),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('mood_filter_search')),
        'no such mood',
      );
      await tester.pumpAndSettle();
      expect(find.text('No matching moods. Try another name.'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear mood search'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Happy'), findsOneWidget);
      await tester.tap(find.text('All moods'));
      await tester.pumpAndSettle();
      expect(repo.selectedMood, isNull);
    },
  );
  testWidgets(
    'mood search fits above keyboard at large text; dismissing does not refresh feed',
    (tester) async {
      final repo = MemoryPosts([
        moment('happy', moodId: 'happy', moodName: 'Happy'),
      ]);
      await openFeed(tester, repo, size: const Size(320, 700), textScale: 2);
      final reads = repo.reads;
      await tester.tap(find.byTooltip('Filter by mood'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(find.byType(TextField), 'happy');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(repo.reads, reads);
      expect(repo.selectedMood, isNull);
    },
  );
}
