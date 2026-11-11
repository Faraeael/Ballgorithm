import '../validation/validation_result.dart';
import 'franchise_situation.dart';
import 'ids.dart';
import 'player.dart';
import 'roster.dart';
import 'roster_category.dart';

final class Team {
  Team({
    required this.id,
    required this.name,
    required this.abbreviation,
    required this.roster,
    this.situation,
  }) {
    final issues = <ValidationIssue>[];
    if (id.value.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.teamIdEmpty,
          path: 'team.id',
          message: 'team id must not be empty',
        ),
      );
    }
    if (name.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.teamNameEmpty,
          path: 'team.name',
          message: 'team name must not be empty',
        ),
      );
    }
    if (!RegExp(r'^[A-Z]{2,4}$').hasMatch(abbreviation)) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.teamAbbreviationInvalid,
          path: 'team.abbreviation',
          message:
              'abbreviation must be 2-4 uppercase letters, got "$abbreviation"',
        ),
      );
    }
    ValidationResult(issues).throwIfInvalid();
  }

  final TeamId id;
  final String name;
  final String abbreviation;
  final Roster roster;
  final FranchiseSituation? situation;
  List<Player> get players => roster.players;

  Team copyWith({
    String? name,
    String? abbreviation,
    Roster? roster,
    FranchiseSituation? situation,
  }) {
    return Team(
      id: id,
      name: name ?? this.name,
      abbreviation: abbreviation ?? this.abbreviation,
      roster: roster ?? this.roster,
      situation: situation ?? this.situation,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id.value,
    'name': name,
    'abbreviation': abbreviation,
    if (situation != null) 'situation': situation!.jsonValue,
    'roster': {
      'players': [for (final player in roster.players) player.toJson()],
      if (roster.categories.values.any((c) => c != RosterCategory.standard))
        'categories': {
          for (final entry in roster.categories.entries)
            entry.key: entry.value.jsonValue,
        },
    },
  };
}
