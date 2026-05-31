extends RefCounted
class_name TradeEngine

const MAX_PLAYERS_PER_SIDE: int = 3
const AI_ACCEPT_THRESHOLD: float = 0.85
const ROSTER_MIN: int = 10
const ROSTER_MAX: int = 15


static func evaluate_trade(offering_players: Array, requesting_players: Array) -> float:
	if offering_players.is_empty() or requesting_players.is_empty():
		return 0.0

	var offering_total: int = _sum_overall(offering_players)
	var requesting_total: int = _sum_overall(requesting_players)
	if requesting_total <= 0:
		return 0.0

	return float(offering_total) / float(requesting_total)


static func is_trade_valid(player_team: Team, ai_team: Team, offering_players: Array, requesting_players: Array) -> Dictionary:
	if player_team == null:
		return {"valid": false, "reason": "Player team not found."}
	if ai_team == null:
		return {"valid": false, "reason": "Select an AI team."}
	if offering_players.is_empty():
		return {"valid": false, "reason": "Offer at least one player."}
	if requesting_players.is_empty():
		return {"valid": false, "reason": "Request at least one player."}
	if offering_players.size() > MAX_PLAYERS_PER_SIDE:
		return {"valid": false, "reason": "You can offer at most 3 players."}
	if requesting_players.size() > MAX_PLAYERS_PER_SIDE:
		return {"valid": false, "reason": "You can request at most 3 players."}

	for player in offering_players:
		if player_team.roster.find(player) == -1:
			return {"valid": false, "reason": "Offered player is no longer on your roster."}

	for player in requesting_players:
		if ai_team.roster.find(player) == -1:
			return {"valid": false, "reason": "Requested player is no longer on their roster."}

	var player_roster_after: int = player_team.roster.size() - offering_players.size() + requesting_players.size()
	var ai_roster_after: int = ai_team.roster.size() - requesting_players.size() + offering_players.size()
	if player_roster_after < ROSTER_MIN or player_roster_after > ROSTER_MAX:
		return {"valid": false, "reason": "Your roster must stay between 10 and 15 players."}
	if ai_roster_after < ROSTER_MIN or ai_roster_after > ROSTER_MAX:
		return {"valid": false, "reason": "AI roster must stay between 10 and 15 players."}

	return {"valid": true, "reason": ""}


static func execute_trade(player_team: Team, ai_team: Team, offering_players: Array, requesting_players: Array) -> bool:
	var validation: Dictionary = is_trade_valid(player_team, ai_team, offering_players, requesting_players)
	if not validation["valid"]:
		return false
	if evaluate_trade(offering_players, requesting_players) < AI_ACCEPT_THRESHOLD:
		return false

	for player in offering_players:
		player_team.roster.erase(player)
		ai_team.roster.append(player)

	for player in requesting_players:
		ai_team.roster.erase(player)
		player_team.roster.append(player)

	# Keep stored cap_space aligned with CapEngine's live payroll calculation after both rosters mutate.
	player_team.cap_space = CapEngine.get_cap_space(player_team)
	ai_team.cap_space = CapEngine.get_cap_space(ai_team)
	return true


static func get_ai_counter_value(ai_team: Team, target_overall: int) -> Player:
	if ai_team == null:
		return null

	var closest_player: Player = null
	var closest_gap: int = 999
	for player in ai_team.roster:
		var overall: int = player.get_overall()
		if overall >= 80:
			continue
		var gap: int = absi(overall - target_overall)
		if closest_player == null or gap < closest_gap:
			closest_player = player
			closest_gap = gap
	return closest_player


static func _sum_overall(players: Array) -> int:
	var total: int = 0
	for player in players:
		total += player.get_overall()
	return total
