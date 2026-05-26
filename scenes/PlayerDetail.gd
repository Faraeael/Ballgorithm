extends CanvasLayer

signal closed

const ScoutingSystemScript = preload("res://scripts/ScoutingSystem.gd")

@onready var player_name_label: Label = $Control/Panel/Content/Header/Identity/PlayerNameLabel
@onready var position_archetype_label: Label = $Control/Panel/Content/Header/Identity/PositionArchetypeLabel
@onready var team_label: Label = $Control/Panel/Content/Header/Identity/TeamLabel
@onready var overall_label: Label = $Control/Panel/Content/Header/Ratings/OverallLabel
@onready var potential_label: Label = $Control/Panel/Content/Header/Ratings/PotentialLabel
@onready var speed_label: Label = $Control/Panel/Content/Attributes/PhysicalsCol/SpeedLabel
@onready var vertical_label: Label = $Control/Panel/Content/Attributes/PhysicalsCol/VerticalLabel
@onready var strength_label: Label = $Control/Panel/Content/Attributes/PhysicalsCol/StrengthLabel
@onready var stamina_label: Label = $Control/Panel/Content/Attributes/PhysicalsCol/StaminaLabel
@onready var durability_label: Label = $Control/Panel/Content/Attributes/PhysicalsCol/DurabilityLabel
@onready var shooting3_label: Label = $Control/Panel/Content/Attributes/SkillsCol/Shooting3Label
@onready var shooting_mid_label: Label = $Control/Panel/Content/Attributes/SkillsCol/ShootingMidLabel
@onready var free_throw_label: Label = $Control/Panel/Content/Attributes/SkillsCol/FreeThrowLabel
@onready var finishing_label: Label = $Control/Panel/Content/Attributes/SkillsCol/FinishingLabel
@onready var ball_handling_label: Label = $Control/Panel/Content/Attributes/SkillsCol/BallHandlingLabel
@onready var passing_label: Label = $Control/Panel/Content/Attributes/SkillsCol/PassingLabel
@onready var post_play_label: Label = $Control/Panel/Content/Attributes/SkillsCol/PostPlayLabel
@onready var perimeter_d_label: Label = $Control/Panel/Content/Attributes/DefenseCol/PerimeterDLabel
@onready var post_d_label: Label = $Control/Panel/Content/Attributes/DefenseCol/PostDLabel
@onready var steal_label: Label = $Control/Panel/Content/Attributes/DefenseCol/StealLabel
@onready var block_label: Label = $Control/Panel/Content/Attributes/DefenseCol/BlockLabel
@onready var def_iq_label: Label = $Control/Panel/Content/Attributes/DefenseCol/DefIQLabel
@onready var off_iq_label: Label = $Control/Panel/Content/Attributes/MentalCol/OffIQLabel
@onready var clutch_label: Label = $Control/Panel/Content/Attributes/MentalCol/ClutchLabel
@onready var composure_label: Label = $Control/Panel/Content/Attributes/MentalCol/ComposureLabel
@onready var leadership_label: Label = $Control/Panel/Content/Attributes/MentalCol/LeadershipLabel
@onready var work_ethic_label: Label = $Control/Panel/Content/Attributes/MentalCol/WorkEthicLabel
@onready var age_label: Label = $Control/Panel/Content/ContractRow/AgeLabel
@onready var salary_label: Label = $Control/Panel/Content/ContractRow/SalaryLabel
@onready var contract_label: Label = $Control/Panel/Content/ContractRow/ContractLabel
@onready var injury_status_label: Label = $Control/Panel/Content/InjuryStatusLabel
@onready var close_button: Button = $Control/Panel/Content/CloseButton


func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close)


