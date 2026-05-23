extends RefCounted
class_name PlayerGenerator

const FIRST_NAMES = [
	"Andre", "Malik", "Jalen", "Darius", "Marcus", "Terrence", "Isaiah", "Jordan",
	"Cameron", "Devin", "Miles", "Tyrese", "Nolan", "Kendrick", "Xavier", "Elijah",
	"Caleb", "Damian", "Quentin", "Wesley", "Bryce", "Julian", "Corey", "Rashad"
]

const LAST_NAMES = [
	"Bennett", "Carter", "Dawson", "Ellis", "Foster", "Griffin", "Hayes", "Irving",
	"Jefferson", "Knight", "Lawson", "Mitchell", "Nelson", "Owens", "Porter", "Reed",
	"Sullivan", "Turner", "Vaughn", "Walker", "Young", "Brooks", "Coleman", "Harris"
]

const ARCHETYPES_BY_POSITION = {
	"PG": [
		"Floor General", "Shot Creator", "Sharpshooter", "Slasher", "Pick-and-Roll Maestro",
		"Microwave Scorer", "Transition Finisher", "Pickpocket", "Combo Guard", "Clutch Performer", "Iso God"
	],
	"SG": [
		"Shot Creator", "Sharpshooter", "Slasher", "Microwave Scorer", "Transition Finisher",
		"Perimeter Stopper", "Pickpocket", "3-and-D Wing", "Combo Guard", "Clutch Performer", "Iso God"
	],
	"SF": [
		"Shot Creator", "Sharpshooter", "Slasher", "Point Forward", "Transition Finisher",
		"Perimeter Stopper", "Switch Defender", "Hustler", "3-and-D Wing", "Glue Guy", "Clutch Performer", "Iso God"
	],
	"PF": [
		"Post Scorer", "Stretch Big", "Transition Finisher", "Paint Protector", "Switch Defender",
		"Glass Cleaner", "Hustler", "Stretch Lock", "Energy Big", "Glue Guy", "Clutch Performer"
	],
	"C": [
		"Post Scorer", "Stretch Big", "Paint Protector", "Defensive Anchor", "Glass Cleaner",
		"Hustler", "Point Center", "Energy Big", "Glue Guy", "Clutch Performer"
	]
}

const SITUATION_OVERALL_RANGES = {
	"Tanking": [42, 60],
	"Rebuilding": [52, 68],
	"Play-In": [60, 74],
	"Playoff": [68, 80],
	"Contender": [73, 86]
}

const SITUATION_POTENTIAL_RANGES = {
	"Tanking": [68, 99],
	"Rebuilding": [62, 94],
	"Play-In": [54, 88],
	"Playoff": [46, 82],
	"Contender": [40, 76]
}

