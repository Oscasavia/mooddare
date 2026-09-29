import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'export_brand_assets.dart' as brand;

void main() {
  test('export Mood-wink notification silhouette', () {
    File(
      'android/app/src/main/res/drawable/ic_notification.xml',
    ).writeAsStringSync(
      brand.vector(
        color: '#FFFFFFFF',
        viewport: 100,
        scale: .84,
        offset: 8,
        size: 24,
      ),
    );
  });
}
