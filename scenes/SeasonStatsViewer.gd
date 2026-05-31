extends CanvasLayer

const CATEGORIES: Array = ["Points", "Rebounds", "Assists", "Steals", "Blocks", "Overall"]
const POSITIONS: Array[String] = ["PG", "SG", "SF", "PF", "C"]

@onready var title_label: Label = $Control/PanelContainer/VBoxContainer/Header/TitleLabel
@onready var year_label: Label = $Control/PanelContainer/VBoxContainer/Header/YearLabel
@onready var category_filter: OptionButton = $Control/PanelContainer/VBoxContainer/Filters/CategoryFilter
@onready var team_filter: OptionButton = $Control/PanelContainer/VBoxContainer/Filters/TeamFilter
@onready var position_filter: OptionButton = $Control/PanelContainer/VBoxContainer/Filters/PositionFilter
@onready var stats_list: ItemList = $Control/PanelContainer/VBoxContainer/StatsList
@onready var close_button: Button = $Control/PanelContainer/VBoxContainer/CloseButton

var all_stat_rows: Array = []
var visible_rows: Array = []


func _ready() -> void:
	visible = false
	category_filter.item_selected.connect(_on_filter_changed)
	team_filter.item_selected.connect(_on_filter_changed)
	position_filter.item_selected.connect(_on_filter_changed)
	stats_list.item_activated.connect(_on_player_activated)
	close_button.pressed.connect(_on_close)


func show_stats() -> void:
	year_label.text = "Year %d" % GameState.current_year
	_build_stat_rows()
	_populate_filters()
	_refresh_list()
	visible = true


func _refresh_list() -> void:
	var selected_category: String = category_filter.get_item_text(category_filter.selected)
	var selected_team: String = team_filter.get_item_text(team_filter.selected)
	var selected_position: String = position_filter.get_item_text(position_filter.selected)
	visible_rows = []

	for row in all_stat_rows:
		var team: Team = row["team"]
		var player: Player = row["player"]
		if selected_team != "All Teams" and _team_name(team) != selected_team:
			continue
		if selected_position != "All Positions" and player.position != selected_position:
			continue
		visible_rows.append(row)

	visible_rows.sort_custom(_sort_rows_by_category.bind(_category_key(selected_category)))
	stats_list.clear()
	stats_list.add_item("RANK  NAME                 POS  PTS  REB  AST  STL  BLK  OVR  TEAM")
	stats_list.set_item_disabled(0, true)

	for index in visible_rows.size():
		var row: Dictionary = visible_rows[index]
		var player: Player = row["player"]
		var team: Team = row["team"]
		var prefix: String = "★" if team != null and team.is_player_team else " "
		stats_list.add_item("%s%s  %s  %s  %s  %s  %s  %s  %s  %s   %s" % [
			prefix,
			_lpad("%d." % (index + 1), 3),
			_rpad(player.full_name, 20),
			_rpad(player.position, 3),
			_lpad("%.1f" % row["points"], 4),
			_lpad("%.1f" % row["rebounds"], 4),
			_lpad("%.1f" % row["assists"], 4),
			_lpad("%.1f" % row["steals"], 4),
			_lpad("%.1f" % row["blocks"], 4),
			_lpad(str(row["overall"]), 3),
			_team_name(team)
		])


func _on_filter_changed(_index: int) -> void:
	_refresh_list()


func _on_player_activated(index: int) -> void:
	var row_index: int = index - 1
	if row_index < 0 or row_index >= visible_rows.size():
		return

	var row: Dictionary = visible_rows[row_index]
	var team: Team = row["team"]
	PlayerDetail.show_player(row["player"], team == null or not team.is_player_team)


func _on_close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and not PlayerDetail.visible and event.is_action_pressed("ui_cancel"):
		visible = false
		get_viewport().set_input_as_handled()


func _build_stat_rows() -> void:
	PlayerDB.rebuild()
	all_stat_rows = []
	for player_id in GameState.season_stats.keys():
		var player: Player = PlayerDB.get_player(player_id)
		if player == null:
			continue

		var team: Team = _find_player_team(player)
		var stats: Dictionary = GameState.season_stats[player_id]
		all_stat_rows.append({
			"player": player,
			"team": team,
			"points": float(stats.get("points", 0.0)),
			"rebounds": float(stats.get("rebounds", 0.0)),
			"assists": float(stats.get("assists", 0.0)),
			"steals": float(stats.get("steals", 0.0)),
			"blocks": float(stats.get("blocks", 0.0)),
			"games_played": int(stats.get("games_played", 0)),
			"overall": player.get_overall()
		})


func _populate_filters() -> void:
	category_filter.clear()
	for category in CATEGORIES:
		category_filter.add_item(category)
	category_filter.select(0)

	team_filter.clear()
	team_filter.add_item("All Teams")
	for team in GameState.all_teams:
		team_filter.add_item(_team_name(team))
	team_filter.select(0)

	position_filter.clear()
	position_filter.add_item("All Positions")
	for position in POSITIONS:
		position_filter.add_item(position)
	position_filter.select(0)


func _sort_rows_by_category(a: Dictionary, b: Dictionary, category_key: String) -> bool:
	if is_equal_approx(float(a[category_key]), float(b[category_key])):
		return int(a["overall"]) > int(b["overall"])
	return float(a[category_key]) > float(b[category_key])


func _category_key(category: String) -> String:
	match category:
		"Points":
			return "points"
		"Rebounds":
			return "rebounds"
		"Assists":
			return "assists"
		"Steals":
			return "steals"
		"Blocks":
			return "blocks"
		"Overall":
			return "overall"
		_:
			return "points"


func _find_player_team(target_player: Player) -> Team:
	for team in GameState.all_teams:
		if team.roster.has(target_player):
			return team
	return null


func _team_name(team: Team) -> String:
	if team == null:
		return "Unknown Team"
	return "%s %s" % [team.city, team.name]


func _rpad(value: String, width: int) -> String:
	var result: String = value.substr(0, width)
	while result.length() < width:
		result += " "
	return result


func _lpad(value: String, width: int) -> String:
	var result: String = value.substr(0, width)
	while result.length() < width:
		result = " " + result
	return result
