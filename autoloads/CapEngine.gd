extends Node

const SALARY_CAP: int = 136_000_000


# Returns the total committed salary for every player currently on the roster.
func get_team_payroll(team: Team) -> int:
	var payroll: int = 0
	for player in team.roster:
		payroll += player.salary
	return payroll


# Calculates live cap room from payroll. This can be negative when a team is over the hard cap.
func get_cap_space(team: Team) -> int:
	return SALARY_CAP - get_team_payroll(team)


# Checks whether the current payroll is above the league salary cap.
func is_over_cap(team: Team) -> bool:
	return get_team_payroll(team) > SALARY_CAP


# Validates a signing using live cap room, not the stored team.cap_space value.
func can_sign_player(team: Team, player: Player) -> bool:
	return get_cap_space(team) >= player.salary


# Adds a player only if the team can afford the full salary; failed signings do not mutate state.
func apply_contract(team: Team, player: Player) -> bool:
	if not can_sign_player(team, player):
		return false

	team.roster.append(player)
	team.cap_space -= player.salary
	return true


# Removes the first matching roster entry and restores its salary to stored cap_space.
func release_player(team: Team, player: Player) -> bool:
	var player_index: int = team.roster.find(player)
	if player_index == -1:
		return false

	team.roster.remove_at(player_index)
	team.cap_space += player.salary
	return true


# Applies a simple 1.5x penalty to any payroll overage. Teams at or under cap owe nothing.
func get_luxury_tax(team: Team) -> int:
	var overage: int = get_team_payroll(team) - SALARY_CAP
	if overage <= 0:
		return 0
	return int(overage * 1.5)


# Provides one dictionary for UI and save/debug screens so cap data is read consistently.
func get_cap_summary(team: Team) -> Dictionary:
	var payroll: int = get_team_payroll(team)
	var cap_space: int = SALARY_CAP - payroll
	return {
		"payroll": payroll,
		"cap_space": cap_space,
		"is_over_cap": payroll > SALARY_CAP,
		"luxury_tax": get_luxury_tax(team),
		"roster_count": team.roster.size(),
		"cap_limit": SALARY_CAP
	}
