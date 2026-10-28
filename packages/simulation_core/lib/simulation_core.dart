/// Pure Dart basketball domain. No Flutter, Flame, database or network.
library;

export 'src/domain_versions.dart';
export 'src/generation/deterministic_random.dart';
export 'src/generation/league_generator.dart';
export 'src/generation/name_corpus.dart' show namePairCapacity, teamCatalog;
export 'src/models/generation_config.dart';
export 'src/models/ids.dart';
export 'src/models/league.dart';
export 'src/models/player.dart';
export 'src/models/player_attributes.dart';
export 'src/models/position.dart';
export 'src/models/roster.dart';
export 'src/models/team.dart';
export 'src/validation/league_validator.dart';
export 'src/validation/validation_result.dart';
