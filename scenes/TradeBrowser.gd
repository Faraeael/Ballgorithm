extends CanvasLayer

const TradeEngineScript = preload("res://scripts/TradeEngine.gd")

signal trade_completed

var selected_ai_team: Team = null
var offering_players: Array = []
var requesting_players: Array = []
var selected_your_player: Player = null
var selected_ai_player: Player = null
var ai_teams: Array = []

@onready var title_label: Label = $Control/PanelContainer/VBoxContainer/Header/TitleLabel
@onready var team_picker: OptionButton = $Control/PanelContainer/VBoxContainer/Header/TeamPicker
@onready var your_team_label: Label = $Control/PanelContainer/VBoxContainer/MainArea/LeftPanel/YourTeamLabel
@onready var your_roster_list: ItemList = $Control/PanelContainer/VBoxContainer/MainArea/LeftPanel/YourRosterList
@onready var offering_label: Label = $Control/PanelContainer/VBoxContainer/MainArea/LeftPanel/OfferingLabel
@onready var add_offer_button: Button = $Control/PanelContainer/VBoxContainer/MainArea/CenterPanel/AddOfferButton
@onready var remove_offer_button: Button = $Control/PanelContainer/VBoxContainer/MainArea/CenterPanel/RemoveOfferButton
@onready var add_request_button: Button = $Control/PanelContainer/VBoxContainer/MainArea/CenterPanel/AddRequestButton
@onready var remove_request_button: Button = $Control/PanelContainer/VBoxContainer/MainArea/CenterPanel/RemoveRequestButton
@onready var ai_team_label: Label = $Control/PanelContainer/VBoxContainer/MainArea/RightPanel/AiTeamLabel
@onready var ai_roster_list: ItemList = $Control/PanelContainer/VBoxContainer/MainArea/RightPanel/AiRosterList
@onready var requesting_label: Label = $Control/PanelContainer/VBoxContainer/MainArea/RightPanel/RequestingLabel
@onready var trade_value_label: Label = $Control/PanelContainer/VBoxContainer/StatusRow/TradeValueLabel
@onready var validation_label: Label = $Control/PanelContainer/VBoxContainer/StatusRow/ValidationLabel
@onready var propose_trade_button: Button = $Control/PanelContainer/VBoxContainer/Actions/ProposeTradeButton
@onready var clear_button: Button = $Control/PanelContainer/VBoxContainer/Actions/ClearButton
@onready var close_button: Button = $Control/PanelContainer/VBoxContainer/Actions/CloseButton


func _ready() -> void:
	visible = false
	team_picker.item_selected.connect(_on_team_selected)
	your_roster_list.item_selected.connect(_on_your_roster_selected)
	your_roster_list.item_activated.connect(_on_your_roster_activated)
	ai_roster_list.item_selected.connect(_on_ai_roster_selected)
	ai_roster_list.item_activated.connect(_on_ai_roster_activated)
	add_offer_button.pressed.connect(_on_add_offer)
	remove_offer_button.pressed.connect(_on_remove_offer)
	add_request_button.pressed.connect(_on_add_request)
	remove_request_button.pressed.connect(_on_remove_request)
	propose_trade_button.pressed.connect(_on_propose_trade)
	clear_button.pressed.connect(_on_clear)
	close_button.pressed.connect(_on_close)


func show_browser() -> void:
	_populate_ai_teams()
	if ai_teams.is_empty():
		selected_ai_team = null
		_refresh_ui()
		visible = true
		return

	team_picker.select(0)
	_on_team_selected(0)
	visible = true


func _on_team_selected(index: int) -> void:
	if index < 0 or index >= ai_teams.size():
		selected_ai_team = null
	else:
		selected_ai_team = ai_teams[index]
	offering_players = []
	requesting_players = []
	selected_your_player = null
	selected_ai_player = null
	_refresh_ui()


func _on_your_roster_selected(index: int) -> void:
	var player_team: Team = GameState.get_player_team()
	if player_team == null or index < 0 or index >= player_team.roster.size():
		selected_your_player = null
	else:
		selected_your_player = player_team.roster[index]
	_refresh_buttons()


func _on_ai_roster_selected(index: int) -> void:
	if selected_ai_team == null or index < 0 or index >= selected_ai_team.roster.size():
		selected_ai_player = null
	else:
		selected_ai_player = selected_ai_team.roster[index]
	_refresh_buttons()


func _on_add_offer() -> void:
	if selected_your_player != null and offering_players.size() < TradeEngineScript.MAX_PLAYERS_PER_SIDE and not offering_players.has(selected_your_player):
		offering_players.append(selected_your_player)
	_refresh_ui()


func _on_remove_offer() -> void:
	if not offering_players.is_empty():
		offering_players.pop_back()
	_refresh_ui()


