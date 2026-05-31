extends RefCounted
class_name ContractExtension

const MAX_EXTENSION_YEARS: int = 5
const MIN_EXTENSION_YEARS: int = 1
const EXTENSION_SALARY_MULTIPLIER: Dictionary = {
	1: 1.05, 2: 1.10, 3: 1.15, 4: 1.20, 5: 1.25
}


static func can_extend(player: Player) -> bool:
	return player.contract_years <= 2


static func calculate_extension_salary(player: Player, years: int) -> int:
	if not EXTENSION_SALARY_MULTIPLIER.has(years):
		return 0

	var base_salary: int = _get_market_salary(player.get_overall(), player.age)
	return int(round(float(base_salary) * EXTENSION_SALARY_MULTIPLIER[years]))


static func calculate_extension_cost(player: Player, years: int) -> int:
	return calculate_extension_salary(player, years) * years


static func apply_extension(team: Team, player: Player, years: int) -> bool:
	if team.roster.find(player) == -1 or not can_extend(player):
		return false
	if years < MIN_EXTENSION_YEARS or years > MAX_EXTENSION_YEARS:
		return false

	var extension_salary: int = calculate_extension_salary(player, years)
	var salary_delta: int = extension_salary - player.salary
	if salary_delta > 0 and CapEngine.get_cap_space(team) < salary_delta:
		return false

	player.contract_years = years
	player.salary = extension_salary
	team.cap_space -= salary_delta
	return true


static func get_extension_options(player: Player) -> Array:
	var options: Array = []
	for years in range(MIN_EXTENSION_YEARS, MAX_EXTENSION_YEARS + 1):
		var annual_salary: int = calculate_extension_salary(player, years)
		options.append({
			"years": years,
			"annual_salary": annual_salary,
			"total_cost": annual_salary * years,
			"salary_increase": annual_salary - player.salary
		})
	return options


static func _get_market_salary(overall: int, age: int) -> int:
	var salary: int = 1_000_000
	if overall >= 85:
		salary = 40_000_000
	elif overall >= 78:
		salary = 27_000_000
	elif overall >= 70:
		salary = 16_000_000
	elif overall >= 62:
		salary = 7_500_000
	elif overall >= 55:
		salary = 3_400_000
	else:
		salary = 1_700_000

	# Match PlayerGenerator's age-based salary adjustments while using deterministic band midpoints.
	if age >= 33:
		salary = int(salary * 0.75)
	elif age <= 22 and overall < 75:
		salary = int(salary * 0.85)

	return salary
