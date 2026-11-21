import 'career_phase.dart';
import 'gm_career.dart';
import 'season_archive.dart';

/// Package-internal proof that [career] and its extracted [archive] have both
/// passed full domain validation within the same trusted call chain.
///
/// Not exported from `package:simulation_core/simulation_core.dart`.
final class RolloverValidationProof {
  RolloverValidationProof._({required this.career, required this.archive});

  final GmCareer career;
  final SeasonArchive archive;

  /// Validates [career] once and constructs + validates its [SeasonArchive] once.
  static RolloverValidationProof validateCompletedSeason(GmCareer career) {
    career.validate();
    final rs = career.regularSeasonState;
    final pi = career.playInState;
    final po = career.playoffState;
    if (career.phase != CareerPhase.playoffs ||
        rs == null ||
        pi == null ||
        po == null ||
        !pi.isComplete ||
        !po.isComplete) {
      throw StateError('Cannot archive season before championship completion');
    }
    final archive = SeasonArchive(
      careerId: career.id,
      seasonId: rs.seasonId,
      seasonYear: career.currentYear,
      archiveId: SeasonArchive.archiveIdFor(rs.seasonId),
      regularSeasonState: rs,
      playInState: pi,
      playoffState: po,
    );
    return RolloverValidationProof._(career: career, archive: archive);
  }
}
