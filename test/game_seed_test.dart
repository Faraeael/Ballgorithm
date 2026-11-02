import 'package:basketball_manager/features/game/game_seed.dart';
import 'package:flutter_test/flutter_test.dart';

const int _golden = 0x9E3779B9;
const int _maxDerived = 0x7FFFFFFF;
const List<int> _leagueSeeds = [20261028, 0, 1, 0xFFFFFFFF, _golden, 12345];

/// The core's documented normalization: raw zero is replaced by the golden
/// value, every other 32-bit value normalizes to itself. Proven against
/// `GameInput.normalizedSeed` in `game_runner_parity_test.dart`.
int _normalized(int seed) => seed == 0 ? _golden : seed;

void main() {
  group('deriveGameSeed', () {
    test('is deterministic and repeatable', () {
      for (final leagueSeed in _leagueSeeds) {
        expect(
          deriveGameSeed(
            leagueSeed: leagueSeed,
            homeIndex: 3,
            awayIndex: 5,
            rematchIndex: 7,
          ),
          deriveGameSeed(
            leagueSeed: leagueSeed,
            homeIndex: 3,
            awayIndex: 5,
            rematchIndex: 7,
          ),
        );
      }
    });

    test('home and away are not interchangeable', () {
      for (final leagueSeed in _leagueSeeds) {
        for (var home = 0; home < 8; home++) {
          for (var away = 0; away < 8; away++) {
            if (home == away) continue;
            expect(
              deriveGameSeed(
                leagueSeed: leagueSeed,
                homeIndex: home,
                awayIndex: away,
                rematchIndex: 0,
              ),
              isNot(
                deriveGameSeed(
                  leagueSeed: leagueSeed,
                  homeIndex: away,
                  awayIndex: home,
                  rematchIndex: 0,
                ),
              ),
            );
          }
        }
      }
    });

    test('rematch cycle has exactly 256 distinct seeds per matchup', () {
      for (final leagueSeed in _leagueSeeds) {
        final seeds = {
          for (var rematch = 0; rematch < 256; rematch++)
            deriveGameSeed(
              leagueSeed: leagueSeed,
              homeIndex: 2,
              awayIndex: 6,
              rematchIndex: rematch,
            ),
        };
        expect(seeds, hasLength(256));
        expect(
          deriveGameSeed(
            leagueSeed: leagueSeed,
            homeIndex: 2,
            awayIndex: 6,
            rematchIndex: 256,
          ),
          deriveGameSeed(
            leagueSeed: leagueSeed,
            homeIndex: 2,
            awayIndex: 6,
            rematchIndex: 0,
          ),
          reason: 'the cycle is exactly 256 games',
        );
      }
    });

    test(
      'derived seeds stay in the 31-bit domain and never hit 0x9E3779B9',
      () {
        for (final leagueSeed in _leagueSeeds) {
          for (var home = 0; home < 8; home++) {
            for (var away = 0; away < 8; away++) {
              for (var rematch = 0; rematch < 256; rematch++) {
                final seed = deriveGameSeed(
                  leagueSeed: leagueSeed,
                  homeIndex: home,
                  awayIndex: away,
                  rematchIndex: rematch,
                );
                if (seed < 0 || seed > _maxDerived || seed == _golden) {
                  fail(
                    'seed out of domain: league=$leagueSeed home=$home '
                    'away=$away rematch=$rematch -> 0x'
                    '${seed.toRadixString(16)}',
                  );
                }
              }
            }
          }
        }
      },
    );

    test(
      'all 16,384 bounded inputs give distinct derived and normalized seeds',
      () {
        for (final leagueSeed in _leagueSeeds) {
          final derived = <int>{};
          final normalized = <int>{};
          for (var home = 0; home < 8; home++) {
            for (var away = 0; away < 8; away++) {
              for (var rematch = 0; rematch < 256; rematch++) {
                final seed = deriveGameSeed(
                  leagueSeed: leagueSeed,
                  homeIndex: home,
                  awayIndex: away,
                  rematchIndex: rematch,
                );
                derived.add(seed);
                normalized.add(_normalized(seed));
              }
            }
          }
          expect(derived, hasLength(16384), reason: 'league seed $leagueSeed');
          expect(
            normalized,
            hasLength(16384),
            reason: 'league seed $leagueSeed',
          );
        }
      },
    );
  });
}
