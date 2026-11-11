import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simulation_core/simulation_core.dart';

import 'app.dart';
import 'features/career/career_storage.dart';
import 'features/season/season_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const generator = LeagueGenerator();
  const config = GenerationConfig(seed: 20261028);

  final SeasonStorage storage;
  final GmCareerStorage careerStorage;
  if (kIsWeb) {
    // Web platform limitation: native File I/O is unavailable.
    // In-memory storage is used for browser demonstrations.
    storage = InMemorySeasonStorage();
    careerStorage = InMemoryGmCareerStorage();
  } else {
    final docsDir = await getApplicationDocumentsDirectory();
    storage = FileSeasonStorage(
      filePath: '${docsDir.path}/ballgorithm_save.json',
    );
    careerStorage = FileGmCareerStorage(
      filePath: '${docsDir.path}/ballgorithm_gm_career.json',
    );
  }

  runApp(
    BasketballManagerApp(
      league: generator.generate(config),
      storage: storage,
      careerStorage: careerStorage,
    ),
  );
}
