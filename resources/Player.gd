extends Resource
class_name Player

@export var id: String = ""
@export var full_name: String = ""
@export var age: int = 0
@export var position: String = ""        # PG | SG | SF | PF | C
@export var archetype: String = ""       # see Archetypes section
@export var salary: int = 0             # in dollars (e.g. 5000000)
@export var contract_years: int = 0
@export var potential: int = 0          # 40–99, hidden until scouted
@export var is_potential_revealed: bool = false

# Attribute groups — all values 0–99
@export var physicals: Dictionary = {
	"Speed": 0, "Vertical": 0, "Strength": 0, "Stamina": 0, "Durability": 0
}
@export var skills: Dictionary = {
	"Shooting3": 0, "ShootingMid": 0, "FreeThrow": 0,
	"Finishing": 0, "BallHandling": 0, "Passing": 0, "PostPlay": 0
}
@export var defense: Dictionary = {
	"PerimeterD": 0, "PostD": 0, "Steal": 0, "Block": 0, "DefIQ": 0
}
@export var mental: Dictionary = {
	"OffIQ": 0, "Clutch": 0, "Composure": 0, "Leadership": 0, "WorkEthic": 0
}

# Computed overall — call this, don't store it
func get_overall() -> int:
	var total = 0
	var count = 0
	for group in [physicals, skills, defense, mental]:
		for val in group.values():
			total += val
			count += 1
	return int(total / count) if count > 0 else 0


func to_dict() -> Dictionary:
	return {
		"id": id,
		"full_name": full_name,
		"age": age,
		"position": position,
		"archetype": archetype,
		"salary": salary,
		"contract_years": contract_years,
		"potential": potential,
		"is_potential_revealed": is_potential_revealed,
		"physicals": physicals,
		"skills": skills,
		"defense": defense,
		"mental": mental
	}


func from_dict(data: Dictionary) -> void:
	id = data.get("id", "")
	full_name = data.get("full_name", "")
	age = data.get("age", 0)
	position = data.get("position", "")
	archetype = data.get("archetype", "")
	salary = data.get("salary", 0)
	contract_years = data.get("contract_years", 0)
	potential = data.get("potential", 0)
	is_potential_revealed = data.get("is_potential_revealed", false)
	physicals = data.get("physicals", {
		"Speed": 0, "Vertical": 0, "Strength": 0, "Stamina": 0, "Durability": 0
	})
	skills = data.get("skills", {
		"Shooting3": 0, "ShootingMid": 0, "FreeThrow": 0,
		"Finishing": 0, "BallHandling": 0, "Passing": 0, "PostPlay": 0
	})
	defense = data.get("defense", {
		"PerimeterD": 0, "PostD": 0, "Steal": 0, "Block": 0, "DefIQ": 0
	})
	mental = data.get("mental", {
		"OffIQ": 0, "Clutch": 0, "Composure": 0, "Leadership": 0, "WorkEthic": 0
	})
