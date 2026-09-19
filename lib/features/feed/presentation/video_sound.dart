import 'package:flutter/foundation.dart';

/// Shared by feed and profile viewers for this app session. A fresh launch is quiet.
final videoMuted = ValueNotifier<bool>(true);
