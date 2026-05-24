extends Control

const ROUND_NAMES: Array = ["First Round", "Conference Semifinals", "Conference Finals", "Finals"]
const GAMES_TO_WIN: int = 4

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var round_label: Label = $VBoxContainer/RoundLabel
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var matchups_list: ItemList = $VBoxContainer/MatchupsList
@onready var sim_round_button: Button = $VBoxContainer/Actions/SimRoundButton
@onready var advance_button: Button = $VBoxContainer/Actions/AdvanceButton

var current_round: int = 1
var round_complete: bool = false
var bracket: Array = []
var round_winners: Array = []
var current_matchups: Array = []
var current_results: Array = []


func _ready() -> void:
	bracket = GameState.playoff_bracket.duplicate()
	sim_round_button.pressed.connect(_on_sim_round)
	advance_button.pressed.connect(_on_advance)

	if bracket.size() != 16:
		status_label.text = "Playoff bracket must contain 16 teams. Found %d." % bracket.size()
		sim_round_button.disabled = true
		advance_button.disabled = true
		return

	current_matchups = _pair_seeded_bracket(bracket)
	_update_round_label()
	_update_status_label()
	_refresh_matchups_list(current_matchups)


func _on_sim_round() -> void:
	if round_complete:
		return

	round_winners = []
	current_results = []

	# Each matchup is a best-of-seven series, including the Finals.
	for matchup in current_matchups:
		var team_a: Team = matchup[0]
		var team_b: Team = matchup[1]
		var series_result: Dictionary = SimEngine.simulate_series(team_a, team_b, GAMES_TO_WIN)
		series_result["team_a"] = team_a
		series_result["team_b"] = team_b
		round_winners.append(series_result["winner"])
		current_results.append(series_result)

	var player_team: Team = GameState.get_player_team()
	if player_team != null and _matchups_include_team(current_matchups, player_team) and not round_winners.has(player_team):
		status_label.text = "Your team was eliminated in the %s." % ROUND_NAMES[current_round - 1]
	elif player_team != null and round_winners.has(player_team):
		status_label.text = "Your team advanced from the %s." % ROUND_NAMES[current_round - 1]
	else:
		_update_status_label()

	_refresh_matchups_list(current_matchups, current_results)
	round_complete = true
	sim_round_button.disabled = true
	advance_button.disabled = false


func _on_advance() -> void:
	if not round_complete:
		return

	current_round += 1
	if current_round > ROUND_NAMES.size():
		_finish_playoffs()
		return

	current_matchups = _pair_adjacent_winners(round_winners)
	round_winners = []
	current_results = []
	round_complete = false
	_update_round_label()
	_refresh_matchups_list(current_matchups)
	_update_status_label()
	sim_round_button.disabled = false
	advance_button.disabled = true


func _finish_playoffs() -> void:
	if round_winners.is_empty():
		return

	var champion: Team = round_winners[0]
	GameState.champion_team_id = champion.team_id
	GameState.champion_name = _format_team_name(champion)
	title_label.text = "CHAMPION: %s" % _format_team_name(champion)

	if champion.team_id == GameState.player_team_id:
		status_label.text = "Your team won the championship."
	else:
		status_label.text = "Your team did not win the championship."

	GameState.set_phase(GameState.Phase.END_OF_SEASON)
	_show_advance_to_end_of_season()


func _show_advance_to_end_of_season() -> void:
	sim_round_button.disabled = true
	advance_button.text = "Advance to End of Season"
	advance_button.disabled = false
	if advance_button.pressed.is_connected(_on_advance):
		advance_button.pressed.disconnect(_on_advance)
	if not advance_button.pressed.is_connected(_on_go_to_end_of_season):
		advance_button.pressed.connect(_on_go_to_end_of_season)


func _on_go_to_end_of_season() -> void:
	get_tree().change_scene_to_file("res://scenes/EndOfSeason.tscn")


func _refresh_matchups_list(matchups: Array, results: Array = []) -> void:
	matchups_list.clear()
	if not results.is_empty():
		for result in results:
			matchups_list.add_item(_format_series_result(result))
		return

	for matchup in matchups:
		matchups_list.add_item("%s vs %s" % [_format_team_name(matchup[0]), _format_team_name(matchup[1])])


func _update_status_label() -> void:
	var player_team: Team = GameState.get_player_team()
	if player_team == null or not bracket.has(player_team):
		status_label.text = "Your team is not in the playoff bracket."
	elif _matchups_include_team(current_matchups, player_team):
		status_label.text = "Your team is in the playoff bracket."
	else:
		status_label.text = "Your team has been eliminated from the playoffs."


func _update_round_label() -> void:
	round_label.text = ROUND_NAMES[current_round - 1] if current_round <= ROUND_NAMES.size() else "Playoffs Complete"


func _pair_seeded_bracket(teams: Array) -> Array:
	var matchups: Array = []
	for index in range(8):
		matchups.append([teams[index], teams[teams.size() - 1 - index]])
	return matchups


func _pair_adjacent_winners(winners: Array) -> Array:
	var matchups: Array = []
	for index in range(0, winners.size(), 2):
		if index + 1 < winners.size():
			matchups.append([winners[index], winners[index + 1]])
	return matchups


func _matchups_include_team(matchups: Array, team: Team) -> bool:
	for matchup in matchups:
		if matchup.has(team):
			return true
	return false


func _format_series_result(result: Dictionary) -> String:
	var winner: Team = result["winner"]
	var loser: Team = result["loser"]
	var loser_wins: int = result["team_b_wins"] if winner == result["team_a"] else result["team_a_wins"]
	return "%s def. %s (%d-%d)" % [
		_format_team_name(winner),
		_format_team_name(loser),
		GAMES_TO_WIN,
		loser_wins
	]


func _format_team_name(team: Team) -> String:
	if team == null:
		return "Unknown Team"
	return "%s %s" % [team.city, team.name]
