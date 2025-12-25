extends Control

# Pause menu for in-game pause functionality
# Includes settings, controls, stats, and game management

signal resumed
signal options_opened
signal main_menu_requested
signal quit_requested

@onready var resume_button: Button = $Panel/VBoxContainer/ResumeButton
@onready var options_button: Button = $Panel/VBoxContainer/OptionsButton
@onready var voice_button: Button = $Panel/VBoxContainer/VoiceOptionsButton
@onready var controls_button: Button = $Panel/VBoxContainer/ControlsButton
@onready var stats_button: Button = $Panel/VBoxContainer/StatsButton if has_node("Panel/VBoxContainer/StatsButton") else null
@onready var main_menu_button: Button = $Panel/VBoxContainer/MainMenuButton
@onready var quit_button: Button = $Panel/VBoxContainer/QuitButton

# Sub-panels
var options_panel: Control = null
var stats_panel: Control = null

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
	if stats_button:
		stats_button.pressed.connect(_on_stats_pressed)
	if main_menu_button:
		main_menu_button.pressed.connect(_on_main_menu_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

	# Create stats button if it doesn't exist
	if not stats_button and has_node("Panel/VBoxContainer"):
		var vbox = get_node("Panel/VBoxContainer")
		var new_stats_btn = Button.new()
		new_stats_btn.name = "StatsButton"
		new_stats_btn.text = "Stats"
		new_stats_btn.pressed.connect(_on_stats_pressed)
		# Insert before MainMenuButton
		var main_idx = main_menu_button.get_index() if main_menu_button else vbox.get_child_count()
		vbox.add_child(new_stats_btn)
		vbox.move_child(new_stats_btn, main_idx)
		stats_button = new_stats_btn

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if is_paused:
			# Check if any sub-panel is open
			if options_panel and options_panel.visible:
				_close_options_panel()
			elif stats_panel and stats_panel.visible:
				_close_stats_panel()
			else:
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

	# Close any open sub-panels
	if options_panel and options_panel.visible:
		options_panel.queue_free()
		options_panel = null
	if stats_panel and stats_panel.visible:
		stats_panel.queue_free()
		stats_panel = null

	resumed.emit()

func _on_resume_pressed():
	resume_game()

func _on_options_pressed():
	options_opened.emit()
	_show_options_panel()

func _show_options_panel():
	# Create comprehensive options panel
	options_panel = PanelContainer.new()
	options_panel.set_anchors_preset(Control.PRESET_CENTER)
	options_panel.custom_minimum_size = Vector2(500, 450)
	options_panel.position = Vector2(-250, -225)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	options_panel.add_child(main_vbox)

	# Title
	var title = Label.new()
	title.text = "OPTIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	main_vbox.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 350)
	main_vbox.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	scroll.add_child(vbox)

	# ============ GRAPHICS ============
	var graphics_label = Label.new()
	graphics_label.text = "Graphics"
	graphics_label.add_theme_font_size_override("font_size", 18)
	graphics_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
	vbox.add_child(graphics_label)

	# Fullscreen toggle
	var fullscreen_hbox = HBoxContainer.new()
	var fullscreen_label = Label.new()
	fullscreen_label.text = "Fullscreen"
	fullscreen_label.custom_minimum_size = Vector2(200, 0)
	fullscreen_hbox.add_child(fullscreen_label)
	var fullscreen_check = CheckBox.new()
	fullscreen_check.button_pressed = _get_setting("fullscreen_enabled", true)
	fullscreen_check.toggled.connect(func(val): _set_setting("fullscreen_enabled", val); _apply_fullscreen(val))
	fullscreen_hbox.add_child(fullscreen_check)
	vbox.add_child(fullscreen_hbox)

	# VSync toggle
	var vsync_hbox = HBoxContainer.new()
	var vsync_label = Label.new()
	vsync_label.text = "VSync"
	vsync_label.custom_minimum_size = Vector2(200, 0)
	vsync_hbox.add_child(vsync_label)
	var vsync_check = CheckBox.new()
	vsync_check.button_pressed = _get_setting("vsync_enabled", true)
	vsync_check.toggled.connect(func(val): _set_setting("vsync_enabled", val); _apply_vsync(val))
	vsync_hbox.add_child(vsync_check)
	vbox.add_child(vsync_hbox)

	# Gore toggle
	var gore_hbox = HBoxContainer.new()
	var gore_label = Label.new()
	gore_label.text = "Gore Effects"
	gore_label.custom_minimum_size = Vector2(200, 0)
	gore_hbox.add_child(gore_label)
	var gore_check = CheckBox.new()
	gore_check.button_pressed = _get_setting("gore_enabled", true)
	gore_check.toggled.connect(func(val): _set_setting("gore_enabled", val))
	gore_hbox.add_child(gore_check)
	vbox.add_child(gore_hbox)

	# FPS Limit
	var fps_hbox = HBoxContainer.new()
	var fps_label = Label.new()
	fps_label.text = "Max FPS"
	fps_label.custom_minimum_size = Vector2(200, 0)
	fps_hbox.add_child(fps_label)
	var fps_option = OptionButton.new()
	fps_option.add_item("30", 30)
	fps_option.add_item("60", 60)
	fps_option.add_item("120", 120)
	fps_option.add_item("144", 144)
	fps_option.add_item("Unlimited", 0)
	var current_fps = _get_setting("target_fps", 60)
	for i in range(fps_option.item_count):
		if fps_option.get_item_id(i) == current_fps:
			fps_option.select(i)
			break
	fps_option.item_selected.connect(func(idx):
		var fps = fps_option.get_item_id(idx)
		_set_setting("target_fps", fps)
		Engine.max_fps = fps
	)
	fps_hbox.add_child(fps_option)
	vbox.add_child(fps_hbox)

	# ============ AUDIO ============
	var audio_label = Label.new()
	audio_label.text = "Audio"
	audio_label.add_theme_font_size_override("font_size", 18)
	audio_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
	vbox.add_child(audio_label)

	# Master Volume
	_add_volume_slider(vbox, "Master Volume", "master_volume", 1.0)
	_add_volume_slider(vbox, "Music Volume", "music_volume", 0.7)
	_add_volume_slider(vbox, "SFX Volume", "sfx_volume", 1.0)

	# ============ GAMEPLAY ============
	var gameplay_label = Label.new()
	gameplay_label.text = "Gameplay"
	gameplay_label.add_theme_font_size_override("font_size", 18)
	gameplay_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
	vbox.add_child(gameplay_label)

	# Mouse Sensitivity
	var sens_hbox = HBoxContainer.new()
	var sens_label = Label.new()
	sens_label.text = "Mouse Sensitivity"
	sens_label.custom_minimum_size = Vector2(200, 0)
	sens_hbox.add_child(sens_label)
	var sens_slider = HSlider.new()
	sens_slider.min_value = 0.1
	sens_slider.max_value = 3.0
	sens_slider.step = 0.1
	sens_slider.value = _get_setting("mouse_sensitivity", 1.0)
	sens_slider.custom_minimum_size = Vector2(150, 20)
	sens_slider.value_changed.connect(func(val): _set_setting("mouse_sensitivity", val))
	sens_hbox.add_child(sens_slider)
	var sens_value = Label.new()
	sens_value.text = "%.1f" % sens_slider.value
	sens_slider.value_changed.connect(func(val): sens_value.text = "%.1f" % val)
	sens_hbox.add_child(sens_value)
	vbox.add_child(sens_hbox)

	# Invert Y
	var invert_hbox = HBoxContainer.new()
	var invert_label = Label.new()
	invert_label.text = "Invert Y-Axis"
	invert_label.custom_minimum_size = Vector2(200, 0)
	invert_hbox.add_child(invert_label)
	var invert_check = CheckBox.new()
	invert_check.button_pressed = _get_setting("invert_y", false)
	invert_check.toggled.connect(func(val): _set_setting("invert_y", val))
	invert_hbox.add_child(invert_check)
	vbox.add_child(invert_hbox)

	# Auto Reload
	var reload_hbox = HBoxContainer.new()
	var reload_label = Label.new()
	reload_label.text = "Auto Reload"
	reload_label.custom_minimum_size = Vector2(200, 0)
	reload_hbox.add_child(reload_label)
	var reload_check = CheckBox.new()
	reload_check.button_pressed = _get_setting("auto_reload", true)
	reload_check.toggled.connect(func(val): _set_setting("auto_reload", val))
	reload_hbox.add_child(reload_check)
	vbox.add_child(reload_hbox)

	# FOV Slider
	var fov_hbox = HBoxContainer.new()
	var fov_label = Label.new()
	fov_label.text = "Field of View"
	fov_label.custom_minimum_size = Vector2(200, 0)
	fov_hbox.add_child(fov_label)
	var fov_slider = HSlider.new()
	fov_slider.min_value = 60
	fov_slider.max_value = 120
	fov_slider.step = 5
	fov_slider.value = _get_setting("field_of_view", 75.0)
	fov_slider.custom_minimum_size = Vector2(150, 20)
	fov_slider.value_changed.connect(func(val): _set_setting("field_of_view", val); _apply_fov(val))
	fov_hbox.add_child(fov_slider)
	var fov_value = Label.new()
	fov_value.text = "%d" % int(fov_slider.value)
	fov_slider.value_changed.connect(func(val): fov_value.text = "%d" % int(val))
	fov_hbox.add_child(fov_value)
	vbox.add_child(fov_hbox)

	# Close button
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	var close_btn = Button.new()
	close_btn.text = "Apply & Close"
	close_btn.custom_minimum_size = Vector2(150, 40)
	close_btn.pressed.connect(_close_options_panel)
	btn_hbox.add_child(close_btn)
	main_vbox.add_child(btn_hbox)

	add_child(options_panel)

func _add_volume_slider(parent: Control, label_text: String, setting_name: String, default: float):
	var hbox = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(label)
	var slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = _get_setting(setting_name, default)
	slider.custom_minimum_size = Vector2(150, 20)
	slider.value_changed.connect(func(val): _set_setting(setting_name, val); _apply_audio(setting_name, val))
	hbox.add_child(slider)
	var value_label = Label.new()
	value_label.text = "%d%%" % int(slider.value * 100)
	slider.value_changed.connect(func(val): value_label.text = "%d%%" % int(val * 100))
	hbox.add_child(value_label)
	parent.add_child(hbox)

func _close_options_panel():
	if options_panel:
		# Save settings
		if has_node("/root/GameSettings"):
			get_node("/root/GameSettings").save_settings()
		options_panel.queue_free()
		options_panel = null

func _on_voice_pressed():
	# Show voice settings dialog
	var dialog = AcceptDialog.new()
	dialog.title = "Voice Settings"

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	# Voice enabled toggle
	var voice_enabled = CheckBox.new()
	voice_enabled.text = "Enable Voice Chat"
	voice_enabled.button_pressed = true
	if has_node("/root/VoiceChatSystem"):
		var vcs = get_node("/root/VoiceChatSystem")
		if "voice_enabled" in vcs:
			voice_enabled.button_pressed = vcs.voice_enabled
	voice_enabled.toggled.connect(func(toggled):
		if has_node("/root/VoiceChatSystem"):
			var vcs = get_node("/root/VoiceChatSystem")
			if vcs.has_method("set_voice_enabled"):
				vcs.set_voice_enabled(toggled)
			elif "voice_enabled" in vcs:
				vcs.voice_enabled = toggled
	)
	vbox.add_child(voice_enabled)

	# Push to talk toggle
	var ptt = CheckBox.new()
	ptt.text = "Push to Talk"
	ptt.button_pressed = true
	if has_node("/root/VoiceChatSystem"):
		var vcs = get_node("/root/VoiceChatSystem")
		if "push_to_talk" in vcs:
			ptt.button_pressed = vcs.push_to_talk
	ptt.toggled.connect(func(toggled):
		if has_node("/root/VoiceChatSystem"):
			var vcs = get_node("/root/VoiceChatSystem")
			if "push_to_talk" in vcs:
				vcs.push_to_talk = toggled
	)
	vbox.add_child(ptt)

	# Microphone input level
	var mic_hbox = HBoxContainer.new()
	var mic_label = Label.new()
	mic_label.text = "Mic Sensitivity"
	mic_label.custom_minimum_size = Vector2(150, 0)
	mic_hbox.add_child(mic_label)
	var mic_slider = HSlider.new()
	mic_slider.min_value = 0.0
	mic_slider.max_value = 2.0
	mic_slider.step = 0.1
	mic_slider.value = 1.0
	mic_slider.custom_minimum_size = Vector2(150, 20)
	mic_hbox.add_child(mic_slider)
	vbox.add_child(mic_hbox)

	# Volume slider
	var vol_label = Label.new()
	vol_label.text = "Voice Volume"
	vbox.add_child(vol_label)

	var volume = HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.1
	volume.value = 1.0
	volume.custom_minimum_size = Vector2(200, 20)
	if has_node("/root/VoiceChatSystem"):
		var vcs = get_node("/root/VoiceChatSystem")
		if "voice_volume" in vcs:
			volume.value = vcs.voice_volume
	volume.value_changed.connect(func(val):
		if has_node("/root/VoiceChatSystem"):
			var vcs = get_node("/root/VoiceChatSystem")
			if "voice_volume" in vcs:
				vcs.voice_volume = val
	)
	vbox.add_child(volume)

	# Output device info
	var device_label = Label.new()
	device_label.text = "Output: Default Device"
	device_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(device_label)

	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered(Vector2i(350, 280))

func _on_controls_pressed():
	# Show controls panel with key bindings
	var dialog = AcceptDialog.new()
	dialog.title = "Controls"
	dialog.size = Vector2i(450, 550)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430, 450)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)

	# Display current control bindings
	var controls = [
		["", "MOVEMENT"],
		["Forward", "W"],
		["Backward", "S"],
		["Left", "A"],
		["Right", "D"],
		["Jump", "Space"],
		["Sprint", "Shift"],
		["Crouch", "Ctrl"],
		["", ""],
		["", "COMBAT"],
		["Fire", "Left Mouse"],
		["Aim/ADS", "Right Mouse"],
		["Reload", "R"],
		["Melee", "V"],
		["Grenade", "G"],
		["", ""],
		["", "WEAPONS"],
		["Weapon 1-9", "1-9 Keys"],
		["Next Weapon", "Mouse Wheel Up"],
		["Prev Weapon", "Mouse Wheel Down"],
		["", ""],
		["", "ACTIONS"],
		["Interact", "E / F"],
		["Phase Through Props", "Z (Hold)"],
		["Place Barricade", "B"],
		["Use Item", "Q"],
		["", ""],
		["", "INTERFACE"],
		["Pause", "Escape"],
		["Inventory/RPG Menu", "Tab / I"],
		["Chat", "T / Enter"],
		["Scoreboard", "Tab (Hold)"],
		["Map", "M"]
	]

	for control in controls:
		var hbox = HBoxContainer.new()

		var action_label = Label.new()
		action_label.text = control[0]
		action_label.custom_minimum_size = Vector2(180, 0)
		if control[1] == "" or control[0] == "":
			# Section header
			action_label.text = control[1]
			action_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
			action_label.add_theme_font_size_override("font_size", 16)
		hbox.add_child(action_label)

		if control[0] != "":
			var key_label = Label.new()
			key_label.text = control[1]
			key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			key_label.custom_minimum_size = Vector2(150, 0)
			key_label.add_theme_color_override("font_color", Color.GOLD)
			hbox.add_child(key_label)

		vbox.add_child(hbox)

	scroll.add_child(vbox)
	dialog.add_child(scroll)
	add_child(dialog)
	dialog.popup_centered()

