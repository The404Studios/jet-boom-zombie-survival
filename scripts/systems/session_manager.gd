extends Node
class_name SessionManager

## Session Manager
## Handles player session persistence, reconnection, and state recovery

signal session_created(session_id: String)
signal session_restored(session_id: String)
signal session_expired(session_id: String)
signal player_reconnected(peer_id: int, session_id: String)
signal player_disconnected_temp(peer_id: int, session_id: String)

# Session configuration
@export var session_timeout: float = 300.0  # 5 minutes
@export var save_interval: float = 30.0  # Save session every 30 seconds
@export var max_reconnect_time: float = 120.0  # 2 minutes to reconnect

# Session storage
var active_sessions: Dictionary = {}  # session_id -> SessionData
var peer_to_session: Dictionary = {}  # peer_id -> session_id
var disconnected_sessions: Dictionary = {}  # session_id -> disconnect_time

# Persistence
const SESSION_FILE = "user://sessions.json"
var save_timer: float = 0.0

class SessionData:
	var session_id: String = ""
	var peer_id: int = 0
	var player_id: int = 0
	var username: String = ""
	var steam_id: int = 0
	var character_class: String = ""
	var level: int = 1
	var created_at: float = 0.0
	var last_active: float = 0.0

	# Game state
	var position: Vector3 = Vector3.ZERO
	var rotation: Vector3 = Vector3.ZERO
	var health: float = 100.0
	var max_health: float = 100.0
	var score: int = 0
	var kills: int = 0
	var deaths: int = 0
	var inventory: Array = []
	var equipped_weapon: String = ""
	var ammo: Dictionary = {}

	# Status
	var is_alive: bool = true
	var is_ready: bool = false
	var is_connected: bool = true

	func to_dict() -> Dictionary:
		return {
			"session_id": session_id,
			"peer_id": peer_id,
			"player_id": player_id,
			"username": username,
			"steam_id": steam_id,
			"character_class": character_class,
			"level": level,
			"created_at": created_at,
			"last_active": last_active,
			"position": [position.x, position.y, position.z],
			"rotation": [rotation.x, rotation.y, rotation.z],
			"health": health,
			"max_health": max_health,
			"score": score,
			"kills": kills,
			"deaths": deaths,
			"inventory": inventory,
			"equipped_weapon": equipped_weapon,
			"ammo": ammo,
			"is_alive": is_alive,
			"is_ready": is_ready
		}

	static func from_dict(data: Dictionary) -> SessionData:
		var session = SessionData.new()
		session.session_id = data.get("session_id", "")
		session.peer_id = data.get("peer_id", 0)
		session.player_id = data.get("player_id", 0)
		session.username = data.get("username", "Player")
		session.steam_id = data.get("steam_id", 0)
		session.character_class = data.get("character_class", "")
		session.level = data.get("level", 1)
		session.created_at = data.get("created_at", 0.0)
		session.last_active = data.get("last_active", 0.0)

		var pos = data.get("position", [0, 0, 0])
		if pos is Array and pos.size() >= 3:
			session.position = Vector3(pos[0], pos[1], pos[2])

		var rot = data.get("rotation", [0, 0, 0])
		if rot is Array and rot.size() >= 3:
			session.rotation = Vector3(rot[0], rot[1], rot[2])

		session.health = data.get("health", 100.0)
		session.max_health = data.get("max_health", 100.0)
		session.score = data.get("score", 0)
		session.kills = data.get("kills", 0)
		session.deaths = data.get("deaths", 0)
		session.inventory = data.get("inventory", [])
		session.equipped_weapon = data.get("equipped_weapon", "")
		session.ammo = data.get("ammo", {})
		session.is_alive = data.get("is_alive", true)
		session.is_ready = data.get("is_ready", false)

		return session

func _ready():
	# Load saved sessions
	_load_sessions()

func _process(delta):
	# Periodic session save
	save_timer += delta
	if save_timer >= save_interval:
		save_timer = 0.0
		_save_sessions()

	# Check for expired disconnected sessions
	_check_expired_sessions()

# ============================================
# SESSION CREATION & MANAGEMENT
# ============================================

func create_session(peer_id: int, player_info: Dictionary) -> String:
	"""Create a new session for a player"""
	var session = SessionData.new()
	session.session_id = _generate_session_id()
	session.peer_id = peer_id
	session.player_id = player_info.get("player_id", 0)
	session.username = player_info.get("username", player_info.get("name", "Player"))
	session.steam_id = player_info.get("steam_id", 0)
	session.character_class = player_info.get("character_class", "")
	session.level = player_info.get("level", 1)
	session.created_at = Time.get_unix_time_from_system()
	session.last_active = session.created_at
	session.is_connected = true

	active_sessions[session.session_id] = session
	peer_to_session[peer_id] = session.session_id

	session_created.emit(session.session_id)
	print("Session created: %s for player %s (peer %d)" % [session.session_id, session.username, peer_id])

	return session.session_id

func get_session(session_id: String) -> SessionData:
	"""Get session by ID"""
	return active_sessions.get(session_id, null)

func get_session_by_peer(peer_id: int) -> SessionData:
	"""Get session by peer ID"""
	if peer_to_session.has(peer_id):
		return active_sessions.get(peer_to_session[peer_id], null)
	return null

func get_session_by_player_id(player_id: int) -> SessionData:
	"""Get session by player ID (for reconnection)"""
	for session_id in active_sessions:
		var session = active_sessions[session_id]
		if session.player_id == player_id:
			return session
	return null

