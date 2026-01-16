extends CanvasLayer

## SVERA Zombies Online Boot Screen
## Terminal-style loading animation with auto-connect

signal boot_complete
signal connection_established
signal connection_failed(reason: String)

# Animation settings
@export var typing_speed: float = 0.03
@export var line_delay: float = 0.15
@export var logo_reveal_time: float = 1.5

# UI References
var terminal_container: Control
var terminal_output: RichTextLabel
var logo_label: Label
var status_label: Label
var progress_bar: ProgressBar
var background: ColorRect
var scanline_effect: ColorRect
var cursor_blink: Timer

# State
var boot_lines: Array[String] = []
var current_line_index: int = 0
var current_char_index: int = 0
var is_typing: bool = false
var boot_phase: int = 0  # 0=boot, 1=connect, 2=auth, 3=complete
var connection_attempts: int = 0
var max_connection_attempts: int = 3

# Network references
var network_manager: Node = null
var backend: Node = null
var account_system: Node = null

func _ready():
	_create_ui()
	_setup_boot_sequence()

	# Get system references
	network_manager = get_node_or_null("/root/NetworkManager")
	backend = get_node_or_null("/root/Backend")
	account_system = get_node_or_null("/root/AccountSystem")

	# Start boot sequence
	await get_tree().create_timer(0.5).timeout
	_start_boot_sequence()

func _create_ui():
	# Main background
	background = ColorRect.new()
	background.name = "Background"
	background.color = Color(0.02, 0.02, 0.05, 1.0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	# Terminal container
	terminal_container = Control.new()
	terminal_container.name = "TerminalContainer"
	terminal_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	terminal_container.offset_left = 50
	terminal_container.offset_top = 50
	terminal_container.offset_right = -50
	terminal_container.offset_bottom = -100
	add_child(terminal_container)

	# Terminal output
	terminal_output = RichTextLabel.new()
	terminal_output.name = "TerminalOutput"
	terminal_output.bbcode_enabled = true
	terminal_output.scroll_following = true
	terminal_output.set_anchors_preset(Control.PRESET_FULL_RECT)
	terminal_output.add_theme_color_override("default_color", Color(0.0, 1.0, 0.4, 1.0))
	terminal_output.add_theme_font_size_override("normal_font_size", 16)
	terminal_container.add_child(terminal_output)

	# Logo (initially hidden)
	logo_label = Label.new()
	logo_label.name = "LogoLabel"
	logo_label.text = ""
	logo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	logo_label.set_anchors_preset(Control.PRESET_CENTER)
	logo_label.add_theme_font_size_override("font_size", 64)
	logo_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
	logo_label.modulate.a = 0.0
	logo_label.visible = false
	add_child(logo_label)

	# Status label at bottom
	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.text = ""
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	status_label.offset_top = -80
	status_label.offset_bottom = -50
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	add_child(status_label)

	# Progress bar
	progress_bar = ProgressBar.new()
	progress_bar.name = "ProgressBar"
	progress_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	progress_bar.offset_left = 100
	progress_bar.offset_right = -100
	progress_bar.offset_top = -40
	progress_bar.offset_bottom = -20
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.value = 0
	progress_bar.show_percentage = false
	progress_bar.visible = false
	add_child(progress_bar)

	# Scanline effect overlay
	scanline_effect = ColorRect.new()
	scanline_effect.name = "ScanlineEffect"
	scanline_effect.set_anchors_preset(Control.PRESET_FULL_RECT)
	scanline_effect.color = Color(0, 0, 0, 0.03)
	scanline_effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scanline_effect)

	# Create scanline shader effect
	_setup_scanline_effect()

func _setup_scanline_effect():
	# Simple scanline animation via process
	pass

func _process(delta):
	# Animate scanlines
	if scanline_effect:
		var offset = fmod(Time.get_ticks_msec() * 0.001, 1.0)
		scanline_effect.material = null  # Could add shader here

