extends Node

var _players_by_id: Dictionary = {}


# Rebuilds the lookup from every active roster and free agency player.
func build_index() -> void:
	_players_by_id = {}
	for team in GameState.all_teams:
		for player in team.roster:
			if player.id != "":
				_players_by_id[player.id] = player

	for player in GameState.free_agents:
		if player.id != "":
			_players_by_id[player.id] = player


func get_player(id: String) -> Player:
	return _players_by_id.get(id, null)


func get_all_players() -> Array:
	return _players_by_id.values()


# Alias used by callers that are refreshing after roster/free-agent changes.
func rebuild() -> void:
	build_index()