func _on_stats_pressed():
	_show_stats_panel()

func _show_stats_panel():
	stats_panel = PanelContainer.new()
	stats_panel.set_anchors_preset(Control.PRESET_CENTER)
	stats_panel.custom_minimum_size = Vector2(400, 350)
	stats_panel.position = Vector2(-200, -175)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	stats_panel.add_child(main_vbox)

	# Title
	var title = Label.new()
	title.text = "GAME STATS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	main_vbox.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 250)
	main_vbox.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	# Get stats from various systems
	var wave = 1
	var zombies_killed = 0
	var points = 0
	var player_health = 100.0
	var player_max_health = 100.0

	# Get arena manager stats
	var arena = get_tree().get_first_node_in_group("arena_manager")
	if arena:
		wave = arena.current_wave
		points = arena.player_points

	# Get player stats
	var player = get_tree().get_first_node_in_group("player")
	if player:
		if "current_health" in player:
			player_health = player.current_health
		if "max_health" in player:
			player_max_health = player.max_health

	# Get points system stats
	if has_node("/root/PointsSystem"):
		var ps = get_node("/root/PointsSystem")
		if ps.has_method("get_points"):
			points = ps.get_points()

	# Display stats
	_add_stat_row(vbox, "Current Wave", str(wave))
	_add_stat_row(vbox, "Zombies Alive", str(arena.zombies_alive if arena else 0))
	_add_stat_row(vbox, "Points", str(points))
	_add_stat_row(vbox, "", "")  # Spacer
	_add_stat_row(vbox, "Health", "%d / %d" % [int(player_health), int(player_max_health)])

	if player and "current_stamina" in player and "max_stamina" in player:
		_add_stat_row(vbox, "Stamina", "%d / %d" % [int(player.current_stamina), int(player.max_stamina)])

	if player and "current_ammo" in player and "reserve_ammo" in player:
		_add_stat_row(vbox, "Ammo", "%d / %d" % [player.current_ammo, player.reserve_ammo])

	# Get character attributes if available
	if player and player.has_node("CharacterAttributes"):
		var attrs = player.get_node("CharacterAttributes")
		_add_stat_row(vbox, "", "")  # Spacer
		_add_stat_row(vbox, "Level", str(attrs.level if "level" in attrs else 1))
		_add_stat_row(vbox, "Experience", "%d / %d" % [attrs.experience if "experience" in attrs else 0, attrs.experience_to_next_level if "experience_to_next_level" in attrs else 100])

	# Close button
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(100, 35)
	close_btn.pressed.connect(_close_stats_panel)
	btn_hbox.add_child(close_btn)
	main_vbox.add_child(btn_hbox)

	add_child(stats_panel)