func _setup_boot_sequence():
	boot_lines = [
		"[color=#00ff66]SVERA SYSTEMS BIOS v4.2.1[/color]",
		"Copyright (C) 2024-2026 SVERA Industries",
		"",
		"[color=#888888]Initializing hardware...[/color]",
		"  CPU: SVERA Neural Processor @ 4.8 GHz ............ [color=#00ff00]OK[/color]",
		"  RAM: 32768 MB DDR5 Extended ...................... [color=#00ff00]OK[/color]",
		"  GPU: SVERA RTX-Z 16GB VRAM ....................... [color=#00ff00]OK[/color]",
		"  NET: Quantum Entanglement Interface .............. [color=#00ff00]OK[/color]",
		"",
		"[color=#888888]Loading core systems...[/color]",
		"  ZombieNet Protocol v3.1 .......................... [color=#00ff00]LOADED[/color]",
		"  SurvivalCore Engine .............................. [color=#00ff00]LOADED[/color]",
		"  WeaponSystems Module ............................. [color=#00ff00]LOADED[/color]",
		"  MultiplayerSync Framework ........................ [color=#00ff00]LOADED[/color]",
		"",
		"[color=#ffaa00]Establishing secure connection...[/color]",
		"",
	]

func _start_boot_sequence():
	is_typing = true
	_type_next_line()

func _type_next_line():
	if current_line_index >= boot_lines.size():
		_boot_sequence_complete()
		return

	var line = boot_lines[current_line_index]

	if line.is_empty():
		terminal_output.append_text("\n")
		current_line_index += 1
		await get_tree().create_timer(line_delay * 0.5).timeout
		_type_next_line()
		return

	# Type character by character for non-status lines
	if "..." in line or line.begins_with("[color=#888888]"):
		# Fast display for header lines
		terminal_output.append_text(line + "\n")
		current_line_index += 1
		await get_tree().create_timer(line_delay).timeout
		_type_next_line()
	else:
		# Character by character typing
		await _type_line_animated(line)
		terminal_output.append_text("\n")
		current_line_index += 1
		await get_tree().create_timer(line_delay).timeout
		_type_next_line()

func _type_line_animated(line: String):
	# Type character by character, handling BBCode tags as single units
	var i = 0
	while i < line.length():
		var c = line[i]
		if c == '[':
			# Find the end of the BBCode tag and output it all at once
			var end = line.find(']', i)
			if end != -1:
				terminal_output.append_text(line.substr(i, end - i + 1))
				i = end + 1
				continue
		# Regular character - type it with delay
		terminal_output.append_text(c)
		i += 1

		# Random typing speed variation
		var delay = typing_speed * randf_range(0.5, 1.5)
		await get_tree().create_timer(delay).timeout

func _boot_sequence_complete():
	boot_phase = 1
	progress_bar.visible = true
	_start_connection_sequence()

func _start_connection_sequence():
	status_label.text = "Connecting to SVERA Network..."
	_add_terminal_line("[color=#ffaa00]> Initiating connection to SVERA Central Server...[/color]")

	await get_tree().create_timer(0.5).timeout

	# Attempt connection
	_connect_to_server()

func _connect_to_server():
	connection_attempts += 1

	_add_terminal_line("  Attempt %d/%d..." % [connection_attempts, max_connection_attempts])
	progress_bar.value = 20

	# Try backend connection first
	if backend and backend.has_method("ping_server"):
		var result = await backend.ping_server()
		if result:
			_on_backend_connected()
			return

	# Try network manager connection
	if network_manager:
		if network_manager.has_signal("connected_to_server"):
			if not network_manager.connected_to_server.is_connected(_on_network_connected):
				network_manager.connected_to_server.connect(_on_network_connected, CONNECT_ONE_SHOT)
			if not network_manager.connection_failed.is_connected(_on_network_failed):
				network_manager.connection_failed.connect(_on_network_failed, CONNECT_ONE_SHOT)

		# Connect to dedicated server
		if network_manager.has_method("connect_to_dedicated_server"):
			network_manager.connect_to_dedicated_server()
		elif network_manager.has_method("join_server"):
			network_manager.join_server("162.248.94.149", 7777)

		# Timeout
		await get_tree().create_timer(5.0).timeout

		# If still not connected, simulate success for offline mode
		if boot_phase == 1:
			_simulate_connection_success()
	else:
		# No network manager, simulate offline mode
		await get_tree().create_timer(1.0).timeout
		_simulate_connection_success()

