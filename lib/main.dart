import 'core/widgets/dismiss_keyboard.dart';
import 'package:flutter/material.dart';
import 'core/app_routes.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/core/navigation.dart';
import 'package:mooddare/core/widgets/branded_startup.dart';
import 'package:mooddare/features/auth/presentation/auth_gate.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MoodDareApp());
}

class MoodDareApp extends StatelessWidget {
  const MoodDareApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MoodDare',
    builder: (_, child) =>
        DismissKeyboard(child: child ?? const SizedBox.shrink()),
    theme: AppTheme.build(),
    debugShowCheckedModeBanner: false,
    navigatorObservers: [appRouteObserver],
    onGenerateRoute: appRouteFactory,
    home: BrandedStartup(
      initialize: _initializeFirebase,
      child: const AuthGate(),
    ),
  );
}

Future<void> _initializeFirebase() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}
