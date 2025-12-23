extends Node

# Chat system for multiplayer communication
# Handles text chat with team/all modes and spam prevention

signal message_received(sender_name: String, message: String, is_team: bool)
signal system_message(message: String)

const MAX_MESSAGE_LENGTH: int = 200
const MAX_MESSAGES_PER_SECOND: int = 3
const CHAT_HISTORY_SIZE: int = 100

var chat_history: Array = []
var message_timestamps: Dictionary = {} # peer_id -> Array of timestamps
var player_muted: Dictionary = {} # peer_id -> bool

func _ready():
	# Connect to network signals
	if NetworkManager:
		NetworkManager.player_joined.connect(_on_player_joined)
		NetworkManager.player_left.connect(_on_player_left)

func _on_player_joined(peer_id: int, player_data: Dictionary):
	var msg = "%s joined the game" % player_data.get("name", "Player")
	emit_system_message(msg)
	message_timestamps[peer_id] = []

func _on_player_left(peer_id: int):
	var player_name = "Player"
	if NetworkManager and NetworkManager.players.has(peer_id):
		player_name = NetworkManager.players[peer_id].get("name", "Player")
	var msg = "%s left the game" % player_name
	emit_system_message(msg)
	message_timestamps.erase(peer_id)
	player_muted.erase(peer_id)

func send_message(message: String, is_team: bool = false):
	# Validate message
	message = message.strip_edges()
	if message.is_empty():
		return

	if message.length() > MAX_MESSAGE_LENGTH:
		message = message.substr(0, MAX_MESSAGE_LENGTH)

	# Check for spam
	if not can_send_message():
		emit_system_message("You are sending messages too quickly!")
		return

	# Get player name
	var sender_name = "Player"
	if NetworkManager and NetworkManager.players.has(multiplayer.get_unique_id()):
		sender_name = NetworkManager.players[multiplayer.get_unique_id()].get("name", "Player")

	# Send via RPC
	if multiplayer.is_server():
		_broadcast_message(multiplayer.get_unique_id(), sender_name, message, is_team)
	else:
		_send_message_to_server.rpc_id(1, message, is_team)

@rpc("any_peer", "call_remote")
func _send_message_to_server(message: String, is_team: bool):
	var sender_id = multiplayer.get_remote_sender_id()

	# Validate on server
	if player_muted.get(sender_id, false):
		return

	if not can_send_message_for_peer(sender_id):
		return

	var sender_name = "Player"
	if NetworkManager and NetworkManager.players.has(sender_id):
		sender_name = NetworkManager.players[sender_id].get("name", "Player")

	_broadcast_message(sender_id, sender_name, message, is_team)

func _broadcast_message(sender_id: int, sender_name: String, message: String, is_team: bool):
	# Record timestamp
	record_message_timestamp(sender_id)

	# Broadcast to all clients
	if is_team:
		# TODO: Filter by team when team system is implemented
		_receive_message.rpc(sender_name, message, true)
	else:
		_receive_message.rpc(sender_name, message, false)

@rpc("authority", "call_local")
func _receive_message(sender_name: String, message: String, is_team: bool):
	# Add to history
	var chat_entry = {
		"sender": sender_name,
		"message": message,
		"is_team": is_team,
		"timestamp": Time.get_unix_time_from_system()
	}

	chat_history.append(chat_entry)
	if chat_history.size() > CHAT_HISTORY_SIZE:
		chat_history.pop_front()

	message_received.emit(sender_name, message, is_team)

func emit_system_message(message: String):
	var chat_entry = {
		"sender": "System",
		"message": message,
		"is_team": false,
		"timestamp": Time.get_unix_time_from_system()
	}

	chat_history.append(chat_entry)
	if chat_history.size() > CHAT_HISTORY_SIZE:
		chat_history.pop_front()

	system_message.emit(message)

func can_send_message() -> bool:
	return can_send_message_for_peer(multiplayer.get_unique_id())

func can_send_message_for_peer(peer_id: int) -> bool:
	if not message_timestamps.has(peer_id):
		message_timestamps[peer_id] = []
		return true

	var current_time = Time.get_unix_time_from_system()
	var timestamps = message_timestamps[peer_id]

	# Remove old timestamps
	var valid_timestamps = []
	for timestamp in timestamps:
		if current_time - timestamp < 1.0:
			valid_timestamps.append(timestamp)

	message_timestamps[peer_id] = valid_timestamps

	return valid_timestamps.size() < MAX_MESSAGES_PER_SECOND

func record_message_timestamp(peer_id: int):
	if not message_timestamps.has(peer_id):
		message_timestamps[peer_id] = []

	message_timestamps[peer_id].append(Time.get_unix_time_from_system())

func mute_player(peer_id: int, muted: bool = true):
	if not multiplayer.is_server():
		return

	player_muted[peer_id] = muted

	var player_name = "Player"
	if NetworkManager and NetworkManager.players.has(peer_id):
		player_name = NetworkManager.players[peer_id].get("name", "Player")

	if muted:
		emit_system_message("%s has been muted" % player_name)
	else:
		emit_system_message("%s has been unmuted" % player_name)

func clear_history():
	chat_history.clear()

func get_recent_messages(count: int = 20) -> Array:
	var start_index = max(0, chat_history.size() - count)
	return chat_history.slice(start_index)
