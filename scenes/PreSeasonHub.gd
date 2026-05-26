extends Control

const StaffGeneratorScript = preload("res://scripts/StaffGenerator.gd")

const FACILITIES_UPGRADE_COST: int = 3_000_000
const MAX_LEVEL: int = 5

@onready var root_layout: VBoxContainer = $VBoxContainer
@onready var header: HBoxContainer = $VBoxContainer/Header
@onready var team_label: Label = $VBoxContainer/Header/TeamLabel
@onready var year_label: Label = $VBoxContainer/Header/YearLabel
@onready var budget_label: Label = $VBoxContainer/Header/BudgetLabel
@onready var top_separator: HSeparator = $VBoxContainer/TopSeparator
@onready var main_area: HBoxContainer = $VBoxContainer/MainArea
@onready var left_panel: VBoxContainer = $VBoxContainer/MainArea/LeftPanel
@onready var roster_title: Label = $VBoxContainer/MainArea/LeftPanel/RosterTitle
@onready var roster_list: ItemList = $VBoxContainer/MainArea/LeftPanel/RosterList
@onready var panel_separator: VSeparator = $VBoxContainer/MainArea/PanelSeparator
@onready var right_panel: VBoxContainer = $VBoxContainer/MainArea/RightPanel
@onready var staff_title: Label = $VBoxContainer/MainArea/RightPanel/StaffTitle
@onready var coach_row: VBoxContainer = $VBoxContainer/MainArea/RightPanel/CoachRow
@onready var coach_name_label: Label = $VBoxContainer/MainArea/RightPanel/CoachRow/CoachNameLabel
@onready var coach_effect_label: Label = $VBoxContainer/MainArea/RightPanel/CoachRow/CoachEffectLabel
@onready var coach_cost_label: Label = $VBoxContainer/MainArea/RightPanel/CoachRow/CoachCostLabel
@onready var find_coach_button: Button = $VBoxContainer/MainArea/RightPanel/CoachRow/FindCoachButton
@onready var scout_row: VBoxContainer = $VBoxContainer/MainArea/RightPanel/ScoutRow
@onready var scout_name_label: Label = $VBoxContainer/MainArea/RightPanel/ScoutRow/ScoutNameLabel
@onready var scout_effect_label: Label = $VBoxContainer/MainArea/RightPanel/ScoutRow/ScoutEffectLabel
@onready var scout_cost_label: Label = $VBoxContainer/MainArea/RightPanel/ScoutRow/ScoutCostLabel
@onready var find_scout_button: Button = $VBoxContainer/MainArea/RightPanel/ScoutRow/FindScoutButton
@onready var medical_row: VBoxContainer = $VBoxContainer/MainArea/RightPanel/MedicalRow
@onready var medical_name_label: Label = $VBoxContainer/MainArea/RightPanel/MedicalRow/MedicalNameLabel
@onready var medical_effect_label: Label = $VBoxContainer/MainArea/RightPanel/MedicalRow/MedicalEffectLabel
@onready var medical_cost_label: Label = $VBoxContainer/MainArea/RightPanel/MedicalRow/MedicalCostLabel
@onready var find_medical_button: Button = $VBoxContainer/MainArea/RightPanel/MedicalRow/FindMedicalButton
@onready var facilities_row: VBoxContainer = $VBoxContainer/MainArea/RightPanel/FacilitiesRow
@onready var facilities_name_label: Label = $VBoxContainer/MainArea/RightPanel/FacilitiesRow/FacilitiesNameLabel
@onready var facilities_effect_label: Label = $VBoxContainer/MainArea/RightPanel/FacilitiesRow/FacilitiesEffectLabel
@onready var facilities_cost_label: Label = $VBoxContainer/MainArea/RightPanel/FacilitiesRow/FacilitiesCostLabel
@onready var upgrade_facilities_button: Button = $VBoxContainer/MainArea/RightPanel/FacilitiesRow/UpgradeFacilitiesButton
@onready var right_separator: HSeparator = $VBoxContainer/MainArea/RightPanel/RightSeparator
@onready var cap_summary_label: Label = $VBoxContainer/MainArea/RightPanel/CapSummaryLabel
@onready var payroll_label: Label = $VBoxContainer/MainArea/RightPanel/PayrollLabel
@onready var bottom_separator: HSeparator = $VBoxContainer/BottomSeparator
@onready var advance_to_draft_button: Button = $VBoxContainer/AdvanceToDraftButton


func _ready() -> void:
	find_coach_button.pressed.connect(_on_find_coach)
	find_scout_button.pressed.connect(_on_find_scout)
	find_medical_button.pressed.connect(_on_find_medical)
	upgrade_facilities_button.pressed.connect(_on_upgrade_facilities)
	advance_to_draft_button.pressed.connect(_on_advance)
	roster_list.item_activated.connect(_on_roster_player_activated)
	if not StaffBrowser.staff_hired.is_connected(_on_staff_hired):
		StaffBrowser.staff_hired.connect(_on_staff_hired)
	_refresh_ui()


