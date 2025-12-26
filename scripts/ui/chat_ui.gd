extends Control

# Chat UI for displaying messages and sending chat

@onready var chat_container = $Panel/MarginContainer/VBoxContainer/ScrollContainer/ChatContainer
@onready var scroll_container = $Panel/MarginContainer/VBoxContainer/ScrollContainer
@onready var input_field = $Panel/MarginContainer/VBoxContainer/InputContainer/ChatInput
@onready var send_button = $Panel/MarginContainer/VBoxContainer/InputContainer/SendButton
@onready var team_toggle = $Panel/MarginContainer/VBoxContainer/InputContainer/TeamToggle
@onready var chat_panel = $Panel

const ChatMessageLabel = preload("res://scenes/ui/chat_message_label.tscn")

var is_chat_visible: bool = true
var message_fade_time: float = 10.0
var max_visible_messages: int = 50

# Cached references for cleanup
var _chat_system: Node = null

func _ready():
	# Connect to chat system
	if has_node("/root/ChatSystem"):
		_chat_system = get_node("/root/ChatSystem")
		_chat_system.message_received.connect(_on_message_received)
		_chat_system.system_message.connect(_on_system_message)

	# Connect UI signals
	send_button.pressed.connect(_on_send_button_pressed)
	input_field.text_submitted.connect(_on_text_submitted)

	# Load recent messages
	_load_recent_messages()

	# Hide input by default
	input_field.visible = false

func _exit_tree():
	# Disconnect chat system signals
	if _chat_system:
		if _chat_system.message_received.is_connected(_on_message_received):
			_chat_system.message_received.disconnect(_on_message_received)
		if _chat_system.system_message.is_connected(_on_system_message):
			_chat_system.system_message.disconnect(_on_system_message)
	# Disconnect UI signals
	if send_button and send_button.pressed.is_connected(_on_send_button_pressed):
		send_button.pressed.disconnect(_on_send_button_pressed)
	if input_field and input_field.text_submitted.is_connected(_on_text_submitted):
		input_field.text_submitted.disconnect(_on_text_submitted)

func _input(event):
	if event.is_action_pressed("ui_chat"):
		toggle_chat_input()
		get_viewport().set_input_as_handled()

	if event.is_action_pressed("ui_cancel") and input_field.visible:
		close_chat_input()
		get_viewport().set_input_as_handled()

func toggle_chat_input():
	if input_field.visible:
		close_chat_input()
	else:
		open_chat_input()

func open_chat_input():
	input_field.visible = true
	input_field.grab_focus()
	input_field.clear()

	# Show chat panel if hidden
	if not chat_panel.visible:
		chat_panel.visible = true

func close_chat_input():
	input_field.visible = false
	input_field.release_focus()
	input_field.clear()

func _on_send_button_pressed():
	_send_current_message()

func _on_text_submitted(_text: String):
	_send_current_message()

func _send_current_message():
	var message = input_field.text.strip_edges()
	if message.is_empty():
		close_chat_input()
		return

	var is_team = team_toggle.button_pressed

	# Send via chat system
	if has_node("/root/ChatSystem"):
		var chat_system = get_node("/root/ChatSystem")
		chat_system.send_message(message, is_team)

	close_chat_input()

func _on_message_received(sender_name: String, message: String, is_team: bool):
	add_chat_message(sender_name, message, is_team, false)

func _on_system_message(message: String):
	add_chat_message("System", message, false, true)

func add_chat_message(sender_name: String, message: String, is_team: bool, is_system: bool):
	var message_label = RichTextLabel.new()
	message_label.bbcode_enabled = true
	message_label.fit_content = true
	message_label.scroll_active = false

	# Format message
	var formatted_text = ""
	if is_system:
		formatted_text = "[color=yellow][SYSTEM] %s[/color]" % message
	elif is_team:
		formatted_text = "[color=cyan][TEAM] %s:[/color] %s" % [sender_name, message]
	else:
		formatted_text = "[color=white]%s:[/color] %s" % [sender_name, message]

	message_label.text = formatted_text

	chat_container.add_child(message_label)

	# Limit message count
	while chat_container.get_child_count() > max_visible_messages:
		var oldest = chat_container.get_child(0)
		oldest.queue_free()

	# Auto-scroll to bottom
	await get_tree().process_frame
	scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value

func _load_recent_messages():
	if not has_node("/root/ChatSystem"):
		return

	var chat_system = get_node("/root/ChatSystem")
	var recent = chat_system.get_recent_messages(20)

	for entry in recent:
		var sender = entry.get("sender", "Unknown")
		var message = entry.get("message", "")
		var is_team = entry.get("is_team", false)
		var is_system = sender == "System"

		add_chat_message(sender, message, is_team, is_system)

func toggle_visibility():
	chat_panel.visible = not chat_panel.visible
