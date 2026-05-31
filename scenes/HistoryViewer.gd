extends CanvasLayer

const HistoryManagerScript = preload("res://scripts/HistoryManager.gd")

@onready var title_label: Label = $Control/PanelContainer/VBoxContainer/Header/TitleLabel
@onready var summary_label: Label = $Control/PanelContainer/VBoxContainer/Header/SummaryLabel
@onready var season_list: ItemList = $Control/PanelContainer/VBoxContainer/MainArea/LeftPanel/SeasonList
@onready var season_title_label: Label = $Control/PanelContainer/VBoxContainer/MainArea/RightPanel/SeasonTitleLabel
@onready var champion_label: Label = $Control/PanelContainer/VBoxContainer/MainArea/RightPanel/ChampionLabel
@onready var player_record_label: Label = $Control/PanelContainer/VBoxContainer/MainArea/RightPanel/PlayerRecordLabel
@onready var awards_list: ItemList = $Control/PanelContainer/VBoxContainer/MainArea/RightPanel/AwardsList
@onready var standings_list: ItemList = $Control/PanelContainer/VBoxContainer/MainArea/RightPanel/StandingsList
@onready var close_button: Button = $Control/PanelContainer/VBoxContainer/CloseButton


func _ready() -> void:
	visible = false
	season_list.item_selected.connect(_on_season_selected)
	close_button.pressed.connect(_on_close)


func show_history() -> void:
	season_list.clear()
	awards_list.clear()
	standings_list.clear()
	_update_summary()

	if GameState.history.is_empty():
		season_title_label.text = "No history yet. Complete a season to begin."
		champion_label.text = ""
		player_record_label.text = ""
		visible = true
		return

	var reversed_history: Array = GameState.history.duplicate()
	reversed_history.reverse()
	for season in reversed_history:
		season_list.add_item("Year %d - Champion: %s" % [
			season.get("year", 0),
			_get_champion_name(season)
		])
	season_list.select(0)
	_show_season(0)
	visible = true


func _show_season(history_index: int) -> void:
	var season: Dictionary = _get_reversed_season(history_index)
	if season.is_empty():
		return

	season_title_label.text = "Year %d Season" % season.get("year", 0)
	champion_label.text = "Champion: %s" % _get_champion_name(season)
	var player_record: Dictionary = season.get("player_record", {})
	player_record_label.text = "Player Record: %d-%d | Result: %s" % [
		player_record.get("wins", 0),
		player_record.get("losses", 0),
		player_record.get("playoff_status", "")
	]

	awards_list.clear()
	var awards: Dictionary = season.get("awards", {})
	for award_name in awards.keys():
		var award: Dictionary = awards[award_name]
		awards_list.add_item("%s - %s (%s)" % [award_name, award.get("player_name", ""), award.get("team_name", "")])

	standings_list.clear()
	var standings: Array = season.get("standings", [])
	for index in standings.size():
		var team: Dictionary = standings[index]
		standings_list.add_item("%d. %s %s  %d-%d" % [
			index + 1,
			team.get("city", ""),
			team.get("name", ""),
			team.get("wins", 0),
			team.get("losses", 0)
		])


func _on_season_selected(index: int) -> void:
	_show_season(index)


func _on_close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		visible = false
		get_viewport().set_input_as_handled()


func _update_summary() -> void:
	var championships: int = HistoryManagerScript.get_player_championships(GameState.history, GameState.player_team_id)
	var best_record: Dictionary = HistoryManagerScript.get_best_record(GameState.history, GameState.player_team_id)
	var best_record_text: String = "--"
	if not best_record.is_empty():
		best_record_text = "%d-%d" % [best_record.get("wins", 0), best_record.get("losses", 0)]
	summary_label.text = "Championships: %d | Best Record: %s | Years Active: %d" % [championships, best_record_text, GameState.history.size()]


func _get_reversed_season(history_index: int) -> Dictionary:
	var source_index: int = GameState.history.size() - 1 - history_index
	if source_index < 0 or source_index >= GameState.history.size():
		return {}
	return GameState.history[source_index]


func _get_champion_name(season: Dictionary) -> String:
	var champion_name: String = season.get("champion_name", "")
	return champion_name if champion_name != "" else "Not crowned"
