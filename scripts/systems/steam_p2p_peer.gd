extends RefCounted
# Note: class_name removed to avoid load order issues
# Access this script via: load("res://scripts/systems/steam_p2p_peer.gd")

# Steam P2P Multiplayer Peer using GodotSteam Networking Sockets
# Wraps Steam's P2P networking for seamless multiplayer
# Note: This extends RefCounted for compatibility. For full multiplayer integration,
# this class should extend MultiplayerPeerExtension when using Godot 4.x with
# the GodotSteam plugin properly configured.

signal peer_connection_established(peer_id: int)
signal peer_connection_failed(peer_id: int)

enum ConnectionState {
	NONE,
	CONNECTING,
	CONNECTED,
	DISCONNECTED
}

var steam: Object = null
var is_active: bool = false
var is_server: bool = false
var connection_state: ConnectionState = ConnectionState.NONE

# Connection tracking
var peer_id_to_steam_id: Dictionary = {}  # peer_id -> steam_id
var steam_id_to_peer_id: Dictionary = {}  # steam_id -> peer_id
var next_peer_id: int = 2  # Start at 2 (1 is always server)

# Packet handling
var incoming_packets: Array = []
var target_peer: int = 0
var transfer_channel: int = 0
var transfer_mode: int = MultiplayerPeer.TRANSFER_MODE_RELIABLE  # MultiplayerPeer.TransferMode

# Send channels (Steam networking uses channels 0-31)
const CHANNEL_RELIABLE: int = 0
const CHANNEL_UNRELIABLE: int = 1
const CHANNEL_UNRELIABLE_NO_DELAY: int = 2

func _init():
	if Engine.has_singleton("Steam"):
		steam = Engine.get_singleton("Steam")

# ============================================
# HOST/SERVER FUNCTIONS
# ============================================

func create_host(max_players: int = 4) -> Error:
	if not steam:
		print("Steam not available for P2P hosting")
		return ERR_UNAVAILABLE

	is_server = true
	is_active = true
	connection_state = ConnectionState.CONNECTED

	# Connect Steam networking signals
	_connect_steam_signals()

	# Register ourselves as peer 1 (server)
	var my_steam_id = steam.getSteamID()
	peer_id_to_steam_id[1] = my_steam_id
	steam_id_to_peer_id[my_steam_id] = 1

	print("Steam P2P host created. Max players: %d" % max_players)
	return OK

func create_client(host_steam_id: int) -> Error:
	if not steam:
		print("Steam not available for P2P connection")
		return ERR_UNAVAILABLE

	is_server = false
	is_active = true
	connection_state = ConnectionState.CONNECTING

	# Connect Steam networking signals
	_connect_steam_signals()

	# Register host as peer 1
	peer_id_to_steam_id[1] = host_steam_id
	steam_id_to_peer_id[host_steam_id] = 1

	# Register ourselves
	var my_steam_id = steam.getSteamID()
	var my_peer_id = 0  # Will be assigned by server

	# Send connection request
	_send_connection_request(host_steam_id)

	print("Connecting to Steam P2P host: %d" % host_steam_id)
	return OK

func _connect_steam_signals():
	if not steam:
		return

	# GodotSteam P2P signals
	if not steam.p2p_session_request.is_connected(_on_p2p_session_request):
		steam.p2p_session_request.connect(_on_p2p_session_request)

	if not steam.p2p_session_connect_fail.is_connected(_on_p2p_session_connect_fail):
		steam.p2p_session_connect_fail.connect(_on_p2p_session_connect_fail)

func _disconnect_steam_signals():
	if not steam:
		return

	if steam.p2p_session_request.is_connected(_on_p2p_session_request):
		steam.p2p_session_request.disconnect(_on_p2p_session_request)

	if steam.p2p_session_connect_fail.is_connected(_on_p2p_session_connect_fail):
		steam.p2p_session_connect_fail.disconnect(_on_p2p_session_connect_fail)

# ============================================
# STEAM P2P CALLBACKS
# ============================================

func _on_p2p_session_request(remote_steam_id: int):
	if is_server:
		# Accept the connection
		steam.acceptP2PSessionWithUser(remote_steam_id)

		# Assign a peer ID
		var new_peer_id = next_peer_id
		next_peer_id += 1

		peer_id_to_steam_id[new_peer_id] = remote_steam_id
		steam_id_to_peer_id[remote_steam_id] = new_peer_id

		# Send peer ID assignment
		_send_peer_assignment(remote_steam_id, new_peer_id)

		# Notify about new peer
		peer_connection_established.emit(new_peer_id)

		print("Accepted P2P session from Steam ID: %d (Peer ID: %d)" % [remote_steam_id, new_peer_id])