func _on_add_request() -> void:
	if selected_ai_player != null and requesting_players.size() < TradeEngineScript.MAX_PLAYERS_PER_SIDE and not requesting_players.has(selected_ai_player):
		requesting_players.append(selected_ai_player)
	_refresh_ui()


func _on_remove_request() -> void:
	if not requesting_players.is_empty():
		requesting_players.pop_back()
	_refresh_ui()


func _on_propose_trade() -> void:
	var player_team: Team = GameState.get_player_team()
	var validation: Dictionary = TradeEngineScript.is_trade_valid(player_team, selected_ai_team, offering_players, requesting_players)
	if not validation["valid"]:
		validation_label.text = validation["reason"]
		return

	if TradeEngineScript.execute_trade(player_team, selected_ai_team, offering_players, requesting_players):
		trade_completed.emit()
		_on_clear()
		validation_label.text = "Trade accepted."
	else:
		validation_label.text = "AI rejected the trade."
		_refresh_ui()


func _on_clear() -> void:
	offering_players = []
	requesting_players = []
	selected_your_player = null
	selected_ai_player = null
	_refresh_ui()


func _on_close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		visible = false
		get_viewport().set_input_as_handled()


func _on_your_roster_activated(index: int) -> void:
	var player_team: Team = GameState.get_player_team()
	if player_team == null or index < 0 or index >= player_team.roster.size():
		return
	PlayerDetail.show_player(player_team.roster[index])


func _on_ai_roster_activated(index: int) -> void:
	if selected_ai_team == null or index < 0 or index >= selected_ai_team.roster.size():
		return
	PlayerDetail.show_player(selected_ai_team.roster[index], true)


func _refresh_ui() -> void:
	var player_team: Team = GameState.get_player_team()
	your_roster_list.clear()
	ai_roster_list.clear()

	if player_team != null:
		your_team_label.text = "YOUR PLAYERS"
		for player in player_team.roster:
			your_roster_list.add_item(_format_player_row(player, offering_players.has(player)))

	if selected_ai_team != null:
		ai_team_label.text = "%s %s PLAYERS" % [selected_ai_team.city.to_upper(), selected_ai_team.name.to_upper()]
		for player in selected_ai_team.roster:
			ai_roster_list.add_item(_format_player_row(player, requesting_players.has(player)))
	else:
		ai_team_label.text = "THEIR PLAYERS"

	offering_label.text = "Offering: %s" % _format_player_names(offering_players)
	requesting_label.text = "Requesting: %s" % _format_player_names(requesting_players)

	var ratio: float = TradeEngineScript.evaluate_trade(offering_players, requesting_players)
	trade_value_label.text = "Trade Value: %d%% (AI accepts at 85%%+)" % int(round(ratio * 100.0))
	trade_value_label.modulate = Color.GREEN if ratio >= TradeEngineScript.AI_ACCEPT_THRESHOLD else Color.RED

	var validation: Dictionary = TradeEngineScript.is_trade_valid(player_team, selected_ai_team, offering_players, requesting_players)
	validation_label.text = validation["reason"] if not validation["valid"] else ""
	propose_trade_button.disabled = not validation["valid"] or ratio < TradeEngineScript.AI_ACCEPT_THRESHOLD
	_refresh_buttons()


func _refresh_buttons() -> void:
	add_offer_button.disabled = selected_your_player == null or offering_players.has(selected_your_player) or offering_players.size() >= TradeEngineScript.MAX_PLAYERS_PER_SIDE
	remove_offer_button.disabled = offering_players.is_empty()
	add_request_button.disabled = selected_ai_player == null or requesting_players.has(selected_ai_player) or requesting_players.size() >= TradeEngineScript.MAX_PLAYERS_PER_SIDE
	remove_request_button.disabled = requesting_players.is_empty()


func _populate_ai_teams() -> void:
	ai_teams = []
	team_picker.clear()
	for team in GameState.all_teams:
		if team.is_player_team:
			continue
		ai_teams.append(team)
		team_picker.add_item("%s %s" % [team.city, team.name])


func _format_player_row(player: Player, is_selected_for_trade: bool) -> String:
	var prefix: String = "✓ " if is_selected_for_trade else ""
	return "%s[%s] %s - OVR %d - %s" % [prefix, player.position, player.full_name, player.get_overall(), _format_money(player.salary)]


func _format_player_names(players: Array) -> String:
	if players.is_empty():
		return "none"

	var names: Array[String] = []
	for player in players:
		names.append(player.full_name)
	return ", ".join(names)


func _format_money(amount: int) -> String:
	var sign: String = "" if amount >= 0 else "-"
	var absolute_amount: int = absi(amount)
	if absolute_amount >= 1_000_000:
		return "%s$%.1fM" % [sign, float(absolute_amount) / 1_000_000.0]
	if absolute_amount >= 1_000:
		return "%s$%dK" % [sign, int(round(float(absolute_amount) / 1_000.0))]
	return "%s$%d" % [sign, absolute_amount]