func _simulate_connection_success():
	_add_terminal_line("  [color=#ffaa00]Offline mode - Local session initialized[/color]")
	progress_bar.value = 50
	await get_tree().create_timer(0.3).timeout
	_on_connection_success(true)

func _on_backend_connected():
	_add_terminal_line("  [color=#00ff00]Backend API connected![/color]")
	progress_bar.value = 40
	await get_tree().create_timer(0.2).timeout
	_on_connection_success(false)

func _on_network_connected():
	_add_terminal_line("  [color=#00ff00]Game server connected![/color]")
	progress_bar.value = 50
	await get_tree().create_timer(0.2).timeout
	_on_connection_success(false)

func _on_network_failed():
	if connection_attempts < max_connection_attempts:
		_add_terminal_line("  [color=#ff4444]Connection failed, retrying...[/color]")
		await get_tree().create_timer(1.0).timeout
		_connect_to_server()
	else:
		_add_terminal_line("  [color=#ffaa00]Server unavailable - Offline mode enabled[/color]")
		await get_tree().create_timer(0.5).timeout
		_on_connection_success(true)

func _on_connection_success(offline: bool):
	boot_phase = 2

	if offline:
		status_label.text = "Running in offline mode..."
	else:
		status_label.text = "Loading account data..."

	_add_terminal_line("")
	_add_terminal_line("[color=#00ff66]Connection established![/color]")
	progress_bar.value = 60

	await get_tree().create_timer(0.3).timeout

	# Load account
	_load_account_data()

func _load_account_data():
	_add_terminal_line("[color=#888888]Loading player profile...[/color]")

	if account_system:
		if account_system.has_method("load_data"):
			account_system.load_data()

		await get_tree().create_timer(0.5).timeout

		var username = "Survivor"
		if "username" in account_system:
			username = account_system.username
		elif "account_data" in account_system and account_system.account_data.has("username"):
			username = account_system.account_data.username

		_add_terminal_line("  Welcome back, [color=#00ffff]%s[/color]!" % username)
	else:
		_add_terminal_line("  Guest session initialized")

	progress_bar.value = 80
	await get_tree().create_timer(0.3).timeout

	_show_logo_animation()

func _show_logo_animation():
	boot_phase = 3
	status_label.text = "Preparing game..."

	_add_terminal_line("")
	_add_terminal_line("[color=#00ff00]All systems operational.[/color]")
	_add_terminal_line("")

	progress_bar.value = 90

	await get_tree().create_timer(0.5).timeout

	# Fade out terminal
	var tween = create_tween()
	tween.tween_property(terminal_container, "modulate:a", 0.0, 0.5)

	await tween.finished

	# Show logo
	logo_label.visible = true
	logo_label.text = "SVERA"
	logo_label.modulate.a = 0.0
	logo_label.scale = Vector2(0.5, 0.5)

	var logo_tween = create_tween()
	logo_tween.set_parallel(true)
	logo_tween.tween_property(logo_label, "modulate:a", 1.0, 0.8)
	logo_tween.tween_property(logo_label, "scale", Vector2(1.0, 1.0), 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await logo_tween.finished

	# Add subtitle
	await get_tree().create_timer(0.3).timeout

	var subtitle = Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "ZOMBIES ONLINE"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.set_anchors_preset(Control.PRESET_CENTER)
	subtitle.offset_top = 50
	subtitle.add_theme_font_size_override("font_size", 28)
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))
	subtitle.modulate.a = 0.0
	add_child(subtitle)

	var sub_tween = create_tween()
	sub_tween.tween_property(subtitle, "modulate:a", 1.0, 0.5)

	await sub_tween.finished

	progress_bar.value = 100
	status_label.text = "Press any key to continue..."

	# Wait for input
	set_process_input(true)

func _input(event):
	if boot_phase == 3:
		if event is InputEventKey or event is InputEventMouseButton:
			if event.pressed:
				set_process_input(false)
				_complete_boot()

func _complete_boot():
	# Fade everything out
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.5)

	await tween.finished

	boot_complete.emit()
	queue_free()

func _add_terminal_line(text: String):
	terminal_output.append_text(text + "\n")

# ============================================
# PUBLIC API
# ============================================

func skip_boot():
	"""Skip directly to completion (for debugging)"""
	boot_phase = 3
	_complete_boot()
