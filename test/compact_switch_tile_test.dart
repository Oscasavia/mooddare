import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/core/widgets/compact_switch_tile.dart';

void main() {
  testWidgets(
    'compact switch retains a full tap target, row toggling and disabled behavior',
    (tester) async {
      var value = false;
      var calls = 0;
      var enabled = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, set) {
                update = set;
                return CompactSwitchTile(
                  title: const Text('Phone alerts'),
                  value: value,
                  onChanged: enabled
                      ? (next) => set(() {
                          value = next;
                          calls++;
                        })
                      : null,
                );
              },
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(ListTile)).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(find.byType(Switch)).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.text('Phone alerts'));
      await tester.pumpAndSettle();
      expect(value, true);
      expect(calls, 1);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(value, false);
      expect(calls, 2);
      update(() => enabled = false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phone alerts'));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(calls, 2);
    },
  );
}
