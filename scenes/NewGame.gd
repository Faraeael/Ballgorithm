extends Control

const SITUATIONS: Array[String] = ["Tanking", "Rebuilding", "Play-In", "Playoff", "Contender"]
const SITUATION_DESCRIPTIONS: Dictionary = {
	"Tanking": "Lose now, build through the draft. You pick first.",
	"Rebuilding": "Young core, limited cap, high upside.",
	"Play-In": "Bubble team fighting for a playoff spot.",
	"Playoff": "Established roster competing for a deep run.",
	"Contender": "Championship or bust. No cap space, no excuses."
}

@onready var city_input: LineEdit = $CenterContainer/VBoxContainer/CityInput
@onready var team_name_input: LineEdit = $CenterContainer/VBoxContainer/TeamNameInput
@onready var situation_picker: OptionButton = $CenterContainer/VBoxContainer/SituationPicker
@onready var situation_desc: Label = $CenterContainer/VBoxContainer/SituationDesc
@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton

var selected_situation: String = "Tanking"


func _ready() -> void:
	for situation in SITUATIONS:
		situation_picker.add_item(situation)

	situation_picker.item_selected.connect(_on_situation_selected)
	start_button.pressed.connect(_on_start)
	situation_desc.text = SITUATION_DESCRIPTIONS[selected_situation]


# Keeps selected situation and description in sync with the picker.
func _on_situation_selected(index: int) -> void:
	selected_situation = situation_picker.get_item_text(index)
	situation_desc.text = SITUATION_DESCRIPTIONS[selected_situation]


# Validates team identity, generates the league, then enters the preseason hub.
func _on_start() -> void:
	var city: String = city_input.text.strip_edges()
	var team_name: String = team_name_input.text.strip_edges()
	if city.is_empty() or team_name.is_empty():
		situation_desc.text = "Please enter a city and team name."
		return

	GameState.initialize_league(selected_situation, city, team_name)
	get_tree().change_scene_to_file("res://scenes/PreSeasonHub.tscn")
