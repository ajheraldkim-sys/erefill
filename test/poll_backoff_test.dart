import 'package:erefill/core/utils/poll_backoff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PollBackoff', () {
    test('starts at the base interval', () {
      final backoff = PollBackoff(
        base: const Duration(seconds: 15),
        max: const Duration(minutes: 2),
      );
      expect(backoff.current, const Duration(seconds: 15));
    });

    test('doubles on each failure up to the cap', () {
      final backoff = PollBackoff(
        base: const Duration(seconds: 15),
        max: const Duration(minutes: 2),
      );
      final seen = [
        for (var i = 0; i < 5; i++) (backoff..failed()).current.inSeconds,
      ];
      expect(seen, [30, 60, 120, 120, 120]);
    });

    test('a success resets to the base interval', () {
      final backoff = PollBackoff(
        base: const Duration(seconds: 8),
        max: const Duration(minutes: 2),
      )
        ..failed()
        ..failed()
        ..succeeded();
      expect(backoff.current, const Duration(seconds: 8));
    });
  });
}
