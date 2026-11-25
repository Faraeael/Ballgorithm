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
