import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/auth/data/repositories/auth_repository.dart';
import 'package:mooddare/features/auth/presentation/screens/auth_form_screen.dart';

import 'entry_polish_test.dart' show mount;

class _Credential implements UserCredential {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements AuthRepository {
  final signups = <(String, String)>[];
  final logins = <(String, String)>[];
  int googleCalls = 0;
  Completer<UserCredential>? pending;
  bool fail = false;

  @override
  Future<UserCredential> signUpWithEmailAndPassword(
    String email,
    String password,
  ) async {
    signups.add((email, password));
    if (fail) throw FirebaseAuthException(code: 'network-request-failed');
    return pending == null ? _Credential() : await pending!.future;
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    logins.add((email, password));
    return _Credential();
  }

  @override
  Future<UserCredential?> signInWithGoogle() async {
    googleCalls++;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

Future<void> enter(WidgetTester tester, String label, String value) async {
  await tester.ensureVisible(field(label));
  await tester.enterText(field(label), value);
  await tester.pumpAndSettle();
}

Future<void> submit(WidgetTester tester, {bool signup = true}) async {
  final button = find.widgetWithText(
    FilledButton,
    signup ? 'Create account' : 'Sign in',
  );
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
}

Future<void> switchMode(WidgetTester tester, {required bool signup}) async {
  final label = find.text(
    signup ? 'Already a member? Sign in' : 'New here? Create an account',
  );
  await tester.ensureVisible(label);
  await tester.pumpAndSettle();
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: label, matching: find.byType(RichText)),
  );
  final text = paragraph.text.toPlainText();
  final start = text.indexOf(signup ? 'Sign in' : 'Create an account');
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: text.length),
      )
      .first;
  await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('confirmation is required and must match exactly', (
    tester,
  ) async {
    final auth = _Auth();
    await mount(tester, AuthFormScreen(signUp: true, repository: auth));
    await enter(tester, 'Email', '  tester@example.com  ');
    await enter(tester, 'Password', 'Example123! ');
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.text('Confirm your password'), findsOneWidget);
    expect(auth.signups, isEmpty);

    for (final mismatch in ['example123! ', 'Example123!', 'wrong-password']) {
      await enter(tester, 'Confirm password', mismatch);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(auth.signups, isEmpty);
    }
    await enter(tester, 'Confirm password', 'Example123! ');
    await submit(tester);
    await tester.pumpAndSettle();
    expect(auth.signups, [('tester@example.com', 'Example123! ')]);
    expect(find.text('Passwords do not match'), findsNothing);
  });

  testWidgets('matching confirmation does not bypass email or password rules', (
    tester,
  ) async {
    final auth = _Auth();
    await mount(tester, AuthFormScreen(signUp: true, repository: auth));
    await enter(tester, 'Email', 'invalid');
    await enter(tester, 'Password', 'short');
    await enter(tester, 'Confirm password', 'short');
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Use at least 8 characters'), findsOneWidget);
    expect(auth.signups, isEmpty);
  });

  testWidgets('editing the original password invalidates an old confirmation', (
    tester,
  ) async {
    final auth = _Auth();
    await mount(tester, AuthFormScreen(signUp: true, repository: auth));
    await enter(tester, 'Email', 'tester@example.com');
    await enter(tester, 'Password', 'original123');
    await enter(tester, 'Confirm password', 'original123');
    await enter(tester, 'Password', 'changed123');
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(auth.signups, isEmpty);
    await enter(tester, 'Confirm password', 'changed123');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(auth.signups, [('tester@example.com', 'changed123')]);
  });

  testWidgets('keyboard Next focuses confirmation and Done submits once', (
    tester,
  ) async {
    final auth = _Auth()..pending = Completer<UserCredential>();
    await mount(tester, AuthFormScreen(signUp: true, repository: auth));
    await enter(tester, 'Email', 'tester@example.com');
    await enter(tester, 'Password', 'Example123!');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    final confirmation = tester.widget<EditableText>(
      find.descendant(
        of: field('Confirm password'),
        matching: find.byType(EditableText),
      ),
    );
    expect(confirmation.focusNode.hasFocus, isTrue);
    expect(auth.signups, isEmpty);
    await enter(tester, 'Confirm password', 'Example123!');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(auth.signups, hasLength(1));
    for (final label in ['Email', 'Password', 'Confirm password']) {
      expect(tester.widget<TextFormField>(field(label)).enabled, isFalse);
    }
    for (final button in tester.widgetList<FilledButton>(
      find.byType(FilledButton),
    )) {
      expect(button.onPressed, isNull);
    }
    // A queued keyboard callback must not create another account.
    tester
        .widget<TextField>(
          find.descendant(
            of: field('Confirm password'),
            matching: find.byType(TextField),
          ),
        )
        .onSubmitted!('Example123!');
    await tester.pump();
    expect(auth.signups, hasLength(1));
    auth.pending!.complete(_Credential());
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(field('Confirm password')).enabled,
      isTrue,
    );
  });

  testWidgets('password visibility controls are independent and accessible', (
    tester,
  ) async {
    await mount(tester, AuthFormScreen(signUp: true, repository: _Auth()));
    bool obscured(String label) => tester
        .widget<TextField>(
          find.descendant(of: field(label), matching: find.byType(TextField)),
        )
        .obscureText;
    expect(obscured('Password'), isTrue);
    expect(obscured('Confirm password'), isTrue);
    await tester.ensureVisible(find.byTooltip('Show confirm password'));
    await tester.tap(find.byTooltip('Show confirm password'));
    await tester.pumpAndSettle();
    expect(obscured('Confirm password'), isFalse);
    expect(obscured('Password'), isTrue);
    expect(find.byTooltip('Hide confirm password'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Show password'));
    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();
    expect(obscured('Password'), isFalse);
    await tester.ensureVisible(find.byTooltip('Hide confirm password'));
    await tester.tap(find.byTooltip('Hide confirm password'));
    await tester.pumpAndSettle();
    expect(obscured('Confirm password'), isTrue);
    expect(obscured('Password'), isFalse);
  });

  testWidgets(
    'sign-in needs no confirmation and switching clears stale values',
    (tester) async {
      final auth = _Auth();
      await mount(tester, AuthFormScreen(signUp: true, repository: auth));
      await enter(tester, 'Email', 'tester@example.com');
      await enter(tester, 'Password', 'Example123!');
      await enter(tester, 'Confirm password', 'mismatch');
      await submit(tester);
      await tester.pumpAndSettle();
      await switchMode(tester, signup: true);
      expect(field('Confirm password'), findsNothing);
      expect(find.text('Passwords do not match'), findsNothing);
      // Existing accounts can have passwords shorter than the new-account rule.
      await enter(tester, 'Password', 'short');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(auth.logins, [('tester@example.com', 'short')]);
      expect(auth.signups, isEmpty);
      await switchMode(tester, signup: false);
      expect(
        tester
            .widget<TextFormField>(field('Confirm password'))
            .controller!
            .text,
        isEmpty,
      );
      await enter(tester, 'Password', 'Example123!');
      await submit(tester);
      await tester.pumpAndSettle();
      expect(find.text('Confirm your password'), findsOneWidget);
      expect(auth.signups, isEmpty);
    },
  );

  testWidgets('Google sign-up bypasses mismatched email password fields', (
    tester,
  ) async {
    final auth = _Auth();
    await mount(tester, AuthFormScreen(signUp: true, repository: auth));
    await enter(tester, 'Password', 'Example123!');
    await enter(tester, 'Confirm password', 'different');
    final google = find.byKey(const ValueKey('google_sign_in'));
    await tester.ensureVisible(google);
    await tester.pumpAndSettle();
    await tester.tap(google);
    await tester.pumpAndSettle();
    expect(auth.googleCalls, 1);
    expect(auth.signups, isEmpty);
    expect(find.text('Passwords do not match'), findsNothing);
  });

  testWidgets('network failure preserves confirmation and allows retry', (
    tester,
  ) async {
    final auth = _Auth()..fail = true;
    await mount(tester, AuthFormScreen(signUp: true, repository: auth));
    await enter(tester, 'Email', 'tester@example.com');
    await enter(tester, 'Password', 'Example123!');
    await enter(tester, 'Confirm password', 'Example123!');
    await submit(tester);
    await tester.pumpAndSettle();
    expect(
      find.text('Check your internet connection and try again.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextFormField>(field('Confirm password')).controller!.text,
      'Example123!',
    );
    auth.fail = false;
    await submit(tester);
    await tester.pumpAndSettle();
    expect(auth.signups, hasLength(2));
    expect(
      find.text('Check your internet connection and try again.'),
      findsNothing,
    );
  });

  testWidgets(
    'confirmation and errors fit a narrow screen with large text and keyboard',
    (tester) async {
      final auth = _Auth();
      await mount(
        tester,
        AuthFormScreen(signUp: true, repository: auth),
        scale: 2,
        size: const Size(320, 640),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await enter(tester, 'Email', 'tester@example.com');
      await enter(tester, 'Password', 'Example123!');
      await enter(tester, 'Confirm password', 'mismatch');
      await submit(tester);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Passwords do not match'));
      await tester.pumpAndSettle();
      expect(find.text('Passwords do not match').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await enter(tester, 'Confirm password', 'Example123!');
      await submit(tester);
      await tester.pumpAndSettle();
      expect(auth.signups, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
