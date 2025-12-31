extends Node
class_name WebSocketClient

# WebSocket client for real-time communication with the backend
# Uses SignalR protocol for server communication

signal connected
signal disconnected
signal connection_error(error: String)
signal message_received(type: String, data: Dictionary)

# Hub-specific signals
signal chat_message_received(player_id: int, username: String, message: String)
signal voice_activity_received(player_id: int, is_speaking: bool)
signal game_state_received(state: Dictionary)
signal wave_started(wave_number: int, zombie_count: int)
signal player_death_received(player_id: int, killer: String, weapon: String)
signal player_revive_received(revived_id: int, reviver_id: int)
signal game_ended(victory: bool, wave_reached: int, stats: Dictionary)
signal notification_received(type: String, message: String)
signal matchmaking_update(status: Dictionary)
signal matchmaking_found(server: Dictionary)

@export var hub_url: String = "ws://localhost:5000/hubs/game"
@export var auto_reconnect: bool = true
@export var reconnect_delay: float = 5.0

var socket: WebSocketPeer
var is_connected: bool = false
var auth_token: String = ""
var current_server_id: int = -1
var reconnect_timer: float = 0.0
var should_reconnect: bool = false
var pending_invocations: Dictionary = {}
var invocation_id: int = 0

func _ready():
	socket = WebSocketPeer.new()

func _process(delta):
	if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		if should_reconnect and auto_reconnect:
			reconnect_timer += delta
			if reconnect_timer >= reconnect_delay:
				reconnect_timer = 0.0
				connect_to_hub()
		return

	socket.poll()

	var state = socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not is_connected:
			is_connected = true
			_on_connected()

		# Process incoming messages
		while socket.get_available_packet_count() > 0:
			var packet = socket.get_packet()
			_handle_message(packet.get_string_from_utf8())

	elif state == WebSocketPeer.STATE_CLOSED:
		if is_connected:
			is_connected = false
			_on_disconnected()

# ============================================
# CONNECTION MANAGEMENT
# ============================================

func connect_to_hub(token: String = "") -> void:
	if not token.is_empty():
		auth_token = token

	# Build URL with token
	var url = hub_url
	if not auth_token.is_empty():
		url += "?access_token=%s" % auth_token

	var error = socket.connect_to_url(url)
	if error != OK:
		connection_error.emit("Failed to initiate connection")
		return

	should_reconnect = true

func disconnect_from_hub() -> void:
	should_reconnect = false
	socket.close()
	is_connected = false

func _on_connected() -> void:
	# Send SignalR handshake
	_send_signalr_handshake()
	connected.emit()

func _on_disconnected() -> void:
	current_server_id = -1
	pending_invocations.clear()
	disconnected.emit()

func _send_signalr_handshake() -> void:
	# SignalR handshake message
	var handshake = {"protocol": "json", "version": 1}
	_send_raw(JSON.stringify(handshake) + "\x1e")  # Record separator

# ============================================
# MESSAGE HANDLING
# ============================================

func _handle_message(raw_message: String) -> void:
	# SignalR messages are separated by \x1e (record separator)
	var messages = raw_message.split("\x1e")

	for msg in messages:
		if msg.is_empty():
			continue

		var json = JSON.new()
		if json.parse(msg) != OK:
			continue

		var data = json.data
		if not data is Dictionary:
			continue

		var msg_type = data.get("type", 0)

		match msg_type:
			1:  # Invocation
				_handle_invocation(data)
			2:  # StreamItem
				pass
			3:  # Completion
				_handle_completion(data)
			6:  # Ping
				_send_pong()
			7:  # Close
				disconnect_from_hub()

