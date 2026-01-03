extends Node
# Note: Do not use class_name here - this script is an autoload singleton

# Manages spawn points for players, zombies, and items
# Handles spawn selection, validation, and dynamic spawn creation

signal spawn_point_added(spawn_point: Node3D, type: String)
signal spawn_point_removed(spawn_point: Node3D)

enum SpawnType {
	PLAYER,
	ZOMBIE,
	ITEM,
	VEHICLE,
	BOSS
}

# Spawn point collections
var player_spawns: Array[Node3D] = []
var zombie_spawns: Array[Node3D] = []
var item_spawns: Array[Node3D] = []
var boss_spawns: Array[Node3D] = []

# Spawn settings
@export var min_spawn_distance_from_players: float = 15.0
@export var max_spawn_attempts: int = 10
@export var spawn_check_radius: float = 1.0
@export var spawn_height_offset: float = 0.5

# Team spawns (for team-based modes)
var team_spawns: Dictionary = {}  # team_id -> Array[Node3D]

# Last used spawns (to avoid clustering)
var last_player_spawn_index: int = -1
var last_zombie_spawn_index: int = -1

# Dynamic spawn tracking
var dynamic_spawns: Array[Node3D] = []

func _ready():
	# Find all spawn points in scene
	call_deferred("_collect_spawn_points")

func _collect_spawn_points():
	"""Find all spawn points in the current scene"""
	player_spawns.clear()
	zombie_spawns.clear()
	item_spawns.clear()
	boss_spawns.clear()
	team_spawns.clear()

	# Player spawns
	for spawn in get_tree().get_nodes_in_group("player_spawn"):
		if spawn is Node3D:
			player_spawns.append(spawn)

			# Check for team assignment
			if spawn.has_meta("team"):
				var team = spawn.get_meta("team")
				if not team_spawns.has(team):
					team_spawns[team] = []
				team_spawns[team].append(spawn)

	# Zombie spawns
	for spawn in get_tree().get_nodes_in_group("zombie_spawn"):
		if spawn is Node3D:
			zombie_spawns.append(spawn)

	# Item spawns
	for spawn in get_tree().get_nodes_in_group("item_spawn"):
		if spawn is Node3D:
			item_spawns.append(spawn)

	# Boss spawns
	for spawn in get_tree().get_nodes_in_group("boss_spawn"):
		if spawn is Node3D:
			boss_spawns.append(spawn)

	print("SpawnManager: Found %d player, %d zombie, %d item, %d boss spawns" % [
		player_spawns.size(), zombie_spawns.size(),
		item_spawns.size(), boss_spawns.size()
	])

# ============================================
# PLAYER SPAWNING
# ============================================

func get_spawn_position(team_id: int = -1) -> Vector3:
	"""Get a valid spawn position for a player"""
	var spawns = _get_player_spawns(team_id)

	if spawns.is_empty():
		push_warning("No player spawn points found!")
		return Vector3(0, 1, 0)

	# Try to find a spawn away from other players
	for _attempt in range(max_spawn_attempts):
		var spawn = _select_spawn_point(spawns, last_player_spawn_index)
		last_player_spawn_index = spawns.find(spawn)

		var pos = spawn.global_position + Vector3(0, spawn_height_offset, 0)

		if _is_spawn_valid(pos, true):
			return pos

	# Fallback to any spawn
	var fallback = spawns[randi() % spawns.size()]
	return fallback.global_position + Vector3(0, spawn_height_offset, 0)

func get_spawn_transform(team_id: int = -1) -> Transform3D:
	"""Get a valid spawn transform (position + rotation)"""
	var spawns = _get_player_spawns(team_id)

	if spawns.is_empty():
		return Transform3D.IDENTITY.translated(Vector3(0, 1, 0))

	var spawn = _select_spawn_point(spawns, last_player_spawn_index)
	last_player_spawn_index = spawns.find(spawn)

	var transform = spawn.global_transform
	transform.origin.y += spawn_height_offset

	return transform

