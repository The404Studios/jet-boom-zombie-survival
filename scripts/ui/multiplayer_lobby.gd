extends Control
class_name MultiplayerLobby

# Pre-game lobby for multiplayer matches
# Shows connected players, class selection, map voting, and ready status

signal game_started
signal lobby_closed
signal player_kicked(peer_id: int)

# UI Panels
var player_list_panel: Control
var class_selection_panel: Control
var map_vote_panel: Control
var chat_panel: Control
var settings_panel: Control

# Player list elements
var player_list_container: VBoxContainer
var player_entries: Dictionary = {}  # peer_id -> UI node

# Map voting
var map_vote_container: GridContainer
var map_buttons: Dictionary = {}  # map_id -> button
var map_votes: Dictionary = {}  # map_id -> vote count
var voted_map: String = ""

# Chat
var chat_messages: RichTextLabel
var chat_input: LineEdit

# Ready system
var ready_players: Dictionary = {}  # peer_id -> is_ready
var countdown_timer: float = -1.0
var countdown_label: Label

# Settings
@export var min_players_to_start: int = 1
@export var countdown_duration: float = 5.0
@export var max_chat_messages: int = 100

# Available maps
var available_maps: Array = [
	{"id": "warehouse", "name": "Warehouse", "max_players": 8, "difficulty": "Easy"},
	{"id": "hospital", "name": "Abandoned Hospital", "max_players": 6, "difficulty": "Medium"},
	{"id": "subway", "name": "Subway Station", "max_players": 8, "difficulty": "Medium"},
	{"id": "mansion", "name": "Haunted Mansion", "max_players": 4, "difficulty": "Hard"},
	{"id": "military_base", "name": "Military Base", "max_players": 10, "difficulty": "Hard"},
	{"id": "shopping_mall", "name": "Shopping Mall", "max_players": 8, "difficulty": "Medium"}
]

# Network references
var network_manager: Node = null
var websocket_hub: Node = null
var backend: Node = null
var is_host: bool = false
var server_info: Dictionary = {}

func _ready():
	network_manager = get_node_or_null("/root/NetworkManager")
	websocket_hub = get_node_or_null("/root/WebSocketHub")
	backend = get_node_or_null("/root/Backend")

	_create_ui()
	_connect_signals()
	_connect_websocket_signals()

	# Check if we're the host
	if multiplayer.has_multiplayer_peer():
		is_host = multiplayer.is_server()

func _create_ui():
	# Main background
	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main layout - horizontal split
	var main_hbox = HBoxContainer.new()
	main_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_hbox.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 20)
	main_hbox.add_theme_constant_override("separation", 15)
	add_child(main_hbox)

	# Left column - Player list and chat
	var left_vbox = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.size_flags_stretch_ratio = 0.4
	left_vbox.add_theme_constant_override("separation", 15)
	main_hbox.add_child(left_vbox)

	# Player list panel
	_create_player_list_panel(left_vbox)

	# Chat panel
	_create_chat_panel(left_vbox)

	# Right column - Map selection and ready
	var right_vbox = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_stretch_ratio = 0.6
	right_vbox.add_theme_constant_override("separation", 15)
	main_hbox.add_child(right_vbox)

	# Map voting panel
	_create_map_vote_panel(right_vbox)

	# Class selection quick access
	_create_class_quick_panel(right_vbox)

	# Ready/Start buttons
	_create_action_buttons(right_vbox)

	# Countdown overlay
	_create_countdown_overlay()

