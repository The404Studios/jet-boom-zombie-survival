extends Node3D
class_name ItemSpawner

## Item Spawner - Spawns consumable items at designated points
## Place in levels to create loot spawn locations

signal item_spawned(item: Node)
signal item_collected(item_id: String)

# Spawn settings
@export_group("Spawn Settings")
@export var spawn_on_ready: bool = true
@export var respawn_enabled: bool = true
@export var respawn_time: float = 120.0  # Seconds
@export var spawn_chance: float = 0.8  # 80% chance to have item

# Item filter
@export_group("Item Filter")
@export var allowed_types: Array[String] = ["food", "water", "health", "stamina"]
@export var item_whitelist: Array[String] = []  # Empty = all items
@export var item_blacklist: Array[String] = []
@export var rarity_modifier: float = 1.0  # Higher = more rare items

# Visual
@export_group("Visual")
@export var show_spawn_indicator: bool = true
@export var indicator_color: Color = Color(0.5, 0.8, 1.0, 0.5)

# State
var current_item: Node = null
var respawn_timer: float = 0.0
var is_waiting_respawn: bool = false

# References
@onready var indicator: MeshInstance3D = $SpawnIndicator if has_node("SpawnIndicator") else null

func _ready():
	add_to_group("item_spawn_points")

	# Create indicator if needed
	if show_spawn_indicator and not indicator:
		_create_spawn_indicator()

	# Initial spawn
	if spawn_on_ready:
		_try_spawn()

func _process(delta):
	# Handle respawn timer
	if is_waiting_respawn and respawn_enabled:
		respawn_timer -= delta
		if respawn_timer <= 0:
			is_waiting_respawn = false
			_try_spawn()

	# Update indicator
	_update_indicator()

func _try_spawn():
	"""Attempt to spawn an item"""
	if current_item and is_instance_valid(current_item):
		return  # Already have an item

	# Check spawn chance
	if randf() > spawn_chance:
		# No spawn this time, set up respawn
		_start_respawn_timer()
		return

	# Get survival system
	var survival_system = get_node_or_null("/root/SurvivalSystem")
	if not survival_system:
		# Create item manually
		_spawn_fallback_item()
		return

	# Pick an item to spawn
	var item_id = _pick_item(survival_system)
	if item_id.is_empty():
		return

	# Spawn the item
	current_item = survival_system.spawn_item_at(item_id, global_position)
	if current_item:
		# Connect to item destruction
		current_item.tree_exited.connect(_on_item_collected)
		item_spawned.emit(current_item)

		# Hide indicator
		if indicator:
			indicator.visible = false

func _pick_item(survival_system) -> String:
	"""Pick an item to spawn based on filters"""
	var all_items = survival_system.get_all_consumable_types()
	var valid_items: Array[String] = []

	for item_id in all_items:
		var data = survival_system.get_consumable_data(item_id)

		# Check type filter
		if not allowed_types.is_empty() and not data.get("type", "") in allowed_types:
			continue

		# Check whitelist
		if not item_whitelist.is_empty() and not item_id in item_whitelist:
			continue

		# Check blacklist
		if item_id in item_blacklist:
			continue

		valid_items.append(item_id)

	if valid_items.is_empty():
		return ""

	# Weight by rarity
	var total_weight = 0.0
	var weights: Array[float] = []

	for item_id in valid_items:
		var data = survival_system.get_consumable_data(item_id)
		var rarity = data.get("rarity", 0.5)
		# Apply rarity modifier (higher modifier = favor rarer items)
		var weight = rarity * (1.0 / rarity_modifier) if rarity_modifier > 0 else rarity
		weights.append(weight)
		total_weight += weight

	var roll = randf() * total_weight
	var current = 0.0

	for i in range(valid_items.size()):
		current += weights[i]
		if roll <= current:
			return valid_items[i]

	return valid_items[0] if valid_items.size() > 0 else ""

func _spawn_fallback_item():
	"""Spawn a basic item if survival system isn't available"""
	var consumable_scene = load("res://scenes/items/consumable_item.tscn")
	if not consumable_scene:
		return

	current_item = consumable_scene.instantiate()
	current_item.global_position = global_position

	# Random basic item
	var types = ["food", "water", "health"]
	var random_type = types[randi() % types.size()]

	if current_item.has_method("setup"):
		current_item.setup("basic_" + random_type, {
			"name": random_type.capitalize(),
			"type": random_type,
			"value": 25.0,
			"use_time": 2.0,
			"weight": 0.5,
			"rarity": 0.5
		})

	get_tree().current_scene.add_child(current_item)
	current_item.tree_exited.connect(_on_item_collected)
	item_spawned.emit(current_item)

	if indicator:
		indicator.visible = false

func _on_item_collected():
	"""Called when the spawned item is collected/destroyed"""
	var item_id = ""
	if current_item and current_item.has_meta("item_id"):
		item_id = current_item.get_meta("item_id")

	current_item = null
	item_collected.emit(item_id)

	# Start respawn timer
	if respawn_enabled:
		_start_respawn_timer()
	else:
		# Show indicator again
		if indicator:
			indicator.visible = show_spawn_indicator

func _start_respawn_timer():
	"""Start the respawn countdown"""
	is_waiting_respawn = true
	respawn_timer = respawn_time

	# Show indicator
	if indicator:
		indicator.visible = show_spawn_indicator

func _create_spawn_indicator():
	"""Create a visual indicator for the spawn point"""
	indicator = MeshInstance3D.new()
	indicator.name = "SpawnIndicator"

	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.3
	mesh.bottom_radius = 0.3
	mesh.height = 0.05
	indicator.mesh = mesh

	var mat = StandardMaterial3D.new()
	mat.albedo_color = indicator_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = indicator_color
	mat.emission_energy_multiplier = 0.5
	indicator.material_override = mat

	indicator.position = Vector3(0, 0.03, 0)
	add_child(indicator)

func _update_indicator():
	"""Update spawn indicator visual"""
	if not indicator or not indicator.visible:
		return

	# Pulse effect
	var pulse = (sin(Time.get_ticks_msec() * 0.003) + 1.0) * 0.5
	var mat = indicator.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color.a = indicator_color.a * (0.5 + pulse * 0.5)

# ============================================
# PUBLIC API
# ============================================

func force_spawn():
	"""Force spawn an item immediately"""
	if current_item and is_instance_valid(current_item):
		current_item.queue_free()
	_try_spawn()

func clear_item():
	"""Remove the current item without triggering respawn"""
	respawn_enabled = false
	if current_item and is_instance_valid(current_item):
		current_item.queue_free()
	respawn_enabled = true

func get_current_item() -> Node:
	"""Get the currently spawned item"""
	return current_item if is_instance_valid(current_item) else null

func has_item() -> bool:
	"""Check if there's currently an item at this spawn point"""
	return current_item != null and is_instance_valid(current_item)

func get_time_until_respawn() -> float:
	"""Get remaining time until next spawn"""
	return respawn_timer if is_waiting_respawn else 0.0
