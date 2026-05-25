extends CanvasLayer

@onready var matchup_label: Label = $Control/Panel/Content/Header/MatchupLabel
@onready var score_label: Label = $Control/Panel/Content/Header/ScoreLabel
@onready var home_title_label: Label = $Control/Panel/Content/Lists/HomePanel/HomeTitleLabel
@onready var home_stats_list: ItemList = $Control/Panel/Content/Lists/HomePanel/HomeStatsList
@onready var away_title_label: Label = $Control/Panel/Content/Lists/AwayPanel/AwayTitleLabel
@onready var away_stats_list: ItemList = $Control/Panel/Content/Lists/AwayPanel/AwayStatsList
@onready var close_button: Button = $Control/Panel/Content/CloseButton

var home_lines: Array = []
var away_lines: Array = []
var reopen_after_player_detail: bool = false


func _ready() -> void:
	visible = false
	home_stats_list.item_activated.connect(_on_home_player_activated)
	away_stats_list.item_activated.connect(_on_away_player_activated)
	close_button.pressed.connect(_on_close)
	PlayerDetail.closed.connect(_on_player_detail_closed)


# Shows one simulated game result without changing the underlying season state.
func show_box_score(result: Dictionary) -> void:
	var home_name: String = result.get("home_team_name", "Home")
	var away_name: String = result.get("away_team_name", "Away")
	var home_score: int = result.get("home_score", 0)
	var away_score: int = result.get("away_score", 0)

	matchup_label.text = "%s vs %s" % [away_name, home_name]
	score_label.text = "%s %d - %d %s" % [away_name, away_score, home_score, home_name]
	home_title_label.text = home_name
	away_title_label.text = away_name

	home_lines = result.get("home_box_score", [])
	away_lines = result.get("away_box_score", [])
	_populate_list(home_stats_list, home_lines)
	_populate_list(away_stats_list, away_lines)
	visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		_on_close()
		get_viewport().set_input_as_handled()


func _on_home_player_activated(index: int) -> void:
	_show_player_from_line(home_lines, index)


func _on_away_player_activated(index: int) -> void:
	_show_player_from_line(away_lines, index)


func _on_close() -> void:
	visible = false


func _populate_list(list: ItemList, lines: Array) -> void:
	list.clear()
	list.add_item("PLAYER                 MIN  PTS REB AST STL BLK  FG      3P")
	list.set_item_disabled(0, true)
	for line in lines:
		list.add_item("%s %2d  %3d %3d %3d %3d %3d  %d/%d  %d/%d" % [
			_pad_name("[%s] %s" % [line.get("position", ""), line.get("player_name", "Unknown")], 22),
			line.get("minutes", 0),
			line.get("points", 0),
			line.get("rebounds", 0),
			line.get("assists", 0),
			line.get("steals", 0),
			line.get("blocks", 0),
			line.get("fgm", 0),
			line.get("fga", 0),
			line.get("tpm", 0),
			line.get("tpa", 0)
		])


func _show_player_from_line(lines: Array, index: int) -> void:
	var line_index: int = index - 1
	if line_index < 0 or line_index >= lines.size():
		return

	var player: Player = lines[line_index].get("player", null)
	if player != null:
		# Hide this overlay while player details are open to prevent stacked panels.
		visible = false
		reopen_after_player_detail = true
		PlayerDetail.show_player(player)


func _on_player_detail_closed() -> void:
	if not reopen_after_player_detail:
		return

	reopen_after_player_detail = false
	visible = true


func _pad_name(value: String, width: int) -> String:
	if value.length() >= width:
		return value.substr(0, width)
	return value + " ".repeat(width - value.length())
