import 'package:flutter/material.dart';
import 'core/app_routes.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/core/navigation.dart';
import 'package:mooddare/core/widgets/app_empty_state.dart';
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
    theme: AppTheme.build(),
    debugShowCheckedModeBanner: false,
    navigatorObservers: [appRouteObserver],
    onGenerateRoute: appRouteFactory,
    home: const _Startup(),
  );
}

class _Startup extends StatefulWidget {
  const _Startup();
  @override
  State<_Startup> createState() => _StartupState();
}

class _StartupState extends State<_Startup> {
  late Future<void> _ready;
  @override
  void initState() {
    super.initState();
    _ready = _initialize();
  }

  Future<void> _initialize() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _ready,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          body: AppEmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Let’s try that again',
            message:
                'MoodDare could not start. Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: () => setState(() => _ready = _initialize()),
          ),
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return const AuthGate();
    },
  );
}
