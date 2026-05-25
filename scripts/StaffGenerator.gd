extends RefCounted
class_name StaffGenerator


class StaffMember:
	var name: String = ""
	var role: String = ""
	var tier: int = 1
	var title: String = ""
	var salary: int = 0
	var effect_description: String = ""

	func to_dict() -> Dictionary:
		return {
			"name": name,
			"role": role,
			"tier": tier,
			"title": title,
			"salary": salary,
			"effect_description": effect_description
		}


	static func from_dict(data: Dictionary) -> StaffMember:
		var member: StaffMember = StaffMember.new()
		member.name = data.get("name", "")
		member.role = data.get("role", "")
		member.tier = data.get("tier", 1)
		member.title = data.get("title", "")
		member.salary = data.get("salary", 0)
		member.effect_description = data.get("effect_description", "")
		return member


const COACH_TITLES: Dictionary = {1: "Rookie Coach", 2: "Assistant Coach", 3: "Head Coach", 4: "Elite Coach", 5: "Legend Coach"}
const SCOUT_TITLES: Dictionary = {1: "Rookie Scout", 2: "Area Scout", 3: "Regional Scout", 4: "Elite Scout", 5: "Legend Scout"}
const DOCTOR_TITLES: Dictionary = {1: "Rookie Doctor", 2: "Team Physician", 3: "Senior Physician", 4: "Elite Doctor", 5: "Legend Doctor"}
const TIER_SALARIES: Dictionary = {1: 500_000, 2: 2_000_000, 3: 5_000_000, 4: 10_000_000, 5: 20_000_000}

const COACH_NAMES: Array[String] = [
	"Miles Corbin", "Dante Voss", "Leon Hale", "Marcus Trent", "Calvin Rook",
	"Nolan Pierce", "Elias Boone", "Tobias Grant", "Reid Coleman", "Jonas Ward",
	"Theo Mercer", "Gavin Cross", "Andre Bell", "Julian Frost", "Malik Price",
	"Simon Drake", "Cyrus Vaughn", "Bennett Shaw", "Isaac Stone", "Roman Ellis",
	"Oscar Finch", "Dorian Hayes"
]
const SCOUT_NAMES: Array[String] = [
	"Quinn Avery", "Silas Reed", "Mason Vale", "Corey Flynn", "Evan North",
	"Jules Mercer", "Rafael Knox", "Adrian Locke", "Micah Wells", "Noah Carr",
	"Luca Hart", "Emmett Rhodes", "Kieran Fox", "Damon West", "Felix Rowe",
	"Arlo Chase", "Soren Blake", "Theo Lane", "Miles Archer", "Nico Stone",
	"Rory Fields", "Jasper Cole"
]
const DOCTOR_NAMES: Array[String] = [
	"Dr. Alma Vance", "Dr. Lena Cross", "Dr. Iris Bell", "Dr. Mara Quinn", "Dr. Selene Park",
	"Dr. Cora Hayes", "Dr. Tessa Vale", "Dr. Mira Stone", "Dr. Naomi Reed", "Dr. Eliza Grant",
	"Dr. Vera Finch", "Dr. Nora Shaw", "Dr. Imani Price", "Dr. Clara Wells", "Dr. Priya Locke",
	"Dr. Sienna Hart", "Dr. June Mercer", "Dr. Ada West", "Dr. Leona Fields", "Dr. Celia Fox",
	"Dr. Amara Lane", "Dr. Reina Cole"
]


static func generate_staff(role: String, tier: int) -> StaffMember:
	var normalized_tier: int = clampi(tier, 1, 5)
	var member: StaffMember = StaffMember.new()
	member.role = role
	member.tier = normalized_tier
	member.name = _pick_name(role)
	member.title = _get_title(role, normalized_tier)
	member.salary = get_tier_salary(normalized_tier)
	member.effect_description = _get_effect_description(role, normalized_tier)
	return member


static func get_upgrade_cost(current_tier: int) -> int:
	if current_tier >= 5:
		return 0
	return TIER_SALARIES.get(current_tier + 1, 0)


static func get_tier_salary(tier: int) -> int:
	return TIER_SALARIES.get(clampi(tier, 1, 5), 0)


static func _pick_name(role: String) -> String:
	match role:
		"Coach":
			return COACH_NAMES.pick_random()
		"Scout":
			return SCOUT_NAMES.pick_random()
		"Doctor":
			return DOCTOR_NAMES.pick_random()
		_:
			return COACH_NAMES.pick_random()


static func _get_title(role: String, tier: int) -> String:
	match role:
		"Coach":
			return COACH_TITLES.get(tier, "Rookie Coach")
		"Scout":
			return SCOUT_TITLES.get(tier, "Rookie Scout")
		"Doctor":
			return DOCTOR_TITLES.get(tier, "Rookie Doctor")
		_:
			return "Staff"


static func _get_effect_description(role: String, tier: int) -> String:
	match role:
		"Coach":
			return "Team OVR +%d in simulations" % (tier * 2)
		"Scout":
			return "Reveals tier %d player info" % tier
		"Doctor":
			return "Reduces injury duration by %d%%" % (tier * 5)
		_:
			return "No effect"
