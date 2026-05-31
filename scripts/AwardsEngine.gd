extends RefCounted
class_name AwardsEngine

const AWARDS: Array = ["MVP", "DPOY", "ROY", "MIP", "SMOY", "Coach of the Year"]
const POSITIONS: Array[String] = ["PG", "SG", "SF", "PF", "C"]
const SEASON_GAMES: int = 82
const EXPECTED_WINS: Dictionary = {
	"Tanking": 20,
	"Rebuilding": 30,
	"Play-In": 38,
	"Playoff": 45,
	"Contender": 52
}


static func calculate_awards(all_teams: Array, season_stats: Dictionary) -> Dictionary:
	return {
		"MVP": _calculate_mvp(all_teams, season_stats),
		"DPOY": _calculate_dpoy(all_teams, season_stats),
		"ROY": _calculate_roy(all_teams, season_stats),
		"MIP": _calculate_mip(all_teams),
		"SMOY": _calculate_smoy(all_teams, season_stats),
		"Coach of the Year": _calculate_coach_of_the_year(all_teams)
	}


static func calculate_all_league_teams(all_teams: Array, season_stats: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"first_team": [],
		"second_team": [],
		"third_team": []
	}
	var used_players: Array = []

	for position in POSITIONS:
		var ranked_players: Array = _rank_players_at_position(all_teams, season_stats, position)
		for team_index in range(3):
			var selected: Player = _pick_next_unused(ranked_players, used_players)
			if selected == null:
				continue
			used_players.append(selected)
			match team_index:
				0:
					result["first_team"].append(selected)
				1:
					result["second_team"].append(selected)
				2:
					result["third_team"].append(selected)

	return result


static func build_season_stats(_schedule: Array, all_teams: Array) -> Dictionary:
	var stats: Dictionary = {}
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(GameState.current_year * 1000003 + all_teams.size())

	# Box scores are not persisted, so season averages are generated deterministically from ratings.
	for team in all_teams:
		var games_scale: float = float(maxi(team.wins, 0)) / float(SEASON_GAMES)
		var games_played: int = clampi(int(round(float(SEASON_GAMES) * games_scale)), 1, SEASON_GAMES)
		for player in team.roster:
			var points: float = (player.skills.get("Shooting3", 0) * 0.15 + player.skills.get("ShootingMid", 0) * 0.20 + player.skills.get("Finishing", 0) * 0.15 + player.mental.get("OffIQ", 0) * 0.10) / 10.0 + rng.randf_range(0.0, 3.0)
			var rebounds: float = (player.physicals.get("Strength", 0) * 0.25 + player.defense.get("PostD", 0) * 0.15) / 10.0 + rng.randf_range(0.0, 2.0)
			var assists: float = (player.skills.get("Passing", 0) * 0.30 + player.mental.get("OffIQ", 0) * 0.20) / 10.0 + rng.randf_range(0.0, 2.0)
			var steals: float = (player.defense.get("Steal", 0) * 0.40 + player.defense.get("PerimeterD", 0) * 0.10) / 10.0
			var blocks: float = (player.defense.get("Block", 0) * 0.40 + player.physicals.get("Vertical", 0) * 0.10) / 10.0

			stats[player.id] = {
				"points": points * games_scale,
				"rebounds": rebounds * games_scale,
				"assists": assists * games_scale,
				"steals": steals * games_scale,
				"blocks": blocks * games_scale,
				"games_played": games_played
			}

	return stats


static func store_player_ratings(all_teams: Array) -> Dictionary:
	var ratings: Dictionary = {}
	for team in all_teams:
		for player in team.roster:
			ratings[player.id] = player.get_overall()
	return ratings


static func _calculate_mvp(all_teams: Array, season_stats: Dictionary) -> Dictionary:
	var best_player: Player = null
	var best_team: Team = null
	var best_points: float = -1.0
	for team in all_teams:
		if team.wins <= team.losses:
			continue
		for player in team.roster:
			var points: float = _get_stat(season_stats, player, "points")
			if best_player == null or points > best_points or (is_equal_approx(points, best_points) and player.get_overall() > best_player.get_overall()):
				best_player = player
				best_team = team
				best_points = points
	return _player_award_info(best_player, best_team, "Led winning-team candidates with %.1f points per game." % best_points)


static func _calculate_dpoy(all_teams: Array, season_stats: Dictionary) -> Dictionary:
	var best_player: Player = null
	var best_team: Team = null
	var best_impact: float = -1.0
	for team in all_teams:
		for player in team.roster:
			var impact: float = _get_stat(season_stats, player, "steals") + _get_stat(season_stats, player, "blocks")
			var def_iq: int = player.defense.get("DefIQ", 0)
			var best_def_iq: int = best_player.defense.get("DefIQ", 0) if best_player != null else -1
			if best_player == null or impact > best_impact or (is_equal_approx(impact, best_impact) and def_iq > best_def_iq):
				best_player = player
				best_team = team
				best_impact = impact
	return _player_award_info(best_player, best_team, "Averaged %.1f combined steals and blocks." % best_impact)


