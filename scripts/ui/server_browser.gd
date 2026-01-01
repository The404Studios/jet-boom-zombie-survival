extends Control
class_name ServerBrowser

# Server browser for finding and joining multiplayer games
# Integrates with Steam lobbies or custom server list

signal server_selected(server_info: Dictionary)
signal join_requested(server_info: Dictionary)
signal create_server_requested
signal refresh_requested
signal back_pressed

# UI References
var server_list_container: VBoxContainer
var server_entries: Array = []
var selected_server: Dictionary = {}

var filter_panel: Control
var name_filter: LineEdit
var map_filter: OptionButton
var gamemode_filter: OptionButton
var hide_full_check: CheckBox
var hide_empty_check: CheckBox
var hide_password_check: CheckBox

var details_panel: Control
var join_button: Button
var refresh_button: Button

# Server data
var servers: Array = []
var filtered_servers: Array = []

# Settings
@export var auto_refresh_interval: float = 30.0
@export var max_servers_displayed: int = 100

var auto_refresh_timer: float = 0.0
var is_refreshing: bool = false

# Network integration
var matchmaking_manager: Node = null
var steam_manager: Node = null
var backend: Node = null

func _ready():
	matchmaking_manager = get_node_or_null("/root/MatchmakingManager")
	steam_manager = get_node_or_null("/root/SteamManager")
	backend = get_node_or_null("/root/Backend")

	_create_ui()
	_connect_signals()

	# Initial server fetch
	_request_servers()

func _create_ui():
	# Main background
	var bg = ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.08, 0.98)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main container
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 25)
	main_vbox.add_theme_constant_override("separation", 15)
	add_child(main_vbox)

	# Header
	_create_header(main_vbox)

	# Content - horizontal layout
	var content_hbox = HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 15)
	main_vbox.add_child(content_hbox)

	# Left side - Filters
	_create_filter_panel(content_hbox)

	# Center - Server list
	_create_server_list_panel(content_hbox)

	# Right side - Details
	_create_details_panel(content_hbox)

	# Footer buttons
	_create_footer(main_vbox)

func _create_header(parent: Control):
	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 20)
	parent.add_child(header_hbox)

	var title = Label.new()
	title.text = "SERVER BROWSER"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	header_hbox.add_child(title)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)

	# Server count
	var count_label = Label.new()
	count_label.name = "ServerCount"
	count_label.text = "0 servers found"
	count_label.add_theme_font_size_override("font_size", 14)
	count_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	header_hbox.add_child(count_label)

	# Refresh button
	refresh_button = Button.new()
	refresh_button.text = "REFRESH"
	refresh_button.custom_minimum_size = Vector2(120, 35)
	refresh_button.pressed.connect(_on_refresh_pressed)
	header_hbox.add_child(refresh_button)