func get_session_by_steam_id(steam_id: int) -> SessionData:
	"""Get session by Steam ID (for reconnection)"""
	for session_id in active_sessions:
		var session = active_sessions[session_id]
		if session.steam_id == steam_id:
			return session
	return null

func update_session_state(peer_id: int, state: Dictionary):
	"""Update session with current game state"""
	var session = get_session_by_peer(peer_id)
	if not session:
		return

	session.last_active = Time.get_unix_time_from_system()

	if state.has("position"):
		session.position = state.position
	if state.has("rotation"):
		session.rotation = state.rotation
	if state.has("health"):
		session.health = state.health
	if state.has("score"):
		session.score = state.score
	if state.has("kills"):
		session.kills = state.kills
	if state.has("deaths"):
		session.deaths = state.deaths
	if state.has("is_alive"):
		session.is_alive = state.is_alive
	if state.has("inventory"):
		session.inventory = state.inventory
	if state.has("equipped_weapon"):
		session.equipped_weapon = state.equipped_weapon
	if state.has("ammo"):
		session.ammo = state.ammo

# ============================================
# DISCONNECTION & RECONNECTION
# ============================================

func on_player_disconnected(peer_id: int):
	"""Handle player disconnect - keep session for potential reconnection"""
	if not peer_to_session.has(peer_id):
		return

	var session_id = peer_to_session[peer_id]
	var session = active_sessions.get(session_id, null)

	if session:
		session.is_connected = false
		session.last_active = Time.get_unix_time_from_system()
		disconnected_sessions[session_id] = Time.get_unix_time_from_system()

		player_disconnected_temp.emit(peer_id, session_id)
		print("Player %s disconnected temporarily (session %s kept for %.0f seconds)" %
			[session.username, session_id, max_reconnect_time])

	peer_to_session.erase(peer_id)

func try_reconnect(peer_id: int, player_info: Dictionary) -> SessionData:
	"""Try to reconnect player to existing session"""
	var session: SessionData = null

	# Try by player ID
	var player_id = player_info.get("player_id", 0)
	if player_id > 0:
		session = get_session_by_player_id(player_id)

	# Try by Steam ID
	if not session:
		var steam_id = player_info.get("steam_id", 0)
		if steam_id > 0:
			session = get_session_by_steam_id(steam_id)

	if session and not session.is_connected:
		# Reconnect to existing session
		session.peer_id = peer_id
		session.is_connected = true
		session.last_active = Time.get_unix_time_from_system()

		peer_to_session[peer_id] = session.session_id
		disconnected_sessions.erase(session.session_id)

		player_reconnected.emit(peer_id, session.session_id)
		print("Player %s reconnected to session %s" % [session.username, session.session_id])

		return session

	return null

func destroy_session(session_id: String):
	"""Destroy a session completely"""
	if not active_sessions.has(session_id):
		return

	var session = active_sessions[session_id]

	# Remove from mappings
	if peer_to_session.has(session.peer_id):
		peer_to_session.erase(session.peer_id)

	disconnected_sessions.erase(session_id)
	active_sessions.erase(session_id)

	session_expired.emit(session_id)
	print("Session destroyed: %s" % session_id)

# ============================================
# SESSION PERSISTENCE
# ============================================

func _save_sessions():
	"""Save sessions to file"""
	var data = []
	for session_id in active_sessions:
		data.append(active_sessions[session_id].to_dict())

	var json_string = JSON.stringify(data)
	var file = FileAccess.open(SESSION_FILE, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()

func _load_sessions():
	"""Load sessions from file"""
	if not FileAccess.file_exists(SESSION_FILE):
		return

	var file = FileAccess.open(SESSION_FILE, FileAccess.READ)
	if not file:
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var result = json.parse(json_string)
	if result != OK:
		return

	var data = json.data
	if data is Array:
		for session_dict in data:
			var session = SessionData.from_dict(session_dict)
			# Only restore recent sessions (within timeout)
			var age = Time.get_unix_time_from_system() - session.last_active
			if age < session_timeout:
				session.is_connected = false  # Mark as disconnected until reconnect
				active_sessions[session.session_id] = session
				print("Restored session: %s for player %s" % [session.session_id, session.username])

# ============================================
# UTILITY
# ============================================

func _generate_session_id() -> String:
	"""Generate a unique session ID"""
	var chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var id = ""
	for i in range(32):
		id += chars[randi() % chars.length()]
	return id

func _check_expired_sessions():
	"""Check and remove expired disconnected sessions"""
	var current_time = Time.get_unix_time_from_system()
	var expired = []

	for session_id in disconnected_sessions:
		var disconnect_time = disconnected_sessions[session_id]
		if current_time - disconnect_time > max_reconnect_time:
			expired.append(session_id)

	for session_id in expired:
		print("Session %s expired (reconnect timeout)" % session_id)
		destroy_session(session_id)

func get_active_session_count() -> int:
	"""Get count of active sessions"""
	var count = 0
	for session_id in active_sessions:
		if active_sessions[session_id].is_connected:
			count += 1
	return count

func get_all_sessions() -> Array:
	"""Get all active sessions as dictionaries"""
	var sessions = []
	for session_id in active_sessions:
		sessions.append(active_sessions[session_id].to_dict())
	return sessions

func clear_all_sessions():
	"""Clear all sessions (for server reset)"""
	active_sessions.clear()
	peer_to_session.clear()
	disconnected_sessions.clear()
	print("All sessions cleared")
