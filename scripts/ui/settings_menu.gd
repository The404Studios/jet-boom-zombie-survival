extends Control
class_name SettingsMenu

# Full settings menu with tabs for different categories
# Video, Audio, Gameplay, Controls, Accessibility

signal settings_changed
signal back_pressed

# Tab content containers
var tab_container: TabContainer
var video_tab: Control
var audio_tab: Control
var gameplay_tab: Control
var controls_tab: Control
var accessibility_tab: Control

# Settings cache (for reverting changes)
var original_settings: Dictionary = {}
var pending_changes: Dictionary = {}

# References
var game_settings: Node = null

func _ready():
	game_settings = get_node_or_null("/root/GameSettings")
	_create_ui()
	_load_current_settings()

func _create_ui():
	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.07, 0.98)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main container
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 40)
	main_vbox.add_theme_constant_override("separation", 20)
	add_child(main_vbox)

	# Header
	var header = Label.new()
	header.text = "SETTINGS"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 36)
	header.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	main_vbox.add_child(header)

	# Tab container
	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(tab_container)

	# Create tabs
	_create_video_tab()
	_create_audio_tab()
	_create_gameplay_tab()
	_create_controls_tab()
	_create_accessibility_tab()

	# Footer buttons
	var footer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 20)
	main_vbox.add_child(footer)

	var back_btn = Button.new()
	back_btn.text = "BACK"
	back_btn.custom_minimum_size = Vector2(150, 50)
	back_btn.pressed.connect(_on_back_pressed)
	footer.add_child(back_btn)

	var reset_btn = Button.new()
	reset_btn.text = "RESET TO DEFAULT"
	reset_btn.custom_minimum_size = Vector2(180, 50)
	reset_btn.pressed.connect(_on_reset_pressed)
	footer.add_child(reset_btn)

	var apply_btn = Button.new()
	apply_btn.text = "APPLY"
	apply_btn.custom_minimum_size = Vector2(150, 50)
	apply_btn.pressed.connect(_on_apply_pressed)
	footer.add_child(apply_btn)

	# Style apply button
	var apply_style = StyleBoxFlat.new()
	apply_style.bg_color = Color(0.2, 0.5, 0.2)
	apply_style.corner_radius_top_left = 6
	apply_style.corner_radius_top_right = 6
	apply_style.corner_radius_bottom_left = 6
	apply_style.corner_radius_bottom_right = 6
	apply_btn.add_theme_stylebox_override("normal", apply_style)

func _create_video_tab():
	video_tab = _create_tab_scroll("Video")

	var vbox = video_tab.get_node("Content")

	# Resolution
	_add_section_header(vbox, "Display")

	var res_options = ["1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440", "3840x2160"]
	_add_option_setting(vbox, "Resolution", "resolution", res_options, 3)

	_add_checkbox_setting(vbox, "Fullscreen", "fullscreen_enabled", true)
	_add_checkbox_setting(vbox, "Borderless Window", "borderless_enabled", false)
	_add_checkbox_setting(vbox, "VSync", "vsync_enabled", true)

	var fps_options = ["30", "60", "120", "144", "240", "Unlimited"]
	_add_option_setting(vbox, "Max FPS", "max_fps", fps_options, 1)

	# Graphics Quality
	_add_section_header(vbox, "Graphics Quality")

	var quality_options = ["Low", "Medium", "High", "Ultra"]
	_add_option_setting(vbox, "Overall Quality", "graphics_quality", quality_options, 2)
	_add_option_setting(vbox, "Texture Quality", "texture_quality", quality_options, 2)
	_add_option_setting(vbox, "Shadow Quality", "shadow_quality", quality_options, 2)

	var aa_options = ["Off", "FXAA", "MSAA 2x", "MSAA 4x", "MSAA 8x"]
	_add_option_setting(vbox, "Anti-Aliasing", "anti_aliasing", aa_options, 1)

	_add_slider_setting(vbox, "Render Scale", "render_scale", 0.5, 2.0, 1.0, true)
	_add_slider_setting(vbox, "View Distance", "view_distance", 50.0, 500.0, 200.0, false)

	# Effects
	_add_section_header(vbox, "Effects")

	_add_checkbox_setting(vbox, "Motion Blur", "motion_blur_enabled", false)
	_add_checkbox_setting(vbox, "Bloom", "bloom_enabled", true)
	_add_checkbox_setting(vbox, "Ambient Occlusion", "ao_enabled", true)
	_add_checkbox_setting(vbox, "Screen Space Reflections", "ssr_enabled", false)
	_add_checkbox_setting(vbox, "Volumetric Fog", "volumetric_fog_enabled", true)
	_add_checkbox_setting(vbox, "Gore Effects", "gore_enabled", true)

