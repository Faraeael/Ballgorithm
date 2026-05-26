extends Control

const SEASON_WEEKS: int = 24

@onready var year_label: Label = $VBoxContainer/Header/YearLabel
@onready var week_label: Label = $VBoxContainer/Header/WeekLabel
@onready var team_record_label: Label = $VBoxContainer/Header/TeamRecordLabel
@onready var standings_list: ItemList = $VBoxContainer/MainArea/LeftPanel/StandingsList
@onready var week_results_list: ItemList = $VBoxContainer/MainArea/RightPanel/WeekResultsList
@onready var sim_week_button: Button = $VBoxContainer/Actions/SimWeekButton
@onready var sim_season_button: Button = $VBoxContainer/Actions/SimSeasonButton
@onready var advance_button: Button = $VBoxContainer/Actions/AdvanceButton

var current_week: int = 1
var season_complete: bool = false
var displayed_standings: Array = []
var displayed_results: Array = []


func _ready() -> void:
	LeagueManager.reset_season_records()
	sim_week_button.pressed.connect(_on_sim_week)
	sim_season_button.pressed.connect(_on_sim_season)
	advance_button.pressed.connect(_on_advance)
	standings_list.item_activated.connect(_on_standings_team_activated)
	week_results_list.item_activated.connect(_on_week_result_activated)
	_refresh_ui()


func _on_sim_week() -> void:
	if season_complete:
		return

	var results: Array = SimEngine.simulate_week(GameState.schedule, current_week, GameState.all_teams)
	current_week += 1
	if current_week > SEASON_WEEKS:
		season_complete = true
		sim_week_button.disabled = true
		sim_season_button.disabled = true
		advance_button.disabled = false
	_refresh_ui(results)


func _on_sim_season() -> void:
	if season_complete:
		return

	SimEngine.simulate_full_season(GameState.schedule, GameState.all_teams)
	current_week = SEASON_WEEKS
	season_complete = true
	sim_week_button.disabled = true
	sim_season_button.disabled = true
	advance_button.disabled = false
	_refresh_ui([])


func _on_advance() -> void:
	if not season_complete:
		return

	var player_team: Team = GameState.get_player_team()
	if player_team == null:
		return

	# Store the player's postseason route for the next scene to resolve.
	if LeagueManager.get_playoff_teams().has(player_team):
		GameState.playoff_status = "playoffs"
	elif LeagueManager.get_playin_teams().has(player_team):
		GameState.playoff_status = "playin"
	else:
		GameState.playoff_status = "lottery"

	GameState.set_phase(GameState.Phase.PLAY_IN)
	get_tree().change_scene_to_file("res://scenes/PlayIn.tscn")


# Double-click a standings row to inspect that team's current roster.
func _on_standings_team_activated(index: int) -> void:
	if index < 0 or index >= displayed_standings.size():
		return

	RosterViewer.show_team(displayed_standings[index])


func _on_week_result_activated(index: int) -> void:
	if index < 0 or index >= displayed_results.size():
		return

	BoxScoreViewer.show_box_score(displayed_results[index])


# Rebuilds standings and latest results from authoritative league state.
func _refresh_ui(results: Array = []) -> void:
	var player_team: Team = GameState.get_player_team()
	year_label.text = "Season Year %d" % GameState.current_year
	week_label.text = "Week %d of %d" % [mini(current_week, SEASON_WEEKS), SEASON_WEEKS]
	team_record_label.text = "Your Record: 0-0"
	if player_team != null:
		team_record_label.text = "Your Record: %d-%d" % [player_team.wins, player_team.losses]

	standings_list.clear()
	displayed_standings = LeagueManager.get_standings()
	for index in displayed_standings.size():
		var team: Team = displayed_standings[index]
		var prefix: String = "★ " if team.is_player_team else ""
		standings_list.add_item("%s%d. %s %s  %d-%d" % [
			prefix,
			index + 1,
			team.city,
			team.name,
			team.wins,
			team.losses
		])

	week_results_list.clear()
	displayed_results = results
	for result in results:
		var home_name: String = _find_team_name(result.get("home_team_id", ""))
		var away_name: String = _find_team_name(result.get("away_team_id", ""))
		week_results_list.add_item("%s %d - %d %s" % [
			home_name,
			result.get("home_score", 0),
			result.get("away_score", 0),
			away_name
		])

	var weekly_injuries: Array = _collect_weekly_injuries(results)
	if not weekly_injuries.is_empty():
		week_results_list.add_item("INJURIES THIS WEEK")
		for injury in weekly_injuries:
			week_results_list.add_item("[%s] %s — %s (%d games)" % [
				_find_team_name(injury.get("team_id", "")),
				injury.get("player_name", "Unknown Player"),
				injury.get("injury_type", "Unknown Injury"),
				injury.get("games_remaining", 0)
			])

	if season_complete:
		sim_week_button.disabled = true
		sim_season_button.disabled = true
		advance_button.disabled = false


func _find_team_name(team_id: String) -> String:
	for team in GameState.all_teams:
		if team.team_id == team_id:
			return "%s %s" % [team.city, team.name]
	return "Unknown Team"


func _collect_weekly_injuries(results: Array) -> Array:
	var injuries: Array = []
	for result in results:
		injuries.append_array(result.get("injuries", []))
	return injuries
