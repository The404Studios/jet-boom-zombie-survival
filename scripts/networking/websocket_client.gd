extends Node

# WebSocket client for real-time communication with the backend
# Uses SignalR protocol for server communication

# SignalR record separator (Unicode char 0x1e)
const RECORD_SEPARATOR = "\u001e"

signal connected
signal disconnected
signal connection_error(error: String)
signal message_received(type: String, data: Dictionary)

# Hub-specific signals
signal chat_message_received(username: String, message: String, channel: String)
signal system_message_received(message: String)
signal voice_activity_received(player_id: int, is_speaking: bool)
signal game_state_received(state: Dictionary)
signal wave_started(wave_number: int, zombie_count: int)
signal wave_state_update(state: Dictionary)
signal player_death_received(player_id: int, killer: String, weapon: String)
signal player_revive_received(revived_id: int, reviver_id: int)
signal player_joined(player_data: Dictionary)
signal player_left(player_data: Dictionary)
signal game_ended(victory: bool, wave_reached: int, stats: Dictionary)
signal notification_received(notification_data: Dictionary)
signal matchmaking_update(status: Dictionary)
signal matchmaking_found(server: Dictionary)

# Trading signals
signal trade_request_received(from_player_id: int, from_username: String)
signal trade_accepted(trade_id: int)
signal trade_declined(trade_id: int)
signal trade_completed(trade_id: int, items_received: Array)

# Friend signals
signal friend_request_received(from_player_id: int, from_username: String)
signal game_invite_received(from_player_id: int, from_username: String, server_info: Dictionary)
signal achievement_unlocked(achievement_data: Dictionary)

# Dedicated server signals
signal server_registered(server_id: int, server_token: String)
signal server_registration_failed(error: String)
signal player_joined_dedicated(peer_id: int, player_info: Dictionary)
signal player_left_dedicated(peer_id: int)
signal player_input_received(peer_id: int, input_data: Dictionary)
signal player_state_received(peer_id: int, state_data: Dictionary)
signal entity_states_broadcast(states: Array)

@export var hub_url: String = "ws://162.248.94.149:5000/hubs/game"
@export var dedicated_hub_url: String = "ws://162.248.94.149:5000/hubs/dedicated"
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
	_send_raw(JSON.stringify(handshake) + RECORD_SEPARATOR)

# ============================================
# MESSAGE HANDLING
# ============================================

func _handle_message(raw_message: String) -> void:
	# SignalR messages are separated by record separator
	var messages = raw_message.split(RECORD_SEPARATOR)

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
					msg.get("Username", ""),
					msg.get("Message", ""),
					msg.get("Channel", "server")
				)

		"SystemMessage":
			if arguments.size() > 0:
				var msg = arguments[0]
				system_message_received.emit(msg.get("Message", ""))

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

		"WaveState":
			if arguments.size() > 0:
				wave_state_update.emit(arguments[0])

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

		"PlayerJoined":
			if arguments.size() > 0:
				player_joined.emit(arguments[0])

		"PlayerLeft":
			if arguments.size() > 0:
				player_left.emit(arguments[0])

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
				notification_received.emit(arguments[0])

		# Trading
		"TradeRequest":
			if arguments.size() > 0:
				var msg = arguments[0]
				trade_request_received.emit(
					msg.get("FromPlayerId", 0),
					msg.get("FromUsername", "")
				)

		"TradeAccepted":
			if arguments.size() > 0:
				trade_accepted.emit(arguments[0].get("TradeId", 0))

		"TradeDeclined":
			if arguments.size() > 0:
				trade_declined.emit(arguments[0].get("TradeId", 0))

		"TradeCompleted":
			if arguments.size() > 0:
				var msg = arguments[0]
				trade_completed.emit(
					msg.get("TradeId", 0),
					msg.get("ItemsReceived", [])
				)

		# Friends
		"FriendRequest":
			if arguments.size() > 0:
				var msg = arguments[0]
				friend_request_received.emit(
					msg.get("FromPlayerId", 0),
					msg.get("FromUsername", "")
				)

		"GameInvite":
			if arguments.size() > 0:
				var msg = arguments[0]
				game_invite_received.emit(
					msg.get("FromPlayerId", 0),
					msg.get("FromUsername", ""),
					msg.get("ServerInfo", {})
				)

		"AchievementUnlocked":
			if arguments.size() > 0:
				achievement_unlocked.emit(arguments[0])

		# Matchmaking
		"MatchmakingUpdate":
			if arguments.size() > 0:
				matchmaking_update.emit(arguments[0])

		"MatchmakingStarted":
			pass  # Handled by caller

		"MatchmakingCancelled":
			matchmaking_update.emit({"status": "cancelled"})

		"MatchmakingTimeout":
			matchmaking_update.emit({"status": "timeout"})

		"MatchFound":
			if arguments.size() > 0:
				matchmaking_found.emit(arguments[0])

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
	_send_raw(JSON.stringify({"type": 6}) + RECORD_SEPARATOR)

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