func _create_player_list_panel(parent: Control):
	player_list_panel = PanelContainer.new()
	player_list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_list_panel.size_flags_stretch_ratio = 0.6
	parent.add_child(player_list_panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	player_list_panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	player_list_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Header
	var header = Label.new()
	header.text = "PLAYERS"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	vbox.add_child(header)

	# Scroll container
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	player_list_container = VBoxContainer.new()
	player_list_container.add_theme_constant_override("separation", 8)
	scroll.add_child(player_list_container)

func _create_chat_panel(parent: Control):
	chat_panel = PanelContainer.new()
	chat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_panel.size_flags_stretch_ratio = 0.4
	parent.add_child(chat_panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	chat_panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	chat_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)

	# Chat messages
	chat_messages = RichTextLabel.new()
	chat_messages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_messages.bbcode_enabled = true
	chat_messages.scroll_following = true
	chat_messages.add_theme_font_size_override("normal_font_size", 12)
	vbox.add_child(chat_messages)

	# Chat input
	var input_hbox = HBoxContainer.new()
	input_hbox.add_theme_constant_override("separation", 5)
	vbox.add_child(input_hbox)

	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Type a message..."
	chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_input.text_submitted.connect(_on_chat_submitted)
	input_hbox.add_child(chat_input)

	var send_btn = Button.new()
	send_btn.text = "Send"
	send_btn.pressed.connect(func(): _on_chat_submitted(chat_input.text))
	input_hbox.add_child(send_btn)

func _create_map_vote_panel(parent: Control):
	map_vote_panel = PanelContainer.new()
	map_vote_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(map_vote_panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	map_vote_panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	map_vote_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)

	# Header
	var header = Label.new()
	header.text = "SELECT MAP"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	vbox.add_child(header)

	# Map grid
	map_vote_container = GridContainer.new()
	map_vote_container.columns = 3
	map_vote_container.add_theme_constant_override("h_separation", 10)
	map_vote_container.add_theme_constant_override("v_separation", 10)
	vbox.add_child(map_vote_container)

	# Create map buttons
	for map_data in available_maps:
		_create_map_button(map_data)

func _create_map_button(map_data: Dictionary):
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(180, 100)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Button content
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)

	var name_label = Label.new()
	name_label.text = map_data.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(name_label)

	var info_label = Label.new()
	info_label.text = "%s | %d players" % [map_data.difficulty, map_data.max_players]
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_font_size_override("font_size", 11)
	info_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(info_label)

	var vote_label = Label.new()
	vote_label.name = "VoteCount"
	vote_label.text = "0 votes"
	vote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vote_label.add_theme_font_size_override("font_size", 12)
	vote_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	vbox.add_child(vote_label)

	btn.add_child(vbox)
	btn.pressed.connect(func(): _on_map_voted(map_data.id))

	map_vote_container.add_child(btn)
	map_buttons[map_data.id] = btn
	map_votes[map_data.id] = 0

func _create_class_quick_panel(parent: Control):
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 80)
	parent.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	margin.add_child(hbox)

	# Current class display
	var class_info = VBoxContainer.new()
	class_info.add_theme_constant_override("separation", 5)
	hbox.add_child(class_info)

	var class_label = Label.new()
	class_label.name = "CurrentClassLabel"
	class_label.text = "Selected Class: Survivor"
	class_label.add_theme_font_size_override("font_size", 16)
	class_label.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	class_info.add_child(class_label)

	var class_desc = Label.new()
	class_desc.name = "ClassDescription"
	class_desc.text = "Balanced class with no specialization"
	class_desc.add_theme_font_size_override("font_size", 12)
	class_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	class_info.add_child(class_desc)

	# Spacer
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	# Change class button
	var change_btn = Button.new()
	change_btn.text = "CHANGE CLASS"
	change_btn.custom_minimum_size = Vector2(150, 40)
	change_btn.pressed.connect(_on_change_class_pressed)
	hbox.add_child(change_btn)

func _create_action_buttons(parent: Control):
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	parent.add_child(hbox)

	# Leave button
	var leave_btn = Button.new()
	leave_btn.text = "LEAVE LOBBY"
	leave_btn.custom_minimum_size = Vector2(150, 50)
	leave_btn.pressed.connect(_on_leave_pressed)
	hbox.add_child(leave_btn)

	# Ready button
	var ready_btn = Button.new()
	ready_btn.name = "ReadyButton"
	ready_btn.text = "READY"
	ready_btn.custom_minimum_size = Vector2(200, 50)
	ready_btn.pressed.connect(_on_ready_pressed)
	hbox.add_child(ready_btn)

	# Style ready button
	var ready_style = StyleBoxFlat.new()
	ready_style.bg_color = Color(0.2, 0.6, 0.2)
	ready_style.corner_radius_top_left = 6
	ready_style.corner_radius_top_right = 6
	ready_style.corner_radius_bottom_left = 6
	ready_style.corner_radius_bottom_right = 6
	ready_btn.add_theme_stylebox_override("normal", ready_style)

	# Start button (host only)
	var start_btn = Button.new()
	start_btn.name = "StartButton"
	start_btn.text = "START GAME"
	start_btn.custom_minimum_size = Vector2(200, 50)
	start_btn.pressed.connect(_on_start_pressed)
	start_btn.visible = is_host
	hbox.add_child(start_btn)

