extends Node
class_name SurvivalSystemNode

## Survival System - Manages hunger, thirst, and related survival mechanics
## Works as an autoload to track player survival stats and spawn consumables

signal player_hunger_critical(player: Node)
signal player_thirst_critical(player: Node)
signal player_starving(player: Node)
signal player_dehydrated(player: Node)
signal consumable_spawned(item: Node)

# Consumable item definitions
const CONSUMABLE_TYPES = {
	"canned_beans": {
		"name": "Canned Beans",
		"type": "food",
		"value": 25.0,
		"use_time": 3.0,
		"weight": 0.5,
		"rarity": 0.6
	},
	"canned_meat": {
		"name": "Canned Meat",
		"type": "food",
		"value": 35.0,
		"use_time": 3.5,
		"weight": 0.6,
		"rarity": 0.4
	},
	"crackers": {
		"name": "Crackers",
		"type": "food",
		"value": 15.0,
		"use_time": 2.0,
		"weight": 0.2,
		"rarity": 0.7
	},
	"energy_bar": {
		"name": "Energy Bar",
		"type": "food",
		"value": 20.0,
		"use_time": 1.5,
		"weight": 0.1,
		"rarity": 0.5,
		"bonus_stamina": 30.0
	},
	"mre": {
		"name": "MRE",
		"type": "food",
		"value": 50.0,
		"use_time": 5.0,
		"weight": 0.8,
		"rarity": 0.2
	},
	"water_bottle": {
		"name": "Water Bottle",
		"type": "water",
		"value": 30.0,
		"use_time": 2.0,
		"weight": 0.5,
		"rarity": 0.6
	},
	"soda": {
		"name": "Soda",
		"type": "water",
		"value": 20.0,
		"use_time": 1.5,
		"weight": 0.4,
		"rarity": 0.5,
		"bonus_stamina": 15.0
	},
	"juice_box": {
		"name": "Juice Box",
		"type": "water",
		"value": 15.0,
		"use_time": 1.0,
		"weight": 0.25,
		"rarity": 0.6,
		"bonus_food": 5.0
	},
	"canteen": {
		"name": "Canteen",
		"type": "water",
		"value": 50.0,
		"use_time": 3.0,
		"weight": 0.7,
		"rarity": 0.3
	},
	"medkit": {
		"name": "Medkit",
		"type": "health",
		"value": 50.0,
		"use_time": 5.0,
		"weight": 1.0,
		"rarity": 0.2
	},
	"bandage": {
		"name": "Bandage",
		"type": "health",
		"value": 20.0,
		"use_time": 2.0,
		"weight": 0.1,
		"rarity": 0.5
	},
	"painkillers": {
		"name": "Painkillers",
		"type": "health",
		"value": 15.0,
		"use_time": 1.0,
		"weight": 0.05,
		"rarity": 0.4,
		"bonus_stamina": 20.0
	},
	"energy_drink": {
		"name": "Energy Drink",
		"type": "stamina",
		"value": 50.0,
		"use_time": 1.5,
		"weight": 0.3,
		"rarity": 0.3,
		"bonus_water": 10.0
	},
	"adrenaline": {
		"name": "Adrenaline Shot",
		"type": "stamina",
		"value": 100.0,
		"use_time": 1.0,
		"weight": 0.1,
		"rarity": 0.1
	}
}

# Spawn settings
@export var spawn_interval: float = 60.0  # Seconds between spawn waves
@export var items_per_wave: int = 5
@export var spawn_radius: float = 50.0
@export var max_spawned_items: int = 30

# Tracked items
var spawned_items: Array[Node] = []
var spawn_timer: float = 0.0
var spawn_points: Array[Vector3] = []

# Network
var is_server: bool = false

func _ready():
	is_server = multiplayer.is_server() if multiplayer.has_multiplayer_peer() else true

	# Find spawn points in the level
	_find_spawn_points()

func _process(delta):
	if not is_server:
		return

	# Periodic spawn
	spawn_timer += delta
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		_spawn_wave()

	# Monitor players
	_check_player_survival()

func _find_spawn_points():
	"""Find item spawn points in the level"""
	spawn_points.clear()

	# Look for designated spawn points
	var spawn_nodes = get_tree().get_nodes_in_group("item_spawn_points")
	for node in spawn_nodes:
		if node is Node3D:
			spawn_points.append(node.global_position)

	# Also add some random points if not enough spawn points
	if spawn_points.size() < 10:
		# Generate random points around origin
		for i in range(20):
			var angle = randf() * TAU
			var dist = randf_range(10.0, spawn_radius)
			spawn_points.append(Vector3(
				cos(angle) * dist,
				1.0,  # Ground level
				sin(angle) * dist
			))

func _spawn_wave():
	"""Spawn a wave of consumable items"""
	# Clean up collected items
	spawned_items = spawned_items.filter(func(item): return is_instance_valid(item))

	if spawned_items.size() >= max_spawned_items:
		return

	var items_to_spawn = min(items_per_wave, max_spawned_items - spawned_items.size())

	for i in range(items_to_spawn):
		_spawn_random_item()

