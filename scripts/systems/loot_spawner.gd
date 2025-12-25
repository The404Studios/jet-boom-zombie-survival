extends Node
class_name LootSpawner

# Loot Spawner System - Spawns loot items around the map
# Handles initial loot, wave loot, zombie drops, and random spawns

signal loot_spawned(loot_node: Node3D, item_data: Resource)
signal loot_collected(player: Node, item_data: Resource)

# Loot item scenes
@export var loot_item_scene: PackedScene
@export var weapon_pickup_scene: PackedScene
@export var ammo_pickup_scene: PackedScene
@export var health_pickup_scene: PackedScene

# Spawn configuration
@export var initial_loot_count: int = 15
@export var loot_per_wave: int = 5
@export var max_active_loot: int = 50
@export var spawn_height_offset: float = 0.5

# Loot spawn areas
var loot_spawn_points: Array[Node3D] = []
var active_loot: Array[Node3D] = []

# Loot tables
var common_loot: Array[Dictionary] = []
var uncommon_loot: Array[Dictionary] = []
var rare_loot: Array[Dictionary] = []
var epic_loot: Array[Dictionary] = []
var legendary_loot: Array[Dictionary] = []

# Reference to arena
var arena: Node = null

func _ready():
	add_to_group("loot_spawner")

	# Load default scenes
	if not loot_item_scene:
		if ResourceLoader.exists("res://scenes/items/loot_item.tscn"):
			loot_item_scene = load("res://scenes/items/loot_item.tscn")
	if not weapon_pickup_scene:
		if ResourceLoader.exists("res://scenes/items/weapon_pickup.tscn"):
			weapon_pickup_scene = load("res://scenes/items/weapon_pickup.tscn")
	if not ammo_pickup_scene:
		if ResourceLoader.exists("res://scenes/items/ammo_pickup.tscn"):
			ammo_pickup_scene = load("res://scenes/items/ammo_pickup.tscn")
	if not health_pickup_scene:
		if ResourceLoader.exists("res://scenes/items/health_pickup.tscn"):
			health_pickup_scene = load("res://scenes/items/health_pickup.tscn")

	# Initialize loot tables
	_initialize_loot_tables()

	# Find spawn points
	await get_tree().create_timer(0.1).timeout
	_collect_spawn_points()

	# Find arena
	arena = get_tree().get_first_node_in_group("arena_manager")

func _collect_spawn_points():
	loot_spawn_points.clear()

	# Find loot spawn markers
	var spawns = get_tree().get_nodes_in_group("loot_spawn")
	for spawn in spawns:
		if spawn is Node3D:
			loot_spawn_points.append(spawn)

	# If no spawn points, create defaults based on arena size
	if loot_spawn_points.is_empty():
		_create_default_spawn_points()

	print("Loot Spawner: Found %d spawn points" % loot_spawn_points.size())

func _create_default_spawn_points():
	# Create a grid of spawn points
	var grid_size = 10
	var spacing = 15.0
	var center = Vector3.ZERO

	# Find sigil for center reference
	var sigil = get_tree().get_first_node_in_group("sigil")
	if sigil:
		center = sigil.global_position

	for x in range(-grid_size / 2, grid_size / 2):
		for z in range(-grid_size / 2, grid_size / 2):
			# Skip center area (near sigil)
			if abs(x) < 2 and abs(z) < 2:
				continue

			var marker = Marker3D.new()
			marker.position = center + Vector3(x * spacing, 0, z * spacing)
			marker.add_to_group("loot_spawn")
			add_child(marker)
			loot_spawn_points.append(marker)