func _create_filter_panel(parent: Control):
	filter_panel = PanelContainer.new()
	filter_panel.custom_minimum_size = Vector2(250, 0)
	parent.add_child(filter_panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	filter_panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	filter_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Header
	var header = Label.new()
	header.text = "FILTERS"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	vbox.add_child(header)

	# Name filter
	var name_label = Label.new()
	name_label.text = "Server Name"
	name_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(name_label)

	name_filter = LineEdit.new()
	name_filter.placeholder_text = "Search..."
	name_filter.text_changed.connect(func(_t): _apply_filters())
	vbox.add_child(name_filter)

	# Map filter
	var map_label = Label.new()
	map_label.text = "Map"
	map_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(map_label)

	map_filter = OptionButton.new()
	map_filter.add_item("Any Map", 0)
	map_filter.add_item("Warehouse", 1)
	map_filter.add_item("Hospital", 2)
	map_filter.add_item("Subway", 3)
	map_filter.add_item("Mansion", 4)
	map_filter.add_item("Military Base", 5)
	map_filter.add_item("Shopping Mall", 6)
	map_filter.item_selected.connect(func(_i): _apply_filters())
	vbox.add_child(map_filter)

	# Gamemode filter
	var mode_label = Label.new()
	mode_label.text = "Game Mode"
	mode_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(mode_label)

	gamemode_filter = OptionButton.new()
	gamemode_filter.add_item("Any Mode", 0)
	gamemode_filter.add_item("Survival", 1)
	gamemode_filter.add_item("Objective", 2)
	gamemode_filter.add_item("Endless", 3)
	gamemode_filter.item_selected.connect(func(_i): _apply_filters())
	vbox.add_child(gamemode_filter)

	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Checkboxes
	hide_full_check = CheckBox.new()
	hide_full_check.text = "Hide Full Servers"
	hide_full_check.toggled.connect(func(_t): _apply_filters())
	vbox.add_child(hide_full_check)

	hide_empty_check = CheckBox.new()
	hide_empty_check.text = "Hide Empty Servers"
	hide_empty_check.toggled.connect(func(_t): _apply_filters())
	vbox.add_child(hide_empty_check)

	hide_password_check = CheckBox.new()
	hide_password_check.text = "Hide Password Protected"
	hide_password_check.toggled.connect(func(_t): _apply_filters())
	vbox.add_child(hide_password_check)

	# Reset filters button
	var reset_btn = Button.new()
	reset_btn.text = "Reset Filters"
	reset_btn.pressed.connect(_reset_filters)
	vbox.add_child(reset_btn)

func _create_server_list_panel(parent: Control):
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)

	# Column headers
	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 0)
	vbox.add_child(header_hbox)

	_create_column_header(header_hbox, "", 30)  # Lock icon
	_create_column_header(header_hbox, "SERVER NAME", 300)
	_create_column_header(header_hbox, "MAP", 150)
	_create_column_header(header_hbox, "PLAYERS", 80)
	_create_column_header(header_hbox, "PING", 60)
	_create_column_header(header_hbox, "MODE", 100)

	# Server list scroll
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	server_list_container = VBoxContainer.new()
	server_list_container.add_theme_constant_override("separation", 2)
	scroll.add_child(server_list_container)

func _create_column_header(parent: Control, text: String, width: int):
	var label = Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 25)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	parent.add_child(label)

func _create_details_panel(parent: Control):
	details_panel = PanelContainer.new()
	details_panel.custom_minimum_size = Vector2(280, 0)
	parent.add_child(details_panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	details_panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	details_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.name = "DetailsContent"
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Header
	var header = Label.new()
	header.text = "SERVER DETAILS"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	vbox.add_child(header)

	# Placeholder message
	var placeholder = Label.new()
	placeholder.name = "Placeholder"
	placeholder.text = "Select a server to view details"
	placeholder.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(placeholder)

	# Server name
	var name_label = Label.new()
	name_label.name = "ServerName"
	name_label.text = ""
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.visible = false
	vbox.add_child(name_label)

	# Details grid
	var details_grid = GridContainer.new()
	details_grid.name = "DetailsGrid"
	details_grid.columns = 2
	details_grid.add_theme_constant_override("h_separation", 15)
	details_grid.add_theme_constant_override("v_separation", 8)
	details_grid.visible = false
	vbox.add_child(details_grid)

	_add_detail_row(details_grid, "Map:", "MapValue")
	_add_detail_row(details_grid, "Mode:", "ModeValue")
	_add_detail_row(details_grid, "Players:", "PlayersValue")
	_add_detail_row(details_grid, "Ping:", "PingValue")
	_add_detail_row(details_grid, "Wave:", "WaveValue")
	_add_detail_row(details_grid, "Difficulty:", "DifficultyValue")

	# Separator
	var sep = HSeparator.new()
	sep.name = "DetailsSeparator"
	sep.visible = false
	vbox.add_child(sep)

	# Player list
	var players_label = Label.new()
	players_label.name = "PlayersHeader"
	players_label.text = "Players in Server:"
	players_label.add_theme_font_size_override("font_size", 14)
	players_label.visible = false
	vbox.add_child(players_label)

	var players_list = VBoxContainer.new()
	players_list.name = "PlayersList"
	players_list.visible = false
	vbox.add_child(players_list)

	# Join button
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	join_button = Button.new()
	join_button.text = "JOIN SERVER"
	join_button.custom_minimum_size = Vector2(0, 45)
	join_button.disabled = true
	join_button.pressed.connect(_on_join_pressed)
	vbox.add_child(join_button)

	# Style join button
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.5, 0.2)
	btn_style.corner_radius_top_left = 6
	btn_style.corner_radius_top_right = 6
	btn_style.corner_radius_bottom_left = 6
	btn_style.corner_radius_bottom_right = 6
	join_button.add_theme_stylebox_override("normal", btn_style)

