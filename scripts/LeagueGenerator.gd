extends RefCounted
class_name LeagueGenerator

const TEAM_COUNT: int = 30
const ROSTER_SIZE: int = 13

const SITUATIONS: Array = [
	"Tanking", "Rebuilding", "Play-In", "Playoff", "Contender"
]

const SITUATION_DRAFT_ORDER: Dictionary = {
	"Tanking": 1, "Rebuilding": 6, "Play-In": 11, "Playoff": 16, "Contender": 21
}

const SITUATION_CAP_SPACE: Dictionary = {
	"Tanking": 100_000_000,
	"Rebuilding": 70_000_000,
	"Play-In": 40_000_000,
	"Playoff": 20_000_000,
	"Contender": 5_000_000
}

const SITUATION_BUDGET: Dictionary = {
	"Tanking": 15_000_000,
	"Rebuilding": 10_000_000,
	"Play-In": 7_000_000,
	"Playoff": 5_000_000,
	"Contender": 3_000_000
}

const AI_SITUATION_COUNTS: Dictionary = {
	"Tanking": 4,
	"Rebuilding": 6,
	"Play-In": 7,
	"Playoff": 7,
	"Contender": 5
}

const TEAM_COMBOS: Array = [
	{"city": "Atlanta", "name": "Firebirds"},
	{"city": "Baltimore", "name": "Barons"},
	{"city": "Boston", "name": "Harbors"},
	{"city": "Brooklyn", "name": "Kings"},
	{"city": "Charlotte", "name": "Flight"},
	{"city": "Chicago", "name": "Foundry"},
	{"city": "Cincinnati", "name": "Royals"},
	{"city": "Cleveland", "name": "Guard"},
	{"city": "Dallas", "name": "Outlaws"},
	{"city": "Denver", "name": "Peaks"},
	{"city": "Detroit", "name": "Motors"},
	{"city": "Houston", "name": "Comets"},
	{"city": "Indianapolis", "name": "Racers"},
	{"city": "Kansas City", "name": "Monarchs"},
	{"city": "Las Vegas", "name": "Aces"},
	{"city": "Los Angeles", "name": "Stars"},
	{"city": "Memphis", "name": "Blues"},
	{"city": "Miami", "name": "Tides"},
	{"city": "Milwaukee", "name": "Stags"},
	{"city": "Minneapolis", "name": "North"},
	{"city": "Nashville", "name": "Strings"},
	{"city": "New Orleans", "name": "Crescents"},
	{"city": "New York", "name": "Empire"},
	{"city": "Orlando", "name": "Orbit"},
	{"city": "Philadelphia", "name": "Liberty"},
	{"city": "Phoenix", "name": "Solar"},
	{"city": "Portland", "name": "Pines"},
	{"city": "San Diego", "name": "Surf"},
	{"city": "Seattle", "name": "Rain"},
	{"city": "St. Louis", "name": "Archers"}
]


static func generate_league(player_situation: String, player_city: String, player_name: String) -> Array:
	var teams: Array = []
	var team_combos: Array = TEAM_COMBOS.duplicate()
	team_combos.shuffle()

	var player_combo: Dictionary = {"city": player_city, "name": player_name}
	teams.append(_create_team(player_combo, player_situation, true))

	# AI teams use the requested league shape: weak teams are scarce, the middle is crowded,
	# and contender slots are limited so the league has a believable competitive spread.
	var ai_situations: Array = _build_ai_situations()
	ai_situations.shuffle()
	for situation in ai_situations:
		var combo: Dictionary = team_combos.pop_back()
		teams.append(_create_team(combo, situation, false))

	_assign_draft_picks(teams)
	return teams


static func _build_ai_situations() -> Array:
	var ai_situations: Array = []
	for situation in AI_SITUATION_COUNTS.keys():
		var count: int = AI_SITUATION_COUNTS[situation]
		for index in count:
			ai_situations.append(situation)
	return ai_situations


static func _create_team(combo: Dictionary, situation: String, is_player_team: bool) -> Team:
	var team: Team = Team.new()
	team.city = combo["city"]
	team.name = combo["name"]
	team.team_id = _create_team_id(team.city, team.name)
	team.situation = situation
	team.is_player_team = is_player_team
	team.roster = _generate_roster(situation)
	team.cap_space = SITUATION_CAP_SPACE.get(situation, 40_000_000)
	team.draft_pick = SITUATION_DRAFT_ORDER.get(situation, 16)
	team.wins = 0
	team.losses = 0
	team.staff_coach = 1
	team.staff_scout = 1
	team.staff_medical = 1
	team.facilities = 1
	team.budget = SITUATION_BUDGET.get(situation, 7_000_000)
	return team


static func _create_team_id(city: String, team_name: String) -> String:
	return "%s_%s" % [_sanitize_id_part(city), _sanitize_id_part(team_name)]


static func _sanitize_id_part(value: String) -> String:
	return value.to_lower().replace(".", "").replace(" ", "_")


static func _generate_roster(situation: String) -> Array:
	var roster: Array = []
	var positions: Array = [
		"PG", "PG", "SG", "SG", "SF", "SF", "PF", "PF", "C", "C"
	]
	var random_positions: Array = ["PG", "SG", "SF", "PF", "C"]

	# The first ten slots guarantee every team has a playable depth chart at all five positions.
	# The remaining three slots are random bench depth to create roster variety.
	for index in 3:
		positions.append(random_positions.pick_random())
	positions.shuffle()

	for position in positions:
		roster.append(PlayerGenerator.generate_player(position, situation))
	return roster


static func _assign_draft_picks(teams: Array) -> void:
	# TODO: pick gaps exist between tiers — refactor to sequential 1-30 assignment before Draft scene is built.
	var next_pick: int = 1
	for situation in SITUATIONS:
		var situation_teams: Array = []
		for team in teams:
			if team.situation == situation:
				situation_teams.append(team)

		# Within each tier, order is random. Across tiers, SITUATION_DRAFT_ORDER keeps weaker
		# situations ahead of stronger ones for draft purposes.
		situation_teams.shuffle()
		for team in situation_teams:
			team.draft_pick = max(next_pick, SITUATION_DRAFT_ORDER.get(situation, next_pick))
			next_pick = team.draft_pick + 1