const ARCHETYPE_BIASES = {
	"Floor General": {"BallHandling": 14, "Passing": 18, "OffIQ": 14, "Leadership": 10},
	"Shot Creator": {"ShootingMid": 16, "BallHandling": 14, "Finishing": 8, "Composure": 8},
	"Sharpshooter": {"Shooting3": 22, "ShootingMid": 12, "FreeThrow": 10, "OffIQ": 6},
	"Slasher": {"Speed": 14, "Vertical": 14, "Finishing": 18, "BallHandling": 6},
	"Post Scorer": {"Strength": 12, "PostPlay": 22, "ShootingMid": 8, "Composure": 6},
	"Point Forward": {"BallHandling": 12, "Passing": 16, "OffIQ": 12, "Strength": 6},
	"Stretch Big": {"Shooting3": 16, "ShootingMid": 12, "PostPlay": 8, "DefIQ": 4},
	"Pick-and-Roll Maestro": {"BallHandling": 12, "Passing": 18, "OffIQ": 12, "ShootingMid": 6},
	"Microwave Scorer": {"Shooting3": 12, "ShootingMid": 12, "Finishing": 10, "Clutch": 12},
	"Transition Finisher": {"Speed": 16, "Vertical": 12, "Stamina": 8, "Finishing": 16},
	"Perimeter Stopper": {"PerimeterD": 22, "Steal": 10, "Speed": 8, "DefIQ": 10},
	"Paint Protector": {"Strength": 12, "PostD": 16, "Block": 22, "DefIQ": 10},
	"Defensive Anchor": {"Strength": 10, "PostD": 18, "Block": 18, "DefIQ": 16, "Leadership": 6},
	"Pickpocket": {"Speed": 10, "PerimeterD": 12, "Steal": 22, "DefIQ": 8},
	"Switch Defender": {"Speed": 8, "Strength": 8, "PerimeterD": 14, "PostD": 12, "DefIQ": 10},
	"Glass Cleaner": {"Strength": 18, "Vertical": 10, "PostD": 10, "Block": 14, "WorkEthic": 10},
	"Hustler": {"Stamina": 18, "Durability": 12, "DefIQ": 8, "WorkEthic": 18},
	"3-and-D Wing": {"Shooting3": 16, "PerimeterD": 18, "Steal": 8, "DefIQ": 8},
	"Combo Guard": {"Shooting3": 10, "BallHandling": 14, "Passing": 8, "Finishing": 8},
	"Point Center": {"Strength": 10, "PostPlay": 10, "Passing": 18, "OffIQ": 12},
	"Stretch Lock": {"Shooting3": 14, "PerimeterD": 12, "PostD": 12, "Block": 10},
	"Energy Big": {"Strength": 12, "Stamina": 14, "Block": 10, "Finishing": 10, "WorkEthic": 14},
	"Glue Guy": {"Passing": 8, "DefIQ": 12, "Leadership": 12, "WorkEthic": 12, "Composure": 8},
	"Clutch Performer": {"ShootingMid": 8, "Finishing": 8, "Clutch": 22, "Composure": 14},
	"Iso God": {"ShootingMid": 14, "Finishing": 14, "BallHandling": 18, "Clutch": 10}
}

const POSITION_BIASES = {
	"PG": {"Speed": 8, "BallHandling": 12, "Passing": 10, "PerimeterD": 4, "PostD": -12, "Block": -10, "PostPlay": -10},
	"SG": {"Speed": 6, "Shooting3": 8, "ShootingMid": 6, "BallHandling": 6, "PostD": -10, "Block": -8, "PostPlay": -8},
	"SF": {"Strength": 4, "Shooting3": 4, "Finishing": 6, "PerimeterD": 6, "PostD": -4},
	"PF": {"Strength": 8, "PostPlay": 8, "PostD": 8, "Block": 6, "BallHandling": -8, "Passing": -4},
	"C": {"Strength": 12, "PostPlay": 10, "PostD": 12, "Block": 12, "Speed": -8, "BallHandling": -12, "Shooting3": -8}
}


static func generate_player(position: String, situation: String) -> Player:
	var player: Player = Player.new()
	player.id = "player_%d_%06d" % [Time.get_ticks_usec(), randi_range(0, 999999)]
	player.full_name = "%s %s" % [FIRST_NAMES.pick_random(), LAST_NAMES.pick_random()]
	player.age = _generate_age(situation)
	player.position = position
	player.archetype = _pick_archetype(position)
	player.potential = _generate_potential(situation, player.age)
	player.is_potential_revealed = false

	# Situation sets the broad talent band, while position and archetype nudge specific ratings.
	# Archetype bonuses are intentionally strong enough to create specialists without hard-locking stats.
	var base_overall: int = _generate_base_overall(situation)
	var attributes: Dictionary = _generate_attributes(base_overall, position, player.archetype)
	player.physicals = attributes["physicals"]
	player.skills = attributes["skills"]
	player.defense = attributes["defense"]
	player.mental = attributes["mental"]

	var overall: int = player.get_overall()
	player.salary = _generate_salary(overall, player.age)
	player.contract_years = _generate_contract_years(overall, player.age)
	return player


static func _generate_age(situation: String) -> int:
	match situation:
		"Tanking":
			return randi_range(19, 26)
		"Rebuilding":
			return randi_range(19, 29)
		"Play-In":
			return randi_range(22, 32)
		"Playoff":
			return randi_range(24, 34)
		"Contender":
			return randi_range(26, 35)
		_:
			return randi_range(19, 35)


static func _pick_archetype(position: String) -> String:
	var archetypes: Array = ARCHETYPES_BY_POSITION.get(position, ARCHETYPES_BY_POSITION["SF"])
	return archetypes.pick_random()


