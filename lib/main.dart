import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'app.dart';

void main() {
  const generator = LeagueGenerator();
  const config = GenerationConfig(seed: 20261028);
  runApp(BasketballManagerApp(league: generator.generate(config)));
}
