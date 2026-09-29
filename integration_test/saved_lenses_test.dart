import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/camera/data/beauty_preferences.dart';
import 'package:mooddare/features/camera/domain/beauty_lens.dart';
import 'package:mooddare/features/camera/presentation/live_beauty_screen.dart';
import 'package:mooddare/features/feed/presentation/screens/preview_screen.dart';
import 'live_video_test.dart' show allowCameraAndAudio;
import 'live_beauty_test.dart' show channel, waitForState;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'favorites and custom makeup survive real Android storage and a camera retake',
    (tester) async {
      final temp = await (await getTemporaryDirectory()).createTemp(
        'saved-lenses-',
      );
      BeautyPreferences store() =>
          BeautyPreferences(directory: () async => temp);
      var preferences = store();
      Future<void> mount() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            home: LiveBeautyScreen(
              preferences: preferences,
              dareText: 'Saved lens test',
            ),
          ),
        );
        await waitForState(tester, (s) => s['ready'] == true);
        await tester.pump(const Duration(milliseconds: 500));
      }

      Future<void> unmount() async {
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await tester.pump(const Duration(milliseconds: 400));
        await channel.invokeMethod<void>('stop');
        await preferences.load(); // Wait for any queued final save.
      }

      try {
        await allowCameraAndAudio();
        await mount();
        final carousel = tester
            .widget<PageView>(find.byType(PageView))
            .controller!;
        carousel.jumpToPage(
          500 * BeautyLens.all.length + BeautyLens.all.length - 1,
        );
        await tester.pump(const Duration(milliseconds: 400));
        for (final (name, amount) in [
          ('smooth', .4),
          ('lips', .75),
          ('blush', .3),
        ]) {
          final tab = find.byKey(ValueKey('beauty_$name'));
          await tester.ensureVisible(tab);
          await tester.tap(tab);
          await tester.pump();
          tester
              .widget<Slider>(
                find.byKey(const ValueKey('custom_beauty_slider')),
              )
              .onChanged!(amount);
          await tester.pump(const Duration(milliseconds: 60));
        }
        carousel.jumpToPage(
          500 * BeautyLens.all.length +
              BeautyLens.all.indexWhere((l) => l.id == 'golden_hour'),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byTooltip('Favorite Golden Hour'));
        await tester.pump();
        // Closing before the favorite debounce fires must still persist it.
        await unmount();
        preferences = store();
        final saved = await preferences.load();
        expect(saved.favorites, {'golden_hour'});
        expect(saved.look.smooth, .4);
        expect(saved.look.lips, .75);
        expect(saved.look.blush, .3);
        await mount();
        expect(find.text('Original'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('lens_library_button')));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Favorites'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byKey(const ValueKey('library_lens_golden_hour')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('library_lens_golden_hour')),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Golden Hour'), findsOneWidget);
        tester
            .widget<PageView>(find.byType(PageView))
            .controller!
            .jumpToPage(
              500 * BeautyLens.all.length + BeautyLens.all.length - 1,
            );
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          tester
              .widget<Slider>(
                find.byKey(const ValueKey('custom_beauty_slider')),
              )
              .value,
          .4,
        );
        await tester.tap(find.byKey(const ValueKey('capture_shutter')));
        for (
          var i = 0;
          i < 150 && find.byType(PreviewScreen).evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(find.byType(PreviewScreen), findsOneWidget);
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pageBack();
        await waitForState(tester, (s) => s['ready'] == true);
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('My look'), findsOneWidget);
        expect(
          tester
              .widget<Slider>(
                find.byKey(const ValueKey('custom_beauty_slider')),
              )
              .value,
          .4,
        );
        await tester.tap(find.byTooltip('Reset my look'));
        await tester.pump(const Duration(milliseconds: 400));
        await unmount();
        final reset = await store().load();
        expect(reset.look.isOriginal, isTrue);
        expect(reset.favorites, {'golden_hour'});
        expect(tester.takeException(), isNull);
      } finally {
        await unmount();
        await temp.delete(recursive: true);
      }
    },
  );
}
