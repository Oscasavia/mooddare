import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/widgets/dismiss_keyboard.dart';
import 'package:mooddare/core/widgets/share_icon.dart';

void main() {
  testWidgets(
    'mobile outside taps unfocus without losing drafts, and another field receives focus',
    (tester) async {
      final first = FocusNode(), second = FocusNode();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => DismissKeyboard(child: child!),
          home: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: first),
                TextField(focusNode: second),
                const Expanded(child: Center(child: Text('Outside'))),
              ],
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'Draft');
      expect(first.hasFocus, isTrue);
      await tester.tap(find.text('Outside'));
      await tester.pump();
      expect(first.hasFocus, isFalse);
      expect(find.text('Draft'), findsOneWidget);
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      await tester.tap(find.byType(TextField).last);
      await tester.pump();
      expect(first.hasFocus, isFalse);
      expect(second.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'share mark faces top right and inherits consistent size and color',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ShareIcon(color: Colors.white)),
      );
      final transform = tester
          .widget<Transform>(find.byType(Transform).last)
          .transform;
      expect(transform.entry(0, 0), closeTo(math.sqrt(.5), .0001));
      expect(transform.entry(1, 0), closeTo(-math.sqrt(.5), .0001));
      final icon = tester.widget<Icon>(find.byIcon(Icons.send_outlined));
      expect(icon.size, 22);
      expect(icon.color, Colors.white);
    },
  );
}