func _create_audio_tab():
	audio_tab = _create_tab_scroll("Audio")

	var vbox = audio_tab.get_node("Content")

	# Volume
	_add_section_header(vbox, "Volume")

	_add_slider_setting(vbox, "Master Volume", "master_volume", 0.0, 1.0, 1.0, true)
	_add_slider_setting(vbox, "Music Volume", "music_volume", 0.0, 1.0, 0.7, true)
	_add_slider_setting(vbox, "SFX Volume", "sfx_volume", 0.0, 1.0, 1.0, true)
	_add_slider_setting(vbox, "Voice Volume", "voice_volume", 0.0, 1.0, 1.0, true)
	_add_slider_setting(vbox, "Ambient Volume", "ambient_volume", 0.0, 1.0, 0.8, true)

	# Voice Chat
	_add_section_header(vbox, "Voice Chat")

	_add_checkbox_setting(vbox, "Enable Voice Chat", "voice_chat_enabled", true)
	_add_checkbox_setting(vbox, "Push to Talk", "push_to_talk", true)
	_add_slider_setting(vbox, "Microphone Sensitivity", "mic_sensitivity", 0.1, 2.0, 1.0, true)
	_add_slider_setting(vbox, "Voice Chat Volume", "voice_chat_volume", 0.0, 1.0, 1.0, true)

	# Audio Options
	_add_section_header(vbox, "Audio Options")

	_add_checkbox_setting(vbox, "Subtitles", "subtitles_enabled", false)
	_add_checkbox_setting(vbox, "Dialogue Captions", "dialogue_captions", true)
	_add_checkbox_setting(vbox, "Mute When Unfocused", "mute_unfocused", false)

	var speaker_options = ["Stereo", "Surround 5.1", "Surround 7.1"]
	_add_option_setting(vbox, "Speaker Configuration", "speaker_config", speaker_options, 0)

func _create_gameplay_tab():
	gameplay_tab = _create_tab_scroll("Gameplay")

	var vbox = gameplay_tab.get_node("Content")

	# Camera
	_add_section_header(vbox, "Camera")

	_add_slider_setting(vbox, "Mouse Sensitivity", "mouse_sensitivity", 0.1, 3.0, 1.0, false)
	_add_slider_setting(vbox, "Controller Sensitivity", "controller_sensitivity", 0.1, 3.0, 1.0, false)
	_add_slider_setting(vbox, "Field of View", "field_of_view", 60.0, 120.0, 90.0, false)
	_add_slider_setting(vbox, "ADS Sensitivity", "ads_sensitivity", 0.1, 2.0, 0.7, false)

	_add_checkbox_setting(vbox, "Invert Y-Axis (Mouse)", "invert_y_mouse", false)
	_add_checkbox_setting(vbox, "Invert Y-Axis (Controller)", "invert_y_controller", false)

	# Gameplay
	_add_section_header(vbox, "Gameplay")

	_add_checkbox_setting(vbox, "Auto Reload", "auto_reload", true)
	_add_checkbox_setting(vbox, "Toggle Sprint", "toggle_sprint", false)
	_add_checkbox_setting(vbox, "Toggle Crouch", "toggle_crouch", false)
	_add_checkbox_setting(vbox, "Toggle Aim", "toggle_aim", false)
	_add_checkbox_setting(vbox, "Aim Assist (Controller)", "aim_assist", true)

	# HUD
	_add_section_header(vbox, "HUD")

	_add_slider_setting(vbox, "HUD Scale", "hud_scale", 0.5, 1.5, 1.0, true)
	_add_slider_setting(vbox, "Crosshair Size", "crosshair_size", 0.5, 2.0, 1.0, false)

	_add_checkbox_setting(vbox, "Show FPS Counter", "show_fps", false)
	_add_checkbox_setting(vbox, "Show Network Stats", "show_network_stats", false)
	_add_checkbox_setting(vbox, "Show Damage Numbers", "show_damage_numbers", true)
	_add_checkbox_setting(vbox, "Show Hit Markers", "show_hit_markers", true)
	_add_checkbox_setting(vbox, "Minimap Rotation", "minimap_rotation", true)

	var crosshair_options = ["Default", "Dot", "Cross", "Circle", "Custom"]
	_add_option_setting(vbox, "Crosshair Style", "crosshair_style", crosshair_options, 0)