func _get_player_spawns(team_id: int) -> Array:
	"""Get appropriate spawn points for a team"""
	if team_id >= 0 and team_spawns.has(team_id):
		return team_spawns[team_id]
	return player_spawns

func _select_spawn_point(spawns: Array, last_index: int) -> Node3D:
	"""Select a spawn point, preferring ones not recently used"""
	if spawns.size() == 1:
		return spawns[0]

	# Weight spawns by distance from last spawn
	var weights = []
	for i in range(spawns.size()):
		var weight = 1.0
		if i == last_index:
			weight = 0.1  # Low weight for last used
		weights.append(weight)

	return _weighted_random_choice(spawns, weights)

# ============================================
# ZOMBIE SPAWNING
# ============================================

func get_zombie_spawn_position(avoid_players: bool = true) -> Vector3:
	"""Get a valid spawn position for a zombie"""
	if zombie_spawns.is_empty():
		# Fallback to player spawns if no zombie spawns
		if not player_spawns.is_empty():
			return player_spawns[randi() % player_spawns.size()].global_position
		return Vector3(0, 1, 0)

	for _attempt in range(max_spawn_attempts):
		var spawn = _select_spawn_point(zombie_spawns, last_zombie_spawn_index)
		last_zombie_spawn_index = zombie_spawns.find(spawn)

		var pos = spawn.global_position + Vector3(0, spawn_height_offset, 0)

		if avoid_players:
			if _is_away_from_players(pos, min_spawn_distance_from_players):
				return pos
		else:
			return pos

	# Fallback
	return zombie_spawns[randi() % zombie_spawns.size()].global_position

func get_zombie_spawn_positions(count: int, avoid_players: bool = true) -> Array[Vector3]:
	"""Get multiple zombie spawn positions"""
	var positions: Array[Vector3] = []

	for _i in range(count):
		var pos = get_zombie_spawn_position(avoid_players)
		positions.append(pos)

	return positions

func get_zombie_spawns_near_position(position: Vector3, radius: float, count: int = 1) -> Array[Vector3]:
	"""Get zombie spawns within radius of a position"""
	var nearby_spawns = zombie_spawns.filter(func(s):
		return s.global_position.distance_to(position) <= radius
	)

	if nearby_spawns.is_empty():
		return [get_zombie_spawn_position()]

	var positions: Array[Vector3] = []
	for i in range(mini(count, nearby_spawns.size())):
		var spawn = nearby_spawns[randi() % nearby_spawns.size()]
		positions.append(spawn.global_position)
		nearby_spawns.erase(spawn)

	return positions

# ============================================
# ITEM SPAWNING
# ============================================

func get_item_spawn_position() -> Vector3:
	"""Get a position for spawning items"""
	if item_spawns.is_empty():
		return Vector3(0, 0.5, 0)

	var spawn = item_spawns[randi() % item_spawns.size()]
	return spawn.global_position

func get_item_spawn_positions(count: int) -> Array[Vector3]:
	"""Get multiple item spawn positions"""
	var positions: Array[Vector3] = []
	var available = item_spawns.duplicate()

	for _i in range(count):
		if available.is_empty():
			available = item_spawns.duplicate()

		var spawn = available[randi() % available.size()]
		positions.append(spawn.global_position)
		available.erase(spawn)

	return positions

# ============================================
# BOSS SPAWNING
# ============================================

func get_boss_spawn_position() -> Vector3:
	"""Get spawn position for a boss"""
	if boss_spawns.is_empty():
		# Fallback to zombie spawn
		return get_zombie_spawn_position(true)

	# Select spawn furthest from all players
	var best_spawn = boss_spawns[0]
	var best_min_dist = 0.0

	for spawn in boss_spawns:
		var min_dist = _get_min_distance_to_players(spawn.global_position)
		if min_dist > best_min_dist:
			best_min_dist = min_dist
			best_spawn = spawn

	return best_spawn.global_position

# ============================================
# DYNAMIC SPAWN CREATION
# ============================================

