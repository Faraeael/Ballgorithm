import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'features/league/league_screen.dart';

class BasketballManagerApp extends StatelessWidget {
  const BasketballManagerApp({super.key, required this.league});

  final League league;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Basketball Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB4541E)),
      ),
      home: LeagueScreen(league: league),
    );
  }
}
