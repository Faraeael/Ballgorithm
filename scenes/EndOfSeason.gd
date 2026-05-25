extends Control

const StaffGeneratorScript = preload("res://scripts/StaffGenerator.gd")

const DRAFT_CLASS_POSITIONS: Array = [
	"PG", "PG", "PG", "PG", "PG", "PG", "PG", "PG", "PG", "PG",
	"SG", "SG", "SG", "SG", "SG", "SG", "SG", "SG", "SG", "SG",
	"SF", "SF", "SF", "SF", "SF", "SF", "SF", "SF", "SF", "SF",
	"PF", "PF", "PF", "PF", "PF", "PF", "PF", "PF", "PF", "PF", "PF", "PF", "PF", "PF", "PF",
	"C", "C", "C", "C", "C", "C", "C", "C", "C", "C", "C", "C", "C", "C", "C"
]

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var champion_label: Label = $VBoxContainer/ChampionLabel
@onready var record_label: Label = $VBoxContainer/RecordLabel
@onready var result_label: Label = $VBoxContainer/ResultLabel
@onready var roster_changes_list: ItemList = $VBoxContainer/RosterChangesList
@onready var next_season_button: Button = $VBoxContainer/NextSeasonButton

var player_wins: int = 0
var player_losses: int = 0
var roster_changes: Array = []


func _ready() -> void:
	next_season_button.pressed.connect(_on_next_season)
	var season_year: int = _process_end_of_season()
	_refresh_ui(season_year, roster_changes)


func _process_end_of_season() -> int:
	var season_year: int = GameState.current_year
	roster_changes = []
	var player_team: Team = GameState.get_player_team()
	if player_team != null:
		# Records are cleared for the next year, so capture the player's result first.
		player_wins = player_team.wins
		player_losses = player_team.losses
		_deduct_staff_salaries(player_team)

	_reassign_draft_picks_by_record()

	for team in GameState.all_teams:
		var remaining_roster: Array = []
		for player in team.roster:
			# Contract expiry happens after the season year rolls over.
			player.age += 1
			player.contract_years -= 1
			_apply_player_development(player)

			if player.contract_years <= 0:
				GameState.free_agents.append(player)
				roster_changes.append("%s left %s. Contract expired." % [player.full_name, _format_team_name(team)])
			else:
				remaining_roster.append(player)
		team.roster = remaining_roster

	_generate_next_draft_pool()
	LeagueManager.reset_season_records()
	GameState.advance_year()
	return season_year


func _refresh_ui(season_year: int, changes: Array) -> void:
	title_label.text = "End of Season - Year %d" % season_year
	champion_label.text = "Champion: %s" % GameState.champion_name if GameState.champion_team_id != "" else "Champion: Not crowned"
	record_label.text = "Record: %d-%d" % [player_wins, player_losses]
	result_label.text = _get_result_text()

	roster_changes_list.clear()
	if changes.is_empty():
		roster_changes_list.add_item("No roster changes recorded.")
		return

	for change in changes:
		roster_changes_list.add_item(change)


func _on_next_season() -> void:
	GameState.playoff_status = ""
	GameState.champion_team_id = ""
	GameState.champion_name = ""
	GameState.playoff_bracket = []
	GameState.schedule = []
	GameState.set_phase(GameState.Phase.PRE_SEASON_HUB)
	get_tree().change_scene_to_file("res://scenes/PreSeasonHub.tscn")


# Staff salaries are annual operating costs paid before the next preseason budget decisions.
func _deduct_staff_salaries(team: Team) -> void:
	var total_salary: int = 0
	for member in [team.staff_coach_member, team.staff_scout_member, team.staff_medical_member]:
		if member.is_empty():
			continue
		var tier: int = member.get("tier", 1)
		total_salary += StaffGeneratorScript.get_tier_salary(tier)

	team.budget = maxi(team.budget - total_salary, 0)


func _apply_player_development(player: Player) -> void:
	if player.age >= 30:
		_apply_random_attribute_changes(player, 1, -3, -1, "regressed")
		return

	if player.age <= 26 and player.mental.get("WorkEthic", 0) >= 60:
		_apply_random_attribute_changes(player, 2, 1, 4, "improved")


func _apply_random_attribute_changes(player: Player, change_count: int, min_delta: int, max_delta: int, label: String) -> void:
	var attributes: Array = _get_attribute_refs(player)
	for count in range(change_count):
		if attributes.is_empty():
			return

		var index: int = randi_range(0, attributes.size() - 1)
		var attribute_ref: Dictionary = attributes[index]
		attributes.remove_at(index)

		var group: Dictionary = attribute_ref["group"]
		var attribute_name: String = attribute_ref["attribute"]
		var old_value: int = group[attribute_name]
		var delta: int = randi_range(min_delta, max_delta)
		var new_value: int = clampi(old_value + delta, 0, 99)
		group[attribute_name] = new_value

		if new_value != old_value:
			roster_changes.append("%s %s: %s %d -> %d" % [player.full_name, label, attribute_name, old_value, new_value])


func _get_attribute_refs(player: Player) -> Array:
	var attributes: Array = []
	for group in [player.physicals, player.skills, player.defense, player.mental]:
		for attribute_name in group.keys():
			attributes.append({"group": group, "attribute": attribute_name})
	return attributes


func _generate_next_draft_pool() -> void:
	GameState.draft_pool_next = []
	# Fixed v1 position distribution keeps every draft class at exactly 60 players.
	for position in DRAFT_CLASS_POSITIONS:
		GameState.draft_pool_next.append(PlayerGenerator.generate_player(position, "Tanking"))


func _reassign_draft_picks_by_record() -> void:
	var teams_by_record: Array = GameState.all_teams.duplicate()
	teams_by_record.sort_custom(_sort_worst_record_first)
	for index in teams_by_record.size():
		var team: Team = teams_by_record[index]
		team.draft_pick = index + 1


func _sort_worst_record_first(team_a: Team, team_b: Team) -> bool:
	if team_a.wins == team_b.wins:
		return team_a.losses > team_b.losses
	return team_a.wins < team_b.wins


func _get_result_text() -> String:
	match GameState.playoff_status:
		"playoffs":
			return "Result: Qualified for the playoffs."
		"playin":
			return "Result: Reached the Play-In tournament."
		"lottery":
			return "Result: Missed the postseason and entered the lottery."
		"eliminated":
			return "Result: Eliminated in the Play-In tournament."
		_:
			return "Result: Season complete."


func _format_team_name(team: Team) -> String:
	if team == null:
		return "Unknown Team"
	return "%s %s" % [team.city, team.name]
