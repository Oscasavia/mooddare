import 'core/analytics/analytics_lifecycle.dart';
import 'features/links/moment_links.dart';
import 'features/auth/presentation/account_access_guard.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'features/notifications/data/push_service.dart';
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
  MomentLinks.instance.start();
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

final _firebaseReady = ValueNotifier(false);
final _rootNavigator = GlobalKey<NavigatorState>();

class MoodDareApp extends StatelessWidget {
  const MoodDareApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MoodDare',
    navigatorKey: _rootNavigator,
    builder: (_, child) => ValueListenableBuilder<bool>(
      valueListenable: _firebaseReady,
      builder: (_, ready, _) => AccountAccessGuard(
        enabled: ready,
        onAccountDeleted: () => _rootNavigator.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate(showWelcome: true)),
          (_) => false,
        ),
        child: DismissKeyboard(child: child ?? const SizedBox.shrink()),
      ),
    ),
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
  _firebaseReady.value = true;
  await AnalyticsLifecycle.start();
  if (PushService.instance == null) {
    final service = PushService(
      auth: FirebaseAuth.instance,
      db: FirebaseFirestore.instance,
      messaging: FirebaseMessaging.instance,
    );
    PushService.instance = service;
    await service.start();
  }
}
