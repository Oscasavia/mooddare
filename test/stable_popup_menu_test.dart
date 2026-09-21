import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/widgets/stable_popup_menu.dart';

void main() {
  testWidgets(
    'removing an action anchor during menu dismissal survives layout changes',
    (tester) async {
      var visible = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, set) => visible
                  ? StablePopupMenu<String>(
                      tooltip: 'Options',
                      onSelected: (_) => set(() => visible = false),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ],
                    )
                  : const Text('Deleted'),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pump();
      tester.view.physicalSize = const Size(380, 760);
      addTearDown(tester.view.resetPhysicalSize);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('Deleted'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
