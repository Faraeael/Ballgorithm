extends CanvasLayer

@onready var save_button: Button = $Control/PanelContainer/VBoxContainer/SaveButton
@onready var load_button: Button = $Control/PanelContainer/VBoxContainer/LoadButton
@onready var main_menu_button: Button = $Control/PanelContainer/VBoxContainer/MainMenuButton
@onready var close_button: Button = $Control/PanelContainer/VBoxContainer/CloseButton


func _ready() -> void:
	visible = false
	save_button.pressed.connect(_on_save)
	load_button.pressed.connect(_on_load)
	main_menu_button.pressed.connect(_on_main_menu)
	close_button.pressed.connect(_on_close)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		visible = not visible
		get_viewport().set_input_as_handled()


func _on_save() -> void:
	GameState.save_game()
	save_button.text = "Saved!"

	var timer: Timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = 1.5
	timer.timeout.connect(func() -> void:
		save_button.text = "Save Game"
		timer.queue_free()
	)
	add_child(timer)
	timer.start()


func _on_load() -> void:
	GameState.load_game()
	_route_to_current_phase()
	visible = false


func _on_main_menu() -> void:
	GameState.reset()
	visible = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _on_close() -> void:
	visible = false


# Mirrors MainMenu.gd load routing so saves resume at the owning scene for each phase.
func _route_to_current_phase() -> void:
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
