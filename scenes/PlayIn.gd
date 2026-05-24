extends Control

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var matchups_container: VBoxContainer = $VBoxContainer/MatchupsContainer
@onready var east_game_1_label: Label = $VBoxContainer/MatchupsContainer/EastGame1Label
@onready var east_game_2_label: Label = $VBoxContainer/MatchupsContainer/EastGame2Label
@onready var west_game_1_label: Label = $VBoxContainer/MatchupsContainer/WestGame1Label
@onready var west_game_2_label: Label = $VBoxContainer/MatchupsContainer/WestGame2Label
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
	_update_status_label()
	_update_matchup_labels()


func _on_sim_playin() -> void:
	if playin_complete:
		return

	playoff_field = LeagueManager.get_playoff_teams().duplicate()
	var east_qualifiers: Array = _simulate_conference_playin(east_playin_teams, east_game_1_label, east_game_2_label)
	var west_qualifiers: Array = _simulate_conference_playin(west_playin_teams, west_game_1_label, west_game_2_label)

	# The 12 direct playoff teams plus two Play-In qualifiers per conference form the v1 playoff field.
	playoff_field.append_array(east_qualifiers)
	playoff_field.append_array(west_qualifiers)
	GameState.playoff_bracket = playoff_field
	if GameState.playoff_status == "playin" and not playoff_field.has(GameState.get_player_team()):
		GameState.playoff_status = "eliminated"

	playin_complete = true
	sim_playin_button.disabled = true
	advance_button.disabled = false
	status_label.text = "Play-In complete. %d teams are set for the playoffs." % playoff_field.size()


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


func _format_matchup(team_a: Team, team_b: Team) -> String:
	return "%s vs %s" % [_format_team_name(team_a), _format_team_name(team_b)]


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
	east_game_1_label.text = _get_matchup_text(east_playin_teams, 0, 1, "7th vs 8th")
	east_game_2_label.text = _get_matchup_text(east_playin_teams, 2, 3, "9th vs 10th")
	west_game_1_label.text = _get_matchup_text(west_playin_teams, 0, 1, "7th vs 8th")
	west_game_2_label.text = _get_matchup_text(west_playin_teams, 2, 3, "9th vs 10th")


func _simulate_conference_playin(conference_teams: Array, game_1_label: Label, game_2_label: Label) -> Array:
	if conference_teams.size() < 4:
		game_1_label.text = "Not enough teams"
		game_2_label.text = "Not enough teams"
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

	game_1_label.text = "%s -> %s advances" % [_format_matchup(seed_7, seed_8), _format_team_name(first_qualifier)]
	game_2_label.text = "%s; final spot -> %s" % [_format_matchup(seed_9, seed_10), _format_team_name(second_qualifier)]
	return [first_qualifier, second_qualifier]


func _get_matchup_text(teams: Array, first_index: int, second_index: int, fallback: String) -> String:
	if teams.size() <= max(first_index, second_index):
		return fallback
	return _format_matchup(teams[first_index], teams[second_index])


func _format_team_name(team: Team) -> String:
	if team == null:
		return "Unknown Team"
	return "%s %s" % [team.city, team.name]
