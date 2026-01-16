extends Node

## Survival System - Manages hunger, thirst, temperature, and related survival mechanics
## Works as an autoload to track player survival stats, environmental hazards, and spawn consumables

signal player_hunger_critical(player: Node)
signal player_thirst_critical(player: Node)
signal player_starving(player: Node)
signal player_dehydrated(player: Node)
signal player_hypothermia(player: Node)
signal player_overheating(player: Node)
signal consumable_spawned(item: Node)
signal hazard_entered(player: Node, hazard_type: String)
signal hazard_exited(player: Node, hazard_type: String)
signal weather_changed(weather_type: String)
signal temperature_changed(player: Node, temperature: float)

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

# Environmental Hazard Types
const HAZARD_TYPES = {
	"radiation": {
		"name": "Radiation Zone",
		"description": "High radiation area - causes radiation sickness",
		"condition": "infected",  # Uses infected condition for radiation sickness
		"damage_per_second": 5.0,
		"color": Color(0.2, 0.8, 0.2, 0.3),
		"warning_message": "Warning: Entering irradiated area!"
	},
	"toxic_gas": {
		"name": "Toxic Gas",
		"description": "Poisonous fumes - causes poisoning",
		"condition": "poison",
		"damage_per_second": 8.0,
		"color": Color(0.6, 0.8, 0.2, 0.4),
		"warning_message": "Warning: Toxic gas detected!"
	},
	"fire": {
		"name": "Fire Zone",
		"description": "Active fire - causes burns",
		"condition": "burn",
		"damage_per_second": 15.0,
		"color": Color(1.0, 0.3, 0.0, 0.5),
		"warning_message": "Warning: Fire hazard!"
	},
	"cold": {
		"name": "Freezing Area",
		"description": "Extreme cold - causes hypothermia",
		"condition": "freeze",
		"damage_per_second": 3.0,
		"temperature_effect": -30.0,  # Degrees below normal
		"color": Color(0.3, 0.5, 1.0, 0.3),
		"warning_message": "Warning: Extreme cold!"
	},
	"acid": {
		"name": "Acid Pool",
		"description": "Corrosive acid - causes rapid damage",
		"condition": "bleed",
		"damage_per_second": 20.0,
		"color": Color(0.4, 1.0, 0.2, 0.5),
		"warning_message": "Warning: Corrosive substance!"
	},
	"darkness": {
		"name": "Dark Zone",
		"description": "Complete darkness - impaired vision, increased zombie aggro",
		"condition": "vulnerable",
		"damage_per_second": 0.0,
		"color": Color(0.0, 0.0, 0.0, 0.8),
		"warning_message": "Warning: Entering darkness..."
	}
}

# Weather Types
const WEATHER_TYPES = {
	"clear": {
		"name": "Clear",
		"temperature_modifier": 0.0,
		"visibility": 1.0,
		"ambient_color": Color(1.0, 1.0, 1.0)
	},
	"rain": {
		"name": "Rainy",
		"temperature_modifier": -5.0,
		"visibility": 0.7,
		"ambient_color": Color(0.7, 0.7, 0.8),
		"condition_chance": 0.1  # Chance to apply "slow" condition
	},
	"storm": {
		"name": "Storm",
		"temperature_modifier": -10.0,
		"visibility": 0.4,
		"ambient_color": Color(0.5, 0.5, 0.6),
		"condition_chance": 0.2
	},
	"fog": {
		"name": "Foggy",
		"temperature_modifier": -3.0,
		"visibility": 0.3,
		"ambient_color": Color(0.8, 0.8, 0.85)
	},
	"snow": {
		"name": "Snow",
		"temperature_modifier": -20.0,
		"visibility": 0.5,
		"ambient_color": Color(0.9, 0.95, 1.0),
		"condition_chance": 0.15  # Chance for "freeze" stacks
	},
	"heatwave": {
		"name": "Heat Wave",
		"temperature_modifier": 25.0,
		"visibility": 0.9,
		"ambient_color": Color(1.1, 0.95, 0.9),
		"stamina_drain_multiplier": 1.5
	},
	"night": {
		"name": "Night",
		"temperature_modifier": -8.0,
		"visibility": 0.4,
		"ambient_color": Color(0.3, 0.3, 0.5),
		"zombie_spawn_multiplier": 1.5
	}
}

# Spawn settings
@export var spawn_interval: float = 60.0  # Seconds between spawn waves
@export var items_per_wave: int = 5
@export var spawn_radius: float = 50.0
@export var max_spawned_items: int = 30

