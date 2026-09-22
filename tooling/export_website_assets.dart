// MOODDARE_FLUTTER_SDK=/path/to/flutter flutter test tooling/export_website_assets.dart
// Exports actual Flutter widgets with bundled example moods, never live users.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/core/branding/mood_wink.dart';
import 'package:mooddare/core/widgets/mooddare_wordmark.dart';
import 'package:mooddare/features/auth/presentation/screens/welcome_screen.dart';
import 'package:mooddare/features/dares/data/repositories/dares_repository.dart';
import 'package:mooddare/features/dares/presentation/screens/dares_screen.dart';
import 'package:mooddare/features/dares/presentation/screens/dare_generation_screen.dart';
import 'package:mooddare/features/settings/presentation/legal_screen.dart';
import 'package:mooddare/models/mood_model.dart';

void exportLegal(String name, String title, List<LegalSection> sections) {
  const escape = HtmlEscape();
  File('website/$name.html').writeAsStringSync('''<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="theme-color" content="#101016"><meta name="description" content="MoodDare $title. Last updated $legalUpdated.">
<title>$title — MoodDare</title><link rel="icon" href="assets/favicon.svg" type="image/svg+xml"><link rel="stylesheet" href="styles.css">
</head><body class="legal-page"><a class="skip-link" href="#main">Skip to content</a>
<header class="site-header wrap"><a class="brand" href="./" aria-label="MoodDare home"><img src="assets/wordmark.png" alt="mooddare" width="296" height="49"></a><a class="button button-small button-outline" href="./#downloads">Get the app <span aria-hidden="true">↗</span></a></header>
<main id="main" class="legal-content wrap"><a class="back-link" href="./">← Back to MoodDare</a><h1>$title</h1><p class="legal-date">Last updated $legalUpdated</p>
${sections.map((section) => '<section><h2>${escape.convert(section.title)}</h2><p>${escape.convert(section.body)}</p></section>').join('\n')}
</main><footer class="site-footer wrap"><div><a class="brand" href="./" aria-label="MoodDare home"><img src="assets/wordmark.png" alt="mooddare" width="296" height="49"></a><p>Stay curious. Be kind. Dare a little.</p></div><nav aria-label="Footer navigation"><a href="privacy.html">Privacy Policy</a><a href="terms.html">Terms of Use</a><a href="mailto:oscasavia@gmail.com">Say hello ↗</a></nav><p class="copyright">© 2026 MoodDare.</p></footer></body></html>
''');
}

void main() {
  testWidgets('export real app screens and approved branding for the website', (
    tester,
  ) async {
    final sdk =
        Platform.environment['MOODDARE_FLUTTER_SDK'] ??
        Platform.environment['FLUTTER_ROOT'];
    if (sdk == null) {
      throw StateError(
        'Set MOODDARE_FLUTTER_SDK to your Flutter SDK directory.',
      );
    }
    await tester.runAsync(() async {
      for (final family in ['Roboto', 'MaterialIcons']) {
        final loader = FontLoader(family);
        for (final name
            in family == 'Roboto'
                ? ['Roboto-Regular.ttf', 'Roboto-Bold.ttf']
                : ['MaterialIcons-Regular.otf']) {
          loader.addFont(
            Future.value(
              ByteData.sublistView(
                File(
                  '$sdk/bin/cache/artifacts/material_fonts/$name',
                ).readAsBytesSync(),
              ),
            ),
          );
        }
        await loader.load();
      }
      final emojiPath =
          Platform.environment['MOODDARE_EMOJI_FONT'] ??
          '/System/Library/Fonts/Apple Color Emoji.ttc';
      if (File(emojiPath).existsSync()) {
        final loader = FontLoader('PreviewEmoji')
          ..addFont(
            Future.value(
              ByteData.sublistView(File(emojiPath).readAsBytesSync()),
            ),
          );
        await loader.load();
      }
    });
    final appTheme = AppTheme.build();
    // Explicit button styles do not inherit the test renderer's text theme.
    final theme = appTheme.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: appTheme.filledButtonTheme.style!.copyWith(
          textStyle: WidgetStatePropertyAll(
            appTheme.filledButtonTheme.style!.textStyle!
                .resolve({})!
                .copyWith(fontFamily: 'Roboto'),
          ),
        ),
      ),
    );
    final key = GlobalKey();
    Future<void> capture(
      String name,
      Widget child, {
      Size size = const Size(390, 844),
      double pixelRatio = 2,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(
              fontFamily: 'Roboto',
              fontFamilyFallback: ['PreviewEmoji'],
            ),
          ),
          home: RepaintBoundary(key: key, child: child),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/branding/mooddare-wordmark.png'),
          key.currentContext!,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: pixelRatio);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          'website/assets/$name.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    }

    await capture(
      'wordmark',
      const Align(
        alignment: Alignment.topLeft,
        child: MoodDareWordmark(width: 592),
      ),
      size: const Size(592, 98),
      pixelRatio: 1,
    );
    await capture(
      'discover',
      Scaffold(
        body: DaresScreen(
          repository: DaresRepository(loadMoods: () async => []),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: 1,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dynamic_feed_outlined),
              label: 'Moments',
            ),
            NavigationDestination(
              icon: MoodWink(size: 26),
              selectedIcon: MoodWink(size: 26),
              label: 'Discover',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              label: 'You',
            ),
          ],
        ),
      ),
    );
    final creative = DaresRepository.starterMoods.first;
    await capture(
      'dare',
      DareDisplayScreen(
        isProofRequired: false,
        mood: MoodModel(
          id: creative.id,
          name: creative.name,
          icon: creative.icon,
          pack: creative.pack,
          color: creative.color,
          isLocked: false,
          dareList: [creative.dareList.last],
        ),
      ),
    );
    await capture('welcome', const WelcomeScreen());
    await capture(
      'social-preview',
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(80),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    MoodDareWordmark(width: 250),
                    SizedBox(height: 60),
                    Text(
                      'A little dare.\nA great story.',
                      style: TextStyle(
                        fontSize: 72,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -3,
                      ),
                    ),
                    SizedBox(height: 25),
                    Text(
                      'Pick a mood. Make a moment.',
                      style: TextStyle(fontSize: 25, color: Colors.white60),
                    ),
                  ],
                ),
              ),
              Transform.rotate(angle: -.12, child: const MoodWink(size: 280)),
            ],
          ),
        ),
      ),
      size: const Size(1200, 630),
      pixelRatio: 1,
    );
    final svg = File('assets/branding/mood-wink.svg').readAsStringSync();
    File(
      'website/assets/mood-wink.svg',
    ).writeAsStringSync(svg.replaceAll('#0D0E14', '#C5B4FF'));
    File('website/assets/favicon.svg').writeAsStringSync(
      svg
          .replaceFirst(
            '><path',
            '><rect width="100" height="100" rx="24" fill="#C5B4FF"/><g transform="translate(14 14) scale(.72)"><path',
          )
          .replaceFirst('</svg>', '</g></svg>'),
    );
    exportLegal('privacy', 'Privacy Policy', privacySections);
    exportLegal('terms', 'Terms of Use', termsSections);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