func _add_detail_row(parent: Control, label_text: String, value_name: String):
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	parent.add_child(label)

	var value = Label.new()
	value.name = value_name
	value.text = "-"
	value.add_theme_font_size_override("font_size", 12)
	parent.add_child(value)

func _create_footer(parent: Control):
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	parent.add_child(hbox)

	# Back button
	var back_btn = Button.new()
	back_btn.text = "BACK"
	back_btn.custom_minimum_size = Vector2(120, 45)
	back_btn.pressed.connect(func(): back_pressed.emit())
	hbox.add_child(back_btn)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	# Direct connect
	var direct_hbox = HBoxContainer.new()
	direct_hbox.add_theme_constant_override("separation", 10)
	hbox.add_child(direct_hbox)

	var ip_input = LineEdit.new()
	ip_input.name = "DirectIPInput"
	ip_input.placeholder_text = "IP:Port"
	ip_input.custom_minimum_size = Vector2(180, 0)
	direct_hbox.add_child(ip_input)

	var direct_btn = Button.new()
	direct_btn.text = "CONNECT"
	direct_btn.pressed.connect(func(): _on_direct_connect(ip_input.text))
	direct_hbox.add_child(direct_btn)

	# Create server button
	var create_btn = Button.new()
	create_btn.text = "CREATE SERVER"
	create_btn.custom_minimum_size = Vector2(150, 45)
	create_btn.pressed.connect(func(): create_server_requested.emit())
	hbox.add_child(create_btn)

func _connect_signals():
	if matchmaking_manager:
		if matchmaking_manager.has_signal("servers_received"):
			matchmaking_manager.servers_received.connect(_on_servers_received)
		if matchmaking_manager.has_signal("server_info_received"):
			matchmaking_manager.server_info_received.connect(_on_server_info_received)

func _exit_tree():
	# Disconnect signals to prevent memory leaks
	if matchmaking_manager:
		if matchmaking_manager.has_signal("servers_received") and matchmaking_manager.servers_received.is_connected(_on_servers_received):
			matchmaking_manager.servers_received.disconnect(_on_servers_received)
		if matchmaking_manager.has_signal("server_info_received") and matchmaking_manager.server_info_received.is_connected(_on_server_info_received):
			matchmaking_manager.server_info_received.disconnect(_on_server_info_received)

	# Clear data
	servers.clear()
	server_entries.clear()

func _process(delta):
	# Auto-refresh
	if visible and not is_refreshing:
		auto_refresh_timer += delta
		if auto_refresh_timer >= auto_refresh_interval:
			auto_refresh_timer = 0.0
			_request_servers()

# ============================================
# SERVER LIST
# ============================================

func _request_servers():
	is_refreshing = true
	refresh_button.text = "REFRESHING..."
	refresh_button.disabled = true

	# First try backend API
	if backend:
		var filters = _build_backend_filters()
		backend.get_servers(filters, func(response):
			if response.success and response.has("servers"):
				var server_list = _convert_backend_servers(response.servers)
				_on_servers_received(server_list)
			elif response.success and response is Array:
				_on_servers_received(_convert_backend_servers(response))
			else:
				# Fallback to test data
				_on_servers_received(_get_test_servers())
		)
		return

	# Try matchmaking manager
	if matchmaking_manager and matchmaking_manager.has_method("request_server_list"):
		matchmaking_manager.request_server_list()
	else:
		# Use test data
		await get_tree().create_timer(0.5).timeout
		_on_servers_received(_get_test_servers())

