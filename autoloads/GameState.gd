extends Node

signal phase_changed(new_phase: int)
signal year_advanced(new_year: int)

enum Phase {
	MAIN_MENU,
	NEW_GAME,
	LEAGUE_GENERATING,
	PRE_SEASON_HUB,
	DRAFT,
	FREE_AGENCY,
	SEASON_SIM,
	PLAY_IN,
	PLAYOFFS,
	FINALS,
	END_OF_SEASON
}

const SAVE_PATH: String = "user://save.json"

var current_phase: Phase = Phase.MAIN_MENU
var current_year: int = 1
var player_team_id: String = ""
var sim_mode: String = "week"
var playoff_status: String = ""
var playoff_bracket: Array = []
var champion_team_id: String = ""
var champion_name: String = ""
var all_teams: Array = []
var free_agents: Array = []
var draft_pool_next: Array = []
var schedule: Array = []


# Changes game flow phase through the single approved path and notifies active scenes.
func set_phase(new_phase: Phase) -> void:
	current_phase = new_phase
	phase_changed.emit(new_phase)


# Returns the player-controlled team from the generated league, or null before setup/load.
func get_player_team() -> Team:
	for team in all_teams:
		if team.is_player_team:
			return team
	return null


# Advances the franchise calendar by one year and emits for UI/state listeners.
func advance_year() -> void:
	current_year += 1
	year_advanced.emit(current_year)


# Clears runtime state without emitting phase signals. Used before starting or replacing a league.
func reset() -> void:
	current_phase = Phase.MAIN_MENU
	current_year = 1
	player_team_id = ""
	sim_mode = "week"
	playoff_status = ""
	playoff_bracket = []
	champion_team_id = ""
	champion_name = ""
	all_teams = []
	free_agents = []
	draft_pool_next = []
	schedule = []


# Builds a new league using the player's chosen team identity, then enters the preseason hub.
func initialize_league(player_situation: String, player_city: String, player_name: String) -> void:
	reset()
	set_phase(Phase.LEAGUE_GENERATING)
	all_teams = LeagueGenerator.generate_league(player_situation, player_city, player_name)
	free_agents = []
	PlayerDB.build_index()

	var player_team: Team = get_player_team()
	player_team_id = player_team.team_id if player_team != null else ""
	set_phase(Phase.PRE_SEASON_HUB)


# Serializes current state and generated resources to JSON at user://save.json.
func save_game() -> void:
	var team_data: Array = []
	for team in all_teams:
		team_data.append(team.to_dict())

	var free_agent_data: Array = []
	for player in free_agents:
		free_agent_data.append(player.to_dict())

	var draft_pool_next_data: Array = []
	for player in draft_pool_next:
		draft_pool_next_data.append(player.to_dict())

	var playoff_bracket_team_ids: Array = []
	for team in playoff_bracket:
		playoff_bracket_team_ids.append(team.team_id)

	var save_data: Dictionary = {
		"current_phase": current_phase,
		"current_year": current_year,
		"player_team_id": player_team_id,
		"sim_mode": sim_mode,
		"playoff_status": playoff_status,
		"playoff_bracket": playoff_bracket_team_ids,
		"champion_team_id": champion_team_id,
		"champion_name": champion_name,
		"all_teams": team_data,
		"free_agents": free_agent_data,
		"draft_pool_next": draft_pool_next_data,
		"schedule": schedule
	}

	var save_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if save_file == null:
		push_error("Could not open save file for writing: %s" % SAVE_PATH)
		return

	save_file.store_string(JSON.stringify(save_data))
	save_file.close()


# Loads saved JSON if present. Missing or invalid saves leave current runtime state unchanged.
func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		push_warning("No save file found at: %s" % SAVE_PATH)
		return

	var save_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if save_file == null:
		push_error("Could not open save file for reading: %s" % SAVE_PATH)
		return

	var json_text: String = save_file.get_as_text()
	save_file.close()

	var json: JSON = JSON.new()
	var parse_error: Error = json.parse(json_text)
	if parse_error != OK:
		push_error("Could not parse save file: %s" % json.get_error_message())
		return

	var save_data: Variant = json.data
	if not save_data is Dictionary:
		push_error("Save file root must be a dictionary.")
		return

	current_year = save_data.get("current_year", 1)
	player_team_id = save_data.get("player_team_id", "")
	sim_mode = save_data.get("sim_mode", "week")
	playoff_status = save_data.get("playoff_status", "")
	champion_team_id = save_data.get("champion_team_id", "")
	champion_name = save_data.get("champion_name", "")
	schedule = save_data.get("schedule", [])

	all_teams = []
	for team_data in save_data.get("all_teams", []):
		var team: Team = Team.new()
		team.from_dict(team_data)
		all_teams.append(team)

	playoff_bracket = []
	for team_id in save_data.get("playoff_bracket", []):
		var bracket_team: Team = _find_team_by_id(team_id)
		if bracket_team != null:
			playoff_bracket.append(bracket_team)

	free_agents = []
	for player_data in save_data.get("free_agents", []):
		var player: Player = Player.new()
		player.from_dict(player_data)
		free_agents.append(player)

	draft_pool_next = []
	for player_data in save_data.get("draft_pool_next", []):
		var draft_player: Player = Player.new()
		draft_player.from_dict(player_data)
		draft_pool_next.append(draft_player)

	current_phase = save_data.get("current_phase", Phase.MAIN_MENU) as Phase
	PlayerDB.build_index()


func _find_team_by_id(team_id: String) -> Team:
	for team in all_teams:
		if team.team_id == team_id:
			return team
	return null