func create_spawn_point(position: Vector3, type: SpawnType, team_id: int = -1) -> Node3D:
	"""Dynamically create a spawn point"""
	var spawn = Marker3D.new()
	spawn.global_position = position

	match type:
		SpawnType.PLAYER:
			spawn.add_to_group("player_spawn")
			player_spawns.append(spawn)
			if team_id >= 0:
				spawn.set_meta("team", team_id)
				if not team_spawns.has(team_id):
					team_spawns[team_id] = []
				team_spawns[team_id].append(spawn)
		SpawnType.ZOMBIE:
			spawn.add_to_group("zombie_spawn")
			zombie_spawns.append(spawn)
		SpawnType.ITEM:
			spawn.add_to_group("item_spawn")
			item_spawns.append(spawn)
		SpawnType.BOSS:
			spawn.add_to_group("boss_spawn")
			boss_spawns.append(spawn)

	var scene = get_tree().current_scene
	if scene:
		scene.add_child(spawn)

	dynamic_spawns.append(spawn)
	spawn_point_added.emit(spawn, SpawnType.keys()[type])

	return spawn

func remove_spawn_point(spawn: Node3D):
	"""Remove a spawn point"""
	player_spawns.erase(spawn)
	zombie_spawns.erase(spawn)
	item_spawns.erase(spawn)
	boss_spawns.erase(spawn)
	dynamic_spawns.erase(spawn)

	for team_id in team_spawns:
		team_spawns[team_id].erase(spawn)

	spawn_point_removed.emit(spawn)

	if is_instance_valid(spawn):
		spawn.queue_free()

func clear_dynamic_spawns():
	"""Remove all dynamically created spawns"""
	for spawn in dynamic_spawns.duplicate():
		remove_spawn_point(spawn)
	dynamic_spawns.clear()

# ============================================
# VALIDATION
# ============================================

func _is_spawn_valid(position: Vector3, check_players: bool = true) -> bool:
	"""Check if a spawn position is valid"""
	# Check for obstructions
	var space_state = get_tree().root.get_world_3d().direct_space_state
	if not space_state:
		return true

	var query = PhysicsShapeQueryParameters3D.new()
	var shape = SphereShape3D.new()
	shape.radius = spawn_check_radius
	query.shape = shape
	query.transform = Transform3D.IDENTITY.translated(position)
	query.collision_mask = 1  # World layer

	var results = space_state.intersect_shape(query)
	if not results.is_empty():
		return false

	# Check distance from players
	if check_players:
		return _is_away_from_players(position, 2.0)  # Minimum distance

	return true

func _is_away_from_players(position: Vector3, min_distance: float) -> bool:
	"""Check if position is far enough from all players"""
	var players = get_tree().get_nodes_in_group("players")

	for player in players:
		if player is Node3D:
			if position.distance_to(player.global_position) < min_distance:
				return false

	return true

func _get_min_distance_to_players(position: Vector3) -> float:
	"""Get minimum distance to any player"""
	var min_dist = INF
	var players = get_tree().get_nodes_in_group("players")

	for player in players:
		if player is Node3D:
			var dist = position.distance_to(player.global_position)
			if dist < min_dist:
				min_dist = dist

	return min_dist

# ============================================
# UTILITY
# ============================================

func _weighted_random_choice(items: Array, weights: Array) -> Variant:
	"""Select random item with weights"""
	var total_weight = 0.0
	for w in weights:
		total_weight += w

	var random = randf() * total_weight
	var cumulative = 0.0

	for i in range(items.size()):
		cumulative += weights[i]
		if random <= cumulative:
			return items[i]

	return items[-1]

func refresh_spawn_points():
	"""Refresh spawn point collections"""
	_collect_spawn_points()

func get_spawn_count(type: SpawnType) -> int:
	"""Get number of spawn points of a type"""
	match type:
		SpawnType.PLAYER:
			return player_spawns.size()
		SpawnType.ZOMBIE:
			return zombie_spawns.size()
		SpawnType.ITEM:
			return item_spawns.size()
		SpawnType.BOSS:
			return boss_spawns.size()
	return 0
