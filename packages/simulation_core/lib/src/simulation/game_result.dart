import '../models/ids.dart';
import 'box_score.dart';
import 'game_event.dart';
import 'game_input.dart';
import 'game_state.dart';

/// Immutable result of one completed, validated game.
///
/// All official statistics come from [boxScore], derived by `EventAccounting`
/// from [ledger]. The result stores the canonical [input] reference rather than
/// copying league or roster data.
final class GameResult {
  GameResult({
    required this.input,
    required this.inputFingerprint,
    required this.ledger,
    required this.state,
    required this.boxScore,
    required this.homeScore,
    required this.awayScore,
    required this.periodsPlayed,
    required this.possessions,
    required this.simulationVersion,
    required this.rulesVersion,
    required this.eventSchemaVersion,
    required this.prngImplementationId,
  });

  final GameInput input;
  final String inputFingerprint;
  final GameEventLedger ledger;
  final GameState state;
  final GameBoxScore boxScore;
  final int homeScore;
  final int awayScore;

  /// Regulation plus overtime periods actually played.
  final int periodsPlayed;

  /// Number of `PossessionStarted` events in the ledger.
  final int possessions;
  final int simulationVersion;
  final int rulesVersion;
  final int eventSchemaVersion;
  final String prngImplementationId;

  TeamId get homeTeamId => input.homeTeamId;
  TeamId get awayTeamId => input.awayTeamId;

  int get overtimes => periodsPlayed > input.rules.periods
      ? periodsPlayed - input.rules.periods
      : 0;

  /// Never a tie: the orchestrator refuses to finish a tied game.
  TeamId get winnerTeamId =>
      homeScore > awayScore ? input.homeTeamId : input.awayTeamId;

  TeamId get loserTeamId =>
      homeScore > awayScore ? input.awayTeamId : input.homeTeamId;

  List<GameEvent> get events => ledger.events;

  int get totalPoints => homeScore + awayScore;

  Map<int, int> get homePeriodScores =>
      boxScore.periodPoints[input.homeTeamId.value]!;

  Map<int, int> get awayPeriodScores =>
      boxScore.periodPoints[input.awayTeamId.value]!;
}
