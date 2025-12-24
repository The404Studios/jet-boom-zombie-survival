extends Control

# Play Mode Selection Panel
# Allows player to choose between Singleplayer and Multiplayer modes

signal singleplayer_selected
signal multiplayer_selected
signal panel_closed

@onready var close_button: Button = $CloseButton
@onready var singleplayer_button: Button = $ModeContainer/SingleplayerPanel/VBox/PlayButton
@onready var multiplayer_button: Button = $ModeContainer/MultiplayerPanel/VBox/PlayButton
@onready var singleplayer_panel: Panel = $ModeContainer/SingleplayerPanel
@onready var multiplayer_panel: Panel = $ModeContainer/MultiplayerPanel

# Visual hover effects
var default_panel_color: Color = Color(0.15, 0.15, 0.18, 1.0)
var hover_panel_color: Color = Color(0.2, 0.25, 0.3, 1.0)

func _ready():
	# Connect button signals
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	if singleplayer_button:
		singleplayer_button.pressed.connect(_on_singleplayer_pressed)
	if multiplayer_button:
		multiplayer_button.pressed.connect(_on_multiplayer_pressed)

	# Connect hover effects
	if singleplayer_panel:
		singleplayer_panel.mouse_entered.connect(_on_singleplayer_hover.bind(true))
		singleplayer_panel.mouse_exited.connect(_on_singleplayer_hover.bind(false))
	if multiplayer_panel:
		multiplayer_panel.mouse_entered.connect(_on_multiplayer_hover.bind(true))
		multiplayer_panel.mouse_exited.connect(_on_multiplayer_hover.bind(false))

func _on_close_pressed():
	panel_closed.emit()
	visible = false

func _on_singleplayer_pressed():
	# Just emit signal - main_menu_controller handles the flow
	singleplayer_selected.emit()

func _on_multiplayer_pressed():
	# Just emit signal - main_menu_controller handles the flow
	multiplayer_selected.emit()

func _on_singleplayer_hover(is_hovering: bool):
	if singleplayer_panel:
		var stylebox = singleplayer_panel.get_theme_stylebox("panel")
		if stylebox is StyleBoxFlat:
			stylebox.bg_color = hover_panel_color if is_hovering else default_panel_color

func _on_multiplayer_hover(is_hovering: bool):
	if multiplayer_panel:
		var stylebox = multiplayer_panel.get_theme_stylebox("panel")
		if stylebox is StyleBoxFlat:
			stylebox.bg_color = hover_panel_color if is_hovering else default_panel_color

func _start_singleplayer_game():
	# Store game mode for systems to check
	if has_node("/root/GameSettings"):
		var settings = get_node("/root/GameSettings")
		settings.is_singleplayer = true

	# Change to the arena scene
	get_tree().change_scene_to_file("res://scenes/levels/arena_01.tscn")

func _input(event):
	if visible and event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()

func open():
	visible = true

func close():
	visible = false
	panel_closed.emit()
