import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/camera/presentation/capture_timer.dart';

void main() {
  testWidgets(
    'countdown refuses overlapping starts and releases a cancelled waiter',
    (tester) async {
      final timer = CaptureCountdown();
      final first = timer.start(3, canContinue: () => true);
      expect(await timer.start(10, canContinue: () => true), isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(timer.remaining, 2);
      timer.cancel();
      expect(await first, isFalse);
      expect(timer.running, isFalse);
      expect(timer.remaining, isNull);
      final next = timer.start(3, canContinue: () => true);
      await tester.pump(const Duration(seconds: 3));
      expect(await next, isTrue);
      timer.dispose();
    },
  );
  testWidgets(
    'invalid capture conditions and disposal never complete as a capture',
    (tester) async {
      final timer = CaptureCountdown();
      expect(await timer.start(0, canContinue: () => false), isFalse);
      expect(await timer.start(0, canContinue: () => true), isTrue);
      var held = true;
      final released = timer.start(3, canContinue: () => held);
      held = false;
      await tester.pump(const Duration(milliseconds: 100));
      expect(await released, isFalse);
      final disposed = timer.start(10, canContinue: () => true);
      timer.dispose();
      expect(await disposed, isFalse);
      await tester.pump(const Duration(seconds: 12));
    },
  );
}
