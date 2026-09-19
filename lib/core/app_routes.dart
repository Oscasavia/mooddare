import 'package:flutter/material.dart';
import '../features/profile/presentation/screens/profile_screen.dart';

const profileRoute = '/profile';

Route<dynamic>? appRouteFactory(RouteSettings settings) {
  if (settings.name == profileRoute && settings.arguments is String) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) =>
          ProfileScreen(isGuest: false, userId: settings.arguments! as String),
    );
  }
  return null;
}
