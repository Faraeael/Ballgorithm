extends RefCounted
class_name HistoryManager


static func record_season(year: int, champion_name: String, champion_team_id: String, awards: Dictionary, standings: Array, player_team_record: Dictionary) -> Dictionary:
	return {
		"year": year,
		"champion_name": champion_name,
		"champion_team_id": champion_team_id,
		"awards": awards,
		"standings": _serialize_standings(standings),
		"player_record": player_team_record
	}


static func _serialize_standings(standings: Array) -> Array:
	var serialized: Array = []
	var limit: int = mini(10, standings.size())
	for index in range(limit):
		var team: Team = standings[index]
		serialized.append({
			"team_id": team.team_id,
			"city": team.city,
			"name": team.name,
			"wins": team.wins,
			"losses": team.losses,
			"situation": team.situation
		})
	return serialized


static func get_player_championships(history: Array, player_team_id: String) -> int:
	var count: int = 0
	for season in history:
		if season.get("champion_team_id", "") == player_team_id:
			count += 1
	return count


static func get_player_award_count(history: Array, player_team_id: String, award_name: String) -> int:
	var count: int = 0
	for season in history:
		var awards: Dictionary = season.get("awards", {})
		var award: Dictionary = awards.get(award_name, {})
		if _award_belongs_to_team(award, player_team_id):
			count += 1
	return count


static func get_best_record(history: Array, _player_team_id: String) -> Dictionary:
	var best_record: Dictionary = {}
	for season in history:
		var player_record: Dictionary = season.get("player_record", {})
		if player_record.is_empty():
			continue
		if not best_record.has("wins") or int(player_record.get("wins", 0)) > int(best_record.get("wins", 0)):
			best_record = {
				"year": season.get("year", 0),
				"wins": player_record.get("wins", 0),
				"losses": player_record.get("losses", 0)
			}
	return best_record


static func _award_belongs_to_team(award: Dictionary, player_team_id: String) -> bool:
	if player_team_id == "":
		return false
	var team_name: String = award.get("team_name", "")
	for team in GameState.all_teams:
		if team.team_id == player_team_id and "%s %s" % [team.city, team.name] == team_name:
			return true
	return false
