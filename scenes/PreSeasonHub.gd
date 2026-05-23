extends Control

const COACH_UPGRADE_COST: int = 2_000_000
const SCOUT_UPGRADE_COST: int = 2_000_000
const MEDICAL_UPGRADE_COST: int = 2_000_000
const FACILITIES_UPGRADE_COST: int = 3_000_000
const MAX_LEVEL: int = 5
const MIN_DRAFT_ADVANCE_ROSTER: int = 10

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
@onready var coach_row: HBoxContainer = $VBoxContainer/MainArea/RightPanel/CoachRow
@onready var coach_label: Label = $VBoxContainer/MainArea/RightPanel/CoachRow/CoachLabel
@onready var upgrade_coach_button: Button = $VBoxContainer/MainArea/RightPanel/CoachRow/UpgradeCoachButton
@onready var scout_row: HBoxContainer = $VBoxContainer/MainArea/RightPanel/ScoutRow
@onready var scout_label: Label = $VBoxContainer/MainArea/RightPanel/ScoutRow/ScoutLabel
@onready var upgrade_scout_button: Button = $VBoxContainer/MainArea/RightPanel/ScoutRow/UpgradeScoutButton
@onready var medical_row: HBoxContainer = $VBoxContainer/MainArea/RightPanel/MedicalRow
@onready var medical_label: Label = $VBoxContainer/MainArea/RightPanel/MedicalRow/MedicalLabel
@onready var upgrade_medical_button: Button = $VBoxContainer/MainArea/RightPanel/MedicalRow/UpgradeMedicalButton
@onready var facilities_row: HBoxContainer = $VBoxContainer/MainArea/RightPanel/FacilitiesRow
@onready var facilities_label: Label = $VBoxContainer/MainArea/RightPanel/FacilitiesRow/FacilitiesLabel
@onready var upgrade_facilities_button: Button = $VBoxContainer/MainArea/RightPanel/FacilitiesRow/UpgradeFacilitiesButton
@onready var right_separator: HSeparator = $VBoxContainer/MainArea/RightPanel/RightSeparator
@onready var cap_summary_label: Label = $VBoxContainer/MainArea/RightPanel/CapSummaryLabel
@onready var payroll_label: Label = $VBoxContainer/MainArea/RightPanel/PayrollLabel
@onready var bottom_separator: HSeparator = $VBoxContainer/BottomSeparator
@onready var advance_to_draft_button: Button = $VBoxContainer/AdvanceToDraftButton


func _ready() -> void:
	upgrade_coach_button.pressed.connect(_on_upgrade_coach)
	upgrade_scout_button.pressed.connect(_on_upgrade_scout)
	upgrade_medical_button.pressed.connect(_on_upgrade_medical)
	upgrade_facilities_button.pressed.connect(_on_upgrade_facilities)
	advance_to_draft_button.pressed.connect(_on_advance)
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
		roster_list.add_item(roster_line)

	coach_label.text = "Coach: Level %d" % team.staff_coach
	scout_label.text = "Scout: Level %d" % team.staff_scout
	medical_label.text = "Medical: Level %d" % team.staff_medical
	facilities_label.text = "Facilities: Level %d" % team.facilities

	var cap_summary: Dictionary = CapEngine.get_cap_summary(team)
	cap_summary_label.text = "Cap Space: %s" % _format_money(cap_summary["cap_space"])
	payroll_label.text = "Payroll: %s" % _format_money(cap_summary["payroll"])

	upgrade_coach_button.disabled = team.staff_coach >= MAX_LEVEL or team.budget < COACH_UPGRADE_COST
	upgrade_scout_button.disabled = team.staff_scout >= MAX_LEVEL or team.budget < SCOUT_UPGRADE_COST
	upgrade_medical_button.disabled = team.staff_medical >= MAX_LEVEL or team.budget < MEDICAL_UPGRADE_COST
	upgrade_facilities_button.disabled = team.facilities >= MAX_LEVEL or team.budget < FACILITIES_UPGRADE_COST
	advance_to_draft_button.text = "Advance to Draft"


# Each upgrade checks both budget and level cap before mutating the team resource.
func _on_upgrade_coach() -> void:
	var team: Team = GameState.get_player_team()
	if team != null and team.budget >= COACH_UPGRADE_COST and team.staff_coach < MAX_LEVEL:
		team.budget -= COACH_UPGRADE_COST
		team.staff_coach += 1
		_refresh_ui()


func _on_upgrade_scout() -> void:
	var team: Team = GameState.get_player_team()
	if team != null and team.budget >= SCOUT_UPGRADE_COST and team.staff_scout < MAX_LEVEL:
		team.budget -= SCOUT_UPGRADE_COST
		team.staff_scout += 1
		_refresh_ui()


func _on_upgrade_medical() -> void:
	var team: Team = GameState.get_player_team()
	if team != null and team.budget >= MEDICAL_UPGRADE_COST and team.staff_medical < MAX_LEVEL:
		team.budget -= MEDICAL_UPGRADE_COST
		team.staff_medical += 1
		_refresh_ui()


func _on_upgrade_facilities() -> void:
	var team: Team = GameState.get_player_team()
	if team != null and team.budget >= FACILITIES_UPGRADE_COST and team.facilities < MAX_LEVEL:
		team.budget -= FACILITIES_UPGRADE_COST
		team.facilities += 1
		_refresh_ui()


# Prevents entering the draft with an invalid roster shell.
func _on_advance() -> void:
	var team: Team = GameState.get_player_team()
	if team == null or team.roster.size() < MIN_DRAFT_ADVANCE_ROSTER:
		advance_to_draft_button.text = "Need at least 10 players"
		return

	GameState.set_phase(GameState.Phase.DRAFT)
	get_tree().change_scene_to_file("res://scenes/Draft.tscn")


func _format_money(amount: int) -> String:
	var sign: String = "" if amount >= 0 else "-"
	var absolute_amount: int = absi(amount)
	if absolute_amount >= 1_000_000:
		return "%s$%.1fM" % [sign, float(absolute_amount) / 1_000_000.0]
	if absolute_amount >= 1_000:
		return "%s$%dK" % [sign, int(round(float(absolute_amount) / 1_000.0))]
	return "%s$%d" % [sign, absolute_amount]