func send_chat_message(message: String, channel: String = "server") -> void:
	"""Send chat message to specified channel"""
	match channel:
		"global":
			_invoke("SendGlobalChatMessage", [message])
		"party":
			_invoke("SendPartyChatMessage", [message])
		"team":
			if current_server_id > 0:
				_invoke("SendTeamChatMessage", [current_server_id, message])
		_:  # "server" or default
			if current_server_id > 0:
				_invoke("SendChatMessage", [current_server_id, message])

func send_whisper(target_player_id: int, message: String) -> void:
	"""Send private message to player"""
	_invoke("SendWhisper", [target_player_id, message])

func join_channel(channel_name: String) -> void:
	"""Join a chat channel"""
	_invoke("JoinChannel", [channel_name])

func leave_channel(channel_name: String) -> void:
	"""Leave a chat channel"""
	_invoke("LeaveChannel", [channel_name])

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
# HUB METHODS - TRADING
# ============================================

func send_trade_request(to_player_id: int) -> void:
	"""Send trade request to player"""
	_invoke("SendTradeRequest", [to_player_id])

func accept_trade(trade_id: int) -> void:
	"""Accept a trade request"""
	_invoke("AcceptTrade", [trade_id])

func decline_trade(trade_id: int) -> void:
	"""Decline a trade request"""
	_invoke("DeclineTrade", [trade_id])

func cancel_trade(trade_id: int) -> void:
	"""Cancel an active trade"""
	_invoke("CancelTrade", [trade_id])

func send_trade_offer(offer: Dictionary) -> void:
	"""Send/update trade offer"""
	_invoke("UpdateTradeOffer", [offer])

func confirm_trade(trade_id: int) -> void:
	"""Confirm trade is ready"""
	_invoke("ConfirmTrade", [trade_id])

# ============================================
# HUB METHODS - SERVER INFO
# ============================================

func update_server_info(info: Dictionary) -> void:
	"""Update server info (for hosts)"""
	if current_server_id > 0:
		_invoke("UpdateServerInfo", [current_server_id, info])

func send_game_invite(friend_id: int, server_info: Dictionary = {}) -> void:
	"""Send game invite to a friend"""
	var info = server_info
	if info.is_empty() and current_server_id > 0:
		info = {"serverId": current_server_id}
	_invoke("SendGameInvite", [friend_id, info])

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

	_send_raw(JSON.stringify(message) + RECORD_SEPARATOR)

func _send_raw(data: String) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(data)

# ============================================
# DEDICATED SERVER HUB CONNECTION
# ============================================

var dedicated_socket: WebSocketPeer = null
var is_dedicated_connected: bool = false

func connect_to_dedicated_hub(token: String = "") -> void:
	"""Connect to the dedicated server hub (for dedicated servers or special operations)"""
	if dedicated_socket == null:
		dedicated_socket = WebSocketPeer.new()

	var url = dedicated_hub_url
	if not token.is_empty():
		url += "?access_token=%s" % token

	var error = dedicated_socket.connect_to_url(url)
	if error != OK:
		connection_error.emit("Failed to connect to dedicated hub")
		return