func _create_controls_tab():
	controls_tab = _create_tab_scroll("Controls")

	var vbox = controls_tab.get_node("Content")

	# Keybinds header
	_add_section_header(vbox, "Keyboard Bindings")

	# Note about rebinding
	var note = Label.new()
	note.text = "Click on a binding to change it. Press Escape to cancel."
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(note)

	# Movement controls
	_add_section_header(vbox, "Movement")
	_add_keybind_row(vbox, "Move Forward", "move_forward", "W")
	_add_keybind_row(vbox, "Move Backward", "move_back", "S")
	_add_keybind_row(vbox, "Move Left", "move_left", "A")
	_add_keybind_row(vbox, "Move Right", "move_right", "D")
	_add_keybind_row(vbox, "Jump", "jump", "Space")
	_add_keybind_row(vbox, "Sprint", "sprint", "Shift")
	_add_keybind_row(vbox, "Crouch", "crouch", "Ctrl")

	# Combat controls
	_add_section_header(vbox, "Combat")
	_add_keybind_row(vbox, "Primary Fire", "shoot", "Mouse Left")
	_add_keybind_row(vbox, "Secondary Fire/Aim", "aim", "Mouse Right")
	_add_keybind_row(vbox, "Reload", "reload", "R")
	_add_keybind_row(vbox, "Melee", "melee", "V")
	_add_keybind_row(vbox, "Use Ability", "use_ability", "Z")
	_add_keybind_row(vbox, "Use Ultimate", "use_ultimate", "X")

	# Interaction
	_add_section_header(vbox, "Interaction")
	_add_keybind_row(vbox, "Interact", "interact", "E")
	_add_keybind_row(vbox, "Use Item", "use_item", "Q")
	_add_keybind_row(vbox, "Drop Item", "drop_item", "G")
	_add_keybind_row(vbox, "Inventory", "inventory", "I")

	# Communication
	_add_section_header(vbox, "Communication")
	_add_keybind_row(vbox, "Text Chat", "ui_chat", "T")
	_add_keybind_row(vbox, "Voice Chat (PTT)", "voice_chat", "V")
	_add_keybind_row(vbox, "Scoreboard", "scoreboard", "Tab")

	# Reset bindings button
	var reset_binds_btn = Button.new()
	reset_binds_btn.text = "Reset All Keybinds"
	reset_binds_btn.custom_minimum_size = Vector2(200, 40)
	reset_binds_btn.pressed.connect(_reset_keybinds)
	vbox.add_child(reset_binds_btn)

func _create_accessibility_tab():
	accessibility_tab = _create_tab_scroll("Accessibility")

	var vbox = accessibility_tab.get_node("Content")

	# Visual
	_add_section_header(vbox, "Visual Accessibility")

	_add_checkbox_setting(vbox, "Colorblind Mode", "colorblind_mode", false)

	var cb_options = ["Off", "Protanopia", "Deuteranopia", "Tritanopia"]
	_add_option_setting(vbox, "Colorblind Type", "colorblind_type", cb_options, 0)

	_add_slider_setting(vbox, "UI Brightness", "ui_brightness", 0.5, 1.5, 1.0, true)
	_add_slider_setting(vbox, "Text Size", "text_size", 0.8, 1.5, 1.0, true)

	_add_checkbox_setting(vbox, "High Contrast Mode", "high_contrast", false)
	_add_checkbox_setting(vbox, "Reduce Motion", "reduce_motion", false)
	_add_checkbox_setting(vbox, "Reduce Flashing", "reduce_flashing", false)

	# Audio
	_add_section_header(vbox, "Audio Accessibility")

	_add_checkbox_setting(vbox, "Visual Audio Cues", "visual_audio_cues", false)
	_add_checkbox_setting(vbox, "Sound Visualization", "sound_visualization", false)
	_add_checkbox_setting(vbox, "Mono Audio", "mono_audio", false)

	# Gameplay
	_add_section_header(vbox, "Gameplay Accessibility")

	_add_checkbox_setting(vbox, "Reduce Screen Shake", "reduce_screen_shake", false)
	_add_checkbox_setting(vbox, "Auto-Aim Assist", "auto_aim_assist", false)
	_add_checkbox_setting(vbox, "Larger Hit Boxes", "larger_hitboxes", false)
	_add_checkbox_setting(vbox, "Slow Motion Option", "slow_motion_option", false)
	_add_checkbox_setting(vbox, "One-Handed Controls", "one_handed_controls", false)

	# Timing
	_add_section_header(vbox, "Timing Assistance")

	_add_slider_setting(vbox, "Hold Duration", "hold_duration", 0.1, 2.0, 0.3, false)
	_add_slider_setting(vbox, "Double-Tap Window", "double_tap_window", 0.1, 1.0, 0.3, false)

	_add_checkbox_setting(vbox, "Auto Quick-Time Events", "auto_qte", false)

