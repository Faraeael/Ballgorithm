extends Resource
class_name Team

@export var team_id: String = ""
@export var city: String = ""
@export var name: String = ""
@export var situation: String = ""      # Tanking | Rebuilding | Play-In | Playoff | Contender
@export var is_player_team: bool = false

@export var roster: Array = []          # Array of Player resources
@export var cap_space: int = 0         # remaining cap (starts at salary cap minus contracts)
@export var draft_pick: int = 0        # 1–30, position in draft

@export var wins: int = 0
@export var losses: int = 0

# Staff levels 1–5
@export var staff_coach: int = 1
@export var staff_scout: int = 1
@export var staff_medical: int = 1

# Facility level 1–5
@export var facilities: int = 1

# Budget for pre-season spending
@export var budget: int = 0


func to_dict() -> Dictionary:
	var roster_data: Array = []
	for player in roster:
		roster_data.append(player.to_dict())

	return {
		"team_id": team_id,
		"city": city,
		"name": name,
		"situation": situation,
		"is_player_team": is_player_team,
		"roster": roster_data,
		"cap_space": cap_space,
		"draft_pick": draft_pick,
		"wins": wins,
		"losses": losses,
		"staff_coach": staff_coach,
		"staff_scout": staff_scout,
		"staff_medical": staff_medical,
		"facilities": facilities,
		"budget": budget
	}


func from_dict(data: Dictionary) -> void:
	team_id = data.get("team_id", "")
	city = data.get("city", "")
	name = data.get("name", "")
	situation = data.get("situation", "")
	is_player_team = data.get("is_player_team", false)
	roster = []
	for player_data in data.get("roster", []):
		var player: Player = Player.new()
		player.from_dict(player_data)
		roster.append(player)
	cap_space = data.get("cap_space", 0)
	draft_pick = data.get("draft_pick", 0)
	wins = data.get("wins", 0)
	losses = data.get("losses", 0)
	staff_coach = data.get("staff_coach", 1)
	staff_scout = data.get("staff_scout", 1)
	staff_medical = data.get("staff_medical", 1)
	facilities = data.get("facilities", 1)
	budget = data.get("budget", 0)