func disconnect_from_dedicated_hub() -> void:
	"""Disconnect from dedicated server hub"""
	if dedicated_socket:
		dedicated_socket.close()
		is_dedicated_connected = false

func poll_dedicated_socket() -> void:
	"""Call this in _process if using dedicated hub"""
	if dedicated_socket == null:
		return

	dedicated_socket.poll()

	var state = dedicated_socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not is_dedicated_connected:
			is_dedicated_connected = true
			_send_signalr_handshake_dedicated()

		while dedicated_socket.get_available_packet_count() > 0:
			var packet = dedicated_socket.get_packet()
			_handle_dedicated_message(packet.get_string_from_utf8())

	elif state == WebSocketPeer.STATE_CLOSED:
		if is_dedicated_connected:
			is_dedicated_connected = false

func _send_signalr_handshake_dedicated() -> void:
	"""Send SignalR handshake to dedicated hub"""
	var handshake = {"protocol": "json", "version": 1}
	_send_dedicated_raw(JSON.stringify(handshake) + RECORD_SEPARATOR)

func _send_dedicated_raw(data: String) -> void:
	if dedicated_socket and dedicated_socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		dedicated_socket.send_text(data)

func _invoke_dedicated(method: String, arguments: Array, callback: Callable = Callable()) -> void:
	"""Invoke method on dedicated server hub"""
	if not is_dedicated_connected:
		if callback.is_valid():
			callback.call({"success": false, "error": "Not connected to dedicated hub"})
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

	_send_dedicated_raw(JSON.stringify(message) + RECORD_SEPARATOR)

func _handle_dedicated_message(raw_message: String) -> void:
	"""Handle messages from dedicated server hub"""
	var messages = raw_message.split(RECORD_SEPARATOR)

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
				_handle_dedicated_invocation(data)
			3:  # Completion
				_handle_completion(data)
			6:  # Ping
				_send_dedicated_raw(JSON.stringify({"type": 6}) + RECORD_SEPARATOR)

func _handle_dedicated_invocation(data: Dictionary) -> void:
	"""Handle invocations from dedicated server hub"""
	var target = data.get("target", "")
	var arguments = data.get("arguments", [])

	match target:
		"PlayerJoined":
			if arguments.size() > 0:
				var info = arguments[0]
				player_joined_dedicated.emit(info.get("PeerId", 0), info)

		"PlayerLeft":
			if arguments.size() > 0:
				var info = arguments[0]
				player_left_dedicated.emit(info.get("PeerId", 0))

		"PlayerDisconnected":
			if arguments.size() > 0:
				var info = arguments[0]
				player_left_dedicated.emit(info.get("PeerId", 0))

		"PlayerInput":
			if arguments.size() > 0:
				var input = arguments[0]
				player_input_received.emit(input.get("PeerId", 0), input)

		"PlayerState":
			if arguments.size() > 0:
				var state = arguments[0]
				player_state_received.emit(state.get("PeerId", 0), state)

		"PlayerAction":
			if arguments.size() > 0:
				var action = arguments[0]
				message_received.emit("PlayerAction", action)

		"EntityStates":
			if arguments.size() > 0:
				entity_states_broadcast.emit(arguments[0])

# ============================================
# DEDICATED SERVER HUB METHODS
# ============================================

func register_dedicated_server(server_info: Dictionary, callback: Callable = Callable()) -> void:
	"""Register as a dedicated game server"""
	_invoke_dedicated("RegisterDedicatedServer", [server_info], func(response):
		if response.get("success", false):
			var result = response.get("result", {})
			if result.get("Success", false):
				server_registered.emit(result.get("ServerId", 0), result.get("ServerToken", ""))
			else:
				server_registration_failed.emit(result.get("Error", "Unknown error"))
		else:
			server_registration_failed.emit(response.get("error", "Registration failed"))

		if callback.is_valid():
			callback.call(response)
	)

