extends Node
class_name SigilDefenseSystem

## Sigil Defense System - Tower Defense style gameplay
## Players protect a sigil from zombie waves
## Extraction becomes available at certain rounds

signal sigil_damaged(damage: float, current_health: float)
signal sigil_destroyed
signal sigil_healed(amount: float, current_health: float)
signal extraction_available(extraction_point: Vector3)
signal extraction_started(player_peer_id: int)
signal extraction_completed(player_peer_id: int)
signal extraction_cancelled(player_peer_id: int)
signal round_started(round_number: int)
signal round_completed(round_number: int)
signal teleport_triggered(new_area: String)
signal final_extraction_complete

# Sigil configuration
@export var sigil_max_health: float = 1000.0
@export var sigil_position: Vector3 = Vector3.ZERO
@export var extraction_interval: int = 5
@export var final_extraction_round: int = 30
@export var extraction_time: float = 15.0

# Current state
var sigil_health: float = 1000.0
var current_round: int = 0
var is_extraction_available: bool = false
var extraction_positions: Array = []
var players_extracting: Dictionary = {}
var is_server: bool = false

# Sigil node reference
var sigil_node: Node3D = null

func _ready():
	is_server = multiplayer.is_server() if multiplayer.has_multiplayer_peer() else true
	sigil_health = sigil_max_health
	call_deferred("_find_sigil")

func _find_sigil():
	var sigils = get_tree().get_nodes_in_group("sigil")
	if sigils.size() > 0:
		sigil_node = sigils[0]
		sigil_position = sigil_node.global_position
		if "health" in sigil_node:
			sigil_health = sigil_node.health
			sigil_max_health = sigil_node.health

func _process(delta):
	if not is_server:
		return
	_update_extractions(delta)

func _update_extractions(delta):
	for peer_id in players_extracting.keys():
		players_extracting[peer_id] -= delta
		if players_extracting[peer_id] <= 0:
			_complete_extraction(peer_id)

# ============================================
# SIGIL MANAGEMENT
# ============================================

func damage_sigil(damage: float, attacker_id: int = 0):
	if not is_server:
		return
	sigil_health = max(0, sigil_health - damage)
	if is_instance_valid(sigil_node) and "health" in sigil_node:
		sigil_node.health = sigil_health
	_sync_sigil_damage.rpc(damage, sigil_health)
	sigil_damaged.emit(damage, sigil_health)
	if sigil_health <= 0:
		_sigil_destroyed()

func heal_sigil(amount: float):
	if not is_server:
		return
	var old_health = sigil_health
	sigil_health = min(sigil_max_health, sigil_health + amount)
	var actual_heal = sigil_health - old_health
	if actual_heal > 0:
		if is_instance_valid(sigil_node) and "health" in sigil_node:
			sigil_node.health = sigil_health
		_sync_sigil_heal.rpc(actual_heal, sigil_health)
		sigil_healed.emit(actual_heal, sigil_health)

func _sigil_destroyed():
	sigil_destroyed.emit()
	_sync_sigil_destroyed.rpc()

@rpc("authority", "call_remote", "reliable")
func _sync_sigil_damage(_damage: float, _health: float):
	sigil_health = _health
	sigil_damaged.emit(_damage, _health)

@rpc("authority", "call_remote", "reliable")
func _sync_sigil_heal(_amount: float, _health: float):
	sigil_health = _health
	sigil_healed.emit(_amount, _health)

@rpc("authority", "call_remote", "reliable")
func _sync_sigil_destroyed():
	sigil_destroyed.emit()

# ============================================
# ROUND MANAGEMENT
# ============================================

func start_round(round_number: int):
	if not is_server:
		return
	current_round = round_number
	is_extraction_available = false
	_sync_round_started.rpc(round_number)
	round_started.emit(round_number)

func complete_round():
	if not is_server:
		return
	_sync_round_completed.rpc(current_round)
	round_completed.emit(current_round)
	if current_round % extraction_interval == 0:
		_spawn_extraction()
	if current_round >= final_extraction_round:
		_enable_final_extraction()