func _build_backend_filters() -> Dictionary:
	var filters = {}

	if hide_empty_check and hide_empty_check.button_pressed:
		filters["hideEmpty"] = true
	if hide_full_check and hide_full_check.button_pressed:
		filters["hideFull"] = true

	# Map filter
	if map_filter and map_filter.selected > 0:
		var map_names = ["", "warehouse", "hospital", "subway", "mansion", "military_base", "shopping_mall"]
		if map_filter.selected < map_names.size():
			filters["map"] = map_names[map_filter.selected]

	# Mode filter
	if gamemode_filter and gamemode_filter.selected > 0:
		var mode_names = ["", "survival", "objective", "endless"]
		if gamemode_filter.selected < mode_names.size():
			filters["gameMode"] = mode_names[gamemode_filter.selected]

	return filters

func _convert_backend_servers(backend_servers) -> Array:
	var result = []

	for s in backend_servers:
		var server = {
			"id": str(s.get("id", 0)),
			"name": s.get("name", "Unknown Server"),
			"ip": s.get("ipAddress", "0.0.0.0"),
			"port": s.get("port", 27015),
			"map": s.get("currentMap", "warehouse"),
			"gamemode": s.get("gameMode", "survival"),
			"current_players": s.get("currentPlayers", 0),
			"max_players": s.get("maxPlayers", 8),
			"ping": s.get("ping", 50),
			"has_password": s.get("hasPassword", false),
			"current_wave": s.get("currentWave", 1),
			"difficulty": s.get("difficulty", "Normal"),
			"region": s.get("region", ""),
			"players": s.get("players", [])
		}

		# Extract player names if players is array of objects
		if server.players is Array and server.players.size() > 0:
			if server.players[0] is Dictionary:
				var names = []
				for p in server.players:
					names.append(p.get("username", "Player"))
				server.players = names

		result.append(server)

	return result

func _on_servers_received(server_list: Array):
	servers = server_list
	is_refreshing = false
	refresh_button.text = "REFRESH"
	refresh_button.disabled = false

	_apply_filters()

func _apply_filters():
	filtered_servers.clear()

	var name_query = name_filter.text.to_lower()
	var map_index = map_filter.selected
	var mode_index = gamemode_filter.selected

	for server in servers:
		# Name filter
		if not name_query.is_empty():
			if not server.name.to_lower().contains(name_query):
				continue

		# Map filter
		if map_index > 0:
			var map_names = ["", "warehouse", "hospital", "subway", "mansion", "military_base", "shopping_mall"]
			if server.map != map_names[map_index]:
				continue

		# Mode filter
		if mode_index > 0:
			var mode_names = ["", "survival", "objective", "endless"]
			if server.gamemode != mode_names[mode_index]:
				continue

		# Hide full
		if hide_full_check.button_pressed:
			if server.current_players >= server.max_players:
				continue

		# Hide empty
		if hide_empty_check.button_pressed:
			if server.current_players == 0:
				continue

		# Hide password
		if hide_password_check.button_pressed:
			if server.has_password:
				continue

		filtered_servers.append(server)

	_display_servers()

func _display_servers():
	# Clear existing
	for child in server_list_container.get_children():
		child.queue_free()
	server_entries.clear()

	# Update count
	var count_label = get_node_or_null("VBoxContainer/HBoxContainer/ServerCount")
	if count_label:
		count_label.text = "%d servers found" % filtered_servers.size()

	# Create entries
	var displayed = 0
	for server in filtered_servers:
		if displayed >= max_servers_displayed:
			break

		var entry = _create_server_entry(server)
		server_list_container.add_child(entry)
		server_entries.append(entry)
		displayed += 1