func update_dedicated_server_status(server_id: int, token: String, status: Dictionary) -> void:
	"""Update dedicated server status"""
	_invoke_dedicated("UpdateServerStatus", [server_id, token, status])

func deregister_dedicated_server(server_id: int, token: String) -> void:
	"""Deregister dedicated server"""
	_invoke_dedicated("DeregisterServer", [server_id, token])

func broadcast_entity_states_dedicated(server_id: int, states: Array) -> void:
	"""Broadcast entity states to all players (from dedicated server)"""
	_invoke_dedicated("BroadcastEntityStates", [server_id, states])

func broadcast_game_event_dedicated(server_id: int, event_name: String, event_data: Dictionary) -> void:
	"""Broadcast game event to all players (from dedicated server)"""
	_invoke_dedicated("BroadcastGameEvent", [server_id, event_name, event_data])

func send_to_player_dedicated(server_id: int, peer_id: int, event_name: String, data: Dictionary) -> void:
	"""Send event to specific player (from dedicated server)"""
	_invoke_dedicated("SendToPlayer", [server_id, peer_id, event_name, data])

func broadcast_wave_start_dedicated(server_id: int, wave_number: int, total_zombies: int) -> void:
	"""Broadcast wave start (from dedicated server)"""
	_invoke_dedicated("BroadcastWaveStart", [server_id, wave_number, total_zombies])

func broadcast_wave_complete_dedicated(server_id: int, wave_number: int, rewards: Dictionary) -> void:
	"""Broadcast wave complete (from dedicated server)"""
	_invoke_dedicated("BroadcastWaveComplete", [server_id, wave_number, rewards])

func spawn_zombie_dedicated(server_id: int, zombie_data: Dictionary) -> void:
	"""Spawn zombie and notify clients (from dedicated server)"""
	_invoke_dedicated("SpawnZombie", [server_id, zombie_data])

func zombie_died_dedicated(server_id: int, zombie_id: int, killer_peer_id: int, drop_data: Dictionary) -> void:
	"""Notify zombie death (from dedicated server)"""
	_invoke_dedicated("ZombieDied", [server_id, zombie_id, killer_peer_id, drop_data])

func broadcast_player_damage_dedicated(server_id: int, peer_id: int, damage: float, body_part: String, new_health: float) -> void:
	"""Broadcast player damage (from dedicated server)"""
	_invoke_dedicated("BroadcastPlayerDamage", [server_id, peer_id, damage, body_part, new_health])

func broadcast_player_death_dedicated(server_id: int, peer_id: int, killer_name: String) -> void:
	"""Broadcast player death (from dedicated server)"""
	_invoke_dedicated("BroadcastPlayerDeath", [server_id, peer_id, killer_name])

func broadcast_player_respawn_dedicated(server_id: int, peer_id: int, position: Array) -> void:
	"""Broadcast player respawn (from dedicated server)"""
	_invoke_dedicated("BroadcastPlayerRespawn", [server_id, peer_id, position])

# ============================================
# CLIENT METHODS FOR DEDICATED SERVER
# ============================================

func join_dedicated_server(server_id: int, player_info: Dictionary, callback: Callable = Callable()) -> void:
	"""Join a dedicated server as a player"""
	_invoke_dedicated("JoinServer", [server_id, player_info], callback)

func leave_dedicated_server() -> void:
	"""Leave current dedicated server"""
	_invoke_dedicated("LeaveServer", [])

func send_player_input_dedicated(input_data: Dictionary) -> void:
	"""Send player input to dedicated server"""
	_invoke_dedicated("SendPlayerInput", [input_data])

func send_player_state_dedicated(state_data: Dictionary) -> void:
	"""Send player state to dedicated server"""
	_invoke_dedicated("SendPlayerState", [state_data])

func send_player_action_dedicated(action_type: String, action_data: Dictionary) -> void:
	"""Send player action to dedicated server"""
	_invoke_dedicated("SendPlayerAction", [action_type, action_data])

func send_chat_dedicated(message: String) -> void:
	"""Send chat message via dedicated server"""
	_invoke_dedicated("SendChatMessage", [message])