# Temperature settings
@export var base_temperature: float = 20.0  # Comfortable temperature (Celsius)
@export var hypothermia_threshold: float = -10.0  # Below this causes hypothermia
@export var overheat_threshold: float = 40.0  # Above this causes overheating
@export var temperature_change_rate: float = 2.0  # How fast body temp changes

# Survival settings
@export var hunger_decay_rate: float = 1.0  # Per minute
@export var thirst_decay_rate: float = 1.5  # Per minute
@export var starving_damage_rate: float = 2.0  # DPS when starving
@export var dehydration_damage_rate: float = 3.0  # DPS when dehydrated

# Tracked items
var spawned_items: Array[Node] = []
var spawn_timer: float = 0.0
var spawn_points: Array[Vector3] = []

# Weather system
var current_weather: String = "clear"
var weather_timer: float = 0.0
var weather_change_interval: float = 300.0  # 5 minutes between weather changes

# Player survival data (peer_id -> survival_stats)
var player_survival_data: Dictionary = {}

# Active hazard zones
var active_hazard_zones: Array[Node] = []

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

	# Weather system
	weather_timer += delta
	if weather_timer >= weather_change_interval:
		weather_timer = 0.0
		_change_weather()

	# Update survival for all players
	_update_player_survival(delta)

	# Monitor players for critical states
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
		var peer_id = player.get_multiplayer_authority() if player.has_method("get_multiplayer_authority") else 0
		var data = _get_or_create_player_data(peer_id)

		# Check hunger
		if data.hunger <= 20 and data.hunger > 0:
			player_hunger_critical.emit(player)
		elif data.hunger <= 0:
			player_starving.emit(player)

		# Check thirst
		if data.thirst <= 20 and data.thirst > 0:
			player_thirst_critical.emit(player)
		elif data.thirst <= 0:
			player_dehydrated.emit(player)

		# Check temperature
		if data.body_temperature <= hypothermia_threshold:
			player_hypothermia.emit(player)
		elif data.body_temperature >= overheat_threshold:
			player_overheating.emit(player)

func _get_or_create_player_data(peer_id: int) -> Dictionary:
	"""Get or create survival data for a player"""
	if not player_survival_data.has(peer_id):
		player_survival_data[peer_id] = {
			"hunger": 100.0,
			"thirst": 100.0,
			"body_temperature": base_temperature,
			"stamina_regen_modifier": 1.0,
			"in_hazard_zones": [],  # List of hazard types player is in
			"last_update": Time.get_ticks_msec()
		}
	return player_survival_data[peer_id]

func _update_player_survival(delta: float):
	"""Update survival stats for all players"""
	var players = get_tree().get_nodes_in_group("player")

	for player in players:
		var peer_id = player.get_multiplayer_authority() if player.has_method("get_multiplayer_authority") else 0
		var data = _get_or_create_player_data(peer_id)

		# Decay hunger and thirst
		data.hunger = max(0.0, data.hunger - (hunger_decay_rate * delta / 60.0))
		data.thirst = max(0.0, data.thirst - (thirst_decay_rate * delta / 60.0))

		# Update body temperature based on environment
		var target_temp = _calculate_target_temperature(player, data)
		data.body_temperature = move_toward(data.body_temperature, target_temp, temperature_change_rate * delta)

		# Apply starvation/dehydration damage
		if data.hunger <= 0 and player.has_method("take_damage"):
			player.take_damage(starving_damage_rate * delta)
		if data.thirst <= 0 and player.has_method("take_damage"):
			player.take_damage(dehydration_damage_rate * delta)

		# Apply temperature effects
		_apply_temperature_effects(player, data)

		# Apply weather effects
		_apply_weather_effects(player, data, delta)

		# Sync to player if they have survival state
		if player.has_method("set_survival_state"):
			player.set_survival_state(data)

