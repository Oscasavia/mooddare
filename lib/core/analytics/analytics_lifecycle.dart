import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:mooddare/features/settings/data/settings_repository.dart';
import 'product_analytics.dart';

class AnalyticsLifecycle with WidgetsBindingObserver {
  static AnalyticsLifecycle? _instance;
  static Future<void> start() async {
    if (_instance != null) return;
    final tracker = _instance = AnalyticsLifecycle();
    WidgetsBinding.instance.addObserver(tracker);
    FirebaseAuth.instance.authStateChanges().listen((_) => tracker.active());
    Timer.periodic(const Duration(minutes: 5), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        tracker.active();
      }
    });
    try {
      ProductAnalytics.version = (await SettingsRepository().version())
          .replaceAll(RegExp(r'[^a-zA-Z0-9_.:-]'), '_');
    } catch (_) {}
    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        kReleaseMode,
      );
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        previous?.call(details);
        unawaited(
          ProductAnalytics.instance.track('app_error', error: 'flutter'),
        );
        if (kReleaseMode) {
          unawaited(
            FirebaseCrashlytics.instance
                .recordFlutterFatalError(details)
                .catchError((Object _) {}),
          );
        }
      };
      final previousAsync = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (error, stack) {
        unawaited(
          ProductAnalytics.instance.track('app_error', error: 'unhandled'),
        );
        if (kReleaseMode) {
          unawaited(
            FirebaseCrashlytics.instance
                .recordError(error, stack, fatal: true)
                .catchError((Object _) {}),
          );
        }
        return previousAsync?.call(error, stack) ?? false;
      };
    } catch (_) {}
    tracker.active();
  }

  void active() => unawaited(ProductAnalytics.instance.track('app_active'));
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) active();
  }
}
