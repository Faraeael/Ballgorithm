extends Control

const AwardsEngineScript = preload("res://scripts/AwardsEngine.gd")

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var year_label: Label = $VBoxContainer/YearLabel
@onready var awards_list: ItemList = $VBoxContainer/MainArea/AwardsPanel/AwardsList
@onready var all_league_list: ItemList = $VBoxContainer/MainArea/AllLeaguePanel/AllLeagueList
@onready var stats_button: Button = $VBoxContainer/Actions/StatsButton
@onready var advance_button: Button = $VBoxContainer/Actions/AdvanceButton

var season_stats: Dictionary = {}


func _ready() -> void:
	stats_button.pressed.connect(_on_stats)
	advance_button.pressed.connect(_on_advance)
	_calculate_and_display()


func _calculate_and_display() -> void:
	year_label.text = "Year %d" % GameState.current_year
	season_stats = AwardsEngineScript.build_season_stats(GameState.schedule, GameState.all_teams)
	GameState.season_stats = season_stats

	# Awards use the prior snapshot first; the new snapshot is saved for next season's MIP before progression runs.
	var awards: Dictionary = AwardsEngineScript.calculate_awards(GameState.all_teams, season_stats)
	var all_league_teams: Dictionary = AwardsEngineScript.calculate_all_league_teams(GameState.all_teams, season_stats)
	GameState.current_awards = awards
	GameState.prior_ratings = AwardsEngineScript.store_player_ratings(GameState.all_teams)

	_populate_awards(awards)
	_populate_all_league(all_league_teams)

func _populate_awards(awards: Dictionary) -> void:
	awards_list.clear()
	for award_name in AwardsEngineScript.AWARDS:
		var winner: Dictionary = awards.get(award_name, {})
		var prefix: String = "★ " if _is_player_team_winner(winner) else ""
		awards_list.add_item("%s%s - %s (%s) - %s" % [
			prefix,
			award_name,
			winner.get("player_name", "No eligible winner"),
			winner.get("team_name", ""),
			winner.get("reason", "")
		])


func _populate_all_league(all_league_teams: Dictionary) -> void:
	all_league_list.clear()
	_add_all_league_team("1ST TEAM", all_league_teams.get("first_team", []))
	_add_all_league_team("2ND TEAM", all_league_teams.get("second_team", []))
	_add_all_league_team("3RD TEAM", all_league_teams.get("third_team", []))


func _add_all_league_team(team_label: String, players: Array) -> void:
	for player in players:
		var team: Team = _find_player_team(player)
		var prefix: String = "★ " if team != null and team.is_player_team else ""
		all_league_list.add_item("%s%s - %s - %s (%s)" % [
			prefix,
			team_label,
			player.position,
			player.full_name,
			_team_name(team)
		])


func _on_advance() -> void:
	GameState.set_phase(GameState.Phase.PLAY_IN)
	get_tree().change_scene_to_file("res://scenes/PlayIn.tscn")


func _on_stats() -> void:
	SeasonStatsViewer.show_stats()


func _is_player_team_winner(winner: Dictionary) -> bool:
	var player_team: Team = GameState.get_player_team()
	if player_team == null:
		return false

	if winner.get("team_name", "") == _team_name(player_team):
		return true

	var player_id: String = winner.get("player_id", "")
	for player in player_team.roster:
		if player.id == player_id:
			return true
	return false


func _find_player_team(target_player: Player) -> Team:
	for team in GameState.all_teams:
		if team.roster.has(target_player):
			return team
	return null


func _team_name(team: Team) -> String:
	if team == null:
		return "Unknown Team"
	return "%s %s" % [team.city, team.name]
