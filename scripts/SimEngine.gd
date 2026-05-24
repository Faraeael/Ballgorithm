extends RefCounted
class_name SimEngine

const TOP_PLAYER_COUNT: int = 8
const COACH_BONUS_MULTIPLIER: int = 2
const FACILITY_BONUS_MULTIPLIER: int = 1
const HOME_COURT_ADVANTAGE: float = 0.03
const SEASON_WEEKS: int = 24
const PLAYOFF_HOME_COURT_PATTERN: Array = [true, true, false, false, true, false, true]


static func simulate_game(home_team: Team, away_team: Team) -> Dictionary:
	var home_strength: float = _calculate_effective_strength(home_team)
	var away_strength: float = _calculate_effective_strength(away_team)
	var total_strength: float = home_strength + away_strength

	# Win probability follows AGENTS.md: home strength share plus a flat home-court boost.
	var home_win_probability: float = 0.5
	if total_strength > 0.0:
		home_win_probability = home_strength / total_strength
	home_win_probability = clampf(home_win_probability + HOME_COURT_ADVANTAGE, 0.0, 1.0)

	var home_won: bool = randf() < home_win_probability
	var winner_score: int = randi_range(95, 128)
	var loser_score: int = maxi(winner_score - randi_range(1, 25), 70)
	var home_score: int = winner_score if home_won else loser_score
	var away_score: int = loser_score if home_won else winner_score

	return {
		"home_team_id": home_team.team_id,
		"away_team_id": away_team.team_id,
		"home_won": home_won,
		"home_score": home_score,
		"away_score": away_score
	}


static func simulate_week(schedule: Array, week: int, all_teams: Array) -> Array:
	var results: Array = []

	for game in schedule:
		if game.get("week", 0) != week or game.get("result", "") != "":
			continue

		var home_team: Team = _find_team_by_id(all_teams, game.get("home_team_id", ""))
		var away_team: Team = _find_team_by_id(all_teams, game.get("away_team_id", ""))
		if home_team == null or away_team == null:
			continue

		var result: Dictionary = simulate_game(home_team, away_team)
		game["result"] = "home" if result["home_won"] else "away"
		LeagueManager.record_result(home_team.team_id, away_team.team_id, result["home_won"])
		results.append(result)

	return results


static func simulate_full_season(schedule: Array, all_teams: Array) -> void:
	for week in range(1, SEASON_WEEKS + 1):
		simulate_week(schedule, week, all_teams)

	# Final pass catches any schedule entries with missing or invalid week metadata.
	for game in schedule:
		if game.get("result", "") != "":
			continue

		var home_team: Team = _find_team_by_id(all_teams, game.get("home_team_id", ""))
		var away_team: Team = _find_team_by_id(all_teams, game.get("away_team_id", ""))
		if home_team == null or away_team == null:
			continue

		var result: Dictionary = simulate_game(home_team, away_team)
		game["result"] = "home" if result["home_won"] else "away"
		LeagueManager.record_result(home_team.team_id, away_team.team_id, result["home_won"])


static func simulate_series(team_a: Team, team_b: Team, games_to_win: int) -> Dictionary:
	var team_a_wins: int = 0
	var team_b_wins: int = 0
	var games_played: int = 0

	while team_a_wins < games_to_win and team_b_wins < games_to_win:
		# NBA playoff home court is 2-2-1-1-1, with team_a holding home-court advantage.
		var pattern_index: int = mini(games_played, PLAYOFF_HOME_COURT_PATTERN.size() - 1)
		var team_a_home: bool = PLAYOFF_HOME_COURT_PATTERN[pattern_index]
		var home_team: Team = team_a if team_a_home else team_b
		var away_team: Team = team_b if team_a_home else team_a
		var result: Dictionary = simulate_game(home_team, away_team)
		var home_won: bool = result["home_won"]

		if (team_a_home and home_won) or (not team_a_home and not home_won):
			team_a_wins += 1
		else:
			team_b_wins += 1
		games_played += 1

	var winner: Team = team_a if team_a_wins >= games_to_win else team_b
	var loser: Team = team_b if winner == team_a else team_a
	return {
		"winner": winner,
		"loser": loser,
		"team_a_wins": team_a_wins,
		"team_b_wins": team_b_wins,
		"games_played": games_played
	}


static func _get_top_players(team: Team, count: int) -> Array:
	var players: Array = team.roster.duplicate()
	players.sort_custom(_sort_players_by_overall)
	return players.slice(0, mini(count, players.size()))


static func _calculate_effective_strength(team: Team) -> float:
	var top_players: Array = _get_top_players(team, TOP_PLAYER_COUNT)
	var total_overall: int = 0
	for player in top_players:
		total_overall += player.get_overall()

	# AGENTS.md uses top-eight average so deep benches do not over-influence game strength.
	var team_strength: float = 0.0
	if not top_players.is_empty():
		team_strength = float(total_overall) / float(top_players.size())

	# Staff and facilities are simple flat modifiers for v1 simulation balance.
	var coach_bonus: float = float(team.staff_coach * COACH_BONUS_MULTIPLIER)
	var facility_bonus: float = float(team.facilities * FACILITY_BONUS_MULTIPLIER)
	return team_strength + coach_bonus + facility_bonus


static func _sort_players_by_overall(player_a: Player, player_b: Player) -> bool:
	return player_a.get_overall() > player_b.get_overall()


static func _find_team_by_id(all_teams: Array, team_id: String) -> Team:
	for team in all_teams:
		if team.team_id == team_id:
			return team
	return null
