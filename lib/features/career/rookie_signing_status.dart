import 'package:simulation_core/simulation_core.dart';

/// Public signing status labels shared by offseason, signing and draft-history
/// surfaces. Never exposes hidden potential or development trajectory.
String rookieSigningStatus(GmCareer career, PlayerId playerId) {
  final contract = career.rookieSigningLedger.forPlayer(playerId);
  if (contract == null) return 'Unsigned rights';
  return switch (contract.category) {
    RosterCategory.standard => 'Signed — Standard',
    RosterCategory.twoWay => 'Signed — Two-Way',
    RosterCategory.trainingCamp => 'Signed',
  };
}

/// True when the player has a signed rookie contract in [career].
bool isSignedRookie(GmCareer career, PlayerId playerId) =>
    career.rookieSigningLedger.isSigned(playerId);
