extends Control

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var matchups_container: VBoxContainer = $VBoxContainer/MatchupsContainer
@onready var east_game_1_team_a_button: Button = $VBoxContainer/MatchupsContainer/EastGame1Row/EastGame1TeamAButton
@onready var east_game_1_team_b_button: Button = $VBoxContainer/MatchupsContainer/EastGame1Row/EastGame1TeamBButton
@onready var east_game_2_team_a_button: Button = $VBoxContainer/MatchupsContainer/EastGame2Row/EastGame2TeamAButton
@onready var east_game_2_team_b_button: Button = $VBoxContainer/MatchupsContainer/EastGame2Row/EastGame2TeamBButton
@onready var west_game_1_team_a_button: Button = $VBoxContainer/MatchupsContainer/WestGame1Row/WestGame1TeamAButton
@onready var west_game_1_team_b_button: Button = $VBoxContainer/MatchupsContainer/WestGame1Row/WestGame1TeamBButton
@onready var west_game_2_team_a_button: Button = $VBoxContainer/MatchupsContainer/WestGame2Row/WestGame2TeamAButton
@onready var west_game_2_team_b_button: Button = $VBoxContainer/MatchupsContainer/WestGame2Row/WestGame2TeamBButton
@onready var sim_playin_button: Button = $VBoxContainer/Actions/SimPlayInButton
@onready var advance_button: Button = $VBoxContainer/Actions/AdvanceButton

var playin_complete: bool = false
var east_playin_teams: Array = []
var west_playin_teams: Array = []
var playoff_field: Array = []


func _ready() -> void:
	var playin_teams: Array = LeagueManager.get_playin_teams()
	east_playin_teams = playin_teams.slice(0, 4)
	west_playin_teams = playin_teams.slice(4, 8)

	sim_playin_button.pressed.connect(_on_sim_playin)
	advance_button.pressed.connect(_on_advance)
	east_game_1_team_a_button.pressed.connect(_on_east_game_1_team_a_pressed)
	east_game_1_team_b_button.pressed.connect(_on_east_game_1_team_b_pressed)
	east_game_2_team_a_button.pressed.connect(_on_east_game_2_team_a_pressed)
	east_game_2_team_b_button.pressed.connect(_on_east_game_2_team_b_pressed)
	west_game_1_team_a_button.pressed.connect(_on_west_game_1_team_a_pressed)
	west_game_1_team_b_button.pressed.connect(_on_west_game_1_team_b_pressed)
	west_game_2_team_a_button.pressed.connect(_on_west_game_2_team_a_pressed)
	west_game_2_team_b_button.pressed.connect(_on_west_game_2_team_b_pressed)
	_update_status_label()
	_update_matchup_labels()


func _on_sim_playin() -> void:
	if playin_complete:
		return

	playoff_field = LeagueManager.get_playoff_teams().duplicate()
	var east_qualifiers: Array = _simulate_conference_playin(east_playin_teams)
	var west_qualifiers: Array = _simulate_conference_playin(west_playin_teams)

	# The 12 direct playoff teams plus two Play-In qualifiers per conference form the v1 playoff field.
	playoff_field.append_array(east_qualifiers)
	playoff_field.append_array(west_qualifiers)
	GameState.playoff_bracket = playoff_field
	if GameState.playoff_status == "playin" and not playoff_field.has(GameState.get_player_team()):
		GameState.playoff_status = "eliminated"

	playin_complete = true
	sim_playin_button.disabled = true
	advance_button.disabled = false
	status_label.text = "Play-In complete. Qualifiers: %s. %d teams are set for the playoffs." % [
		_format_qualifier_names(east_qualifiers + west_qualifiers),
		playoff_field.size()
	]


func _on_advance() -> void:
	if not playin_complete:
		return

	var player_team: Team = GameState.get_player_team()
	var should_enter_playoffs: bool = GameState.playoff_status == "playoffs"
	should_enter_playoffs = should_enter_playoffs or (GameState.playoff_status == "playin" and GameState.playoff_bracket.has(player_team))

	if should_enter_playoffs:
		GameState.set_phase(GameState.Phase.PLAYOFFS)
		get_tree().change_scene_to_file("res://scenes/Playoffs.tscn")
	else:
		GameState.set_phase(GameState.Phase.END_OF_SEASON)
		get_tree().change_scene_to_file("res://scenes/EndOfSeason.tscn")