func _create_server_entry(server: Dictionary) -> Control:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 35)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)

	# Store server data
	panel.set_meta("server_data", server)

	# Make clickable
	var button = Button.new()
	button.flat = true
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.pressed.connect(func(): _on_server_clicked(server))
	panel.add_child(button)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(hbox)

	# Lock icon
	var lock = Label.new()
	lock.text = "[L]" if server.has_password else ""
	lock.custom_minimum_size = Vector2(30, 0)
	lock.add_theme_font_size_override("font_size", 12)
	lock.add_theme_color_override("font_color", Color(1, 0.6, 0.3))
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lock)

	# Server name
	var name_label = Label.new()
	name_label.text = server.name
	name_label.custom_minimum_size = Vector2(300, 0)
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_label)

	# Map
	var map_label = Label.new()
	map_label.text = server.map.capitalize()
	map_label.custom_minimum_size = Vector2(150, 0)
	map_label.add_theme_font_size_override("font_size", 13)
	map_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	map_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(map_label)

	# Players
	var players_label = Label.new()
	players_label.text = "%d/%d" % [server.current_players, server.max_players]
	players_label.custom_minimum_size = Vector2(80, 0)
	players_label.add_theme_font_size_override("font_size", 13)
	var players_color = Color(0.3, 0.8, 0.3)
	if server.current_players >= server.max_players:
		players_color = Color(0.8, 0.3, 0.3)
	elif server.current_players > server.max_players * 0.7:
		players_color = Color(0.8, 0.8, 0.3)
	players_label.add_theme_color_override("font_color", players_color)
	players_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(players_label)

	# Ping
	var ping_label = Label.new()
	ping_label.text = "%dms" % server.ping
	ping_label.custom_minimum_size = Vector2(60, 0)
	ping_label.add_theme_font_size_override("font_size", 13)
	var ping_color = Color(0.3, 0.8, 0.3)
	if server.ping > 150:
		ping_color = Color(0.8, 0.3, 0.3)
	elif server.ping > 80:
		ping_color = Color(0.8, 0.8, 0.3)
	ping_label.add_theme_color_override("font_color", ping_color)
	ping_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(ping_label)

	# Mode
	var mode_label = Label.new()
	mode_label.text = server.gamemode.capitalize()
	mode_label.custom_minimum_size = Vector2(100, 0)
	mode_label.add_theme_font_size_override("font_size", 13)
	mode_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(mode_label)

	return panel

func _on_server_clicked(server: Dictionary):
	selected_server = server
	server_selected.emit(server)

	# Highlight selected
	for entry in server_entries:
		var style = entry.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			if entry.get_meta("server_data") == server:
				style.bg_color = Color(0.2, 0.25, 0.35)
			else:
				style.bg_color = Color(0.12, 0.12, 0.15)

	# Update details panel
	_show_server_details(server)

func _show_server_details(server: Dictionary):
	var content = details_panel.get_node_or_null("MarginContainer/DetailsContent")
	if not content:
		return

	# Hide placeholder
	var placeholder = content.get_node_or_null("Placeholder")
	if placeholder:
		placeholder.visible = false

	# Show server name
	var name_label = content.get_node_or_null("ServerName")
	if name_label:
		name_label.text = server.name
		name_label.visible = true

	# Show details grid
	var grid = content.get_node_or_null("DetailsGrid")
	if grid:
		grid.visible = true
		_set_detail_value(grid, "MapValue", server.map.capitalize())
		_set_detail_value(grid, "ModeValue", server.gamemode.capitalize())
		_set_detail_value(grid, "PlayersValue", "%d/%d" % [server.current_players, server.max_players])
		_set_detail_value(grid, "PingValue", "%dms" % server.ping)
		_set_detail_value(grid, "WaveValue", str(server.get("current_wave", 1)))
		_set_detail_value(grid, "DifficultyValue", server.get("difficulty", "Normal"))

	# Show separator
	var sep = content.get_node_or_null("DetailsSeparator")
	if sep:
		sep.visible = true

	# Show players list
	var players_header = content.get_node_or_null("PlayersHeader")
	var players_list = content.get_node_or_null("PlayersList")
	if players_header and players_list:
		players_header.visible = true
		players_list.visible = true

		# Clear and populate
		for child in players_list.get_children():
			child.queue_free()

		var player_names = server.get("players", [])
		for player_name in player_names:
			var player_label = Label.new()
			player_label.text = "• " + player_name
			player_label.add_theme_font_size_override("font_size", 12)
			player_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
			players_list.add_child(player_label)

	# Enable join button
	join_button.disabled = false

