import 'package:simulation_core/simulation_core.dart';

/// Human-readable presentation formatters for GM Career domain values.
abstract final class CareerUiLabels {
  static String phaseName(CareerPhase phase) => switch (phase) {
    CareerPhase.openingOffseason => 'Opening Offseason',
    CareerPhase.regularSeason => 'Regular Season',
    CareerPhase.playIn => 'Play-In Tournament',
    CareerPhase.playoffs => 'Playoffs',
  };

  static String draftStatus(DraftExecutionStatus status) => switch (status) {
    DraftExecutionStatus.notStarted => 'Not Started',
    DraftExecutionStatus.inProgress => 'In Progress',
    DraftExecutionStatus.completed => 'Completed',
  };

  static String contractSource(ContractSource source) => switch (source) {
    ContractSource.legacy => 'Initial Roster',
    ContractSource.rookie => 'Rookie Scale',
    ContractSource.freeAgent => 'Free Agent Signing',
    ContractSource.extension => 'Contract Extension',
    ContractSource.trade => 'Acquired via Trade',
  };

  static String coachPhilosophy(CoachPhilosophy p) => switch (p) {
    CoachPhilosophy.balanced => 'Balanced',
    CoachPhilosophy.starFocused => 'Star-Focused',
    CoachPhilosophy.deepRotation => 'Deep Rotation',
    CoachPhilosophy.defensiveMinded => 'Defensive-Minded',
  };

  /// What the philosophy actually does in M011 (no hidden bonuses).
  static String coachPhilosophyEffect(CoachPhilosophy p) => switch (p) {
    CoachPhilosophy.balanced =>
      'Starts the highest-rated player at each position; balanced '
          'nine-player rotation.',
    CoachPhilosophy.starFocused =>
      'Starts the highest-rated player at each position; starter-heavy '
          'eight-player rotation.',
    CoachPhilosophy.deepRotation =>
      'Starts the highest-rated player at each position; ten-player '
          'rotation (starters 28:48, five reserves 19:12). Balanced '
          'rotation if fewer than ten standard players.',
    CoachPhilosophy.defensiveMinded =>
      'Starts the best perimeter defense + interior defense + rebounding '
          'player at each position; balanced nine-player rotation.',
  };

  static String staffRole(StaffCategory c) => switch (c) {
    StaffCategory.headCoach => 'Head Coach',
    StaffCategory.assistant => 'Assistant Coach',
    StaffCategory.playerDevelopment => 'Player Development',
    StaffCategory.scout => 'Scout',
    StaffCategory.medical => 'Medical',
  };

  static String staffTier(StaffTier t) => switch (t) {
    StaffTier.basic => 'Basic',
    StaffTier.standard => 'Standard',
    StaffTier.premium => 'Premium',
  };

  /// Who decides the human rotation, for status lines.
  static String rotationAuthority(TeamRotationDecision d) =>
      switch (d.authority) {
        RotationAuthority.automatic => 'Default rotation (coaching off)',
        RotationAuthority.manual => 'You (MANUAL plan)',
        RotationAuthority.headCoach =>
          'Head Coach ${d.coach!.firstName} ${d.coach!.lastName} · '
              '${coachPhilosophy(d.coach!.philosophy!)}',
        RotationAuthority.vacantFallback => 'No head coach — default rotation',
        RotationAuthority.coachPlanUnavailable =>
          'Coach plan unavailable — default rotation',
      };

  static String staffRejection(StaffRejectionCode code) => switch (code) {
    StaffRejectionCode.coachingDisabled => 'Coaching & Staff is not enabled.',
    StaffRejectionCode.coachingAlreadyEnabled => 'Coaching is already on.',
    StaffRejectionCode.wrongPhase =>
      'Staff changes are only allowed in the offseason, before the season '
          'starts.',
    StaffRejectionCode.unknownTeam => 'Unknown franchise.',
    StaffRejectionCode.teamHasHeadCoach =>
      'You already employ a head coach. Use Replace instead.',
    StaffRejectionCode.noHeadCoach => 'You have no employed head coach.',
    StaffRejectionCode.candidateUnavailable =>
      'This coach is no longer available.',
    StaffRejectionCode.invalidDuration => 'Contracts run 1–5 years.',
    StaffRejectionCode.overOperatingBudget =>
      'Operating commitments would exceed the operating budget.',
    StaffRejectionCode.insufficientCash =>
      'Projected cash would fall below the minimum-salary roster reserve.',
    StaffRejectionCode.renewalExceedsMaximum =>
      'Total contract length cannot exceed 5 years.',
  };

  static String formatCu(int amount) {
    final negative = amount < 0;
    final abs = amount.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < abs.length; i++) {
      final remaining = abs.length - i;
      if (i > 0 && remaining % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(abs[i]);
    }
    return '${negative ? '-' : ''}$buffer CU';
  }
}
