import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

void main() {
  const service = CareerSetupService();
  const seed = 20261028;

  group('M008-T04: GmCareer & GmCareerCodec Domain & Serialization', () {
    late CareerSetupResult setupResult;

    setUpAll(() {
      final request = CareerSetupRequest(
        selectedTeamId: TeamId('team-1'),
        selectedSituation: FranchiseSituation.tanking,
        seed: seed,
      );
      setupResult = service.generate(request);
    });

    test(
      'AC-008-32: initializes GmCareer with correct initial Year 1 state',
      () {
        final career = GmCareer.fromSetupResult(setupResult);

        expect(career.schemaVersion, GmCareer.currentSchemaVersion);
        expect(career.currentYear, 1);
        expect(career.phase, CareerPhase.openingOffseason);
        expect(career.userFranchiseId, TeamId('team-1'));
        expect(career.originalSituation, FranchiseSituation.tanking);
        expect(career.userOpeningDraftPick, 1);
        expect(career.league.teams.length, 30);
        expect(career.careerProfiles.profiles.length, 360);
        expect(career.userTeam.id, TeamId('team-1'));
      },
    );

    test(
      'AC-008-33 & AC-008-34: save/load round-trip preserves exact state without regeneration',
      () {
        final career = GmCareer.fromSetupResult(setupResult);
        final jsonString = GmCareerCodec.encode(career);

        final decoded = GmCareerCodec.decode(jsonString);

        expect(decoded.id, career.id);
        expect(decoded.schemaVersion, career.schemaVersion);
        expect(decoded.generationSeed, career.generationSeed);
        expect(decoded.userFranchiseId, career.userFranchiseId);
        expect(decoded.originalSituation, career.originalSituation);
        expect(decoded.currentYear, career.currentYear);
        expect(decoded.phase, career.phase);
        expect(decoded.userOpeningDraftPick, career.userOpeningDraftPick);
        expect(decoded.league.teams.length, 30);

        // Verify all 30 teams and 360 players match exactly
        for (var t = 0; t < 30; t++) {
          final origTeam = career.league.teams[t];
          final decTeam = decoded.league.teams[t];
          expect(decTeam.id, origTeam.id);
          expect(decTeam.name, origTeam.name);
          expect(decTeam.abbreviation, origTeam.abbreviation);
          expect(decTeam.situation, origTeam.situation);
          expect(decTeam.players.length, 12);

          for (var p = 0; p < 12; p++) {
            final origPlayer = origTeam.players[p];
            final decPlayer = decTeam.players[p];
            expect(decPlayer.id, origPlayer.id);
            expect(decPlayer.firstName, origPlayer.firstName);
            expect(decPlayer.lastName, origPlayer.lastName);
            expect(decPlayer.position, origPlayer.position);
            expect(decPlayer.attributes.asMap, origPlayer.attributes.asMap);

            // Verify career profile
            final origProfile = career.careerProfiles.forPlayer(origPlayer.id);
            final decProfile = decoded.careerProfiles.forPlayer(decPlayer.id);
            expect(decProfile!.age, origProfile!.age);
            expect(decProfile.potential, origProfile.potential);
            expect(decProfile.trajectory, origProfile.trajectory);
          }
        }
      },
    );

    test(
      'AC-008-35: preserves selected franchise, situation, and draft pick across all situations',
      () {
        for (final situation in FranchiseSituation.values) {
          final request = CareerSetupRequest(
            selectedTeamId: TeamId('team-7'),
            selectedSituation: situation,
            seed: seed + situation.index,
          );
          final res = service.generate(request);
          final career = GmCareer.fromSetupResult(res);
          final jsonString = GmCareerCodec.encode(career);
          final decoded = GmCareerCodec.decode(jsonString);

          expect(decoded.userFranchiseId, TeamId('team-7'));
          expect(decoded.originalSituation, situation);
          expect(decoded.userOpeningDraftPick, situation.userOpeningDraftPick);
        }
      },
    );

    test('AC-008-36: codec rejects malformed or corrupted JSON', () {
      expect(
        () => GmCareerCodec.decode('not-json'),
        throwsA(isA<FormatException>()),
      );
      expect(() => GmCareerCodec.decode('[]'), throwsA(isA<FormatException>()));
      expect(() => GmCareerCodec.decode('{}'), throwsA(isA<FormatException>()));
    });

    test('AC-008-36: codec rejects unsupported schema version', () {
      final career = GmCareer.fromSetupResult(setupResult);
      final jsonMap =
          jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;
      jsonMap['schemaVersion'] = 999;

      expect(
        () => GmCareerCodec.decode(jsonEncode(jsonMap)),
        throwsA(
          predicate<FormatException>(
            (e) => e.message.contains('Unsupported career schema version: 999'),
          ),
        ),
      );
    });

    test('AC-008-36: codec rejects missing or empty ID and fields', () {
      final career = GmCareer.fromSetupResult(setupResult);
      final jsonMap =
          jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;

      final withoutId = Map<String, dynamic>.from(jsonMap)..['id'] = '';
      expect(
        () => GmCareerCodec.decode(jsonEncode(withoutId)),
        throwsA(isA<FormatException>()),
      );

      final withoutSeed = Map<String, dynamic>.from(jsonMap)
        ..remove('generationSeed');
      expect(
        () => GmCareerCodec.decode(jsonEncode(withoutSeed)),
        throwsA(isA<FormatException>()),
      );

      final withoutPhase = Map<String, dynamic>.from(jsonMap)..remove('phase');
      expect(
        () => GmCareerCodec.decode(jsonEncode(withoutPhase)),
        throwsA(isA<FormatException>()),
      );
    });

    test('validation rejects invalid Year 1 draft pick mismatch', () {
      final career = GmCareer.fromSetupResult(setupResult);
      final jsonMap =
          jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;
      // Tanking expected pick 1, force pick 30
      jsonMap['userOpeningDraftPick'] = 30;

      expect(
        () => GmCareerCodec.decode(jsonEncode(jsonMap)),
        throwsA(
          predicate<FormatException>(
            (e) => e.message.contains('Opening draft pick mismatch'),
          ),
        ),
      );
    });

    test('validation rejects incomplete player career profiles', () {
      final career = GmCareer.fromSetupResult(setupResult);
      final jsonMap =
          jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;
      final rawProfiles = jsonMap['careerProfiles'] as Map<String, dynamic>;
      final profileMap = Map<String, dynamic>.from(
        rawProfiles['profiles'] as Map,
      );
      // Remove one player profile
      profileMap.remove(profileMap.keys.first);
      rawProfiles['profiles'] = profileMap;

      expect(
        () => GmCareerCodec.decode(jsonEncode(jsonMap)),
        throwsA(
          predicate<FormatException>(
            (e) => e.message.contains('Missing career profile for player'),
          ),
        ),
      );
    });
  });
}
