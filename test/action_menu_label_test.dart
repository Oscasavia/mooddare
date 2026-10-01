import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/widgets/action_menu_label.dart';
import 'package:mooddare/core/widgets/share_icon.dart';
import 'package:mooddare/core/widgets/stable_popup_menu.dart';

void main() {
  testWidgets(
    'all actions share icon sizing; only destructive actions are red',
    (tester) async {
      final theme = ThemeData.dark();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                for (final action in MenuAction.values)
                  ActionMenuLabel(action: action, text: action.name),
              ],
            ),
          ),
        ),
      );
      for (final action in MenuAction.values) {
        final root = find.widgetWithText(ActionMenuLabel, action.name);
        final text = tester.widget<Text>(
          find.descendant(of: root, matching: find.byType(Text)),
        );
        final color = action == MenuAction.delete || action == MenuAction.block
            ? theme.colorScheme.error
            : theme.colorScheme.onSurface;
        expect(text.style?.color, color);
        if (action == MenuAction.share) {
          final icon = tester.widget<ShareIcon>(
            find.descendant(of: root, matching: find.byType(ShareIcon)),
          );
          expect(icon.color, color);
          expect(icon.size, 20);
        } else {
          final icon = tester.widget<Icon>(
            find.descendant(of: root, matching: find.byType(Icon)),
          );
          expect(icon.color, color);
          expect(icon.size, 20);
        }
      }
    },
  );
  testWidgets(
    'narrow enlarged menus wrap labels, disable blocked actions and dispatch enabled actions',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? selected;
      final theme = ThemeData.dark();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Scaffold(
            body: StablePopupMenu<String>(
              tooltip: 'Options',
              onSelected: (value) => selected = value,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'block',
                  enabled: false,
                  child: ActionMenuLabel(
                    action: MenuAction.block,
                    text: 'Blocked',
                    enabled: false,
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ActionMenuLabel(
                    action: MenuAction.delete,
                    text: 'Delete comment',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Options'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('Blocked')).style?.color,
        theme.disabledColor,
      );
      await tester.tap(find.text('Blocked'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      await tester.tap(find.text('Delete comment'));
      await tester.pumpAndSettle();
      expect(selected, 'delete');
      expect(tester.takeException(), isNull);
    },
  );
}
