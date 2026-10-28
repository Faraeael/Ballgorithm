import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

void main() {
  group('DeterministicRandom', () {
    test('matches the pinned xorshift32-v1 sequence for seed 42', () {
      final random = DeterministicRandom(42);

      expect(
        [for (var i = 0; i < 5; i++) random.nextUint32()],
        [11355432, 2836018348, 476557059, 3648046016, 3759983556],
      );
    });

    test('matches the pinned bounded sequence for seed 42', () {
      final random = DeterministicRandom(42);

      expect(
        [for (var i = 0; i < 8; i++) random.nextInt(100)],
        [32, 48, 59, 16, 56, 34, 40, 34],
      );
    });

    test('normalises the zero seed', () {
      final random = DeterministicRandom(0);

      expect(
        [for (var i = 0; i < 3; i++) random.nextUint32()],
        [1359758873, 3761132862, 2075758394],
      );
    });

    test('keeps nextInt within bounds', () {
      final random = DeterministicRandom(7);

      for (var i = 0; i < 500; i++) {
        final value = random.nextInt(13);
        expect(value, inInclusiveRange(0, 12));
      }
      expect(() => random.nextInt(0), throwsArgumentError);
    });

    test('supports the full 32-bit range and rejects larger bounds', () {
      final random = DeterministicRandom(42);

      expect(random.nextInt(1), 0);
      expect(random.nextInt(0x100000000), inInclusiveRange(0, 0xFFFFFFFF));
      expect(() => random.nextInt(0x100000001), throwsArgumentError);
      expect(() => random.nextInt(-1), throwsArgumentError);
    });

    test('shuffles deterministically for the same seed', () {
      final first = [for (var i = 0; i < 20; i++) i];
      final second = [for (var i = 0; i < 20; i++) i];
      DeterministicRandom(3).shuffle(first);
      DeterministicRandom(3).shuffle(second);

      expect(first, second);
      expect(first.toSet(), hasLength(20));
      expect(first, isNot([for (var i = 0; i < 20; i++) i]));
    });
  });
}
