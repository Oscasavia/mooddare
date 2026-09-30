import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/membership/membership_preview.dart';
import 'package:mooddare/features/profile/presentation/screens/settings_screen.dart';
import '../test/support/settings_fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'development membership comparison opens, switches and returns safely',
    (tester) async {
      expect(
        membershipPreviewEnabled,
        isTrue,
        reason: 'Run with --dart-define=MOODDARE_MEMBERSHIP_PREVIEW=true',
      );
      final shot = GlobalKey();
      final repo = MemorySettings();
      await tester.pumpWidget(
        RepaintBoundary(
          key: shot,
          child: MaterialApp(
            theme: AppTheme.build(),
            home: SettingsScreen(repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Membership preview'));
      await tester.tap(find.text('Membership preview'));
      await tester.pumpAndSettle();
      Future<void> screenshot(String name) async {
        final image =
            await (shot.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${(await getTemporaryDirectory()).path}/$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      }

      await screenshot('membership-daring');
      await tester.tap(find.byKey(const ValueKey('membership_epic')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View plan options'));
      await tester.pumpAndSettle();
      final yearly = find.byKey(const ValueKey('membership_yearly'));
      await tester.ensureVisible(yearly);
      await tester.tap(yearly);
      await tester.pumpAndSettle();
      expect(
        find.text('One payment per year · Pricing to come'),
        findsOneWidget,
      );
      await screenshot('membership-epic');
      await tester.tap(find.text('Keep exploring'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Make it your look'));
      await tester.pumpAndSettle();
      await screenshot('membership-comparison');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(repo.deletions + repo.signOuts, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
