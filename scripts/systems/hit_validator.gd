extends Node
class_name HitValidator

# Server-side hit validation with lag compensation (backtrack)
# Stores historical positions of all entities for hit verification
# Provides client-side prediction with server confirmation

signal hit_confirmed(attacker_id: int, target: Node, damage: float, hit_data: Dictionary)
signal hit_rejected(attacker_id: int, reason: String)
signal hit_predicted(target: Node, damage: float, hit_data: Dictionary)

# Configuration
@export var max_backtrack_time: float = 0.2  # Maximum lag compensation (200ms)
@export var position_record_interval: float = 0.015  # ~66 tick rate
@export var max_position_records: int = 20  # Keep ~300ms of history
@export var tolerance_distance: float = 0.5  # Hit tolerance in meters
@export var max_ping_tolerance: float = 0.3  # Maximum allowed ping for backtrack

# Position history for all tracked entities
# entity_id -> Array[{timestamp: float, position: Vector3, rotation: Vector3, hitbox_data: Dictionary}]
var position_history: Dictionary = {}

# Pending hit confirmations (client-side)
# hit_id -> {predicted_damage: float, target: Node, timestamp: float, callback: Callable}
var pending_hits: Dictionary = {}
var next_hit_id: int = 0

# Network reference
var network_manager: Node = null

# Timing
var _record_timer: float = 0.0
var _server_time: float = 0.0

func _ready():
	network_manager = get_node_or_null("/root/NetworkManager")
	add_to_group("hit_validator")

func _process(delta):
	_server_time += delta
	_record_timer += delta

	# Record positions at fixed interval
	if _record_timer >= position_record_interval:
		_record_timer = 0.0
		_record_all_positions()

	# Clean old pending hits
	_cleanup_pending_hits()

# ============================================
# POSITION RECORDING (Server & Client)
# ============================================

func _record_all_positions():
	"""Record positions of all trackable entities"""
	# Record zombies
	var zombies = get_tree().get_nodes_in_group("zombies")
	for zombie in zombies:
		if is_instance_valid(zombie):
			_record_entity_position(zombie)

	# Record players (for PvP if needed)
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if is_instance_valid(player):
			_record_entity_position(player)

func _record_entity_position(entity: Node):
	"""Record a single entity's position for backtracking"""
	var entity_id = entity.get_instance_id()

	if not position_history.has(entity_id):
		position_history[entity_id] = []

	var record = {
		"timestamp": _server_time,
		"position": entity.global_position,
		"rotation": entity.global_rotation if "global_rotation" in entity else Vector3.ZERO,
		"hitbox_data": _get_hitbox_data(entity)
	}

	position_history[entity_id].append(record)

	# Limit history size
	while position_history[entity_id].size() > max_position_records:
		position_history[entity_id].pop_front()

func _get_hitbox_data(entity: Node) -> Dictionary:
	"""Get current hitbox information for an entity"""
	var data = {
		"height": 2.0,
		"radius": 0.5,
		"head_height": 1.7
	}

	# Try to get from entity properties
	if "hitbox_height" in entity:
		data.height = entity.hitbox_height
	if "hitbox_radius" in entity:
		data.radius = entity.hitbox_radius
	if "head_height" in entity:
		data.head_height = entity.head_height

	# Try to get from collision shape
	var collision = entity.get_node_or_null("CollisionShape3D")
	if collision and collision.shape:
		if collision.shape is CapsuleShape3D:
			data.height = collision.shape.height
			data.radius = collision.shape.radius
			data.head_height = data.height * 0.85
		elif collision.shape is BoxShape3D:
			data.height = collision.shape.size.y
			data.radius = max(collision.shape.size.x, collision.shape.size.z) * 0.5
			data.head_height = data.height * 0.85

	return data