func _calculate_target_temperature(player: Node, data: Dictionary) -> float:
	"""Calculate target body temperature based on environment"""
	var target = base_temperature

	# Weather modifier
	var weather_data = WEATHER_TYPES.get(current_weather, {})
	target += weather_data.get("temperature_modifier", 0.0)

	# Hazard zone modifiers
	for hazard_type in data.in_hazard_zones:
		var hazard_data = HAZARD_TYPES.get(hazard_type, {})
		if "temperature_effect" in hazard_data:
			target += hazard_data.temperature_effect

	# Indoor bonus (if player is in a structure)
	if player.has_method("is_indoors") and player.is_indoors():
		# Normalize temperature toward comfortable range
		target = move_toward(target, base_temperature, 15.0)

	# Equipment insulation (if they have warm clothing)
	if player.has_node("EquipmentSystem"):
		var equip = player.get_node("EquipmentSystem")
		if equip.has_method("get_total_bonuses"):
			var bonuses = equip.get_total_bonuses()
			var insulation = bonuses.get("cold_resist", 0.0) / 100.0
			if target < base_temperature:
				target = lerp(target, base_temperature, insulation * 0.5)

	return target

func _apply_temperature_effects(player: Node, data: Dictionary):
	"""Apply effects based on body temperature"""
	var conditions = player.get_node_or_null("PlayerConditions")
	if not conditions:
		return

	# Hypothermia effects
	if data.body_temperature <= hypothermia_threshold:
		if not conditions.has_condition("freeze"):
			conditions.apply_condition("freeze", 5.0)
		# Slow movement, reduce stamina regen
		data.stamina_regen_modifier = 0.5

	# Overheating effects
	elif data.body_temperature >= overheat_threshold:
		# Faster stamina drain, dehydration
		data.stamina_regen_modifier = 0.7
		data.thirst = max(0.0, data.thirst - 0.5)  # Extra thirst loss

	else:
		data.stamina_regen_modifier = 1.0

func _apply_weather_effects(player: Node, _data: Dictionary, delta: float):
	"""Apply weather-specific effects to players"""
	var weather_data = WEATHER_TYPES.get(current_weather, {})

	# Random condition application (rain/storm/snow)
	if "condition_chance" in weather_data:
		if randf() < weather_data.condition_chance * delta:
			var conditions = player.get_node_or_null("PlayerConditions")
			if conditions:
				match current_weather:
					"rain", "storm":
						conditions.apply_condition("slow", 3.0, 1)
					"snow":
						conditions.apply_condition("freeze", 2.0, 1)

func _change_weather():
	"""Change to a new random weather type"""
	var weather_types = WEATHER_TYPES.keys()
	var new_weather = weather_types[randi() % weather_types.size()]

	# Don't allow instant switch to extreme weather
	if current_weather == "clear" and new_weather in ["storm", "heatwave"]:
		# Transition through intermediate weather
		new_weather = ["rain", "fog", "night"][randi() % 3]

	current_weather = new_weather
	weather_changed.emit(current_weather)
	sync_weather.rpc(current_weather)

# ============================================
# HAZARD ZONE HANDLING
# ============================================

func register_hazard_zone(zone: Node):
	"""Register a hazard zone with the system"""
	if zone not in active_hazard_zones:
		active_hazard_zones.append(zone)

func unregister_hazard_zone(zone: Node):
	"""Unregister a hazard zone"""
	active_hazard_zones.erase(zone)

func player_entered_hazard(player: Node, hazard_type: String):
	"""Called when a player enters a hazard zone"""
	var peer_id = player.get_multiplayer_authority() if player.has_method("get_multiplayer_authority") else 0
	var data = _get_or_create_player_data(peer_id)

	if hazard_type not in data.in_hazard_zones:
		data.in_hazard_zones.append(hazard_type)
		hazard_entered.emit(player, hazard_type)

		# Apply immediate condition
		var hazard_data = HAZARD_TYPES.get(hazard_type, {})
		var conditions = player.get_node_or_null("PlayerConditions")
		if conditions and "condition" in hazard_data:
			conditions.apply_condition(hazard_data.condition, 5.0, 1)

func player_exited_hazard(player: Node, hazard_type: String):
	"""Called when a player exits a hazard zone"""
	var peer_id = player.get_multiplayer_authority() if player.has_method("get_multiplayer_authority") else 0
	var data = _get_or_create_player_data(peer_id)

	data.in_hazard_zones.erase(hazard_type)
	hazard_exited.emit(player, hazard_type)

func apply_hazard_damage(player: Node, hazard_type: String, delta: float):
	"""Apply damage from being in a hazard zone"""
	var hazard_data = HAZARD_TYPES.get(hazard_type, {})
	var dps = hazard_data.get("damage_per_second", 0.0)

	if dps > 0 and player.has_method("take_damage"):
		player.take_damage(dps * delta)

	# Stack conditions while in hazard
	var conditions = player.get_node_or_null("PlayerConditions")
	if conditions and "condition" in hazard_data:
		if not conditions.has_condition(hazard_data.condition):
			conditions.apply_condition(hazard_data.condition, 5.0, 1)

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

