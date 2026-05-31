extends CanvasLayer

const ContractExtensionScript = preload("res://scripts/ContractExtension.gd")

signal extension_signed(player: Player)

var current_player: Player = null
var current_team: Team = null

@onready var title_label: Label = $Control/PanelContainer/VBoxContainer/TitleLabel
@onready var player_info_label: Label = $Control/PanelContainer/VBoxContainer/PlayerInfoLabel
@onready var current_contract_label: Label = $Control/PanelContainer/VBoxContainer/CurrentContractLabel
@onready var options_container: VBoxContainer = $Control/PanelContainer/VBoxContainer/OptionsContainer
@onready var cap_impact_label: Label = $Control/PanelContainer/VBoxContainer/CapImpactLabel
@onready var close_button: Button = $Control/PanelContainer/VBoxContainer/CloseButton


func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close)


func show_extension(player: Player, team: Team) -> void:
	current_player = player
	current_team = team
	title_label.text = "Extend: %s" % player.full_name
	player_info_label.text = "%s | %s | OVR %d | Age %d" % [player.position, player.archetype, player.get_overall(), player.age]
	current_contract_label.text = "Current: %s/yr - %d years remaining" % [_format_money(player.salary), player.contract_years]
	_clear_options()

	if not ContractExtensionScript.can_extend(player):
		_add_message("Player has %d years remaining. Extensions available with 2 or fewer years left." % player.contract_years)
		cap_impact_label.text = _get_cap_space_text(team)
		visible = true
		return

	# Build one option card per extension length; buttons validate the required cap-space delta.
	for option in ContractExtensionScript.get_extension_options(player):
		_add_option_card(option, team)

	cap_impact_label.text = _get_cap_space_text(team)
	visible = true


func _on_sign_extension(years: int) -> void:
	if current_player == null or current_team == null:
		return

	if ContractExtensionScript.apply_extension(current_team, current_player, years):
		extension_signed.emit(current_player)
		visible = false
	else:
		cap_impact_label.text = "Insufficient cap space"


func _on_close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		visible = false
		get_viewport().set_input_as_handled()


func _add_option_card(option: Dictionary, team: Team) -> void:
	var card: PanelContainer = PanelContainer.new()
	options_container.add_child(card)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 4)
	card.add_child(layout)

	var years: int = option["years"]
	var title: Label = Label.new()
	title.text = "%d year extension" % years
	layout.add_child(title)

	var salary_label: Label = Label.new()
	salary_label.text = "%s/yr (total %s)" % [_format_money(option["annual_salary"]), _format_money(option["total_cost"])]
	layout.add_child(salary_label)

	var increase_label: Label = Label.new()
	increase_label.text = "%s vs current salary" % _format_salary_delta(option["salary_increase"])
	layout.add_child(increase_label)

	var sign_button: Button = Button.new()
	sign_button.text = "Sign Extension"
	# Extension cap impact is only the annual raise over the existing contract.
	sign_button.disabled = option["salary_increase"] > 0 and CapEngine.get_cap_space(team) < option["salary_increase"]
	sign_button.pressed.connect(_on_sign_extension.bind(years))
	layout.add_child(sign_button)


func _add_message(message: String) -> void:
	var message_label: Label = Label.new()
	message_label.text = message
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	options_container.add_child(message_label)


func _clear_options() -> void:
	for child in options_container.get_children():
		options_container.remove_child(child)
		child.queue_free()


func _get_cap_space_text(team: Team) -> String:
	var cap_summary: Dictionary = CapEngine.get_cap_summary(team)
	return "Current cap space: %s" % _format_money(cap_summary["cap_space"])


func _format_money(amount: int) -> String:
	var sign: String = "" if amount >= 0 else "-"
	var absolute_amount: int = absi(amount)
	if absolute_amount >= 1_000_000:
		return "%s$%.1fM" % [sign, float(absolute_amount) / 1_000_000.0]
	if absolute_amount >= 1_000:
		return "%s$%dK" % [sign, int(round(float(absolute_amount) / 1_000.0))]
	return "%s$%d" % [sign, absolute_amount]


func _format_salary_delta(amount: int) -> String:
	if amount >= 0:
		return "+%s" % _format_money(amount)
	return _format_money(amount)