# ============================================
# UI HELPERS
# ============================================

func _create_tab_scroll(tab_name: String) -> Control:
	var scroll = ScrollContainer.new()
	scroll.name = tab_name
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.add_child(scroll)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	scroll.add_child(margin)

	var content = VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	return scroll

func _add_section_header(parent: Control, text: String):
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	parent.add_child(spacer)

	var header = Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	parent.add_child(header)

	var sep = HSeparator.new()
	parent.add_child(sep)

func _add_slider_setting(parent: Control, label_text: String, setting_name: String, min_val: float, max_val: float, default_val: float, is_percent: bool):
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	parent.add_child(hbox)

	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(label)

	var slider = HSlider.new()
	slider.name = setting_name
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = _get_setting(setting_name, default_val)
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(250, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(val): _queue_change(setting_name, val))
	hbox.add_child(slider)

	var value_label = Label.new()
	value_label.custom_minimum_size = Vector2(60, 0)
	if is_percent:
		value_label.text = "%d%%" % int(slider.value * 100)
		slider.value_changed.connect(func(val): value_label.text = "%d%%" % int(val * 100))
	else:
		value_label.text = "%.1f" % slider.value
		slider.value_changed.connect(func(val): value_label.text = "%.1f" % val)
	hbox.add_child(value_label)

func _add_checkbox_setting(parent: Control, label_text: String, setting_name: String, default_val: bool):
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	parent.add_child(hbox)

	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(label)

	var checkbox = CheckBox.new()
	checkbox.name = setting_name
	checkbox.button_pressed = _get_setting(setting_name, default_val)
	checkbox.toggled.connect(func(val): _queue_change(setting_name, val))
	hbox.add_child(checkbox)

func _add_option_setting(parent: Control, label_text: String, setting_name: String, options: Array, default_idx: int):
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	parent.add_child(hbox)

	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(label)

	var option_btn = OptionButton.new()
	option_btn.name = setting_name
	for opt in options:
		option_btn.add_item(opt)
	option_btn.selected = _get_setting(setting_name, default_idx)
	option_btn.custom_minimum_size = Vector2(200, 0)
	option_btn.item_selected.connect(func(idx): _queue_change(setting_name, idx))
	hbox.add_child(option_btn)

func _add_keybind_row(parent: Control, label_text: String, action_name: String, default_key: String):
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	parent.add_child(hbox)

	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(label)

	var key_button = Button.new()
	key_button.name = action_name
	key_button.text = _get_key_name(action_name, default_key)
	key_button.custom_minimum_size = Vector2(150, 35)
	key_button.pressed.connect(func(): _start_keybind_capture(key_button, action_name))
	hbox.add_child(key_button)

func _get_key_name(action_name: String, default: String) -> String:
	if InputMap.has_action(action_name):
		var events = InputMap.action_get_events(action_name)
		if events.size() > 0:
			return events[0].as_text()
	return default

func _start_keybind_capture(button: Button, action_name: String):
	button.text = "Press a key..."
	button.set_meta("capturing", true)
	button.set_meta("action", action_name)

	# Create input catcher
	var catcher = Control.new()
	catcher.name = "KeybindCatcher"
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP

	# Handle input
	catcher.gui_input.connect(func(event):
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ESCAPE:
				# Cancel
				button.text = _get_key_name(action_name, "Unbound")
			else:
				# Set new binding
				_set_keybind(action_name, event)
				button.text = event.as_text()

			button.set_meta("capturing", false)
			catcher.queue_free()
		elif event is InputEventMouseButton and event.pressed:
			_set_keybind(action_name, event)
			button.text = event.as_text()
			button.set_meta("capturing", false)
			catcher.queue_free()
	)

	add_child(catcher)
	catcher.grab_focus()

