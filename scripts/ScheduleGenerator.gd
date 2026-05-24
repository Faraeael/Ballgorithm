extends RefCounted
class_name ScheduleGenerator


# Kept as a separate script for architectural separation; LeagueManager owns the actual schedule rules.
static func build_schedule() -> Array:
	return LeagueManager.generate_schedule()