func get_entity_position_at_time(entity: Node, timestamp: float) -> Dictionary:
	"""Get interpolated position of entity at a past timestamp"""
	var entity_id = entity.get_instance_id()

	if not position_history.has(entity_id):
		# No history, return current position
		return {
			"position": entity.global_position,
			"rotation": entity.global_rotation if "global_rotation" in entity else Vector3.ZERO,
			"hitbox_data": _get_hitbox_data(entity),
			"valid": true,
			"interpolated": false
		}

	var history = position_history[entity_id]
	if history.is_empty():
		return {
			"position": entity.global_position,
			"rotation": entity.global_rotation if "global_rotation" in entity else Vector3.ZERO,
			"hitbox_data": _get_hitbox_data(entity),
			"valid": true,
			"interpolated": false
		}

	# Find bracketing records
	var before_record = null
	var after_record = null

	for i in range(history.size() - 1, -1, -1):
		if history[i].timestamp <= timestamp:
			before_record = history[i]
			if i + 1 < history.size():
				after_record = history[i + 1]
			break

	# If no before record found, timestamp is too old
	if not before_record:
		if history.size() > 0:
			before_record = history[0]
		else:
			return {"valid": false}

	# If no after record, use before record directly
	if not after_record:
		return {
			"position": before_record.position,
			"rotation": before_record.rotation,
			"hitbox_data": before_record.hitbox_data,
			"valid": true,
			"interpolated": false
		}

	# Interpolate between records
	var t = (timestamp - before_record.timestamp) / (after_record.timestamp - before_record.timestamp)
	t = clamp(t, 0.0, 1.0)

	return {
		"position": before_record.position.lerp(after_record.position, t),
		"rotation": before_record.rotation.lerp(after_record.rotation, t),
		"hitbox_data": before_record.hitbox_data,
		"valid": true,
		"interpolated": true
	}

# ============================================
# CLIENT-SIDE HIT PREDICTION
# ============================================

func predict_hit(attacker: Node, target: Node, hit_position: Vector3, damage: float, is_headshot: bool) -> int:
	"""Client predicts a hit and waits for server confirmation"""
	var hit_id = next_hit_id
	next_hit_id += 1

	var hit_data = {
		"hit_id": hit_id,
		"target_id": target.get_instance_id(),
		"target_path": target.get_path(),
		"hit_position": hit_position,
		"predicted_damage": damage,
		"is_headshot": is_headshot,
		"timestamp": _server_time,
		"attacker_position": attacker.global_position if attacker else Vector3.ZERO,
		"target": target
	}

	pending_hits[hit_id] = hit_data

	# Emit prediction for immediate feedback (hit markers, damage numbers)
	hit_predicted.emit(target, damage, hit_data)

	# Send to server for validation
	if network_manager and multiplayer.has_multiplayer_peer():
		var attacker_id = multiplayer.get_unique_id()
		_request_hit_validation.rpc_id(1, attacker_id, hit_id, {
			"target_path": str(target.get_path()),
			"hit_position": [hit_position.x, hit_position.y, hit_position.z],
			"predicted_damage": damage,
			"is_headshot": is_headshot,
			"client_timestamp": _server_time,
			"attacker_position": [attacker.global_position.x, attacker.global_position.y, attacker.global_position.z] if attacker else [0, 0, 0]
		})
	else:
		# Single player - confirm immediately
		_confirm_hit_locally(hit_id, damage)

	return hit_id

func _confirm_hit_locally(hit_id: int, confirmed_damage: float):
	"""Confirm hit in single player mode"""
	if pending_hits.has(hit_id):
		var hit_data = pending_hits[hit_id]
		hit_data["confirmed_damage"] = confirmed_damage
		hit_confirmed.emit(0, hit_data.target, confirmed_damage, hit_data)
		pending_hits.erase(hit_id)

# ============================================
# SERVER-SIDE HIT VALIDATION
# ============================================