func _set_keybind(action_name: String, event: InputEvent):
	if InputMap.has_action(action_name):
		# Clear existing events
		InputMap.action_erase_events(action_name)
		# Add new event
		InputMap.action_add_event(action_name, event)

func _reset_keybinds():
	# Reload default keybindings from project settings
	var default_actions = [
		"move_forward", "move_back", "move_left", "move_right",
		"jump", "sprint", "crouch", "shoot", "aim", "reload",
		"melee", "use_ability", "use_ultimate", "interact",
		"use_item", "drop_item", "inventory", "ui_chat",
		"voice_chat", "scoreboard"
	]

	# Reset each action to its default from ProjectSettings
	for action_name in default_actions:
		if InputMap.has_action(action_name):
			# Get default events from project settings
			var default_events = ProjectSettings.get_setting("input/" + action_name)
			if default_events:
				# Clear current events
				InputMap.action_erase_events(action_name)
				# Re-add default events
				if default_events.has("events"):
					for event in default_events.events:
						InputMap.action_add_event(action_name, event)

	# Refresh the controls tab UI
	if controls_tab:
		var content = controls_tab.get_node_or_null("MarginContainer/Content")
		if content:
			# Update all keybind buttons with new values
			for child in content.get_children():
				if child is HBoxContainer:
					for sub_child in child.get_children():
						if sub_child is Button and sub_child.has_meta("action"):
							var action = sub_child.get_meta("action")
							sub_child.text = _get_key_name(action, "Unbound")

# ============================================
# SETTINGS MANAGEMENT
# ============================================

func _get_setting(setting_name: String, default_value):
	if game_settings and setting_name in game_settings:
		return game_settings.get(setting_name)
	return default_value

func _queue_change(setting_name: String, value):
	pending_changes[setting_name] = value
	settings_changed.emit()

func _apply_changes():
	for setting_name in pending_changes:
		var value = pending_changes[setting_name]

		# Apply to game settings
		if game_settings:
			if setting_name in game_settings:
				game_settings.set(setting_name, value)

		# Apply immediately for certain settings
		_apply_immediate_setting(setting_name, value)

	# Save settings
	if game_settings and game_settings.has_method("save_settings"):
		game_settings.save_settings()

	pending_changes.clear()

func _apply_immediate_setting(setting_name: String, value):
	match setting_name:
		"fullscreen_enabled":
			if value:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

		"vsync_enabled":
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED
			)

		"master_volume":
			AudioServer.set_bus_volume_db(0, linear_to_db(value))

		"music_volume":
			var idx = AudioServer.get_bus_index("Music")
			if idx >= 0:
				AudioServer.set_bus_volume_db(idx, linear_to_db(value))

		"sfx_volume":
			var idx = AudioServer.get_bus_index("SFX")
			if idx >= 0:
				AudioServer.set_bus_volume_db(idx, linear_to_db(value))

		"max_fps":
			var fps_values = [30, 60, 120, 144, 240, 0]
			if value < fps_values.size():
				Engine.max_fps = fps_values[value]

		"field_of_view":
			var camera = get_viewport().get_camera_3d()
			if camera:
				camera.fov = value

func _load_current_settings():
	# Cache current settings for potential revert
	if game_settings:
		for prop in game_settings.get_property_list():
			if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				original_settings[prop.name] = game_settings.get(prop.name)

# ============================================
# BUTTON CALLBACKS
# ============================================

func _on_back_pressed():
	if pending_changes.size() > 0:
		# Show confirm dialog
		var dialog = ConfirmationDialog.new()
		dialog.dialog_text = "You have unsaved changes. Discard them?"
		dialog.confirmed.connect(func():
			pending_changes.clear()
			back_pressed.emit()
		)
		add_child(dialog)
		dialog.popup_centered()
	else:
		back_pressed.emit()

func _on_reset_pressed():
	var dialog = ConfirmationDialog.new()
	dialog.dialog_text = "Reset all settings to default values?"
	dialog.confirmed.connect(_reset_to_defaults)
	add_child(dialog)
	dialog.popup_centered()

func _reset_to_defaults():
	if game_settings and game_settings.has_method("reset_to_defaults"):
		game_settings.reset_to_defaults()

	# Reload UI
	_load_current_settings()
	queue_redraw()

func _on_apply_pressed():
	_apply_changes()