@rpc("authority", "call_remote", "reliable")
func _sync_round_started(_round: int):
	current_round = _round
	round_started.emit(_round)

@rpc("authority", "call_remote", "reliable")
func _sync_round_completed(_round: int):
	round_completed.emit(_round)

# ============================================
# EXTRACTION SYSTEM
# ============================================

func _spawn_extraction():
	var spawn_points = get_tree().get_nodes_in_group("extraction_spawn")
	if spawn_points.is_empty():
		return
	var point = spawn_points[randi() % spawn_points.size()]
	var pos = point.global_position
	extraction_positions.append(pos)
	is_extraction_available = true
	_sync_extraction_available.rpc(pos)
	extraction_available.emit(pos)

func _enable_final_extraction():
	is_extraction_available = true
	for point in get_tree().get_nodes_in_group("extraction_spawn"):
		extraction_positions.append(point.global_position)
		_sync_extraction_available.rpc(point.global_position)
		extraction_available.emit(point.global_position)

@rpc("authority", "call_remote", "reliable")
func _sync_extraction_available(_position: Vector3):
	extraction_positions.append(_position)
	is_extraction_available = true
	extraction_available.emit(_position)

func start_extraction(peer_id: int) -> bool:
	if not is_extraction_available:
		return false
	if players_extracting.has(peer_id):
		return false
	players_extracting[peer_id] = extraction_time
	_sync_extraction_started.rpc(peer_id)
	extraction_started.emit(peer_id)
	return true

func cancel_extraction(peer_id: int):
	if players_extracting.has(peer_id):
		players_extracting.erase(peer_id)
		_sync_extraction_cancelled.rpc(peer_id)
		extraction_cancelled.emit(peer_id)

func _complete_extraction(peer_id: int):
	players_extracting.erase(peer_id)
	_sync_extraction_completed.rpc(peer_id)
	extraction_completed.emit(peer_id)

	# Check if this was final extraction
	if current_round >= final_extraction_round:
		_sync_final_extraction.rpc()
		final_extraction_complete.emit()

@rpc("authority", "call_remote", "reliable")
func _sync_final_extraction():
	final_extraction_complete.emit()

@rpc("authority", "call_remote", "reliable")
func _sync_extraction_started(_peer_id: int):
	extraction_started.emit(_peer_id)

@rpc("authority", "call_remote", "reliable")
func _sync_extraction_cancelled(_peer_id: int):
	extraction_cancelled.emit(_peer_id)

@rpc("authority", "call_remote", "reliable")
func _sync_extraction_completed(_peer_id: int):
	extraction_completed.emit(_peer_id)

@rpc("any_peer", "reliable")
func request_start_extraction():
	if is_server:
		var peer_id = multiplayer.get_remote_sender_id()
		start_extraction(peer_id)

@rpc("any_peer", "reliable")
func request_cancel_extraction():
	if is_server:
		var peer_id = multiplayer.get_remote_sender_id()
		cancel_extraction(peer_id)

# ============================================
# TELEPORT SYSTEM
# ============================================

func trigger_teleport(new_area: String):
	if not is_server:
		return
	_sync_teleport.rpc(new_area)
	teleport_triggered.emit(new_area)
	current_round = 0
	sigil_health = sigil_max_health
	extraction_positions.clear()
	is_extraction_available = false

@rpc("authority", "call_remote", "reliable")
func _sync_teleport(_area: String):
	teleport_triggered.emit(_area)

# ============================================
# UTILITY
# ============================================

func get_sigil_health_percent() -> float:
	return (sigil_health / sigil_max_health) * 100.0

func is_player_in_extraction_zone(position: Vector3, radius: float = 3.0) -> bool:
	for ext_pos in extraction_positions:
		if position.distance_to(ext_pos) <= radius:
			return true
	return false

func get_round_difficulty_multiplier() -> float:
	return 1.0 + (current_round * 0.1)

func get_loot_multiplier() -> float:
	if current_round >= final_extraction_round:
		return 2.0
	return 1.0 + (current_round * 0.05)