func _handle_invocation(data: Dictionary) -> void:
	var target = data.get("target", "")
	var arguments = data.get("arguments", [])

	match target:
		"ChatMessage":
			if arguments.size() > 0:
				var msg = arguments[0]
				chat_message_received.emit(
					msg.get("PlayerId", 0),
					msg.get("Username", ""),
					msg.get("Message", "")
				)

		"VoiceActivity":
			if arguments.size() > 0:
				var msg = arguments[0]
				voice_activity_received.emit(
					msg.get("PlayerId", 0),
					msg.get("IsSpeaking", false)
				)

		"GameState":
			if arguments.size() > 0:
				game_state_received.emit(arguments[0])

		"WaveStart":
			if arguments.size() > 0:
				var msg = arguments[0]
				wave_started.emit(
					msg.get("WaveNumber", 0),
					msg.get("ZombieCount", 0)
				)

		"PlayerDeath":
			if arguments.size() > 0:
				var msg = arguments[0]
				player_death_received.emit(
					msg.get("PlayerId", 0),
					msg.get("KillerName", ""),
					msg.get("Weapon", "")
				)

		"PlayerRevive":
			if arguments.size() > 0:
				var msg = arguments[0]
				player_revive_received.emit(
					msg.get("RevivedPlayerId", 0),
					msg.get("ReviverPlayerId", 0)
				)

		"GameEnd":
			if arguments.size() > 0:
				var msg = arguments[0]
				game_ended.emit(
					msg.get("Victory", false),
					msg.get("WaveReached", 0),
					msg.get("Stats", {})
				)

		"Notification":
			if arguments.size() > 0:
				var msg = arguments[0]
				notification_received.emit(
					msg.get("Type", ""),
					msg.get("Message", "")
				)

		"MatchmakingUpdate":
			if arguments.size() > 0:
				matchmaking_update.emit(arguments[0])

		"MatchmakingStarted":
			pass  # Handled by caller

		"MatchmakingCancelled":
			pass

		"MatchmakingTimeout":
			matchmaking_update.emit({"status": "timeout"})

	message_received.emit(target, arguments[0] if arguments.size() > 0 else {})

func _handle_completion(data: Dictionary) -> void:
	var inv_id = data.get("invocationId", "")

	if pending_invocations.has(inv_id):
		var callback = pending_invocations[inv_id]
		pending_invocations.erase(inv_id)

		var result = data.get("result")
		var error = data.get("error")

		if callback.is_valid():
			if error:
				callback.call({"success": false, "error": error})
			else:
				callback.call({"success": true, "result": result})

func _send_pong() -> void:
	_send_raw(JSON.stringify({"type": 6}) + "\x1e")

# ============================================
# HUB METHODS - GAME
# ============================================

func join_server(server_id: int) -> void:
	current_server_id = server_id
	_invoke("JoinServer", [server_id])

func leave_server(server_id: int = -1) -> void:
	var sid = server_id if server_id > 0 else current_server_id
	if sid > 0:
		_invoke("LeaveServer", [sid])
	current_server_id = -1

func send_chat_message(message: String) -> void:
	if current_server_id > 0:
		_invoke("SendChatMessage", [current_server_id, message])

func send_voice_activity(is_speaking: bool) -> void:
	if current_server_id > 0:
		_invoke("VoiceActivity", [current_server_id, is_speaking])

# ============================================
# HUB METHODS - MATCHMAKING
# ============================================

func start_matchmaking(game_mode: String, preferred_region: String = "", preferred_map: String = "") -> void:
	_invoke("StartMatchmaking", [game_mode, preferred_region, preferred_map])

func cancel_matchmaking() -> void:
	_invoke("CancelMatchmaking", [])

func join_party(party_code: String) -> void:
	_invoke("JoinParty", [party_code])

func leave_party(party_code: String) -> void:
	_invoke("LeaveParty", [party_code])

# ============================================
# HUB METHODS - GAME SERVER (for dedicated servers)
# ============================================

func register_as_game_server(server_id: int, server_token: String) -> void:
	_invoke("RegisterGameServer", [server_id, server_token])

func broadcast_game_state(state: Dictionary) -> void:
	if current_server_id > 0:
		_invoke("BroadcastGameState", [current_server_id, state])

func broadcast_wave_start(wave_number: int, zombie_count: int) -> void:
	if current_server_id > 0:
		_invoke("BroadcastWaveStart", [current_server_id, wave_number, zombie_count])

func broadcast_player_death(player_id: int, killer_name: String, weapon: String) -> void:
	if current_server_id > 0:
		_invoke("BroadcastPlayerDeath", [current_server_id, player_id, killer_name, weapon])

func broadcast_player_revive(revived_player_id: int, reviver_player_id: int) -> void:
	if current_server_id > 0:
		_invoke("BroadcastPlayerRevive", [current_server_id, revived_player_id, reviver_player_id])

func broadcast_game_end(victory: bool, wave_reached: int, stats: Dictionary) -> void:
	if current_server_id > 0:
		_invoke("BroadcastGameEnd", [current_server_id, victory, wave_reached, stats])

# ============================================
# INTERNAL
# ============================================

func _invoke(method: String, arguments: Array, callback: Callable = Callable()) -> void:
	if not is_connected:
		if callback.is_valid():
			callback.call({"success": false, "error": "Not connected"})
		return

	invocation_id += 1
	var inv_id = str(invocation_id)

	var message = {
		"type": 1,
		"invocationId": inv_id,
		"target": method,
		"arguments": arguments
	}

	if callback.is_valid():
		pending_invocations[inv_id] = callback

	_send_raw(JSON.stringify(message) + "\x1e")

func _send_raw(data: String) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(data)