func _create_countdown_overlay():
	var overlay = ColorRect.new()
	overlay.name = "CountdownOverlay"
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)

	var starting_label = Label.new()
	starting_label.text = "GAME STARTING IN"
	starting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	starting_label.add_theme_font_size_override("font_size", 32)
	starting_label.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	vbox.add_child(starting_label)

	countdown_label = Label.new()
	countdown_label.name = "CountdownNumber"
	countdown_label.text = "5"
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.add_theme_font_size_override("font_size", 96)
	countdown_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(countdown_label)

func _connect_signals():
	if network_manager:
		if network_manager.has_signal("player_connected"):
			network_manager.player_connected.connect(_on_player_connected)
		if network_manager.has_signal("player_disconnected"):
			network_manager.player_disconnected.connect(_on_player_disconnected)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _connect_websocket_signals():
	if websocket_hub:
		if websocket_hub.has_signal("chat_message_received"):
			websocket_hub.chat_message_received.connect(_on_websocket_chat_message)
		if websocket_hub.has_signal("game_state_received"):
			websocket_hub.game_state_received.connect(_on_websocket_game_state)
		if websocket_hub.has_signal("wave_started"):
			websocket_hub.wave_started.connect(_on_websocket_wave_started)
		if websocket_hub.has_signal("notification_received"):
			websocket_hub.notification_received.connect(_on_websocket_notification)

func _on_websocket_chat_message(player_id: int, username: String, message: String):
	_add_chat_message("[color=white]%s:[/color] %s" % [username, message])

func _on_websocket_game_state(state: Dictionary):
	# Update lobby state from server
	if state.has("players"):
		for player in state.players:
			var peer_id = player.get("id", 0)
			if not player_entries.has(peer_id):
				add_player(peer_id, player)

func _on_websocket_wave_started(wave_number: int, _zombie_count: int):
	_add_chat_message("[color=yellow]Wave %d starting![/color]" % wave_number)

func _on_websocket_notification(type: String, message: String):
	_add_chat_message("[color=cyan][%s] %s[/color]" % [type, message])

func _process(delta):
	# Handle countdown
	if countdown_timer > 0:
		countdown_timer -= delta
		countdown_label.text = str(int(countdown_timer) + 1)

		if countdown_timer <= 0:
			_start_game()

# ============================================
# PLAYER MANAGEMENT
# ============================================

func add_player(peer_id: int, player_data: Dictionary):
	"""Add a player to the lobby"""
	if player_entries.has(peer_id):
		return

	var entry = _create_player_entry(peer_id, player_data)
	player_list_container.add_child(entry)
	player_entries[peer_id] = entry
	ready_players[peer_id] = false

	_add_chat_message("[color=gray]%s joined the lobby[/color]" % player_data.get("name", "Player"))

func remove_player(peer_id: int):
	"""Remove a player from the lobby"""
	if not player_entries.has(peer_id):
		return

	var entry = player_entries[peer_id]
	entry.queue_free()
	player_entries.erase(peer_id)
	ready_players.erase(peer_id)

	_add_chat_message("[color=gray]A player left the lobby[/color]")
	_check_ready_state()

func _create_player_entry(peer_id: int, player_data: Dictionary) -> Control:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 50)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.18)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	panel.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	margin.add_child(hbox)

	# Host indicator
	var local_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var is_this_host = (peer_id == 1)  # Server is always ID 1
	var is_local = (peer_id == local_id)

	if is_this_host:
		var host_label = Label.new()
		host_label.text = "[HOST]"
		host_label.add_theme_font_size_override("font_size", 10)
		host_label.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
		hbox.add_child(host_label)

	# Player name
	var name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = player_data.get("name", "Player %d" % peer_id)
	if is_local:
		name_label.text += " (You)"
	name_label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(name_label)

	# Class indicator
	var class_label = Label.new()
	class_label.name = "ClassLabel"
	class_label.text = player_data.get("class", "Survivor")
	class_label.add_theme_font_size_override("font_size", 12)
	class_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.8))
	hbox.add_child(class_label)

	# Spacer
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	# Ready indicator
	var ready_indicator = Label.new()
	ready_indicator.name = "ReadyIndicator"
	ready_indicator.text = "NOT READY"
	ready_indicator.add_theme_font_size_override("font_size", 12)
	ready_indicator.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3))
	hbox.add_child(ready_indicator)

	# Kick button (host only, not for self)
	if is_host and not is_local and not is_this_host:
		var kick_btn = Button.new()
		kick_btn.text = "X"
		kick_btn.custom_minimum_size = Vector2(30, 30)
		kick_btn.pressed.connect(func(): _kick_player(peer_id))
		hbox.add_child(kick_btn)

	return panel