# Rebuilds all visible hub state from GameState and the player team resource.
func _refresh_ui() -> void:
	var team: Team = GameState.get_player_team()
	if team == null:
		team_label.text = "No Team Found"
		return

	team_label.text = "%s %s" % [team.city, team.name]
	year_label.text = "Year %d" % GameState.current_year
	budget_label.text = "Budget: %s" % _format_money(team.budget)

	roster_list.clear()
	for player in team.roster:
		var roster_line: String = "[%s] %s — OVR %d — %s — %d yrs" % [
			player.position,
			player.full_name,
			player.get_overall(),
			_format_money(player.salary),
			player.contract_years
		]
		if player.is_injured:
			roster_line += " ⚠ [%s]" % player.injury_type
		roster_list.add_item(roster_line)

	_refresh_staff_row("Coach", team.staff_coach, team.staff_coach_member, coach_name_label, coach_effect_label, coach_cost_label, find_coach_button)
	_refresh_staff_row("Scout", team.staff_scout, team.staff_scout_member, scout_name_label, scout_effect_label, scout_cost_label, find_scout_button)
	_refresh_staff_row("Doctor", team.staff_medical, team.staff_medical_member, medical_name_label, medical_effect_label, medical_cost_label, find_medical_button)
	_refresh_facilities_row(team)

	var cap_summary: Dictionary = CapEngine.get_cap_summary(team)
	cap_summary_label.text = "Cap Space: %s" % _format_money(cap_summary["cap_space"])
	payroll_label.text = "Payroll: %s" % _format_money(cap_summary["payroll"])

	advance_to_draft_button.text = "Advance to Draft"


# Staff candidates are shown in a shared autoload overlay so hiring can compare named options.
func _on_find_coach() -> void:
	_show_staff_browser("Coach")


func _on_find_scout() -> void:
	_show_staff_browser("Scout")


func _on_find_medical() -> void:
	_show_staff_browser("Doctor")


func _on_upgrade_facilities() -> void:
	var team: Team = GameState.get_player_team()
	if team != null and team.budget >= FACILITIES_UPGRADE_COST and team.facilities < MAX_LEVEL:
		team.budget -= FACILITIES_UPGRADE_COST
		team.facilities += 1
		_refresh_ui()


func _show_staff_browser(role: String) -> void:
	var team: Team = GameState.get_player_team()
	if team == null:
		return

	var current_tier: int = _get_staff_tier(team, role)
	if current_tier >= MAX_LEVEL:
		return

	StaffBrowser.show_browser(role, current_tier, team.budget)


func _on_staff_hired(_role: String, _member_dict: Dictionary) -> void:
	_refresh_ui()


func _on_advance() -> void:
	GameState.set_phase(GameState.Phase.DRAFT)
	get_tree().change_scene_to_file("res://scenes/Draft.tscn")


# Double-click opens the shared detail overlay for the matching roster entry.
func _on_roster_player_activated(index: int) -> void:
	var team: Team = GameState.get_player_team()
	if team == null or index < 0 or index >= team.roster.size():
		return

	PlayerDetail.show_player(team.roster[index])


func _refresh_staff_row(role: String, tier: int, member: Dictionary, name_label: Label, effect_label: Label, cost_label: Label, button: Button) -> void:
	var display_name: String = member.get("name", "Vacant")
	var title: String = member.get("title", "Vacant")
	var effect: String = member.get("effect_description", StaffGeneratorScript.generate_staff(role, tier).effect_description)
	name_label.text = "%s: %s - %s" % [role, display_name, title]
	effect_label.text = "Level %d - %s" % [tier, effect]
	cost_label.text = "Candidate search: %s" % ("Max tier" if tier >= MAX_LEVEL else "Tier %d+ available" % [tier + 1])
	button.text = "Max Staff Tier" if tier >= MAX_LEVEL else "Find Candidates"
	button.disabled = tier >= MAX_LEVEL


func _refresh_facilities_row(team: Team) -> void:
	var cost: int = FACILITIES_UPGRADE_COST
	facilities_name_label.text = "Facilities"
	facilities_effect_label.text = "Level %d - Simulation bonus +%d" % [team.facilities, team.facilities]
	facilities_cost_label.text = "Next upgrade: %s" % (_format_money(cost) if team.facilities < MAX_LEVEL else "Max tier")
	upgrade_facilities_button.text = "Max Facility Tier" if team.facilities >= MAX_LEVEL else "Upgrade Tier %d Facilities (%s)" % [team.facilities + 1, _format_money(cost)]
	upgrade_facilities_button.disabled = team.facilities >= MAX_LEVEL or team.budget < cost


func _get_staff_tier(team: Team, role: String) -> int:
	match role:
		"Coach":
			return team.staff_coach
		"Scout":
			return team.staff_scout
		"Doctor":
			return team.staff_medical
		_:
			return 1


func _format_money(amount: int) -> String:
	var sign: String = "" if amount >= 0 else "-"
	var absolute_amount: int = absi(amount)
	if absolute_amount >= 1_000_000:
		return "%s$%.1fM" % [sign, float(absolute_amount) / 1_000_000.0]
	if absolute_amount >= 1_000:
		return "%s$%dK" % [sign, int(round(float(absolute_amount) / 1_000.0))]
	return "%s$%d" % [sign, absolute_amount]
