extends Control

const ScoutingSystemScript = preload("res://scripts/ScoutingSystem.gd")

const ROSTER_MAX: int = 15
const ROSTER_MIN_TO_ADVANCE: int = 10
const EXTRA_FREE_AGENT_COUNT: int = 40
const POSITIONS: Array[String] = ["PG", "SG", "SF", "PF", "C"]
const SITUATIONS: Array[String] = ["Tanking", "Rebuilding", "Play-In", "Playoff", "Contender"]

@onready var title_label: Label = $VBoxContainer/Header/TitleLabel
@onready var cap_space_label: Label = $VBoxContainer/Header/CapSpaceLabel
@onready var roster_count_label: Label = $VBoxContainer/Header/RosterCountLabel
@onready var position_filter: OptionButton = $VBoxContainer/MainArea/LeftPanel/PositionFilter
@onready var free_agent_list: ItemList = $VBoxContainer/MainArea/LeftPanel/FreeAgentList
@onready var roster_list: ItemList = $VBoxContainer/MainArea/RightPanel/RosterList
@onready var player_info_label: Label = $VBoxContainer/MainArea/RightPanel/PlayerInfoLabel
@onready var sign_player_button: Button = $VBoxContainer/Actions/SignPlayerButton
@onready var release_player_button: Button = $VBoxContainer/Actions/ReleasePlayerButton
@onready var advance_to_season_button: Button = $VBoxContainer/Actions/AdvanceToSeasonButton

var selected_free_agent: Player = null
var selected_roster_player: Player = null
var filtered_agents: Array = []


func _ready() -> void:
	_build_free_agent_pool()
	_populate_position_filter()
	position_filter.item_selected.connect(_on_position_filter_selected)
	free_agent_list.item_selected.connect(_on_free_agent_selected)
	free_agent_list.item_activated.connect(_on_free_agent_activated)
	roster_list.item_selected.connect(_on_roster_player_selected)
	roster_list.item_activated.connect(_on_roster_player_activated)
	sign_player_button.pressed.connect(_on_sign_player)
	release_player_button.pressed.connect(_on_release_player)
	advance_to_season_button.pressed.connect(_on_advance)
	_apply_position_filter()
	_refresh_ui()


# Builds the v1 market from roster overflow plus generated replacement-level options.
func _build_free_agent_pool() -> void:
	GameState.free_agents = []
	for team in GameState.all_teams:
		if team.is_player_team:
			continue

		while team.roster.size() > ROSTER_MAX:
			var player: Player = team.roster.pop_back()
			GameState.free_agents.append(player)

	for index in EXTRA_FREE_AGENT_COUNT:
		var position: String = POSITIONS.pick_random()
		var situation: String = SITUATIONS.pick_random()
		GameState.free_agents.append(PlayerGenerator.generate_player(position, situation))


func _populate_position_filter() -> void:
	position_filter.clear()
	position_filter.add_item("All")
	for position in POSITIONS:
		position_filter.add_item(position)


func _on_position_filter_selected(index: int) -> void:
	_apply_position_filter()
	selected_free_agent = null
	_refresh_ui()


# Rebuilds the visible market from the selected position filter.
func _apply_position_filter() -> void:
	filtered_agents = []
	var selected_filter: String = position_filter.get_item_text(position_filter.selected)
	for player in GameState.free_agents:
		if selected_filter == "All" or player.position == selected_filter:
			filtered_agents.append(player)


func _on_free_agent_selected(index: int) -> void:
	if index < 0 or index >= filtered_agents.size():
		return

	selected_free_agent = filtered_agents[index]
	selected_roster_player = null
	var team: Team = GameState.get_player_team()
	var visibility: Dictionary = _get_scouting_visibility(selected_free_agent)
	var archetype_text: String = selected_free_agent.archetype if visibility["show_archetype"] else "??"
	player_info_label.text = "%s | %s | %s | OVR %s | %s/yr | %d yrs" % [
		selected_free_agent.full_name,
		selected_free_agent.position,
		archetype_text,
		_get_scouted_overall_text(selected_free_agent, visibility),
		_format_money(selected_free_agent.salary),
		selected_free_agent.contract_years
	]
	sign_player_button.disabled = team == null or team.roster.size() >= ROSTER_MAX or not CapEngine.can_sign_player(team, selected_free_agent)
	release_player_button.disabled = true


func _on_roster_player_selected(index: int) -> void:
	var team: Team = GameState.get_player_team()
	if team == null or index < 0 or index >= team.roster.size():
		return

	selected_roster_player = team.roster[index]
	selected_free_agent = null
	player_info_label.text = "%s | %s | %s | OVR %d | %s/yr | %d yrs" % [
		selected_roster_player.full_name,
		selected_roster_player.position,
		selected_roster_player.archetype,
		selected_roster_player.get_overall(),
		_format_money(selected_roster_player.salary),
		selected_roster_player.contract_years
	]
	sign_player_button.disabled = true
	release_player_button.disabled = false