func _initialize_loot_tables():
	# Common loot (60% chance)
	common_loot = [
		{"type": "ammo", "subtype": "pistol", "quantity": 30, "weight": 30},
		{"type": "ammo", "subtype": "rifle", "quantity": 30, "weight": 25},
		{"type": "ammo", "subtype": "shotgun", "quantity": 10, "weight": 20},
		{"type": "health", "subtype": "small", "amount": 25, "weight": 15},
		{"type": "material", "subtype": "scrap_small", "quantity": 5, "weight": 10},
	]

	# Uncommon loot (25% chance)
	uncommon_loot = [
		{"type": "ammo", "subtype": "rifle", "quantity": 60, "weight": 25},
		{"type": "ammo", "subtype": "heavy", "quantity": 50, "weight": 20},
		{"type": "health", "subtype": "medium", "amount": 50, "weight": 20},
		{"type": "material", "subtype": "scrap_small", "quantity": 15, "weight": 15},
		{"type": "material", "subtype": "weapon_parts", "quantity": 3, "weight": 10},
		{"type": "weapon", "subtype": "pistol", "weight": 10},
	]

	# Rare loot (10% chance)
	rare_loot = [
		{"type": "ammo", "subtype": "special", "quantity": 30, "weight": 20},
		{"type": "health", "subtype": "large", "amount": 100, "weight": 15},
		{"type": "material", "subtype": "scrap_medium", "quantity": 10, "weight": 20},
		{"type": "material", "subtype": "weapon_parts", "quantity": 8, "weight": 15},
		{"type": "weapon", "subtype": "revolver", "weight": 15},
		{"type": "weapon", "subtype": "shotgun", "weight": 10},
		{"type": "gear", "subtype": "helmet", "rarity": "uncommon", "weight": 5},
	]

	# Epic loot (4% chance)
	epic_loot = [
		{"type": "material", "subtype": "scrap_large", "quantity": 10, "weight": 25},
		{"type": "material", "subtype": "rare_alloy", "quantity": 3, "weight": 20},
		{"type": "weapon", "subtype": "ak47", "weight": 20},
		{"type": "weapon", "subtype": "sniper", "weight": 15},
		{"type": "gear", "subtype": "chest", "rarity": "rare", "weight": 10},
		{"type": "augment", "subtype": "damage", "weight": 10},
	]

	# Legendary loot (1% chance)
	legendary_loot = [
		{"type": "material", "subtype": "mythic_core", "quantity": 1, "weight": 20},
		{"type": "material", "subtype": "rare_alloy", "quantity": 8, "weight": 20},
		{"type": "weapon", "subtype": "legendary_deagle", "weight": 15},
		{"type": "weapon", "subtype": "minigun", "weight": 15},
		{"type": "gear", "subtype": "chest", "rarity": "legendary", "weight": 15},
		{"type": "augment", "subtype": "legendary", "weight": 15},
	]

# ============================================
# SPAWN FUNCTIONS
# ============================================

func spawn_initial_loot():
	"""Spawn loot at the start of the game"""
	print("Spawning initial loot: %d items" % initial_loot_count)

	var spawned = 0
	var used_points: Array[Node3D] = []

	while spawned < initial_loot_count and used_points.size() < loot_spawn_points.size():
		var spawn_point = _get_unused_spawn_point(used_points)
		if not spawn_point:
			break

		used_points.append(spawn_point)

		# Higher chance of common/uncommon for initial loot
		var loot_data = _roll_loot_with_bias(0.7, 0.2, 0.08, 0.02, 0.0)
		if loot_data:
			_spawn_loot_at_point(spawn_point.global_position, loot_data)
			spawned += 1

	print("Spawned %d initial loot items" % spawned)

func spawn_wave_loot(wave_number: int):
	"""Spawn additional loot for a wave"""
	var loot_count = loot_per_wave + int(wave_number / 2)

	print("Spawning wave %d loot: %d items" % [wave_number, loot_count])

	for i in range(loot_count):
		if active_loot.size() >= max_active_loot:
			break

		var spawn_point = _get_random_spawn_point()
		if not spawn_point:
			continue

		# Better loot chances in later waves
		var legendary_chance = min(0.02 + (wave_number * 0.005), 0.1)
		var epic_chance = min(0.05 + (wave_number * 0.01), 0.15)
		var rare_chance = min(0.15 + (wave_number * 0.02), 0.25)
		var uncommon_chance = 0.3
		var common_chance = 1.0 - legendary_chance - epic_chance - rare_chance - uncommon_chance

		var loot_data = _roll_loot_with_bias(common_chance, uncommon_chance, rare_chance, epic_chance, legendary_chance)
		if loot_data:
			_spawn_loot_at_point(spawn_point.global_position, loot_data)

