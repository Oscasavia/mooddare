import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mooddare/features/main/presentation/widgets/profile_navigation_icon.dart';

import 'support/fixture_images.dart';

void main() {
  Future<void> showIcon(
    WidgetTester tester,
    String? url, {
    bool selected = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ProfileNavigationIcon(photoUrl: url, selected: selected),
        ),
      ),
    ),
  );

  testWidgets('missing photos keep the selected and unselected person icons', (
    tester,
  ) async {
    for (final url in [null, '', '   ']) {
      for (final selected in [false, true]) {
        await showIcon(tester, url, selected: selected);
        expect(
          find.byIcon(selected ? Icons.person : Icons.person_outline),
          findsOneWidget,
        );
        expect(find.byType(Image), findsNothing);
      }
    }
  });

  testWidgets('photo is circular and updates when the profile photo changes', (
    tester,
  ) async {
    final previous = debugNetworkImageHttpClientProvider;
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 40, height: 30)),
    );
    debugNetworkImageHttpClientProvider = () => FixtureImages(bytes);
    addTearDown(() {
      debugNetworkImageHttpClientProvider = previous;
      PaintingBinding.instance.imageCache.clear();
    });
    for (final url in [
      'https://fixture.invalid/first.png',
      'https://fixture.invalid/new.png',
    ]) {
      await tester.runAsync(() async {
        final loaded = Completer<void>();
        final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener(
          (_, _) => loaded.complete(),
          onError: (Object e, StackTrace? s) => loaded.completeError(e, s),
        );
        stream.addListener(listener);
        await loaded.future;
        stream.removeListener(listener);
      });
      for (final selected in [false, true]) {
        await showIcon(tester, url, selected: selected);
        await tester.pumpAndSettle();
        final image = tester.widget<Image>(find.byType(Image));
        expect((image.image as NetworkImage).url, url);
        expect(image.fit, BoxFit.cover);
        expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
        expect(tester.getSize(find.byType(ClipOval)), const Size(24, 24));
        expect(find.byType(Icon), findsNothing);
      }
    }
    await showIcon(tester, null);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    debugNetworkImageHttpClientProvider = previous;
  });

  testWidgets('broken photos fall back without a layout change or exception', (
    tester,
  ) async {
    final previous = debugNetworkImageHttpClientProvider;
    debugNetworkImageHttpClientProvider = () => FixtureImages(Uint8List(0));
    addTearDown(() {
      debugNetworkImageHttpClientProvider = previous;
      PaintingBinding.instance.imageCache.clear();
    });
    await showIcon(
      tester,
      'https://fixture.invalid/broken.png',
      selected: true,
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(tester.getSize(find.byType(ClipOval)), const Size(24, 24));
    expect(tester.takeException(), isNull);
    debugNetworkImageHttpClientProvider = previous;
  });
}
