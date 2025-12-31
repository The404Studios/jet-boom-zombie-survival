extends Control
class_name GlobalChatPanel

signal message_sent(message: String)

# UI Elements
var chat_messages: RichTextLabel
var chat_input: LineEdit
var send_button: Button
var channel_tabs: TabBar
var minimize_button: Button

# State
var is_minimized: bool = false
var current_channel: String = "global"
var max_messages: int = 100

# Backend integration
var websocket_hub: Node = null
var backend: Node = null

func _ready():
	backend = get_node_or_null("/root/Backend")
	websocket_hub = get_node_or_null("/root/WebSocketHub")

	_create_ui()
	_connect_signals()

func _create_ui():
	custom_minimum_size = Vector2(350, 250)

	# Main panel
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.9)
	style.border_color = Color(0.2, 0.2, 0.25)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)

	# Header with channel tabs and minimize button
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 5)
	vbox.add_child(header)

	channel_tabs = TabBar.new()
	channel_tabs.add_tab("Global")
	channel_tabs.add_tab("Party")
	channel_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(channel_tabs)

	minimize_button = Button.new()
	minimize_button.text = "_"
	minimize_button.custom_minimum_size = Vector2(25, 25)
	header.add_child(minimize_button)

	# Chat messages area
	chat_messages = RichTextLabel.new()
	chat_messages.name = "Messages"
	chat_messages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_messages.bbcode_enabled = true
	chat_messages.scroll_following = true
	chat_messages.add_theme_font_size_override("normal_font_size", 12)
	vbox.add_child(chat_messages)

	# Input area
	var input_hbox = HBoxContainer.new()
	input_hbox.add_theme_constant_override("separation", 5)
	vbox.add_child(input_hbox)

	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Type a message..."
	chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_hbox.add_child(chat_input)

	send_button = Button.new()
	send_button.text = "Send"
	send_button.custom_minimum_size = Vector2(60, 30)
	input_hbox.add_child(send_button)

func _connect_signals():
	if send_button:
		send_button.pressed.connect(_on_send_pressed)
	if chat_input:
		chat_input.text_submitted.connect(func(_text): _on_send_pressed())
	if channel_tabs:
		channel_tabs.tab_changed.connect(_on_channel_changed)
	if minimize_button:
		minimize_button.pressed.connect(_on_minimize_pressed)

	# Connect to WebSocket chat messages
	if websocket_hub:
		if websocket_hub.has_signal("chat_message_received"):
			websocket_hub.chat_message_received.connect(_on_chat_message_received)
		if websocket_hub.has_signal("connected"):
			websocket_hub.connected.connect(_on_websocket_connected)

func _on_send_pressed():
	var text = chat_input.text.strip_edges()
	if text.is_empty():
		return

	chat_input.text = ""

	# Get username
	var username = "Guest"
	if backend and backend.current_player:
		username = backend.current_player.get("username", "Guest")

	# Send via WebSocket
	if websocket_hub and websocket_hub.is_connected:
		if current_channel == "global":
			websocket_hub.send_chat_message(text)
		else:
			websocket_hub.send_party_chat_message(text)

	# Show locally immediately
	_add_message(username, text, true)
	message_sent.emit(text)

func _on_chat_message_received(player_id: int, username: String, message: String):
	# Don't duplicate our own messages
	var our_id = 0
	if backend and backend.current_player:
		our_id = backend.current_player.get("id", 0)

	if player_id != our_id:
		_add_message(username, message, false)

func _add_message(username: String, message: String, is_local: bool):
	var color = "cyan" if is_local else "white"
	var formatted = "[color=%s]%s:[/color] %s" % [color, username, message]
	chat_messages.append_text(formatted + "\n")

	# Limit message count by clearing if too long
	var lines = chat_messages.text.count("\n")
	if lines > max_messages:
		# Simple approach: just show a limit message
		pass

func add_system_message(message: String):
	chat_messages.append_text("[color=yellow][System] %s[/color]\n" % message)

func _on_channel_changed(tab_index: int):
	match tab_index:
		0:
			current_channel = "global"
		1:
			current_channel = "party"

	# Could load channel history here
	chat_messages.clear()
	add_system_message("Switched to %s chat" % current_channel.capitalize())

func _on_minimize_pressed():
	is_minimized = not is_minimized

	if is_minimized:
		# Collapse to just the header
		custom_minimum_size = Vector2(350, 35)
		chat_messages.visible = false
		chat_input.visible = false
		send_button.visible = false
		minimize_button.text = "+"
	else:
		# Expand
		custom_minimum_size = Vector2(350, 250)
		chat_messages.visible = true
		chat_input.visible = true
		send_button.visible = true
		minimize_button.text = "_"

func _on_websocket_connected():
	add_system_message("Connected to chat")

func focus_input():
	if chat_input:
		chat_input.grab_focus()

func clear():
	if chat_messages:
		chat_messages.clear()