func _set_detail_value(grid: Control, value_name: String, text: String):
	var value = grid.get_node_or_null(value_name)
	if value:
		value.text = text

# ============================================
# ACTIONS
# ============================================

func _on_refresh_pressed():
	auto_refresh_timer = 0.0
	_request_servers()
	refresh_requested.emit()

func _on_join_pressed():
	if selected_server.is_empty():
		return

	if selected_server.has_password:
		# Would show password dialog
		_request_join_with_password(selected_server, "")
	else:
		join_requested.emit(selected_server)

func _request_join_with_password(server: Dictionary, password: String):
	# Would validate password
	join_requested.emit(server)

func _on_direct_connect(address: String):
	if address.is_empty():
		return

	var parts = address.split(":")
	var ip = parts[0]
	var port = int(parts[1]) if parts.size() > 1 else 27015

	var server_info = {
		"ip": ip,
		"port": port,
		"name": "Direct Connect",
		"map": "Unknown",
		"gamemode": "Unknown",
		"current_players": 0,
		"max_players": 8,
		"ping": 0,
		"has_password": false
	}

	join_requested.emit(server_info)

func _reset_filters():
	name_filter.text = ""
	map_filter.select(0)
	gamemode_filter.select(0)
	hide_full_check.button_pressed = false
	hide_empty_check.button_pressed = false
	hide_password_check.button_pressed = false
	_apply_filters()

# ============================================
# TEST DATA
# ============================================

func _get_test_servers() -> Array:
	return [
		{
			"id": "1",
			"name": "Official Server #1",
			"ip": "192.168.1.1",
			"port": 27015,
			"map": "warehouse",
			"gamemode": "survival",
			"current_players": 5,
			"max_players": 8,
			"ping": 25,
			"has_password": false,
			"current_wave": 3,
			"difficulty": "Normal",
			"players": ["Player1", "Player2", "Player3", "Player4", "Player5"]
		},
		{
			"id": "2",
			"name": "[EU] Hardcore Survival",
			"ip": "192.168.1.2",
			"port": 27015,
			"map": "hospital",
			"gamemode": "survival",
			"current_players": 6,
			"max_players": 6,
			"ping": 45,
			"has_password": false,
			"current_wave": 7,
			"difficulty": "Hard",
			"players": ["Pro1", "Pro2", "Pro3", "Pro4", "Pro5", "Pro6"]
		},
		{
			"id": "3",
			"name": "Private Chill Server",
			"ip": "192.168.1.3",
			"port": 27015,
			"map": "mansion",
			"gamemode": "endless",
			"current_players": 2,
			"max_players": 4,
			"ping": 60,
			"has_password": true,
			"current_wave": 15,
			"difficulty": "Easy",
			"players": ["Chiller1", "Chiller2"]
		},
		{
			"id": "4",
			"name": "[US] Noobs Welcome",
			"ip": "192.168.1.4",
			"port": 27015,
			"map": "subway",
			"gamemode": "objective",
			"current_players": 3,
			"max_players": 8,
			"ping": 90,
			"has_password": false,
			"current_wave": 1,
			"difficulty": "Easy",
			"players": ["Newbie1", "Newbie2", "Newbie3"]
		},
		{
			"id": "5",
			"name": "Empty Test Server",
			"ip": "192.168.1.5",
			"port": 27015,
			"map": "military_base",
			"gamemode": "survival",
			"current_players": 0,
			"max_players": 10,
			"ping": 15,
			"has_password": false,
			"current_wave": 0,
			"difficulty": "Normal",
			"players": []
		}
	]

# ============================================
# PUBLIC API
# ============================================

func refresh():
	"""Manual refresh"""
	_on_refresh_pressed()

func add_server(server_info: Dictionary):
	"""Add a server to the list"""
	servers.append(server_info)
	_apply_filters()

func clear_servers():
	"""Clear all servers"""
	servers.clear()
	filtered_servers.clear()
	_display_servers()
