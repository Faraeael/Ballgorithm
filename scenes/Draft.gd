extends Control

@onready var round_label: Label = $VBoxContainer/Header/RoundLabel
@onready var pick_label: Label = $VBoxContainer/Header/PickLabel
@onready var on_the_clock_label: Label = $VBoxContainer/Header/OnTheClockLabel
@onready var draft_board_list: ItemList = $VBoxContainer/MainArea/LeftPanel/DraftBoardList
@onready var roster_list: ItemList = $VBoxContainer/MainArea/RightPanel/RosterList
@onready var player_info_label: Label = $VBoxContainer/PlayerInfoLabel
@onready var draft_player_button: Button = $VBoxContainer/DraftPlayerButton

var draft_pool: Array = []
var draft_order: Array = []
var current_pick: int = 0
var current_round: int = 1
var selected_player: Player = null


func _ready() -> void:
	draft_board_list.item_selected.connect(_on_player_selected)
	draft_board_list.item_activated.connect(_on_draft_player_activated)
	roster_list.item_activated.connect(_on_roster_player_activated)
	draft_player_button.pressed.connect(_on_draft_player)
	_initialize_draft()


# Creates a fresh draft class and advances through AI picks until the user is on the clock.
func _initialize_draft() -> void:
	draft_pool = DraftSystem.build_draft_pool(GameState.all_teams)
	draft_order = DraftSystem.get_draft_order(GameState.all_teams)
	current_pick = 0
	current_round = 1
	_refresh_ui()
	_process_until_player_turn()


func _get_current_team() -> Team:
	if draft_order.is_empty():
		return null

	var round_order: Array = draft_order
	if current_round == 2:
		round_order = draft_order.duplicate()
		round_order.reverse()

	return round_order[current_pick % round_order.size()]


func _is_player_turn() -> bool:
	var current_team: Team = _get_current_team()
	return current_team != null and current_team.is_player_team


# AI selections happen immediately so the player only interacts on their own picks.
func _process_until_player_turn() -> void:
	while not _is_player_turn() and not draft_pool.is_empty() and current_round <= DraftSystem.DRAFT_ROUNDS:
		var current_team: Team = _get_current_team()
		if current_team == null:
			_finish_draft()
			return

		var picked_player: Player = DraftSystem.ai_pick(current_team, draft_pool)
		if picked_player != null:
			DraftSystem.apply_pick(current_team, picked_player)

		_advance_pick()
		if current_round <= DraftSystem.DRAFT_ROUNDS:
			_refresh_ui()

	if current_round <= DraftSystem.DRAFT_ROUNDS:
		_refresh_ui()


func _advance_pick() -> void:
	current_pick += 1
	if current_pick >= draft_order.size():
		current_round += 1
		current_pick = 0

	if current_round > DraftSystem.DRAFT_ROUNDS or draft_pool.is_empty():
		_finish_draft()


func _on_player_selected(index: int) -> void:
	if not _is_player_turn() or index < 0 or index >= draft_pool.size():
		return

	selected_player = draft_pool[index]
	var potential_text: String = str(selected_player.potential) if selected_player.is_potential_revealed else "??"
	player_info_label.text = "%s | %s | %s | OVR %d | Potential %s" % [
		selected_player.full_name,
		selected_player.position,
		selected_player.archetype,
		selected_player.get_overall(),
		potential_text
	]
	draft_player_button.disabled = false


func _on_draft_player() -> void:
	if selected_player == null or not _is_player_turn():
		return

	var player_team: Team = GameState.get_player_team()
	if player_team == null:
		return

	DraftSystem.apply_pick(player_team, selected_player)
	draft_pool.erase(selected_player)
	selected_player = null
	_advance_pick()
	if current_round <= DraftSystem.DRAFT_ROUNDS:
		_refresh_ui()
		_process_until_player_turn()


# Double-click opens details without changing draft selection state.
func _on_draft_player_activated(index: int) -> void:
	if index < 0 or index >= draft_pool.size():
		return

	PlayerDetail.show_player(draft_pool[index])


func _on_roster_player_activated(index: int) -> void:
	var player_team: Team = GameState.get_player_team()
	if player_team == null or index < 0 or index >= player_team.roster.size():
		return

	PlayerDetail.show_player(player_team.roster[index])


func _refresh_ui() -> void:
	var current_team: Team = _get_current_team()
	round_label.text = "Round %d" % current_round
	pick_label.text = "Pick %d" % (current_pick + 1)
	on_the_clock_label.text = "On The Clock: %s" % _get_team_display_name(current_team)

	draft_board_list.clear()
	for player in draft_pool:
		draft_board_list.add_item("[%s] %s — OVR %d — %s" % [
			player.position,
			player.full_name,
			player.get_overall(),
			player.archetype
		])

	roster_list.clear()
	var player_team: Team = GameState.get_player_team()
	if player_team != null:
		for player in player_team.roster:
			roster_list.add_item("[%s] %s — OVR %d" % [player.position, player.full_name, player.get_overall()])

	if not _is_player_turn():
		selected_player = null
		draft_player_button.disabled = true
		player_info_label.text = "Waiting for your pick"
	elif selected_player == null:
		draft_player_button.disabled = true
		player_info_label.text = "Select a player to see details"


func _finish_draft() -> void:
	GameState.set_phase(GameState.Phase.FREE_AGENCY)
	get_tree().change_scene_to_file("res://scenes/FreeAgency.tscn")


func _get_team_display_name(team: Team) -> String:
	if team == null:
		return "—"
	return "%s %s" % [team.city, team.name]
