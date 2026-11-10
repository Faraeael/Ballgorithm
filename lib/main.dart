import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'app.dart';
import 'features/season/season_storage.dart';

void main() {
  const generator = LeagueGenerator();
  const config = GenerationConfig(seed: 20261028);
  runApp(
    BasketballManagerApp(
      league: generator.generate(config),
      storage: FileSeasonStorage(filePath: 'ballgorithm_save.json'),
    ),
  );
}