static func _calculate_roy(all_teams: Array, season_stats: Dictionary) -> Dictionary:
	var best_player: Player = null
	var best_team: Team = null
	var best_points: float = -1.0
	for team in all_teams:
		for player in team.roster:
			if player.age > 22:
				continue
			var points: float = _get_stat(season_stats, player, "points")
			if best_player == null or points > best_points or (is_equal_approx(points, best_points) and player.get_overall() > best_player.get_overall()):
				best_player = player
				best_team = team
				best_points = points
	return _player_award_info(best_player, best_team, "Best young scorer at %.1f points per game." % best_points)


static func _calculate_mip(all_teams: Array) -> Dictionary:
	var best_player: Player = null
	var best_team: Team = null
	var best_improvement: int = -999
	if not GameState.prior_ratings.is_empty():
		for team in all_teams:
			for player in team.roster:
				if not GameState.prior_ratings.has(player.id):
					continue
				var improvement: int = player.get_overall() - int(GameState.prior_ratings[player.id])
				if best_player == null or improvement > best_improvement:
					best_player = player
					best_team = team
					best_improvement = improvement
		if best_player != null:
			return _player_award_info(best_player, best_team, "Improved by %d overall points from last season." % best_improvement)

	for team in all_teams:
		if team.situation != "Tanking" and team.situation != "Rebuilding":
			continue
		for player in team.roster:
			if best_player == null or player.age < best_player.age or (player.age == best_player.age and player.get_overall() > best_player.get_overall()):
				best_player = player
				best_team = team
	return _player_award_info(best_player, best_team, "No prior ratings available; selected the youngest high-upside player on a rebuilding roster.")


static func _calculate_smoy(all_teams: Array, season_stats: Dictionary) -> Dictionary:
	var best_player: Player = null
	var best_team: Team = null
	var best_points: float = -1.0
	for team in all_teams:
		var starters: Array = _get_top_players_by_overall(team.roster, 5)
		for player in team.roster:
			if starters.has(player):
				continue
			var points: float = _get_stat(season_stats, player, "points")
			if best_player == null or points > best_points or (is_equal_approx(points, best_points) and player.get_overall() > best_player.get_overall()):
				best_player = player
				best_team = team
				best_points = points
	return _player_award_info(best_player, best_team, "Led non-starters with %.1f points per game." % best_points)


static func _calculate_coach_of_the_year(all_teams: Array) -> Dictionary:
	var best_team: Team = null
	var best_surplus: int = -999
	for team in all_teams:
		var expected: int = EXPECTED_WINS.get(team.situation, 38)
		var surplus: int = team.wins - expected
		if best_team == null or surplus > best_surplus:
			best_team = team
			best_surplus = surplus
	if best_team == null:
		return _empty_award_info()
	var coach_name: String = best_team.staff_coach_member.get("name", "Coach Level %d" % best_team.staff_coach)
	return {"player_id": "", "player_name": coach_name, "team_name": _team_name(best_team), "reason": "%d wins above %s expectation." % [best_surplus, best_team.situation]}


static func _rank_players_at_position(all_teams: Array, season_stats: Dictionary, position: String) -> Array:
	var ranked: Array = []
	for team in all_teams:
		for player in team.roster:
			if player.position != position:
				continue
			ranked.append({"player": player, "score": _all_league_score(player, season_stats)})
	ranked.sort_custom(_sort_score_desc)
	var players: Array = []
	for entry in ranked:
		players.append(entry["player"])
	return players


static func _all_league_score(player: Player, season_stats: Dictionary) -> float:
	var points: float = _get_stat(season_stats, player, "points")
	var assists: float = _get_stat(season_stats, player, "assists")
	var rebounds: float = _get_stat(season_stats, player, "rebounds")
	if player.position == "PG" or player.position == "SG":
		return points + assists
	if player.position == "PF" or player.position == "C":
		return points + rebounds
	return points + rebounds * 0.5 + assists * 0.5


static func _sort_score_desc(a: Dictionary, b: Dictionary) -> bool:
	if is_equal_approx(a["score"], b["score"]):
		return a["player"].get_overall() > b["player"].get_overall()
	return a["score"] > b["score"]


static func _pick_next_unused(players: Array, used_players: Array) -> Player:
	for player in players:
		if not used_players.has(player):
			return player
	return null


static func _get_top_players_by_overall(players: Array, count: int) -> Array:
	var ranked: Array = players.duplicate()
	ranked.sort_custom(_sort_player_overall_desc)
	return ranked.slice(0, mini(count, ranked.size()))


static func _sort_player_overall_desc(a: Player, b: Player) -> bool:
	return a.get_overall() > b.get_overall()


static func _get_stat(season_stats: Dictionary, player: Player, stat_name: String) -> float:
	return float(season_stats.get(player.id, {}).get(stat_name, 0.0))


static func _sum_overall(players: Array) -> int:
	var total: int = 0
	for player in players:
		total += player.get_overall()
	return total


static func _player_award_info(player: Player, team: Team, reason: String) -> Dictionary:
	if player == null or team == null:
		return _empty_award_info()
	return {"player_id": player.id, "player_name": player.full_name, "team_name": _team_name(team), "reason": reason}


static func _empty_award_info() -> Dictionary:
	return {"player_id": "", "player_name": "No eligible winner", "team_name": "", "reason": "No eligible candidates."}


static func _team_name(team: Team) -> String:
	return "%s %s" % [team.city, team.name]
