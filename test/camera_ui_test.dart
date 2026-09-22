import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/camera/presentation/live_beauty_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mooddare/live_beauty');
  double? sentAspect;
  final zooms = <double>[];
  var texture = 0;
  var captures = 0, videoStarts = 0, videoStops = 0;
  var allowRecording = false, nativeRecording = false, microphoneAllowed = true;
  final lightRequests = <bool>[];
  final looks = <Map<String, dynamic>>[];
  Map<String, dynamic>? captureLook;
  Map<String, dynamic>? videoLook;
  var geometryAvailable = false;
  setUp(() {
    sentAspect = null;
    zooms.clear();
    texture = 0;
    captures = videoStarts = videoStops = 0;
    allowRecording = nativeRecording = false;
    microphoneAllowed = true;
    lightRequests.clear();
    looks.clear();
    captureLook = null;
    videoLook = null;
    geometryAvailable = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setZoom') {
            expect(call.arguments['textureId'], texture);
            final zoom = (call.arguments['ratio'] as num).toDouble();
            zooms.add(zoom);
            return zoom;
          }
          if (call.method == 'setLook') {
            sentAspect = (call.arguments['aspectRatio'] as num).toDouble();
            looks.add(Map<String, dynamic>.from(call.arguments as Map));
          }
          if (call.method == 'setCaptureLight') {
            lightRequests.add(call.arguments['enabled'] as bool);
          }
          if (call.method == 'capture') {
            captureLook = looks.last;
            captures++;
            throw PlatformException(
              code: 'capture',
              message: 'Capture interrupted',
            );
          }
          if (call.method == 'stopRecording') {
            videoStops++;
            nativeRecording = false;
          }
          if (call.method == 'startRecording') {
            videoLook = looks.last;
            videoStarts++;
            if (allowRecording) {
              nativeRecording = true;
              return null;
            }
            throw PlatformException(
              code: 'recording',
              message: 'Recording interrupted',
            );
          }
          return switch (call.method) {
            'requestCamera' => true,
            'requestMicrophone' => microphoneAllowed,
            'start' => {
              'textureId': ++texture,
              'minZoom': 1.0,
              'maxZoom': 4.0,
              'zoom': 1.0,
            },
            'status' => {
              'ready': true,
              'recording': nativeRecording,
              'width': 960,
              'height': 1280,
              'faceDetected': true,
              'geometryDetected': geometryAvailable,
            },
            _ => null,
          };
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  Future<void> openTimerCamera(WidgetTester tester, {int seconds = 3}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: const LiveBeautyScreen(dareText: 'Timer test'),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    if (seconds != 0) {
      final timer = find.byKey(const ValueKey('camera_timer'));
      expect(
        tester.getTopLeft(timer).dy,
        greaterThan(
          tester.getBottomLeft(find.byTooltip('Screen flash off')).dy,
        ),
      );
      expect(
        tester.getTopLeft(timer).dy,
        lessThan(tester.getTopLeft(find.byTooltip('Adjust lens')).dy),
      );
      await tester.tap(timer);
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(
          of: find.text('$seconds seconds'),
          matching: find.byType(CheckedPopupMenuItem<int>),
        ),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> closeTimerCamera(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  Future<void> pinchPreview(WidgetTester tester) async {
    final center = tester.getCenter(find.byKey(const ValueKey('camera_frame')));
    final a = await tester.startGesture(
      center - const Offset(40, 0),
      pointer: 20,
    );
    final b = await tester.startGesture(
      center + const Offset(40, 0),
      pointer: 21,
    );
    await b.moveBy(const Offset(80, 0));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pump();
  }

  testWidgets(
    'preview pinch leaves photo, hold/lock recording and camera switching intact',
    (tester) async {
      allowRecording = true;
      await openTimerCamera(tester, seconds: 0);
      await pinchPreview(tester);
      expect(zooms.last, 2);
      expect(captures, 0);
      expect(videoStarts, 0);
      final shutter = find.byKey(const ValueKey('capture_shutter'));
      await tester.tap(shutter);
      await tester.pumpAndSettle();
      expect(captures, 1);
      // The mock capture fails and intentionally reopens the camera.
      expect(find.text('1.0×'), findsOneWidget);
      final finger = await tester.startGesture(
        tester.getCenter(shutter),
        pointer: 1,
      );
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pump();
      expect(videoStarts, 1);
      await pinchPreview(tester);
      expect(zooms.last, 2);
      expect(videoStops, 0);
      await finger.moveBy(const Offset(0, -110));
      await tester.pump();
      await finger.up();
      await tester.pump();
      expect(videoStops, 0);
      await pinchPreview(tester);
      expect(zooms.last, 4);
      expect(videoStops, 0);
      await tester.tap(shutter);
      await tester.pumpAndSettle();
      expect(videoStops, 1);
      await tester.tap(find.byTooltip('Switch camera'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.text('1.0×'), findsOneWidget);
      await pinchPreview(tester);
      expect(zooms.last, 2);
      expect(tester.takeException(), isNull);
      await closeTimerCamera(tester);
    },
  );

  for (final seconds in [3, 10]) {
    testWidgets(
      '$seconds second photo timer counts down once, delays flash and preserves the selected delay',
      (tester) async {
        await openTimerCamera(tester, seconds: seconds);
        await tester.tap(find.byTooltip('Screen flash off'));
        await tester.pump();
        final shutter = find.byKey(const ValueKey('capture_shutter'));
        await tester.tap(shutter);
        await tester.pump();
        expect(find.text('$seconds'), findsOneWidget);
        await tester.tap(shutter);
        await tester.pump();
        for (var remaining = seconds - 1; remaining >= 1; remaining--) {
          await tester.pump(const Duration(seconds: 1));
          expect(find.text('$remaining'), findsOneWidget);
          expect(captures, 0);
          expect(lightRequests, isEmpty);
        }
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(find.byKey(const ValueKey('capture_countdown')), findsNothing);
        expect(lightRequests, [true]);
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpAndSettle();
        expect(captures, 1);
        expect(lightRequests, [true, false]);
        expect(find.byTooltip('Timer: $seconds seconds'), findsOneWidget);
        await closeTimerCamera(tester);
      },
    );
  }
  for (final action in ['cancel', 'back', 'close', 'background', 'dispose']) {
    testWidgets('photo countdown cancels safely on $action', (tester) async {
      await openTimerCamera(tester);
      await tester.tap(find.byKey(const ValueKey('capture_shutter')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      switch (action) {
        case 'cancel':
          await tester.tap(find.text('Cancel timer'));
        case 'back':
          await tester.binding.handlePopRoute();
        case 'close':
          await tester.tap(find.byTooltip('Close camera'));
        case 'background':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
      }
      await tester.pump(const Duration(seconds: 12));
      await tester.pump();
      expect(captures, 0);
      expect(lightRequests, isEmpty);
      expect(find.byKey(const ValueKey('capture_countdown')), findsNothing);
      expect(tester.takeException(), isNull);
      await closeTimerCamera(tester);
    });
  }
  testWidgets('timer can be turned off and capture is immediate again', (
    tester,
  ) async {
    await openTimerCamera(tester);
    await tester.tap(find.byKey(const ValueKey('camera_timer')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('Off'),
        matching: find.byType(CheckedPopupMenuItem<int>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('capture_shutter')));
    await tester.pumpAndSettle();
    expect(captures, 1);
    expect(find.byKey(const ValueKey('capture_countdown')), findsNothing);
    await closeTimerCamera(tester);
  });
  testWidgets(
    'timed video starts hands-free after release and stops immediately on tap',
    (tester) async {
      allowRecording = true;
      await openTimerCamera(tester);
      final shutter = find.byKey(const ValueKey('capture_shutter'));
      final finger = await tester.startGesture(tester.getCenter(shutter));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      await finger.up();
      await tester.pump(const Duration(seconds: 2));
      expect(videoStarts, 0);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(videoStarts, 1);
      expect(nativeRecording, isTrue);
      expect(find.text('Tap to stop'), findsOneWidget);
      await tester.tap(shutter);
      await tester.pumpAndSettle();
      expect(videoStops, 1);
      expect(nativeRecording, isFalse);
      expect(captures, 0);
      await closeTimerCamera(tester);
    },
  );
  for (final action in ['cancel', 'background', 'permission denied']) {
    testWidgets('timed video does not record after $action', (tester) async {
      allowRecording = true;
      microphoneAllowed = action != 'permission denied';
      await openTimerCamera(tester);
      final finger = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('capture_shutter'))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await finger.up();
      if (action == 'cancel') await tester.tap(find.text('Cancel timer'));
      if (action == 'background') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
      }
      await tester.pump(const Duration(seconds: 12));
      await tester.pump();
      expect(videoStarts, 0);
      expect(captures, 0);
      expect(find.byKey(const ValueKey('capture_countdown')), findsNothing);
      await closeTimerCamera(tester);
    });
  }

  testWidgets(
    'Rosy guides missing geometry and clears makeup when switching looks',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: const LiveBeautyScreen(dareText: 'Rosy test'),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      final shutter = find.byKey(const ValueKey('capture_shutter'));
      // Original -> My look -> Rosy around the left edge of the repeating wheel.
      for (var i = 0; i < 2; i++) {
        await tester.drag(shutter, const Offset(90, 0));
        await tester.pumpAndSettle();
      }
      expect(find.text('Rosy'), findsOneWidget);
      expect(find.text('Face the camera for makeup'), findsOneWidget);
      expect(looks.last['makeup'], .65);
      await tester.tap(find.byTooltip('Compare original'));
      await tester.pump(const Duration(milliseconds: 60));
      expect(looks.last['original'], isTrue);
      expect(find.text('Face the camera for makeup'), findsNothing);
      await tester.tap(find.byTooltip('Show lens'));
      await tester.pump(const Duration(milliseconds: 60));
      geometryAvailable = true;
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Face the camera for makeup'), findsNothing);
      await tester.drag(shutter, const Offset(-90, 0));
      await tester.pumpAndSettle();
      expect(find.text('My look'), findsOneWidget);
      expect(looks.last['makeup'], 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('shaping explains missing mesh and clears the hint on recovery', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: const LiveBeautyScreen(dareText: 'Shape test'),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final shutter = find.byKey(const ValueKey('capture_shutter'));
    for (var i = 0; i < 3; i++) {
      await tester.drag(shutter, const Offset(-90, 0));
      await tester.pumpAndSettle();
    }
    expect(find.text('Wide eyes'), findsOneWidget);
    expect(find.text('Face the camera for shaping'), findsOneWidget);
    geometryAvailable = true;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Face the camera for shaping'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  for (final size in [const Size(320, 640), const Size(768, 1024)]) {
    testWidgets(
      'custom look retains independent amounts, compares and resets at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const LiveBeautyScreen(dareText: 'Your own look'),
          ),
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(find.text('Original'), findsOneWidget);
        final originalDisc = find.descendant(
          of: find.byKey(const ValueKey('capture_shutter')),
          matching: find.byKey(const ValueKey('original_lens_disc')),
        );
        final originalStyle =
            tester.widget<DecoratedBox>(originalDisc).decoration
                as BoxDecoration;
        expect(originalStyle.shape, BoxShape.circle);
        expect(originalStyle.color, AppTheme.accent.withValues(alpha: .25));
        expect(originalStyle.gradient, isNull);
        expect(
          find.descendant(of: originalDisc, matching: find.byType(Icon)),
          findsNothing,
        );
        for (final effect in [
          'smooth',
          'light',
          'warmth',
          'eyeSize',
          'faceSlim',
          'makeup',
        ]) {
          expect(looks.last[effect], 0);
        }
        final frame = tester.getRect(
          find.byKey(const ValueKey('camera_frame')),
        );
        // My look is immediately to the left of Original in the repeating wheel.
        await tester.drag(
          find.byKey(const ValueKey('capture_shutter')),
          const Offset(90, 0),
        );
        await tester.pumpAndSettle();
        expect(find.text('My look'), findsOneWidget);
        expect(find.byType(Slider), findsOneWidget);
        final slider = find.byKey(const ValueKey('custom_beauty_slider'));
        Future<void> adjust(String name, double value) async {
          final tab = find.byKey(ValueKey('beauty_$name'));
          await tester.ensureVisible(tab);
          await tester.tap(tab);
          await tester.pump();
          tester.widget<Slider>(slider).onChanged!(value);
          await tester.pump(const Duration(milliseconds: 60));
        }

        await adjust('smooth', .8);
        await adjust('eyes', .35);
        await adjust('face', .6);
        expect(looks.last, containsPair('smooth', .8));
        expect(looks.last, containsPair('eyeSize', .35));
        expect(looks.last, containsPair('faceSlim', .6));
        expect(
          tester.getRect(find.byKey(const ValueKey('camera_frame'))),
          frame,
        );

        await tester.tap(find.byTooltip('Compare original'));
        await tester.pump(const Duration(milliseconds: 60));
        expect(looks.last['original'], isTrue);
        expect(tester.widget<Slider>(slider).onChanged, isNull);
        await tester.tap(find.byTooltip('Show my look'));
        await tester.pump(const Duration(milliseconds: 60));
        expect(looks.last['original'], isFalse);
        expect(tester.widget<Slider>(slider).value, .6);

        // Switching through Original and a preset must not overwrite custom amounts.
        for (var i = 0; i < 2; i++) {
          await tester.drag(
            find.byKey(const ValueKey('capture_shutter')),
            const Offset(-90, 0),
          );
          await tester.pumpAndSettle();
        }
        expect(find.text('Soft'), findsOneWidget);
        expect(looks.last['eyeSize'], 0);
        for (var i = 0; i < 2; i++) {
          await tester.drag(
            find.byKey(const ValueKey('capture_shutter')),
            const Offset(90, 0),
          );
          await tester.pumpAndSettle();
        }
        expect(looks.last['eyeSize'], .35);
        expect(looks.last['smooth'], .8);
        await tester.tap(find.byTooltip('Switch camera'));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(looks.last['faceSlim'], .6);

        // Capture uses custom amounts and retains them after a native failure.
        await adjust('eyes', .45);
        await tester.tap(find.byKey(const ValueKey('capture_shutter')));
        await tester.pumpAndSettle();
        expect(captureLook?['eyeSize'], .45);
        expect(captureLook?['smooth'], .8);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        // Let the failure message leave the shutter's hit area before recording.
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        final hold = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('capture_shutter'))),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
        await hold.up();
        await tester.pumpAndSettle();
        expect(videoLook?['eyeSize'], .45);
        expect(videoLook?['faceSlim'], .6);
        await tester.tap(find.byTooltip('Adjust lens'));
        await tester.pump();
        await tester.tap(find.byTooltip('Reset my look'));
        await tester.pump(const Duration(milliseconds: 60));
        expect(looks.last['smooth'], 0);
        expect(looks.last['eyeSize'], 0);
        expect(looks.last['faceSlim'], 0);
        expect(tester.widget<Slider>(slider).value, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }

  for (final interrupt in [false, true]) {
    testWidgets(
      'screen flash is cleared after ${interrupt ? 'backgrounding' : 'capture failure'}',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            home: const LiveBeautyScreen(dareText: 'Flash test'),
          ),
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        await tester.tap(find.byTooltip('Screen flash off'));
        await tester.pump();
        expect(find.byTooltip('Screen flash on'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('capture_shutter')));
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const ValueKey('screen_flash')), findsOneWidget);
        expect(lightRequests, [true]);
        if (interrupt) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pump();
        expect(lightRequests, [true, false]);
        expect(captures, interrupt ? 0 : 1);
        expect(find.byKey(const ValueKey('screen_flash')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      },
    );
  }

  for (final size in [const Size(320, 640), const Size(768, 1024)]) {
    testWidgets(
      'camera framing stays consistent at $size with floating controls',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: const LiveBeautyScreen(
              dareText:
                  'A longer dare that stays out of the way while you capture your moment.',
            ),
          ),
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        final frame = find.byKey(const ValueKey('camera_frame'));
        expect(tester.getSize(frame).aspectRatio, closeTo(9 / 16, .0001));
        expect(tester.getCenter(frame), size.center(Offset.zero));
        expect(sentAspect, 9 / 16);
        for (final entry in {
          '3:4': 3 / 4,
          'Full': size.aspectRatio,
          '9:16': 9 / 16,
        }.entries) {
          await tester.tap(find.byKey(const ValueKey('camera_ratio')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.ancestor(
              of: find.text(entry.key).last,
              matching: find.byWidgetPredicate(
                (widget) => widget is PopupMenuItem,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.getSize(frame).aspectRatio,
            closeTo(entry.value, .0001),
          );
          expect(
            sentAspect,
            entry.value,
            reason:
                'The native export must use the same ratio as the viewfinder',
          );
          expect(tester.getRect(frame).left, greaterThanOrEqualTo(0));
          expect(tester.getRect(frame).right, lessThanOrEqualTo(size.width));
          expect(tester.getRect(frame).bottom, lessThanOrEqualTo(size.height));
          expect(tester.getCenter(frame), size.center(Offset.zero));
        }
        expect(tester.getSize(find.byType(PageView)).width, size.width);
        expect(tester.getRect(find.byType(TextButton)).bottom, lessThan(100));
        expect(find.byType(SegmentedButton<bool>), findsNothing);
        expect(find.byType(Slider), findsNothing);
        await tester.drag(
          find.byKey(const ValueKey('capture_shutter')),
          const Offset(-80, 0),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Adjust lens'));
        await tester.pump();
        expect(find.byType(Slider), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
}