func update_player_ready(peer_id: int, is_ready: bool):
	"""Update a player's ready status"""
	ready_players[peer_id] = is_ready

	if player_entries.has(peer_id):
		var entry = player_entries[peer_id]
		var indicator = entry.get_node_or_null("MarginContainer/HBoxContainer/ReadyIndicator")
		if indicator:
			indicator.text = "READY" if is_ready else "NOT READY"
			indicator.add_theme_color_override("font_color",
				Color(0.3, 0.8, 0.3) if is_ready else Color(0.8, 0.3, 0.3))

	_check_ready_state()

func update_player_class(peer_id: int, class_id: String):
	"""Update a player's class display"""
	if player_entries.has(peer_id):
		var entry = player_entries[peer_id]
		var class_label = entry.get_node_or_null("MarginContainer/HBoxContainer/ClassLabel")
		if class_label:
			class_label.text = class_id.capitalize()

# ============================================
# MAP VOTING
# ============================================

func _on_map_voted(map_id: String):
	# Unvote previous
	if not voted_map.is_empty():
		map_votes[voted_map] -= 1
		_update_map_vote_display(voted_map)

	# Vote new
	voted_map = map_id
	map_votes[map_id] += 1
	_update_map_vote_display(map_id)

	# Highlight selected
	for mid in map_buttons:
		var btn = map_buttons[mid]
		if mid == map_id:
			btn.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
		else:
			btn.remove_theme_color_override("font_color")

	# Sync to network
	if multiplayer.has_multiplayer_peer():
		rpc("_sync_map_vote", multiplayer.get_unique_id(), map_id)

func _update_map_vote_display(map_id: String):
	if map_buttons.has(map_id):
		var btn = map_buttons[map_id]
		var vote_label = btn.get_node_or_null("VBoxContainer/VoteCount")
		if vote_label:
			vote_label.text = "%d vote%s" % [map_votes[map_id], "s" if map_votes[map_id] != 1 else ""]

@rpc("any_peer", "reliable")
func _sync_map_vote(peer_id: int, map_id: String):
	# Server processes vote
	if multiplayer.is_server():
		# Update vote count and broadcast
		rpc("_receive_map_votes", map_votes)

@rpc("authority", "reliable")
func _receive_map_votes(votes: Dictionary):
	map_votes = votes
	for map_id in map_votes:
		_update_map_vote_display(map_id)

func get_winning_map() -> String:
	"""Get the map with most votes"""
	var max_votes = 0
	var winner = available_maps[0].id

	for map_id in map_votes:
		if map_votes[map_id] > max_votes:
			max_votes = map_votes[map_id]
			winner = map_id

	return winner

# ============================================
# CHAT
# ============================================

func _on_chat_submitted(text: String):
	if text.is_empty():
		return

	chat_input.text = ""

	var local_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var player_name = "You"

	# Get player name from backend if available
	if backend and backend.current_player:
		player_name = backend.current_player.get("username", "You")

	# Send via WebSocket hub first
	if websocket_hub and websocket_hub.is_connected:
		websocket_hub.send_chat_message(text)
		_add_chat_message("[color=cyan]%s:[/color] %s" % [player_name, text])
	# Fallback to peer-to-peer
	elif multiplayer.has_multiplayer_peer():
		rpc("_receive_chat_message", local_id, player_name, text)
	else:
		_add_chat_message("[color=cyan]%s:[/color] %s" % [player_name, text])

@rpc("any_peer", "reliable")
func _receive_chat_message(sender_id: int, sender_name: String, message: String):
	var local_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var color = "cyan" if sender_id == local_id else "white"
	_add_chat_message("[color=%s]%s:[/color] %s" % [color, sender_name, message])

func _add_chat_message(bbcode_text: String):
	chat_messages.append_text(bbcode_text + "\n")

	# Limit messages
	# Note: Would need more complex logic to actually remove old messages

# ============================================
# READY SYSTEM
# ============================================