func spawn_zombie_drop(position: Vector3, zombie_type: String = "shambler"):
	"""Spawn loot when a zombie dies"""
	# Drop chance based on zombie type
	var drop_chance = 0.3
	match zombie_type:
		"runner": drop_chance = 0.25
		"tank": drop_chance = 0.5
		"monster": drop_chance = 0.8
		"boss": drop_chance = 1.0

	if randf() > drop_chance:
		return

	# Rarity chances based on zombie type
	var common = 0.6
	var uncommon = 0.25
	var rare = 0.1
	var epic = 0.04
	var legendary = 0.01

	match zombie_type:
		"tank":
			common = 0.4
			uncommon = 0.35
			rare = 0.2
			epic = 0.05
		"monster":
			common = 0.2
			uncommon = 0.3
			rare = 0.3
			epic = 0.15
			legendary = 0.05
		"boss":
			common = 0.0
			uncommon = 0.2
			rare = 0.4
			epic = 0.3
			legendary = 0.1

	var loot_data = _roll_loot_with_bias(common, uncommon, rare, epic, legendary)
	if loot_data:
		# Add slight random offset
		var offset = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		_spawn_loot_at_point(position + offset, loot_data)

func spawn_specific_loot(position: Vector3, loot_type: String, loot_subtype: String, quantity: int = 1):
	"""Spawn a specific type of loot"""
	var loot_data = {
		"type": loot_type,
		"subtype": loot_subtype,
		"quantity": quantity
	}
	_spawn_loot_at_point(position, loot_data)

# ============================================
# INTERNAL SPAWN LOGIC
# ============================================

func _get_unused_spawn_point(used: Array) -> Node3D:
	var available: Array[Node3D] = []
	for point in loot_spawn_points:
		if point not in used:
			available.append(point)

	if available.is_empty():
		return null

	return available[randi() % available.size()]

func _get_random_spawn_point() -> Node3D:
	if loot_spawn_points.is_empty():
		return null
	return loot_spawn_points[randi() % loot_spawn_points.size()]

func _roll_loot_with_bias(common: float, uncommon: float, rare: float, epic: float, legendary: float) -> Dictionary:
	var roll = randf()
	var loot_table: Array[Dictionary]

	if roll < legendary:
		loot_table = legendary_loot
	elif roll < legendary + epic:
		loot_table = epic_loot
	elif roll < legendary + epic + rare:
		loot_table = rare_loot
	elif roll < legendary + epic + rare + uncommon:
		loot_table = uncommon_loot
	else:
		loot_table = common_loot

	return _roll_from_table(loot_table)

func _roll_from_table(table: Array[Dictionary]) -> Dictionary:
	if table.is_empty():
		return {}

	# Calculate total weight
	var total_weight = 0.0
	for item in table:
		total_weight += item.get("weight", 1.0)

	# Roll
	var roll = randf() * total_weight
	var cumulative = 0.0

	for item in table:
		cumulative += item.get("weight", 1.0)
		if roll <= cumulative:
			return item.duplicate()

	return table[0].duplicate()

func _spawn_loot_at_point(position: Vector3, loot_data: Dictionary):
	if active_loot.size() >= max_active_loot:
		return

	var spawn_pos = position + Vector3(0, spawn_height_offset, 0)

	var loot_node: Node3D = null

	match loot_data.get("type", ""):
		"ammo":
			loot_node = _spawn_ammo(spawn_pos, loot_data)
		"health":
			loot_node = _spawn_health(spawn_pos, loot_data)
		"weapon":
			loot_node = _spawn_weapon(spawn_pos, loot_data)
		"material":
			loot_node = _spawn_material(spawn_pos, loot_data)
		"gear":
			loot_node = _spawn_gear(spawn_pos, loot_data)
		"augment":
			loot_node = _spawn_augment(spawn_pos, loot_data)
		_:
			loot_node = _spawn_generic(spawn_pos, loot_data)

	if loot_node:
		active_loot.append(loot_node)

		# Connect pickup signal
		if loot_node.has_signal("picked_up"):
			loot_node.picked_up.connect(_on_loot_picked_up.bind(loot_node))

		# Store loot data
		loot_node.set_meta("loot_data", loot_data)

		loot_spawned.emit(loot_node, null)