func _on_p2p_session_connect_fail(steam_id: int, session_error: int):
	print("P2P connection failed to %d. Error: %d" % [steam_id, session_error])

	if steam_id_to_peer_id.has(steam_id):
		var peer_id = steam_id_to_peer_id[steam_id]
		peer_connection_failed.emit(peer_id)

		# Clean up
		steam_id_to_peer_id.erase(steam_id)
		peer_id_to_steam_id.erase(peer_id)

	if not is_server and connection_state == ConnectionState.CONNECTING:
		connection_state = ConnectionState.DISCONNECTED

# ============================================
# PACKET SENDING
# ============================================

func _send_connection_request(host_steam_id: int):
	var packet = PackedByteArray()
	packet.append(0x01)  # Connection request type

	var my_steam_id = steam.getSteamID()
	packet.append_array(_int64_to_bytes(my_steam_id))

	steam.sendP2PPacket(host_steam_id, packet, 2, CHANNEL_RELIABLE)  # 2 = reliable

func _send_peer_assignment(target_steam_id: int, assigned_peer_id: int):
	var packet = PackedByteArray()
	packet.append(0x02)  # Peer assignment type
	packet.append_array(_int32_to_bytes(assigned_peer_id))

	steam.sendP2PPacket(target_steam_id, packet, 2, CHANNEL_RELIABLE)

func _send_game_packet(target_steam_id: int, data: PackedByteArray, channel: int):
	var packet = PackedByteArray()
	packet.append(0x10)  # Game data type
	packet.append_array(data)

	var send_type = 2 if transfer_mode == MultiplayerPeer.TRANSFER_MODE_RELIABLE else 0
	steam.sendP2PPacket(target_steam_id, packet, send_type, channel)

# ============================================
# MULTIPLAYER PEER EXTENSION OVERRIDES
# ============================================

func _get_packet() -> PackedByteArray:
	if incoming_packets.is_empty():
		return PackedByteArray()

	var packet_data = incoming_packets.pop_front()
	return packet_data.data

func _get_packet_channel() -> int:
	return transfer_channel

func _get_packet_mode() -> int:  # Returns MultiplayerPeer.TransferMode
	return transfer_mode

func _get_packet_peer() -> int:
	if incoming_packets.is_empty():
		return 0

	return incoming_packets[0].from_peer

func _get_available_packet_count() -> int:
	return incoming_packets.size()

func _put_packet(p_buffer: PackedByteArray) -> Error:
	if target_peer == 0:
		# Broadcast to all
		for peer_id in peer_id_to_steam_id:
			if peer_id != get_unique_id():
				var steam_id = peer_id_to_steam_id[peer_id]
				_send_game_packet(steam_id, p_buffer, CHANNEL_RELIABLE)
	elif target_peer < 0:
		# Broadcast except one
		var exclude_peer = -target_peer
		for peer_id in peer_id_to_steam_id:
			if peer_id != get_unique_id() and peer_id != exclude_peer:
				var steam_id = peer_id_to_steam_id[peer_id]
				_send_game_packet(steam_id, p_buffer, CHANNEL_RELIABLE)
	else:
		# Send to specific peer
		if peer_id_to_steam_id.has(target_peer):
			var steam_id = peer_id_to_steam_id[target_peer]
			_send_game_packet(steam_id, p_buffer, CHANNEL_RELIABLE)

	return OK

func _set_target_peer(p_peer: int):
	target_peer = p_peer

func _get_unique_id() -> int:
	if is_server:
		return 1

	# Find our peer ID
	var my_steam_id = steam.getSteamID() if steam else 0
	if steam_id_to_peer_id.has(my_steam_id):
		return steam_id_to_peer_id[my_steam_id]

	return 0

func _get_connection_status() -> int:  # Returns MultiplayerPeer.ConnectionStatus
	match connection_state:
		ConnectionState.NONE:
			return MultiplayerPeer.CONNECTION_DISCONNECTED
		ConnectionState.CONNECTING:
			return MultiplayerPeer.CONNECTION_CONNECTING
		ConnectionState.CONNECTED:
			return MultiplayerPeer.CONNECTION_CONNECTED
		ConnectionState.DISCONNECTED:
			return MultiplayerPeer.CONNECTION_DISCONNECTED

	return MultiplayerPeer.CONNECTION_DISCONNECTED

func _set_transfer_channel(p_channel: int):
	transfer_channel = p_channel

func _get_transfer_channel() -> int:
	return transfer_channel

func _set_transfer_mode(p_mode: int):  # p_mode: MultiplayerPeer.TransferMode
	transfer_mode = p_mode