# Populates every field from the provided player resource before showing the overlay.
func show_player(player: Player, is_opponent: bool = false) -> void:
	if player == null:
		return

	var visibility: Dictionary = _get_visibility(player, is_opponent)
	var archetype_text: String = player.archetype if visibility["show_archetype"] else "??"
	var overall_text: String = _get_overall_text(player, visibility)
	player_name_label.text = player.full_name
	position_archetype_label.text = "%s — %s" % [player.position, archetype_text]
	team_label.text = _get_team_name(player)
	overall_label.text = "OVR %s" % overall_text
	potential_label.text = "POT %s" % (str(player.potential) if visibility["show_potential"] else "??")
	age_label.text = "Age: %d" % player.age
	salary_label.text = "Salary: $%.1fM" % (float(player.salary) / 1_000_000.0)
	contract_label.text = "Contract: %d yrs" % player.contract_years
	_set_injury_status(player)

	if not visibility["show_attributes"]:
		_hide_attribute_labels()
		visible = true
		return

	_set_attribute_label(speed_label, "Speed", player.physicals.get("Speed", 0))
	_set_attribute_label(vertical_label, "Vertical", player.physicals.get("Vertical", 0))
	_set_attribute_label(strength_label, "Strength", player.physicals.get("Strength", 0))
	_set_attribute_label(stamina_label, "Stamina", player.physicals.get("Stamina", 0))
	_set_attribute_label(durability_label, "Durability", player.physicals.get("Durability", 0))
	_set_attribute_label(shooting3_label, "Shooting3", player.skills.get("Shooting3", 0))
	_set_attribute_label(shooting_mid_label, "ShootingMid", player.skills.get("ShootingMid", 0))
	_set_attribute_label(free_throw_label, "FreeThrow", player.skills.get("FreeThrow", 0))
	_set_attribute_label(finishing_label, "Finishing", player.skills.get("Finishing", 0))
	_set_attribute_label(ball_handling_label, "BallHandling", player.skills.get("BallHandling", 0))
	_set_attribute_label(passing_label, "Passing", player.skills.get("Passing", 0))
	_set_attribute_label(post_play_label, "PostPlay", player.skills.get("PostPlay", 0))
	_set_attribute_label(perimeter_d_label, "PerimeterD", player.defense.get("PerimeterD", 0))
	_set_attribute_label(post_d_label, "PostD", player.defense.get("PostD", 0))
	_set_attribute_label(steal_label, "Steal", player.defense.get("Steal", 0))
	_set_attribute_label(block_label, "Block", player.defense.get("Block", 0))
	_set_attribute_label(def_iq_label, "DefIQ", player.defense.get("DefIQ", 0))
	_set_attribute_label(off_iq_label, "OffIQ", player.mental.get("OffIQ", 0))
	_set_attribute_label(clutch_label, "Clutch", player.mental.get("Clutch", 0))
	_set_attribute_label(composure_label, "Composure", player.mental.get("Composure", 0))
	_set_attribute_label(leadership_label, "Leadership", player.mental.get("Leadership", 0))
	_set_attribute_label(work_ethic_label, "WorkEthic", player.mental.get("WorkEthic", 0))

	visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		_on_close()
		get_viewport().set_input_as_handled()


func _on_close() -> void:
	closed.emit()
	visible = false


func _get_visibility(player: Player, is_opponent: bool) -> Dictionary:
	if not is_opponent:
		return ScoutingSystemScript.get_player_info(player, 5, false)

	var player_team: Team = GameState.get_player_team()
	var scout_level: int = player_team.staff_scout if player_team != null else 1
	return ScoutingSystemScript.get_player_info(player, scout_level, true)


func _get_overall_text(player: Player, visibility: Dictionary) -> String:
	if visibility["show_exact_overall"]:
		return str(player.get_overall())
	if visibility["show_overall_range"] and visibility["overall_range"] != "":
		return visibility["overall_range"]
	return "??"


func _hide_attribute_labels() -> void:
	for label in _get_attribute_labels():
		label.text = "??"
		label.remove_theme_color_override("font_color")


func _get_attribute_labels() -> Array[Label]:
	return [
		speed_label, vertical_label, strength_label, stamina_label, durability_label,
		shooting3_label, shooting_mid_label, free_throw_label, finishing_label, ball_handling_label,
		passing_label, post_play_label, perimeter_d_label, post_d_label, steal_label, block_label,
		def_iq_label, off_iq_label, clutch_label, composure_label, leadership_label, work_ethic_label
	]


# Finds the current roster owner by player id; unmatched players are displayed as free agents.
func _get_team_name(player: Player) -> String:
	for team in GameState.all_teams:
		for roster_player in team.roster:
			if roster_player.id == player.id:
				return "%s %s" % [team.city, team.name]
	return "Free Agent"


func _set_attribute_label(label: Label, attribute_name: String, value: int) -> void:
	label.text = "%s: %d" % [attribute_name, value]
	label.add_theme_color_override("font_color", _get_attribute_color(value))


func _set_injury_status(player: Player) -> void:
	if player.is_injured:
		injury_status_label.text = "%s — %d games remaining" % [player.injury_type, player.injury_games_remaining]
		injury_status_label.add_theme_color_override("font_color", Color(0.95, 0.25, 0.25))
		return

	injury_status_label.text = "Healthy"
	injury_status_label.add_theme_color_override("font_color", Color(0.25, 0.85, 0.35))


func _get_attribute_color(value: int) -> Color:
	if value >= 80:
		return Color(0.25, 0.85, 0.35)
	if value >= 65:
		return Color(0.95, 0.82, 0.25)
	if value >= 50:
		return Color(1.0, 1.0, 1.0)
	return Color(0.95, 0.25, 0.25)
