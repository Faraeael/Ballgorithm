extends RefCounted
class_name ScoutingSystem


# Opposing players are progressively revealed by scout level; owned players are always fully known.
static func get_player_info(player: Player, scout_level: int, is_player_team_viewing: bool) -> Dictionary:
	var full_visibility: bool = not is_player_team_viewing
	var show_overall_range: bool = full_visibility or scout_level >= 2
	var show_exact_overall: bool = full_visibility or scout_level >= 3
	var show_archetype: bool = full_visibility or scout_level >= 3
	var show_attributes: bool = full_visibility or scout_level >= 4
	var show_potential: bool = full_visibility or scout_level >= 5 or player.is_potential_revealed

	return {
		"show_name": true,
		"show_position": true,
		"show_age": true,
		"show_salary": true,
		"show_overall_range": show_overall_range,
		"show_exact_overall": show_exact_overall,
		"show_archetype": show_archetype,
		"show_attributes": show_attributes,
		"show_potential": show_potential,
		"overall_range": _get_overall_range(player, scout_level) if not full_visibility and scout_level == 2 else ""
	}


static func _get_overall_range(player: Player, scout_level: int) -> String:
	var noisy_overall: int = player.get_overall() + randi_range(-3, 3)
	var low: int = clampi(noisy_overall - 5, 0, 99)
	var high: int = clampi(noisy_overall + 5, 0, 99)
	return "%d-%d" % [low, high]
