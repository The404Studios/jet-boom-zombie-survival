extends Control

# Pause menu for in-game pause functionality

signal resumed
signal options_opened
signal main_menu_requested
signal quit_requested

@onready var resume_button: Button = $Panel/VBoxContainer/ResumeButton
@onready var options_button: Button = $Panel/VBoxContainer/OptionsButton
@onready var voice_button: Button = $Panel/VBoxContainer/VoiceOptionsButton
@onready var controls_button: Button = $Panel/VBoxContainer/ControlsButton
@onready var main_menu_button: Button = $Panel/VBoxContainer/MainMenuButton
@onready var quit_button: Button = $Panel/VBoxContainer/QuitButton

var is_paused: bool = false

func _ready():
	# Start hidden
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Connect buttons
	if resume_button:
		resume_button.pressed.connect(_on_resume_pressed)
	if options_button:
		options_button.pressed.connect(_on_options_pressed)
	if voice_button:
		voice_button.pressed.connect(_on_voice_pressed)
	if controls_button:
		controls_button.pressed.connect(_on_controls_pressed)
	if main_menu_button:
		main_menu_button.pressed.connect(_on_main_menu_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if is_paused:
			resume_game()
		else:
			pause_game()
		get_viewport().set_input_as_handled()

func pause_game():
	# Don't pause in multiplayer
	if multiplayer.has_multiplayer_peer():
		# In multiplayer, just show the menu without pausing
		visible = true
		is_paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	# Singleplayer - actually pause
	is_paused = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func resume_game():
	is_paused = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	resumed.emit()

func _on_resume_pressed():
	resume_game()

func _on_options_pressed():
	options_opened.emit()
	# Would show options panel here

func _on_voice_pressed():
	# Show voice settings
	pass

func _on_controls_pressed():
	# Show controls panel
	pass

func _on_main_menu_pressed():
	# Confirm before returning to main menu
	var confirm = ConfirmationDialog.new()
	confirm.dialog_text = "Return to main menu?\nAny unsaved progress will be lost."
	confirm.ok_button_text = "Yes"
	confirm.cancel_button_text = "No"
	confirm.confirmed.connect(_confirm_main_menu)
	add_child(confirm)
	confirm.popup_centered()

func _confirm_main_menu():
	# Unpause and return to main menu
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main_menu_requested.emit()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _on_quit_pressed():
	# Confirm before quitting
	var confirm = ConfirmationDialog.new()
	confirm.dialog_text = "Are you sure you want to quit?"
	confirm.ok_button_text = "Quit"
	confirm.cancel_button_text = "Cancel"
	confirm.confirmed.connect(_confirm_quit)
	add_child(confirm)
	confirm.popup_centered()

func _confirm_quit():
	quit_requested.emit()
	get_tree().quit()