@rpc("any_peer", "reliable")
func _request_hit_validation(attacker_id: int, hit_id: int, hit_data: Dictionary):
	"""Server receives hit validation request"""
	if not multiplayer.is_server():
		return

	var sender_id = multiplayer.get_remote_sender_id()

	# Validate attacker matches sender
	if sender_id != attacker_id and sender_id != 0:
		_send_hit_rejection.rpc_id(sender_id, hit_id, "Invalid attacker ID")
		return

	# Get target entity
	var target_path = hit_data.get("target_path", "")
	var target = get_node_or_null(target_path)

	if not target or not is_instance_valid(target):
		_send_hit_rejection.rpc_id(sender_id, hit_id, "Target not found")
		return

	# Calculate client latency (estimate based on ping)
	var client_timestamp = hit_data.get("client_timestamp", _server_time)
	var latency = _server_time - client_timestamp
	latency = clamp(latency, 0.0, max_ping_tolerance)

	# Get target position at the time of the shot (lag compensation)
	var backtrack_time = _server_time - latency
	var historical_data = get_entity_position_at_time(target, backtrack_time)

	if not historical_data.get("valid", false):
		# Fallback to current position
		historical_data = {
			"position": target.global_position,
			"hitbox_data": _get_hitbox_data(target)
		}

	# Reconstruct hit position
	var hit_pos_arr = hit_data.get("hit_position", [0, 0, 0])
	var hit_position = Vector3(hit_pos_arr[0], hit_pos_arr[1], hit_pos_arr[2])

	# Validate hit geometry
	var validation_result = _validate_hit_geometry(
		historical_data.position,
		historical_data.hitbox_data,
		hit_position,
		hit_data.get("is_headshot", false)
	)

	if not validation_result.valid:
		_send_hit_rejection.rpc_id(sender_id, hit_id, validation_result.reason)
		hit_rejected.emit(attacker_id, validation_result.reason)
		return

	# Validate damage calculation
	var predicted_damage = hit_data.get("predicted_damage", 0.0)
	var validated_damage = _validate_damage(attacker_id, target, predicted_damage, hit_data.get("is_headshot", false))

	# Apply damage on server
	if target.has_method("take_damage"):
		target.take_damage(validated_damage, hit_position)

	# Confirm hit to client
	_send_hit_confirmation.rpc_id(sender_id, hit_id, validated_damage, {
		"is_headshot": validation_result.is_headshot,
		"was_kill": _check_if_kill(target),
		"target_health": target.current_health if "current_health" in target else 0.0
	})

	# Broadcast hit effect to all clients
	_broadcast_hit_effect.rpc(hit_position, validation_result.is_headshot, target_path)

	hit_confirmed.emit(attacker_id, target, validated_damage, hit_data)

func _validate_hit_geometry(target_position: Vector3, hitbox_data: Dictionary, hit_position: Vector3, claimed_headshot: bool) -> Dictionary:
	"""Validate that the hit position makes geometric sense"""
	var height = hitbox_data.get("height", 2.0)
	var radius = hitbox_data.get("radius", 0.5)
	var head_height = hitbox_data.get("head_height", height * 0.85)

	# Check horizontal distance
	var horizontal_dist = Vector2(
		hit_position.x - target_position.x,
		hit_position.z - target_position.z
	).length()

	if horizontal_dist > radius + tolerance_distance:
		return {"valid": false, "reason": "Hit too far from target horizontally"}

	# Check vertical position
	var relative_height = hit_position.y - target_position.y
	if relative_height < -tolerance_distance or relative_height > height + tolerance_distance:
		return {"valid": false, "reason": "Hit outside target height"}

	# Validate headshot claim
	var actual_headshot = relative_height >= head_height - 0.2

	# Allow some tolerance on headshot detection
	if claimed_headshot and not actual_headshot:
		# Client claimed headshot but server disagrees - use server's determination
		actual_headshot = false

	return {
		"valid": true,
		"is_headshot": actual_headshot,
		"reason": ""
	}