func _get_transfer_mode() -> int:  # Returns MultiplayerPeer.TransferMode
	return transfer_mode

func _is_server() -> bool:
	return is_server

func _poll() -> Error:
	if not steam or not is_active:
		return OK

	# Check for incoming P2P packets
	while true:
		var packet_size = steam.getAvailableP2PPacketSize(CHANNEL_RELIABLE)
		if packet_size == 0:
			packet_size = steam.getAvailableP2PPacketSize(CHANNEL_UNRELIABLE)
			if packet_size == 0:
				break

		var packet = steam.readP2PPacket(packet_size, CHANNEL_RELIABLE if packet_size > 0 else CHANNEL_UNRELIABLE)
		if packet.is_empty():
			break

		var sender_steam_id = packet.remote_steam_id
		var data = packet.data

		_handle_packet(sender_steam_id, data)

	return OK

func _handle_packet(sender_steam_id: int, data: PackedByteArray):
	if data.is_empty():
		return

	var packet_type = data[0]
	var packet_data = data.slice(1)

	match packet_type:
		0x01:  # Connection request
			_handle_connection_request(sender_steam_id, packet_data)
		0x02:  # Peer assignment
			_handle_peer_assignment(packet_data)
		0x10:  # Game data
			_handle_game_data(sender_steam_id, packet_data)
		0xFF:  # Disconnect
			_handle_disconnect(sender_steam_id)

func _handle_connection_request(sender_steam_id: int, _data: PackedByteArray):
	if is_server:
		# Accept and assign peer ID (handled in _on_p2p_session_request)
		steam.acceptP2PSessionWithUser(sender_steam_id)

func _handle_peer_assignment(data: PackedByteArray):
	if is_server:
		return

	var assigned_id = _bytes_to_int32(data)
	var my_steam_id = steam.getSteamID()

	peer_id_to_steam_id[assigned_id] = my_steam_id
	steam_id_to_peer_id[my_steam_id] = assigned_id

	connection_state = ConnectionState.CONNECTED
	print("Assigned peer ID: %d" % assigned_id)

func _handle_game_data(sender_steam_id: int, data: PackedByteArray):
	var from_peer = 1  # Default to server
	if steam_id_to_peer_id.has(sender_steam_id):
		from_peer = steam_id_to_peer_id[sender_steam_id]

	incoming_packets.append({
		"from_peer": from_peer,
		"data": data
	})

func _handle_disconnect(sender_steam_id: int):
	if steam_id_to_peer_id.has(sender_steam_id):
		var peer_id = steam_id_to_peer_id[sender_steam_id]
		steam_id_to_peer_id.erase(sender_steam_id)
		peer_id_to_steam_id.erase(peer_id)

func _close():
	is_active = false
	connection_state = ConnectionState.DISCONNECTED

	# Close all P2P sessions
	if steam:
		for steam_id in steam_id_to_peer_id:
			steam.closeP2PSessionWithUser(steam_id)

	peer_id_to_steam_id.clear()
	steam_id_to_peer_id.clear()
	incoming_packets.clear()

	_disconnect_steam_signals()

func _disconnect_peer(p_peer: int, _p_force: bool = false):
	if peer_id_to_steam_id.has(p_peer):
		var steam_id = peer_id_to_steam_id[p_peer]

		# Send disconnect packet
		var packet = PackedByteArray()
		packet.append(0xFF)
		steam.sendP2PPacket(steam_id, packet, 2, CHANNEL_RELIABLE)

		# Close session
		steam.closeP2PSessionWithUser(steam_id)

		steam_id_to_peer_id.erase(steam_id)
		peer_id_to_steam_id.erase(p_peer)

# ============================================
# UTILITY
# ============================================

func _int64_to_bytes(value: int) -> PackedByteArray:
	var bytes = PackedByteArray()
	bytes.resize(8)
	bytes.encode_s64(0, value)
	return bytes

func _bytes_to_int64(bytes: PackedByteArray) -> int:
	if bytes.size() < 8:
		return 0
	return bytes.decode_s64(0)

func _int32_to_bytes(value: int) -> PackedByteArray:
	var bytes = PackedByteArray()
	bytes.resize(4)
	bytes.encode_s32(0, value)
	return bytes

func _bytes_to_int32(bytes: PackedByteArray) -> int:
	if bytes.size() < 4:
		return 0
	return bytes.decode_s32(0)

func get_peer_steam_id(peer_id: int) -> int:
	return peer_id_to_steam_id.get(peer_id, 0)

func get_peer_id_from_steam(steam_id: int) -> int:
	return steam_id_to_peer_id.get(steam_id, 0)