func _add_stat_row(parent: Control, label_text: String, value_text: String):
	var hbox = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(180, 0)
	if label_text == "":
		label.custom_minimum_size = Vector2(180, 10)  # Spacer height
	hbox.add_child(label)
	var value = Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.custom_minimum_size = Vector2(150, 0)
	value.add_theme_color_override("font_color", Color.GOLD)
	hbox.add_child(value)
	parent.add_child(hbox)

func _close_stats_panel():
	if stats_panel:
		stats_panel.queue_free()
		stats_panel = null

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
	# Stop network connection if any
	if has_node("/root/NetworkManager"):
		var network = get_node("/root/NetworkManager")
		if network.has_method("disconnect_from_server"):
			network.disconnect_from_server()
		if network.has_method("stop_server"):
			network.stop_server()

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
	# Save settings before quitting
	if has_node("/root/GameSettings"):
		get_node("/root/GameSettings").save_settings()

	# Save player data
	if has_node("/root/PlayerPersistence"):
		var persistence = get_node("/root/PlayerPersistence")
		if persistence.has_method("save_player_data"):
			persistence.save_player_data()

	quit_requested.emit()
	get_tree().quit()

# ============================================
# SETTINGS HELPERS
# ============================================

func _get_setting(setting_name: String, default_value):
	if has_node("/root/GameSettings"):
		var settings = get_node("/root/GameSettings")
		if setting_name in settings:
			return settings.get(setting_name)
	return default_value

func _set_setting(setting_name: String, value):
	if has_node("/root/GameSettings"):
		var settings = get_node("/root/GameSettings")
		if setting_name in settings:
			settings.set(setting_name, value)

func _apply_fullscreen(enabled: bool):
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _apply_vsync(enabled: bool):
	if enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _apply_audio(setting_name: String, value: float):
	if has_node("/root/AudioManager"):
		var audio = get_node("/root/AudioManager")
		match setting_name:
			"master_volume":
				if audio.has_method("set_master_volume"):
					audio.set_master_volume(value)
			"music_volume":
				if audio.has_method("set_music_volume"):
					audio.set_music_volume(value)
			"sfx_volume":
				if audio.has_method("set_sfx_volume"):
					audio.set_sfx_volume(value)

func _apply_fov(value: float):
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_node("Camera3D"):
		var camera = player.get_node("Camera3D")
		camera.fov = value
