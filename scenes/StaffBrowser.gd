extends CanvasLayer

const StaffGeneratorScript = preload("res://scripts/StaffGenerator.gd")

signal staff_hired(role: String, member: Dictionary)

var candidates: Array = []
var current_role: String = ""

@onready var title_label: Label = $Control/PanelContainer/VBoxContainer/TitleLabel
@onready var current_staff_label: Label = $Control/PanelContainer/VBoxContainer/CurrentStaffLabel
@onready var candidates_container: VBoxContainer = $Control/PanelContainer/VBoxContainer/CandidatesContainer
@onready var budget_label: Label = $Control/PanelContainer/VBoxContainer/BudgetLabel
@onready var close_button: Button = $Control/PanelContainer/VBoxContainer/CloseButton


func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close)


func show_browser(role: String, current_tier: int, budget: int) -> void:
	current_role = role
	title_label.text = "Available %s" % _get_role_plural(role)

	var team: Team = GameState.get_player_team()
	var current_member: Dictionary = _get_current_staff_member(team, role)
	var fallback = StaffGeneratorScript.generate_staff(role, current_tier)
	var current_name: String = current_member.get("name", fallback.name)
	var current_title: String = current_member.get("title", fallback.title)
	var current_effect: String = current_member.get("effect_description", fallback.effect_description)
	current_staff_label.text = "Current: %s — %s — %s" % [current_name, current_title, current_effect]

	# Show the next tier and, when available, one tier beyond so the player can scout ahead.
	candidates = []
	var next_tier: int = min(current_tier + 1, 5)
	for index in range(2):
		candidates.append(StaffGeneratorScript.generate_staff(role, next_tier))
	if current_tier + 2 <= 5:
		for index in range(2):
			candidates.append(StaffGeneratorScript.generate_staff(role, current_tier + 2))

	_clear_candidates()
	for index in range(candidates.size()):
		_add_candidate_card(index, budget)

	budget_label.text = "Budget: %s" % _format_money(budget)
	visible = true


func _on_hire(index: int) -> void:
	if index < 0 or index >= candidates.size():
		return

	var team: Team = GameState.get_player_team()
	if team == null:
		return

	var candidate = candidates[index]
	if team.budget < candidate.salary:
		return

	team.budget -= candidate.salary
	var member_dict: Dictionary = candidate.to_dict()
	match current_role:
		"Coach":
			team.staff_coach = candidate.tier
			team.staff_coach_member = member_dict
		"Scout":
			team.staff_scout = candidate.tier
			team.staff_scout_member = member_dict
		"Doctor":
			team.staff_medical = candidate.tier
			team.staff_medical_member = member_dict
		_:
			return

	staff_hired.emit(current_role, member_dict)
	visible = false


func _on_close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		visible = false
		get_viewport().set_input_as_handled()


func _add_candidate_card(index: int, budget: int) -> void:
	var candidate = candidates[index]
	var card: PanelContainer = PanelContainer.new()
	candidates_container.add_child(card)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 4)
	card.add_child(layout)

	var name_label: Label = Label.new()
	name_label.text = "%s — %s" % [candidate.name, candidate.title]
	layout.add_child(name_label)

	var effect_label: Label = Label.new()
	effect_label.text = candidate.effect_description
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(effect_label)

	var salary_label: Label = Label.new()
	salary_label.text = "Annual cost: %s" % _format_money(candidate.salary)
	layout.add_child(salary_label)

	var hire_button: Button = Button.new()
	hire_button.text = "Hire (%s)" % _format_money(candidate.salary)
	hire_button.disabled = budget < candidate.salary
	hire_button.pressed.connect(_on_hire.bind(index))
	layout.add_child(hire_button)


func _clear_candidates() -> void:
	for child in candidates_container.get_children():
		candidates_container.remove_child(child)
		child.queue_free()


func _get_current_staff_member(team: Team, role: String) -> Dictionary:
	if team == null:
		return {}

	match role:
		"Coach":
			return team.staff_coach_member
		"Scout":
			return team.staff_scout_member
		"Doctor":
			return team.staff_medical_member
		_:
			return {}


func _get_role_plural(role: String) -> String:
	match role:
		"Coach":
			return "Coaches"
		"Doctor":
			return "Doctors"
		"Scout":
			return "Scouts"
		_:
			return "%ss" % role


func _format_money(amount: int) -> String:
	var sign: String = "" if amount >= 0 else "-"
	var absolute_amount: int = absi(amount)
	if absolute_amount >= 1_000_000:
		return "%s$%.1fM" % [sign, float(absolute_amount) / 1_000_000.0]
	if absolute_amount >= 1_000:
		return "%s$%dK" % [sign, int(round(float(absolute_amount) / 1_000.0))]
	return "%s$%d" % [sign, absolute_amount]
