extends RefCounted
class_name DraftSystem

const DRAFT_ROUNDS: int = 2


# Builds a 60-player class with fixed positional distribution for draft balance.
static func build_draft_pool(all_teams: Array) -> Array:
	var draft_pool: Array = []
	var positions: Array = []
	positions.append_array(_repeat_position("PG", 10))
	positions.append_array(_repeat_position("SG", 10))
	positions.append_array(_repeat_position("SF", 10))
	positions.append_array(_repeat_position("PF", 15))
	positions.append_array(_repeat_position("C", 15))

	for position in positions:
		# Draft prospects use Tanking weighting because that path skews younger/high-upside.
		draft_pool.append(PlayerGenerator.generate_player(position, "Tanking"))

	draft_pool.shuffle()
	return draft_pool


# Round 1 order is determined by each team's assigned draft pick.
static func get_draft_order(all_teams: Array) -> Array:
	var draft_order: Array = all_teams.duplicate()
	draft_order.sort_custom(_sort_by_draft_pick)
	return draft_order


# AI prioritizes roster holes first, then falls back to best player available.
static func ai_pick(team: Team, draft_pool: Array) -> Player:
	if draft_pool.is_empty():
		return null

	var needed_positions: Array = _get_needed_positions(team)
	var selected_player: Player = null
	var selected_index: int = -1

	for index in draft_pool.size():
		var player: Player = draft_pool[index]
		if not needed_positions.is_empty() and not needed_positions.has(player.position):
			continue

		if selected_player == null or player.get_overall() > selected_player.get_overall():
			selected_player = player
			selected_index = index

	if selected_player == null:
		for index in draft_pool.size():
			var player: Player = draft_pool[index]
			if selected_player == null or player.get_overall() > selected_player.get_overall():
				selected_player = player
				selected_index = index

	if selected_index != -1:
		draft_pool.remove_at(selected_index)
	return selected_player


# Draft picks bypass cap checks in v1; rookie contracts are free placeholders.
static func apply_pick(team: Team, player: Player) -> void:
	team.roster.append(player)


static func _repeat_position(position: String, count: int) -> Array:
	var positions: Array = []
	for index in count:
		positions.append(position)
	return positions


static func _sort_by_draft_pick(team_a: Team, team_b: Team) -> bool:
	return team_a.draft_pick < team_b.draft_pick


static func _get_needed_positions(team: Team) -> Array:
	var position_counts: Dictionary = {
		"PG": 0,
		"SG": 0,
		"SF": 0,
		"PF": 0,
		"C": 0
	}

	for player in team.roster:
		if position_counts.has(player.position):
			position_counts[player.position] += 1

	var needed_positions: Array = []
	for position in position_counts.keys():
		if position_counts[position] < 2:
			needed_positions.append(position)
	return needed_positions
