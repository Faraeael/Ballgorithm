import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 't04_v6_canonical_fixture.dart';

/// SHA-256 over the UTF-8 bytes of [t04CanonicalLedgerV6Json].
const String pinnedV6Digest =
    '7f0c3d2962f05a66ff54ad42b3a8d53059871ceca31ac1402cbc5c14e024aa12';

/// v6 fingerprint of the planned fixture input.
const String pinnedV6Fingerprint =
    '493b7c4f70cb297de89c4d0dd7e5ccda1a6e3e53c7a9ea4096e5c115ca4d8103';

const int pinnedV6EventCount = 804;

String sha256Hex(String value) => sha256.convert(utf8.encode(value)).toString();

void main() {
  // M006 T04: the v6 fixture is archive evidence only. Reproduction, replay,
  // link integrity and the mutation matrix moved to the v7 fixture in
  // t04_v7_fixture_test.dart, and v6 generation was verified once at the M005
  // checkpoint 68018db in a detached worktree (recorded in the M006 T04
  // evidence). The bytes and digest here must never change.
  group('v6 historical archive', () {
    test('pinned bytes, digest and header', () {
      expect(sha256Hex(t04CanonicalLedgerV6Json), pinnedV6Digest);
      final json = jsonDecode(t04CanonicalLedgerV6Json) as Map<String, Object?>;
      expect(jsonEncode(json), t04CanonicalLedgerV6Json);
      expect(json['eventSchemaVersion'], 3);
      expect(json['gameSimulationVersion'], 6);
      expect(json['gameRulesVersion'], 3);
      expect(json['prngImplementationId'], 'xorshift32-v1');
      expect(json['inputFingerprint'], pinnedV6Fingerprint);
      expect(json['gameId'], 'game-1');
      expect(json['events'], hasLength(pinnedV6EventCount));
    });
  });
}