# Matchup buttons are styled as labels; each team name opens its own roster.
func _on_east_game_1_team_a_pressed() -> void:
	_show_playin_team(east_playin_teams, 0)


func _on_east_game_1_team_b_pressed() -> void:
	_show_playin_team(east_playin_teams, 1)


func _on_east_game_2_team_a_pressed() -> void:
	_show_playin_team(east_playin_teams, 2)


func _on_east_game_2_team_b_pressed() -> void:
	_show_playin_team(east_playin_teams, 3)


func _on_west_game_1_team_a_pressed() -> void:
	_show_playin_team(west_playin_teams, 0)


func _on_west_game_1_team_b_pressed() -> void:
	_show_playin_team(west_playin_teams, 1)


func _on_west_game_2_team_a_pressed() -> void:
	_show_playin_team(west_playin_teams, 2)


func _on_west_game_2_team_b_pressed() -> void:
	_show_playin_team(west_playin_teams, 3)


func _show_playin_team(teams: Array, index: int) -> void:
	if index < 0 or index >= teams.size():
		return

	RosterViewer.show_team(teams[index])


func _update_status_label() -> void:
	match GameState.playoff_status:
		"playoffs":
			status_label.text = "You qualified directly for the playoffs. Watch the Play-In results."
		"playin":
			status_label.text = "You are in the Play-In tournament. Win to advance."
		"lottery":
			status_label.text = "Your season is over. Watch the Play-In results."
		_:
			status_label.text = "Watch the Play-In results."


func _update_matchup_labels() -> void:
	_set_matchup_buttons(east_playin_teams, 0, 1, east_game_1_team_a_button, east_game_1_team_b_button, "7th", "8th")
	_set_matchup_buttons(east_playin_teams, 2, 3, east_game_2_team_a_button, east_game_2_team_b_button, "9th", "10th")
	_set_matchup_buttons(west_playin_teams, 0, 1, west_game_1_team_a_button, west_game_1_team_b_button, "7th", "8th")
	_set_matchup_buttons(west_playin_teams, 2, 3, west_game_2_team_a_button, west_game_2_team_b_button, "9th", "10th")


func _set_matchup_buttons(teams: Array, first_index: int, second_index: int, first_button: Button, second_button: Button, first_fallback: String, second_fallback: String) -> void:
	first_button.text = _format_team_name(teams[first_index]) if teams.size() > first_index else first_fallback
	second_button.text = _format_team_name(teams[second_index]) if teams.size() > second_index else second_fallback


func _simulate_conference_playin(conference_teams: Array) -> Array:
	if conference_teams.size() < 4:
		return []

	var seed_7: Team = conference_teams[0]
	var seed_8: Team = conference_teams[1]
	var seed_9: Team = conference_teams[2]
	var seed_10: Team = conference_teams[3]

	# Game 1 sends the 7/8 winner directly to the playoffs.
	var game_1: Dictionary = SimEngine.simulate_series(seed_7, seed_8, 1)
	var first_qualifier: Team = game_1["winner"]
	var game_1_loser: Team = game_1["loser"]

	# Game 2 is elimination; its winner gets one more chance against the 7/8 loser.
	var game_2: Dictionary = SimEngine.simulate_series(seed_9, seed_10, 1)
	var game_2_winner: Team = game_2["winner"]
	var final_game: Dictionary = SimEngine.simulate_series(game_1_loser, game_2_winner, 1)
	var second_qualifier: Team = final_game["winner"]

	return [first_qualifier, second_qualifier]


func _format_qualifier_names(teams: Array) -> String:
	var names: Array[String] = []
	for team in teams:
		names.append(_format_team_name(team))
	return ", ".join(names)


func _format_team_name(team: Team) -> String:
	if team == null:
		return "Unknown Team"
	return "%s %s" % [team.city, team.name]