@rpc("authority", "call_local", "reliable")
func sync_weather(weather_type: String):
	"""Sync weather state across network"""
	current_weather = weather_type
	weather_changed.emit(current_weather)

@rpc("authority", "call_local", "reliable")
func sync_player_survival(peer_id: int, hunger: float, thirst: float, temperature: float):
	"""Sync player survival data from server"""
	var data = _get_or_create_player_data(peer_id)
	data.hunger = hunger
	data.thirst = thirst
	data.body_temperature = temperature

# ============================================
# ADDITIONAL PUBLIC API
# ============================================

func get_player_survival_data(peer_id: int) -> Dictionary:
	"""Get survival data for a specific player"""
	return _get_or_create_player_data(peer_id).duplicate()

func modify_hunger(peer_id: int, amount: float):
	"""Add or remove hunger (positive = add food, negative = remove)"""
	var data = _get_or_create_player_data(peer_id)
	data.hunger = clamp(data.hunger + amount, 0.0, 100.0)

func modify_thirst(peer_id: int, amount: float):
	"""Add or remove thirst (positive = add water, negative = remove)"""
	var data = _get_or_create_player_data(peer_id)
	data.thirst = clamp(data.thirst + amount, 0.0, 100.0)

func get_current_weather() -> String:
	"""Get current weather type"""
	return current_weather

func get_weather_data() -> Dictionary:
	"""Get data for current weather"""
	return WEATHER_TYPES.get(current_weather, {})

func set_weather(weather_type: String):
	"""Force set weather (server only)"""
	if is_server and WEATHER_TYPES.has(weather_type):
		current_weather = weather_type
		weather_changed.emit(current_weather)
		sync_weather.rpc(current_weather)

func get_hazard_data(hazard_type: String) -> Dictionary:
	"""Get data for a hazard type"""
	return HAZARD_TYPES.get(hazard_type, {})

func get_all_hazard_types() -> Array:
	"""Get all hazard type IDs"""
	return HAZARD_TYPES.keys()

func is_player_in_hazard(peer_id: int, hazard_type: String) -> bool:
	"""Check if player is in a specific hazard zone"""
	var data = _get_or_create_player_data(peer_id)
	return hazard_type in data.in_hazard_zones

func get_player_hazards(peer_id: int) -> Array:
	"""Get list of hazards player is currently in"""
	var data = _get_or_create_player_data(peer_id)
	return data.in_hazard_zones.duplicate()

func consume_item_on_player(player: Node, item_id: String) -> bool:
	"""Apply a consumable's effects to a player"""
	var item_data = CONSUMABLE_TYPES.get(item_id)
	if not item_data:
		return false

	var peer_id = player.get_multiplayer_authority() if player.has_method("get_multiplayer_authority") else 0
	var survival_data = _get_or_create_player_data(peer_id)

	match item_data.type:
		"food":
			survival_data.hunger = min(100.0, survival_data.hunger + item_data.value)
			if "bonus_stamina" in item_data and player.has_method("restore_stamina"):
				player.restore_stamina(item_data.bonus_stamina)
		"water":
			survival_data.thirst = min(100.0, survival_data.thirst + item_data.value)
			if "bonus_food" in item_data:
				survival_data.hunger = min(100.0, survival_data.hunger + item_data.bonus_food)
			if "bonus_stamina" in item_data and player.has_method("restore_stamina"):
				player.restore_stamina(item_data.bonus_stamina)
		"health":
			if player.has_method("heal"):
				player.heal(item_data.value)
			if "bonus_stamina" in item_data and player.has_method("restore_stamina"):
				player.restore_stamina(item_data.bonus_stamina)
		"stamina":
			if player.has_method("restore_stamina"):
				player.restore_stamina(item_data.value)
			if "bonus_water" in item_data:
				survival_data.thirst = min(100.0, survival_data.thirst + item_data.bonus_water)

	return true

func reset_player_survival(peer_id: int):
	"""Reset a player's survival stats to full"""
	var data = _get_or_create_player_data(peer_id)
	data.hunger = 100.0
	data.thirst = 100.0
	data.body_temperature = base_temperature
	data.stamina_regen_modifier = 1.0
	data.in_hazard_zones.clear()

func remove_player_survival_data(peer_id: int):
	"""Remove survival data for a disconnected player"""
	player_survival_data.erase(peer_id)
