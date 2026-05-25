extends CanvasLayer

@onready var team_name_label: Label = $Control/Panel/Content/Header/Identity/TeamNameLabel
@onready var team_situation_label: Label = $Control/Panel/Content/Header/Identity/TeamSituationLabel
@onready var record_label: Label = $Control/Panel/Content/Header/Summary/RecordLabel
@onready var cap_label: Label = $Control/Panel/Content/Header/Summary/CapLabel
@onready var staff_coach_label: Label = $Control/Panel/Content/StaffRow/StaffCoachLabel
@onready var staff_scout_label: Label = $Control/Panel/Content/StaffRow/StaffScoutLabel
@onready var staff_medical_label: Label = $Control/Panel/Content/StaffRow/StaffMedicalLabel
@onready var facilities_label: Label = $Control/Panel/Content/StaffRow/FacilitiesLabel
@onready var roster_list: ItemList = $Control/Panel/Content/RosterList
@onready var close_button: Button = $Control/Panel/Content/CloseButton

var sorted_roster: Array = []
var reopen_after_player_detail: bool = false
var is_viewing_opponent_team: bool = false


func _ready() -> void:
	visible = false
	roster_list.item_activated.connect(_on_player_activated)
	close_button.pressed.connect(_on_close)
	PlayerDetail.closed.connect(_on_player_detail_closed)


# Rebuilds the overlay from the passed team so any scene can inspect roster details.
func show_team(team: Team) -> void:
	if team == null:
		return

	var cap_summary: Dictionary = CapEngine.get_cap_summary(team)
	is_viewing_opponent_team = not team.is_player_team
	team_name_label.text = "%s %s" % [team.city, team.name]
	team_situation_label.text = team.situation
	record_label.text = "%d-%d" % [team.wins, team.losses]
	cap_label.text = "Cap: %s" % _format_money(cap_summary["cap_space"])
	staff_coach_label.text = "Coach: L%d" % team.staff_coach
	staff_scout_label.text = "Scout: L%d" % team.staff_scout
	staff_medical_label.text = "Medical: L%d" % team.staff_medical
	facilities_label.text = "Facilities: L%d" % team.facilities

	# Keep this sorted copy so double-click indexes match the displayed order.
	sorted_roster = team.roster.duplicate()
	sorted_roster.sort_custom(_sort_players_by_overall_desc)

	roster_list.clear()
	for player in sorted_roster:
		roster_list.add_item("[%s] %s — OVR %d — %s — %s" % [
			player.position,
			player.full_name,
			player.get_overall(),
			player.archetype,
			_format_money(player.salary)
		])

	visible = true


func _on_player_activated(index: int) -> void:
	if index < 0 or index >= sorted_roster.size():
		return

	# Hide the roster overlay so the player detail panel is not visually stacked under it.
	visible = false
	reopen_after_player_detail = true
	PlayerDetail.show_player(sorted_roster[index], is_viewing_opponent_team)


func _on_player_detail_closed() -> void:
	if not reopen_after_player_detail:
		return

	reopen_after_player_detail = false
	visible = true


func _on_close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible or PlayerDetail.visible:
		return

	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		_on_close()
		get_viewport().set_input_as_handled()


func _sort_players_by_overall_desc(player_a: Player, player_b: Player) -> bool:
	return player_a.get_overall() > player_b.get_overall()


func _format_money(amount: int) -> String:
	var sign: String = "" if amount >= 0 else "-"
	var absolute_amount: int = absi(amount)
	if absolute_amount >= 1_000_000:
		return "%s$%.1fM" % [sign, float(absolute_amount) / 1_000_000.0]
	if absolute_amount >= 1_000:
		return "%s$%dK" % [sign, int(round(float(absolute_amount) / 1_000.0))]
	return "%s$%d" % [sign, absolute_amount]
