extends Control

@onready var new_game_button: Button = $CenterContainer/VBoxContainer/NewGameButton
@onready var load_game_button: Button = $CenterContainer/VBoxContainer/LoadGameButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton


func _ready() -> void:
	new_game_button.pressed.connect(_on_new_game)
	load_game_button.pressed.connect(_on_load_game)
	quit_button.pressed.connect(_on_quit)
	load_game_button.disabled = not FileAccess.file_exists("user://save.json")


# Starts the new-game flow and moves to team creation.
func _on_new_game() -> void:
	GameState.set_phase(GameState.Phase.NEW_GAME)
	get_tree().change_scene_to_file("res://scenes/NewGame.tscn")


# Loads saved state, then routes to the scene that owns the restored phase.
func _on_load_game() -> void:
	GameState.load_game()
	match GameState.current_phase:
		GameState.Phase.MAIN_MENU:
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		GameState.Phase.NEW_GAME:
			get_tree().change_scene_to_file("res://scenes/NewGame.tscn")
		GameState.Phase.LEAGUE_GENERATING:
			get_tree().change_scene_to_file("res://scenes/NewGame.tscn")
		GameState.Phase.PRE_SEASON_HUB:
			get_tree().change_scene_to_file("res://scenes/PreSeasonHub.tscn")
		GameState.Phase.DRAFT:
			get_tree().change_scene_to_file("res://scenes/Draft.tscn")
		GameState.Phase.FREE_AGENCY:
			get_tree().change_scene_to_file("res://scenes/FreeAgency.tscn")
		GameState.Phase.SEASON_SIM:
			get_tree().change_scene_to_file("res://scenes/SeasonSim.tscn")
		GameState.Phase.PLAY_IN:
			get_tree().change_scene_to_file("res://scenes/PlayIn.tscn")
		GameState.Phase.PLAYOFFS:
			get_tree().change_scene_to_file("res://scenes/Playoffs.tscn")
		GameState.Phase.FINALS:
			get_tree().change_scene_to_file("res://scenes/Playoffs.tscn")
		GameState.Phase.END_OF_SEASON:
			get_tree().change_scene_to_file("res://scenes/EndOfSeason.tscn")
		_:
			get_tree().change_scene_to_file("res://scenes/NewGame.tscn")


# Exits the application from the main menu.
func _on_quit() -> void:
	get_tree().quit()
