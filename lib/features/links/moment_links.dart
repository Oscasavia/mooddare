import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

class MomentLinks {
  static final instance = MomentLinks();
  static const host = 'mooddare.web.app';
  final pending = ValueNotifier<String?>(null);
  StreamSubscription<Uri>? _subscription;
  static bool validId(String value) =>
      RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(value);
  static Uri url(String id) {
    if (!validId(id)) throw const FormatException('Invalid moment.');
    return Uri.https(host, '/moment/$id');
  }

  static String? parse(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host != host ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final segments = uri.pathSegments;
    if (segments.length != 2 ||
        segments.first != 'moment' ||
        !validId(segments.last) ||
        uri.path != '/moment/${segments.last}') {
      return null;
    }
    return segments.last;
  }

  void receive(Uri uri) {
    final id = parse(uri);
    if (id != null) pending.value = id;
  }

  void start({Stream<Uri>? links}) {
    _subscription ??= (links ?? AppLinks().uriLinkStream).listen(
      receive,
      onError: (Object _) {},
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    pending.dispose();
  }
}
