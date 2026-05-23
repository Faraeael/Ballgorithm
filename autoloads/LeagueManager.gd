extends Node

const TEAMS_PER_CONFERENCE: int = 15
const SEASON_GAMES: int = 82
const WEEKS_IN_SEASON: int = 24


# Returns all teams sorted by best record. Fewer losses wins the tiebreaker.
func get_standings() -> Array:
	var standings: Array = GameState.all_teams.duplicate()
	standings.sort_custom(_sort_by_record)
	return standings


# Splits the generated league by array order: first 15 East, last 15 West.
func get_conference_standings(conference: String) -> Array:
	var conference_teams: Array = []
	if conference == "East":
		conference_teams = GameState.all_teams.slice(0, TEAMS_PER_CONFERENCE)
	elif conference == "West":
		conference_teams = GameState.all_teams.slice(TEAMS_PER_CONFERENCE, TEAMS_PER_CONFERENCE * 2)
	else:
		return []

	conference_teams.sort_custom(_sort_by_record)
	return conference_teams


# Returns direct playoff qualifiers: seeds 1 through 6 from each conference.
func get_playoff_teams() -> Array:
	var playoff_teams: Array = []
	playoff_teams.append_array(get_conference_standings("East").slice(0, 6))
	playoff_teams.append_array(get_conference_standings("West").slice(0, 6))
	return playoff_teams


# Returns Play-In teams: seeds 7 through 10 from each conference.
func get_playin_teams() -> Array:
	var playin_teams: Array = []
	playin_teams.append_array(get_conference_standings("East").slice(6, 10))
	playin_teams.append_array(get_conference_standings("West").slice(6, 10))
	return playin_teams


# Returns lottery teams: seeds 11 through 15 from each conference.
func get_lottery_teams() -> Array:
	var lottery_teams: Array = []
	lottery_teams.append_array(get_conference_standings("East").slice(10, 15))
	lottery_teams.append_array(get_conference_standings("West").slice(10, 15))
	return lottery_teams


# Builds a flat 1,230-game schedule where each team appears in exactly 82 games.
func generate_schedule() -> Array:
	var schedule: Array = []
	var game_counts: Dictionary = {}
	var east_teams: Array = GameState.all_teams.slice(0, TEAMS_PER_CONFERENCE)
	var west_teams: Array = GameState.all_teams.slice(TEAMS_PER_CONFERENCE, TEAMS_PER_CONFERENCE * 2)

	for team in GameState.all_teams:
		game_counts[team.team_id] = 0

	_add_conference_games(schedule, game_counts, east_teams)
	_add_conference_games(schedule, game_counts, west_teams)
	_add_interconference_games(schedule, game_counts, east_teams, west_teams)

	GameState.schedule = schedule
	return schedule


# Updates records for a completed game. Missing teams are ignored safely.
func record_result(home_team_id: String, away_team_id: String, home_won: bool) -> void:
	var home_team: Team = _find_team_by_id(home_team_id)
	var away_team: Team = _find_team_by_id(away_team_id)
	if home_team == null or away_team == null:
		return

	if home_won:
		home_team.wins += 1
		away_team.losses += 1
	else:
		away_team.wins += 1
		home_team.losses += 1


# Clears standings before a new season simulation starts.
func reset_season_records() -> void:
	for team in GameState.all_teams:
		team.wins = 0
		team.losses = 0


func _sort_by_record(team_a: Team, team_b: Team) -> bool:
	if team_a.wins == team_b.wins:
		return team_a.losses < team_b.losses
	return team_a.wins > team_b.wins


func _add_conference_games(schedule: Array, game_counts: Dictionary, conference_teams: Array) -> void:
	for first_index in conference_teams.size():
		for second_index in range(first_index + 1, conference_teams.size()):
			var team_a: Team = conference_teams[first_index]
			var team_b: Team = conference_teams[second_index]

			# Four conference games per opponent: two at each arena.
			_add_game(schedule, game_counts, team_a, team_b)
			_add_game(schedule, game_counts, team_b, team_a)
			_add_game(schedule, game_counts, team_a, team_b)
			_add_game(schedule, game_counts, team_b, team_a)


func _add_interconference_games(schedule: Array, game_counts: Dictionary, east_teams: Array, west_teams: Array) -> void:
	for east_index in east_teams.size():
		var east_team: Team = east_teams[east_index]

		# Every East team plays every West team once for the first 15 interconference games.
		for west_index in west_teams.size():
			var west_team: Team = west_teams[west_index]
			if (east_index + west_index) % 2 == 0:
				_add_game(schedule, game_counts, east_team, west_team)
			else:
				_add_game(schedule, game_counts, west_team, east_team)

		# The remaining 11 interconference games use a shifted rotation so West teams also get 26.
		for offset in 11:
			var shifted_west_index: int = (east_index + offset) % west_teams.size()
			var extra_west_team: Team = west_teams[shifted_west_index]
			if offset % 2 == 0:
				_add_game(schedule, game_counts, east_team, extra_west_team)
			else:
				_add_game(schedule, game_counts, extra_west_team, east_team)


func _add_game(schedule: Array, game_counts: Dictionary, home_team: Team, away_team: Team) -> void:
	game_counts[home_team.team_id] += 1
	game_counts[away_team.team_id] += 1

	var game_number: int = max(game_counts[home_team.team_id], game_counts[away_team.team_id])
	var week: int = ceili(float(game_number) / float(SEASON_GAMES) * float(WEEKS_IN_SEASON))
	week = clampi(week, 1, WEEKS_IN_SEASON)

	schedule.append({
		"home_team_id": home_team.team_id,
		"away_team_id": away_team.team_id,
		"week": week,
		"game_number": game_number,
		"result": ""
	})


func _find_team_by_id(team_id: String) -> Team:
	for team in GameState.all_teams:
		if team.team_id == team_id:
			return team
	return null