func _validate_damage(attacker_id: int, target: Node, predicted_damage: float, is_headshot: bool) -> float:
	"""Validate and potentially adjust damage based on server state"""
	# Get attacker's player node
	var attacker = null
	if network_manager and network_manager.player_nodes.has(attacker_id):
		attacker = network_manager.player_nodes[attacker_id]

	if not attacker:
		# Can't find attacker, trust client damage within limits
		return clamp(predicted_damage, 0.0, 500.0)  # Max damage cap

	# Recalculate damage on server (authoritative)
	var base_damage = 15.0
	if attacker.has("current_weapon_data") and attacker.current_weapon_data:
		base_damage = attacker.current_weapon_data.damage if "damage" in attacker.current_weapon_data else 15.0

	var damage = base_damage

	# Apply attribute bonuses from server's knowledge of player
	if attacker.has("character_attributes") and attacker.character_attributes:
		var attrs = attacker.character_attributes
		if attrs.has_method("calculate_ranged_damage"):
			damage = attrs.calculate_ranged_damage(base_damage)

	# Apply skill bonuses
	if attacker.has("skill_tree") and attacker.skill_tree:
		var st = attacker.skill_tree
		if st.has_method("get_effect_value"):
			var damage_bonus = st.get_effect_value("damage_bonus")
			damage *= (1.0 + damage_bonus / 100.0)

	# Apply headshot multiplier
	if is_headshot:
		var headshot_mult = 2.0
		if attacker.has("skill_tree") and attacker.skill_tree:
			var st = attacker.skill_tree
			if st.has_method("get_effect_value"):
				headshot_mult += st.get_effect_value("headshot_bonus") / 100.0
		damage *= headshot_mult

	# Apply executioner skill
	if attacker.has("skill_tree") and attacker.skill_tree:
		var st = attacker.skill_tree
		if st.has_method("has_skill") and st.has_skill("executioner"):
			if target and "current_health" in target and "max_health" in target:
				if target.max_health > 0 and target.current_health / target.max_health < 0.3:
					damage *= 1.5

	# Sanity check - don't let damage differ too much from predicted
	var damage_ratio = damage / max(predicted_damage, 1.0)
	if damage_ratio < 0.5 or damage_ratio > 2.0:
		# Something's wrong, use average
		damage = (damage + predicted_damage) / 2.0

	return damage

func _check_if_kill(target: Node) -> bool:
	"""Check if target is dead/will die"""
	if "current_health" in target:
		return target.current_health <= 0
	if target.has_method("is_dead"):
		return target.is_dead()
	return false

# ============================================
# CLIENT-SIDE CALLBACKS
# ============================================

@rpc("authority", "reliable")
func _send_hit_confirmation(hit_id: int, confirmed_damage: float, extra_data: Dictionary):
	"""Server confirms hit to client"""
	if pending_hits.has(hit_id):
		var hit_data = pending_hits[hit_id]
		hit_data["confirmed_damage"] = confirmed_damage
		hit_data["was_kill"] = extra_data.get("was_kill", false)
		hit_data["server_headshot"] = extra_data.get("is_headshot", false)

		var target = hit_data.get("target")
		hit_confirmed.emit(multiplayer.get_unique_id(), target, confirmed_damage, hit_data)
		pending_hits.erase(hit_id)

@rpc("authority", "reliable")
func _send_hit_rejection(hit_id: int, reason: String):
	"""Server rejects hit"""
	if pending_hits.has(hit_id):
		pending_hits.erase(hit_id)
	hit_rejected.emit(multiplayer.get_unique_id(), reason)

@rpc("authority", "call_local", "unreliable")
func _broadcast_hit_effect(hit_position: Vector3, is_headshot: bool, _target_path: String):
	"""Broadcast hit effects to all clients"""
	# Spawn blood effect
	var gore_system = get_node_or_null("/root/GoreSystem")
	if gore_system and gore_system.has_method("spawn_blood_effect"):
		gore_system.spawn_blood_effect(hit_position, Vector3.UP, 2 if is_headshot else 1)

# ============================================
# CLEANUP
# ============================================

func _cleanup_pending_hits():
	"""Remove old pending hits that timed out"""
	var timeout = 2.0  # 2 second timeout
	var current_time = _server_time
	var to_remove = []

	for hit_id in pending_hits:
		var hit_data = pending_hits[hit_id]
		if current_time - hit_data.timestamp > timeout:
			to_remove.append(hit_id)

	for hit_id in to_remove:
		pending_hits.erase(hit_id)

func clear_entity_history(entity: Node):
	"""Clear history for a specific entity (on death/removal)"""
	var entity_id = entity.get_instance_id()
	if position_history.has(entity_id):
		position_history.erase(entity_id)

func clear_all_history():
	"""Clear all position history"""
	position_history.clear()

func _exit_tree():
	"""Cleanup on removal"""
	position_history.clear()
	pending_hits.clear()