static func _generate_base_overall(situation: String) -> int:
	var overall_range: Array = SITUATION_OVERALL_RANGES.get(situation, [55, 72])
	return randi_range(overall_range[0], overall_range[1])


static func _generate_potential(situation: String, age: int) -> int:
	var potential_range: Array = SITUATION_POTENTIAL_RANGES.get(situation, [45, 90])
	var potential: int = randi_range(potential_range[0], potential_range[1])

	# Younger players keep more upside; veterans lose ceiling even if they are current-impact players.
	if age <= 22:
		potential += randi_range(4, 10)
	elif age >= 30:
		potential -= randi_range(6, 14)

	return clampi(potential, 40, 99)


static func _generate_attributes(base_overall: int, position: String, archetype: String) -> Dictionary:
	return {
		"physicals": {
			"Speed": _weighted_attribute("Speed", base_overall, position, archetype),
			"Vertical": _weighted_attribute("Vertical", base_overall, position, archetype),
			"Strength": _weighted_attribute("Strength", base_overall, position, archetype),
			"Stamina": _weighted_attribute("Stamina", base_overall, position, archetype),
			"Durability": _weighted_attribute("Durability", base_overall, position, archetype)
		},
		"skills": {
			"Shooting3": _weighted_attribute("Shooting3", base_overall, position, archetype),
			"ShootingMid": _weighted_attribute("ShootingMid", base_overall, position, archetype),
			"FreeThrow": _weighted_attribute("FreeThrow", base_overall, position, archetype),
			"Finishing": _weighted_attribute("Finishing", base_overall, position, archetype),
			"BallHandling": _weighted_attribute("BallHandling", base_overall, position, archetype),
			"Passing": _weighted_attribute("Passing", base_overall, position, archetype),
			"PostPlay": _weighted_attribute("PostPlay", base_overall, position, archetype)
		},
		"defense": {
			"PerimeterD": _weighted_attribute("PerimeterD", base_overall, position, archetype),
			"PostD": _weighted_attribute("PostD", base_overall, position, archetype),
			"Steal": _weighted_attribute("Steal", base_overall, position, archetype),
			"Block": _weighted_attribute("Block", base_overall, position, archetype),
			"DefIQ": _weighted_attribute("DefIQ", base_overall, position, archetype)
		},
		"mental": {
			"OffIQ": _weighted_attribute("OffIQ", base_overall, position, archetype),
			"Clutch": _weighted_attribute("Clutch", base_overall, position, archetype),
			"Composure": _weighted_attribute("Composure", base_overall, position, archetype),
			"Leadership": _weighted_attribute("Leadership", base_overall, position, archetype),
			"WorkEthic": _weighted_attribute("WorkEthic", base_overall, position, archetype)
		}
	}


static func _weighted_attribute(attribute: String, base_overall: int, position: String, archetype: String) -> int:
	var position_biases: Dictionary = POSITION_BIASES.get(position, {})
	var archetype_biases: Dictionary = ARCHETYPE_BIASES.get(archetype, {})

	# Base overall supplies the player's general quality, random noise keeps players varied,
	# position bias shapes role expectations, and archetype bias creates the signature skill spike.
	var value: int = base_overall + randi_range(-10, 10)
	value += position_biases.get(attribute, 0)
	value += archetype_biases.get(attribute, 0)
	return clampi(value, 0, 99)


static func _generate_salary(overall: int, age: int) -> int:
	var salary: int = 1_000_000
	if overall >= 85:
		salary = randi_range(32_000_000, 48_000_000)
	elif overall >= 78:
		salary = randi_range(20_000_000, 34_000_000)
	elif overall >= 70:
		salary = randi_range(10_000_000, 22_000_000)
	elif overall >= 62:
		salary = randi_range(4_000_000, 11_000_000)
	elif overall >= 55:
		salary = randi_range(1_800_000, 5_000_000)
	else:
		salary = randi_range(900_000, 2_500_000)

	if age >= 33:
		salary = int(salary * 0.75)
	elif age <= 22 and overall < 75:
		salary = int(salary * 0.85)

	return salary


static func _generate_contract_years(overall: int, age: int) -> int:
	if age >= 33:
		return randi_range(1, 2)
	if overall >= 78:
		return randi_range(3, 5)
	if overall >= 65:
		return randi_range(2, 4)
	return randi_range(1, 3)
