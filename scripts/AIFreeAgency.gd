extends RefCounted
class_name AIFreeAgency

const ROSTER_TARGET: int = 13
const MIN_ROSTER: int = 10
const POSITION_SLOTS: Dictionary = {
	"PG": 2, "SG": 2, "SF": 2, "PF": 2, "C": 2
}


static func run_ai_free_agency(all_teams: Array, free_agents: Array) -> void:
	var signed_players: Array = []
	for team in all_teams:
		if team.is_player_team:
			continue

		_fill_team_roster(team, free_agents, signed_players)

	for player in signed_players:
		GameState.free_agents.erase(player)


static func _fill_team_roster(team: Team, available_agents: Array, signed_players: Array) -> void:
	# First pass: prioritize positional minimums so AI teams enter the season with a playable depth chart.
	for position in POSITION_SLOTS.keys():
		var skipped_position_players: Array = []
		while team.roster.size() < ROSTER_TARGET and _count_position(team, position) < POSITION_SLOTS[position]:
			var player: Player = _find_best_at_position_excluding(position, available_agents, skipped_position_players)
			if player == null:
				break

			if _try_sign_player(team, player, available_agents, signed_players):
				continue

			skipped_position_players.append(player)

			# Over-cap teams cannot use normal cap room, but can still chase minimum-salary depth until MIN_ROSTER.
			var minimum_player: Player = _find_minimum_salary_at_position(position, available_agents)
			if minimum_player == null or not _try_sign_minimum_player(team, minimum_player, available_agents, signed_players):
				continue

	# Second pass: after position needs, take the best remaining talent until the target roster size is reached.
	var skipped_players: Array = []
	while team.roster.size() < ROSTER_TARGET:
		var player: Player = _find_best_available_excluding(available_agents, skipped_players)
		if player == null:
			break

		if _try_sign_player(team, player, available_agents, signed_players):
			continue

		skipped_players.append(player)

		# If no cap room exists, only allow minimum-salary signings while below the hard floor.
		var minimum_player: Player = _find_minimum_salary_available(available_agents)
		if minimum_player == null or not _try_sign_minimum_player(team, minimum_player, available_agents, signed_players):
			continue


static func _find_best_at_position(position: String, available_agents: Array) -> Player:
	return _find_best_at_position_excluding(position, available_agents, [])


static func _find_best_at_position_excluding(position: String, available_agents: Array, skipped_players: Array) -> Player:
	var best_player: Player = null
	for player in available_agents:
		if player.position != position or skipped_players.has(player):
			continue
		if best_player == null or player.get_overall() > best_player.get_overall():
			best_player = player
	return best_player


static func _find_best_available(available_agents: Array) -> Player:
	return _find_best_available_excluding(available_agents, [])


static func _find_best_available_excluding(available_agents: Array, skipped_players: Array) -> Player:
	var best_player: Player = null
	for player in available_agents:
		if skipped_players.has(player):
			continue
		if best_player == null or player.get_overall() > best_player.get_overall():
			best_player = player
	return best_player


static func _count_position(team: Team, position: String) -> int:
	var count: int = 0
	for player in team.roster:
		if player.position == position:
			count += 1
	return count


static func _try_sign_player(team: Team, player: Player, available_agents: Array, signed_players: Array) -> bool:
	if not CapEngine.apply_contract(team, player):
		return false

	available_agents.erase(player)
	signed_players.append(player)
	return true


static func _try_sign_minimum_player(team: Team, player: Player, available_agents: Array, signed_players: Array) -> bool:
	if team.roster.size() >= MIN_ROSTER:
		return false

	team.roster.append(player)
	team.cap_space -= player.salary
	available_agents.erase(player)
	signed_players.append(player)
	return true


static func _find_minimum_salary_at_position(position: String, available_agents: Array) -> Player:
	var minimum_player: Player = null
	for player in available_agents:
		if player.position != position:
			continue
		if minimum_player == null or player.salary < minimum_player.salary:
			minimum_player = player
	return minimum_player


static func _find_minimum_salary_available(available_agents: Array) -> Player:
	var minimum_player: Player = null
	for player in available_agents:
		if minimum_player == null or player.salary < minimum_player.salary:
			minimum_player = player
	return minimum_player