func _on_ready_pressed():
	var local_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var is_ready = not ready_players.get(local_id, false)

	update_player_ready(local_id, is_ready)

	# Update button text
	var ready_btn = get_node_or_null("HBoxContainer/VBoxContainer/HBoxContainer/ReadyButton")
	if ready_btn:
		ready_btn.text = "UNREADY" if is_ready else "READY"

	# Sync to network
	if multiplayer.has_multiplayer_peer():
		rpc("_sync_ready_state", local_id, is_ready)

@rpc("any_peer", "reliable")
func _sync_ready_state(peer_id: int, is_ready: bool):
	update_player_ready(peer_id, is_ready)

func _check_ready_state():
	"""Check if all players are ready to start countdown"""
	if not is_host:
		return

	var total_players = player_entries.size()
	var ready_count = 0

	for peer_id in ready_players:
		if ready_players[peer_id]:
			ready_count += 1

	# Check if enough players and all ready
	if total_players >= min_players_to_start and ready_count == total_players:
		_start_countdown()

func _start_countdown():
	countdown_timer = countdown_duration

	var overlay = get_node_or_null("CountdownOverlay")
	if overlay:
		overlay.visible = true

	# Sync to clients
	if multiplayer.has_multiplayer_peer():
		rpc("_sync_countdown", countdown_duration)

@rpc("authority", "reliable")
func _sync_countdown(duration: float):
	countdown_timer = duration
	var overlay = get_node_or_null("CountdownOverlay")
	if overlay:
		overlay.visible = true

# ============================================
# GAME START
# ============================================

func _on_start_pressed():
	if not is_host:
		return

	_start_countdown()

func _start_game():
	var selected_map = get_winning_map()

	# Notify all clients
	if multiplayer.has_multiplayer_peer():
		rpc("_game_starting", selected_map)

	game_started.emit()

@rpc("authority", "reliable")
func _game_starting(map_id: String):
	# All clients receive this
	game_started.emit()

# ============================================
# OTHER ACTIONS
# ============================================

func _on_leave_pressed():
	# Disconnect from server
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null

	lobby_closed.emit()

func _on_change_class_pressed():
	# Would show class selection UI
	# For now, emit signal that parent can handle
	pass

func _kick_player(peer_id: int):
	if not is_host:
		return

	player_kicked.emit(peer_id)

	# Disconnect the peer
	if multiplayer.has_multiplayer_peer():
		# Would need to implement kick on server
		pass

# ============================================
# NETWORK CALLBACKS
# ============================================

func _on_peer_connected(peer_id: int):
	# Request player info
	pass

func _on_peer_disconnected(peer_id: int):
	remove_player(peer_id)

func _on_player_connected(peer_id: int, player_data: Dictionary):
	add_player(peer_id, player_data)

func _on_player_disconnected(peer_id: int):
	remove_player(peer_id)

# ============================================
# PUBLIC API
# ============================================

func refresh_players():
	"""Refresh player list from network manager"""
	if not network_manager:
		return

	# Clear existing
	for peer_id in player_entries.keys():
		remove_player(peer_id)

	# Add current players
	if "players" in network_manager:
		for peer_id in network_manager.players:
			add_player(peer_id, network_manager.players[peer_id])

func set_available_maps(maps: Array):
	"""Set custom map list"""
	available_maps = maps

	# Rebuild map buttons
	for child in map_vote_container.get_children():
		child.queue_free()
	map_buttons.clear()
	map_votes.clear()

	for map_data in available_maps:
		_create_map_button(map_data)

func set_server_info(info: Dictionary):
	"""Set server info when joining a server"""
	server_info = info

	# Update UI with server info
	var server_name = info.get("name", "Game Server")
	_add_chat_message("[color=gray]Connected to %s[/color]" % server_name)

	# Pre-select map if specified
	var map_id = info.get("map", "")
	if not map_id.is_empty() and map_buttons.has(map_id):
		_on_map_voted(map_id)

func set_as_host(hosting: bool):
	"""Set whether this client is the host"""
	is_host = hosting

	# Update start button visibility
	var start_btn = get_node_or_null("HBoxContainer/VBoxContainer/HBoxContainer/StartButton")
	if start_btn:
		start_btn.visible = is_host

	if is_host:
		_add_chat_message("[color=yellow]You are the host[/color]")

func leave_server():
	"""Leave the current server"""
	if websocket_hub:
		websocket_hub.leave_server()

	_on_leave_pressed()