func _spawn_random_item():
	"""Spawn a single random consumable item"""
	if spawn_points.is_empty():
		return

	# Pick random spawn point
	var spawn_pos = spawn_points[randi() % spawn_points.size()]
	spawn_pos += Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))

	# Pick random item based on rarity
	var item_id = _pick_random_item()
	if item_id.is_empty():
		return

	# Create the item
	var item = _create_consumable(item_id, spawn_pos)
	if item:
		spawned_items.append(item)
		consumable_spawned.emit(item)

func _pick_random_item() -> String:
	"""Pick a random item weighted by rarity"""
	var total_weight = 0.0
	for id in CONSUMABLE_TYPES:
		total_weight += CONSUMABLE_TYPES[id].rarity

	var roll = randf() * total_weight
	var current = 0.0

	for id in CONSUMABLE_TYPES:
		current += CONSUMABLE_TYPES[id].rarity
		if roll <= current:
			return id

	return CONSUMABLE_TYPES.keys()[0]

func _create_consumable(item_id: String, position: Vector3) -> Node:
	"""Create a consumable item at the given position"""
	var item_data = CONSUMABLE_TYPES.get(item_id)
	if not item_data:
		return null

	# Load or create the consumable scene
	var consumable_scene = load("res://scenes/items/consumable_item.tscn")
	if not consumable_scene:
		# Create a basic consumable if scene doesn't exist
		consumable_scene = _create_basic_consumable_scene()

	var item = consumable_scene.instantiate()
	item.global_position = position

	# Set item properties
	if item.has_method("setup"):
		item.setup(item_id, item_data)
	else:
		item.set_meta("item_id", item_id)
		item.set_meta("item_data", item_data)

	# Add to scene
	var items_container = get_tree().root.get_node_or_null("Main/Items")
	if items_container:
		items_container.add_child(item)
	else:
		get_tree().current_scene.add_child(item)

	return item

func _create_basic_consumable_scene() -> PackedScene:
	"""Create a basic consumable scene programmatically"""
	var scene = PackedScene.new()
	var root = RigidBody3D.new()
	root.name = "ConsumableItem"

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.3, 0.2, 0.3)
	collision.shape = shape
	root.add_child(collision)
	collision.owner = root

	var mesh = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(0.3, 0.2, 0.3)
	mesh.mesh = box_mesh
	root.add_child(mesh)
	mesh.owner = root

	scene.pack(root)
	return scene

func _check_player_survival():
	"""Check all players for critical survival states"""
	var players = get_tree().get_nodes_in_group("player")

	for player in players:
		if not player.has_method("get_state"):
			continue

		var state = player.get_state() if player.has_method("get_state") else {}

		# Check hunger
		var hunger = state.get("hunger", 100.0)
		if hunger <= 20 and hunger > 0:
			player_hunger_critical.emit(player)
		elif hunger <= 0:
			player_starving.emit(player)

		# Check thirst
		var thirst = state.get("thirst", 100.0)
		if thirst <= 20 and thirst > 0:
			player_thirst_critical.emit(player)
		elif thirst <= 0:
			player_dehydrated.emit(player)

# ============================================
# PUBLIC API
# ============================================

func get_consumable_data(item_id: String) -> Dictionary:
	"""Get data for a consumable item"""
	return CONSUMABLE_TYPES.get(item_id, {})

func get_all_consumable_types() -> Array:
	"""Get all consumable type IDs"""
	return CONSUMABLE_TYPES.keys()

func spawn_item_at(item_id: String, position: Vector3) -> Node:
	"""Spawn a specific item at a position"""
	return _create_consumable(item_id, position)

func spawn_random_item_at(position: Vector3) -> Node:
	"""Spawn a random item at a position"""
	var item_id = _pick_random_item()
	return _create_consumable(item_id, position)

func add_spawn_point(position: Vector3):
	"""Add a spawn point for items"""
	spawn_points.append(position)

func clear_spawn_points():
	"""Clear all spawn points"""
	spawn_points.clear()

func force_spawn_wave():
	"""Force spawn a wave of items immediately"""
	_spawn_wave()

# ============================================
# NETWORK
# ============================================

@rpc("authority", "call_local", "reliable")
func sync_spawn_item(item_id: String, position: Vector3):
	"""Sync item spawn across network"""
	_create_consumable(item_id, position)

@rpc("any_peer", "call_local", "reliable")
func request_consume_item(item_node_path: String, player_id: int):
	"""Request to consume an item (server validates)"""
	if not is_server:
		return

	var item = get_node_or_null(item_node_path)
	if not item:
		return

	# Find the player
	var players = get_tree().get_nodes_in_group("player")
	for player in players:
		if player.get_multiplayer_authority() == player_id:
			if item.has_method("consume"):
				item.consume(player)
			break