# Double-click opens the shared detail overlay for market and roster players.
func _on_free_agent_activated(index: int) -> void:
	if index < 0 or index >= filtered_agents.size():
		return

	PlayerDetail.show_player(filtered_agents[index], true)


func _on_roster_player_activated(index: int) -> void:
	var team: Team = GameState.get_player_team()
	if team == null or index < 0 or index >= team.roster.size():
		return

	PlayerDetail.show_player(team.roster[index], false)


func _on_sign_player() -> void:
	var team: Team = GameState.get_player_team()
	if team == null or selected_free_agent == null:
		return

	if CapEngine.apply_contract(team, selected_free_agent):
		GameState.free_agents.erase(selected_free_agent)
		selected_free_agent = null
		_apply_position_filter()
		_refresh_ui()
	else:
		player_info_label.text = "Cannot afford this player"


func _on_release_player() -> void:
	var team: Team = GameState.get_player_team()
	if team == null or selected_roster_player == null:
		return

	if CapEngine.release_player(team, selected_roster_player):
		GameState.free_agents.append(selected_roster_player)
		selected_roster_player = null
		_apply_position_filter()
		_refresh_ui()


func _on_advance() -> void:
	var team: Team = GameState.get_player_team()
	if team == null or team.roster.size() < ROSTER_MIN_TO_ADVANCE:
		advance_to_season_button.text = "Need at least 10 players"
		return

	GameState.schedule = LeagueManager.generate_schedule()
	GameState.set_phase(GameState.Phase.SEASON_SIM)
	get_tree().change_scene_to_file("res://scenes/SeasonSim.tscn")


func _refresh_ui() -> void:
	var team: Team = GameState.get_player_team()
	if team == null:
		title_label.text = "Free Agency"
		cap_space_label.text = "Cap Space: $0"
		roster_count_label.text = "Roster: 0/15"
		return

	var cap_summary: Dictionary = CapEngine.get_cap_summary(team)
	title_label.text = "Free Agency"
	cap_space_label.text = "Cap Space: %s" % _format_money(cap_summary["cap_space"])
	roster_count_label.text = "Roster: %d/%d" % [team.roster.size(), ROSTER_MAX]

	free_agent_list.clear()
	for player in filtered_agents:
		free_agent_list.add_item(_format_scouted_free_agent_row(player))

	roster_list.clear()
	for player in team.roster:
		var roster_line: String = "[%s] %s — OVR %d — %s/yr — %d yrs" % [
			player.position,
			player.full_name,
			player.get_overall(),
			_format_money(player.salary),
			player.contract_years
		]
		roster_list.add_item(_append_injury_flag(roster_line, player))

	sign_player_button.disabled = true
	release_player_button.disabled = true
	advance_to_season_button.text = "Advance to Season"
	if selected_free_agent == null and selected_roster_player == null:
		player_info_label.text = "Select a player to see details"


func _format_money(amount: int) -> String:
	var sign: String = "" if amount >= 0 else "-"
	var absolute_amount: int = absi(amount)
	if absolute_amount >= 1_000_000:
		return "%s$%.1fM" % [sign, float(absolute_amount) / 1_000_000.0]
	if absolute_amount >= 1_000:
		return "%s$%dK" % [sign, int(round(float(absolute_amount) / 1_000.0))]
	return "%s$%d" % [sign, absolute_amount]


# Free agents are external players, so visible rating/archetype data depends on scout level.
func _format_scouted_free_agent_row(player: Player) -> String:
	var visibility: Dictionary = _get_scouting_visibility(player)
	var row: String = ""
	if visibility["show_exact_overall"]:
		row = "[%s] %s — OVR %d — %s — %s/yr — %d yrs" % [player.position, player.full_name, player.get_overall(), player.archetype, _format_money(player.salary), player.contract_years]
	elif visibility["show_overall_range"]:
		row = "[%s] %s — OVR %s — %s/yr — %d yrs" % [player.position, player.full_name, visibility["overall_range"], _format_money(player.salary), player.contract_years]
	else:
		row = "[%s] %s — ??? — %s/yr — %d yrs" % [player.position, player.full_name, _format_money(player.salary), player.contract_years]
	return _append_injury_flag(row, player)


func _append_injury_flag(row: String, player: Player) -> String:
	if player.is_injured:
		return "%s ⚠ [%s]" % [row, player.injury_type]
	return row


func _get_scouting_visibility(player: Player) -> Dictionary:
	var player_team: Team = GameState.get_player_team()
	var scout_level: int = player_team.staff_scout if player_team != null else 1
	return ScoutingSystemScript.get_player_info(player, scout_level, true)


func _get_scouted_overall_text(player: Player, visibility: Dictionary) -> String:
	if visibility["show_exact_overall"]:
		return str(player.get_overall())
	if visibility["show_overall_range"] and visibility["overall_range"] != "":
		return visibility["overall_range"]
	return "??"