func _spawn_ammo(position: Vector3, data: Dictionary) -> Node3D:
	if not ammo_pickup_scene:
		return _spawn_generic(position, data)

	var ammo = ammo_pickup_scene.instantiate()
	_add_to_arena(ammo)
	ammo.global_position = position

	if "subtype" in data:
		ammo.set_meta("ammo_type", data.subtype)
	if "quantity" in data:
		ammo.set_meta("quantity", data.quantity)

	return ammo

func _spawn_health(position: Vector3, data: Dictionary) -> Node3D:
	if not health_pickup_scene:
		return _spawn_generic(position, data)

	var health = health_pickup_scene.instantiate()
	_add_to_arena(health)
	health.global_position = position

	if "amount" in data:
		health.set_meta("heal_amount", data.amount)

	return health

func _spawn_weapon(position: Vector3, data: Dictionary) -> Node3D:
	if not weapon_pickup_scene:
		return _spawn_generic(position, data)

	var weapon = weapon_pickup_scene.instantiate()
	_add_to_arena(weapon)
	weapon.global_position = position

	if "subtype" in data:
		weapon.set_meta("weapon_type", data.subtype)

	return weapon

func _spawn_material(position: Vector3, data: Dictionary) -> Node3D:
	return _spawn_generic(position, data)

func _spawn_gear(position: Vector3, data: Dictionary) -> Node3D:
	return _spawn_generic(position, data)

func _spawn_augment(position: Vector3, data: Dictionary) -> Node3D:
	return _spawn_generic(position, data)

func _spawn_generic(position: Vector3, data: Dictionary) -> Node3D:
	var loot: Node3D

	if loot_item_scene:
		loot = loot_item_scene.instantiate()
	else:
		# Create a simple visual loot node
		loot = Node3D.new()
		loot.add_to_group("loot")
		loot.add_to_group("interactable")

		var mesh = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.3, 0.3, 0.3)
		mesh.mesh = box

		var mat = StandardMaterial3D.new()
		mat.albedo_color = _get_loot_color(data)
		mat.emission_enabled = true
		mat.emission = _get_loot_color(data)
		mat.emission_energy_multiplier = 0.5
		mesh.material_override = mat

		loot.add_child(mesh)

		# Add collision
		var area = Area3D.new()
		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(0.5, 0.5, 0.5)
		collision.shape = shape
		area.add_child(collision)
		loot.add_child(area)

		# Add script behavior
		loot.set_script(preload("res://scripts/items/loot_item.gd") if ResourceLoader.exists("res://scripts/items/loot_item.gd") else null)

	_add_to_arena(loot)
	loot.global_position = position

	return loot

func _get_loot_color(data: Dictionary) -> Color:
	match data.get("type", ""):
		"ammo": return Color(0.8, 0.6, 0.2)
		"health": return Color(0.2, 0.8, 0.2)
		"weapon": return Color(0.8, 0.3, 0.3)
		"material": return Color(0.5, 0.5, 0.8)
		"gear": return Color(0.8, 0.5, 0.8)
		"augment": return Color(0.8, 0.2, 0.8)
	return Color(0.6, 0.6, 0.6)

func _add_to_arena(node: Node):
	if arena:
		arena.add_child(node)
	else:
		var current_scene = get_tree().current_scene
		if current_scene:
			current_scene.add_child(node)
		else:
			add_child(node)

func _on_loot_picked_up(player: Node, loot_node: Node3D):
	active_loot.erase(loot_node)

	var loot_data = loot_node.get_meta("loot_data", {})
	loot_collected.emit(player, null)

# ============================================
# CLEANUP
# ============================================

func clear_all_loot():
	"""Remove all active loot from the map"""
	for loot in active_loot:
		if is_instance_valid(loot):
			loot.queue_free()
	active_loot.clear()

func despawn_distant_loot(center: Vector3, max_distance: float):
	"""Despawn loot too far from center"""
	var to_remove: Array[Node3D] = []

	for loot in active_loot:
		if is_instance_valid(loot):
			if loot.global_position.distance_to(center) > max_distance:
				to_remove.append(loot)

	for loot in to_remove:
		active_loot.erase(loot)
		loot.queue_free()
