extends Node
# Note: Do not use class_name here - this script is an autoload singleton
# Access via: PlayerPersistence (the autoload name)

const SAVE_FILE_PATH = "user://player_data.save"
const STASH_FILE_PATH = "user://stash_data.save"

signal data_loaded
signal data_saved
signal backend_synced

# Backend integration
var backend: Node = null
var use_backend: bool = true

# Player data structure
var player_data = {
	"character": {
		"level": 1,
		"experience": 0,
		"stat_points": 0,
		"strength": 10.0,
		"dexterity": 10.0,
		"intelligence": 10.0,
		"agility": 10.0,
		"vitality": 10.0,
		"endurance": 10.0,
		"luck": 10.0
	},
	"currency": {
		"coins": 0,
		"tokens": 0,
		"scrap": 0,
		"sigils": 500  # Starting sigils for shop
	},
	"materials": {
		"scrap_small": 0,
		"scrap_medium": 0,
		"scrap_large": 0,
		"weapon_parts": 0,
		"rare_alloy": 0,
		"mythic_core": 0,
		"augment_crystal": 0
	},
	"stash": [],
	"equipped": {
		"head": null,
		"chest": null,
		"hands": null,
		"legs": null,
		"feet": null,
		"back": null,
		"ring_left": null,
		"ring_right": null,
		"pendant": null,
		"weapon_main": null,
		"weapon_off": null
	},
	"unlocks": {
		"weapons": [],
		"perks": [],
		"zones": []
	},
	"stats": {
		"zombies_killed": 0,
		"waves_survived": 0,
		"items_looted": 0,
		"extractions": 0,
		"deaths": 0
	},
	"settings": {
		"mouse_sensitivity": 0.003,
		"master_volume": 1.0,
		"psx_effects": true
	}
}

func save_player_data(character_stats: Node = null, equipment: Node = null, inventory: Node = null):
	# Update character stats
	if character_stats:
		player_data.character.level = character_stats.level
		player_data.character.experience = character_stats.experience
		player_data.character.stat_points = character_stats.stat_points
		player_data.character.strength = character_stats.strength
		player_data.character.dexterity = character_stats.dexterity
		player_data.character.intelligence = character_stats.intelligence
		player_data.character.agility = character_stats.agility
		player_data.character.vitality = character_stats.vitality

	# Save equipped items
	if equipment:
		player_data.equipped = serialize_equipment(equipment)

	# Save stash
	if inventory:
		player_data.stash = serialize_inventory(inventory.stash)

	# Write to file
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_var(player_data)
		file.close()
		data_saved.emit()
		print("Player data saved successfully")

		# Also sync to backend if available
		if use_backend:
			sync_to_backend()

		return true
	else:
		print("Failed to save player data")
		return false

func _ready():
	# Get backend reference after autoloads are ready
	call_deferred("_init_backend")

func _init_backend():
	backend = get_node_or_null("/root/Backend")
	if backend:
		backend.logged_in.connect(_on_backend_logged_in)

func _exit_tree():
	# Disconnect signals to prevent memory leaks
	if backend:
		if backend.has_signal("logged_in") and backend.logged_in.is_connected(_on_backend_logged_in):
			backend.logged_in.disconnect(_on_backend_logged_in)

func _on_backend_logged_in(_player_data: Dictionary):
	# Sync from backend when logged in
	sync_from_backend()

func load_player_data() -> bool:
	# Try backend first if available and authenticated
	if use_backend and backend and backend.is_authenticated:
		sync_from_backend()
		return true

	# Fallback to local file
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		print("No save file found, using defaults")
		return false

	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if file:
		player_data = file.get_var()
		file.close()
		data_loaded.emit()
		print("Player data loaded successfully")
		return true
	else:
		print("Failed to load player data")
		return false

func sync_from_backend():
	"""Sync player data from backend"""
	if not backend or not backend.is_authenticated:
		return

	var profile = backend.current_player
	if not profile:
		return

	# Map backend profile to local player_data structure
	player_data.character.level = profile.get("level", 1)
	player_data.character.experience = profile.get("experience", 0)
	player_data.currency.sigils = profile.get("currency", 0)

	# Update stats
	player_data.stats.zombies_killed = profile.get("totalKills", 0)
	player_data.stats.waves_survived = profile.get("highestWave", 0)

	# Fetch inventory from backend
	backend.get_inventory(func(response):
		if response.success and response.has("items"):
			_populate_stash_from_backend(response.items)
	)

	data_loaded.emit()
	backend_synced.emit()
	print("Player data synced from backend")

func _populate_stash_from_backend(items: Array):
	player_data.stash = []
	for item in items:
		player_data.stash.append({
			"item_id": item.get("itemId", ""),
			"name": item.get("itemName", "Unknown"),
			"quantity": item.get("quantity", 1),
			"equipped": item.get("isEquipped", false)
		})

func sync_to_backend():
	"""Sync player data to backend"""
	if not backend or not backend.is_authenticated:
		return

	# Update stats on backend
	var stat_update = {
		"kills": player_data.stats.get("zombies_killed", 0),
		"deaths": player_data.stats.get("deaths", 0),
		"highestWave": player_data.stats.get("waves_survived", 0)
	}

	backend.update_stats(stat_update, func(response):
		if response.success:
			backend_synced.emit()
			print("Player data synced to backend")
	)

func apply_to_character_stats(character_stats: Node):
	if not character_stats:
		return

	character_stats.level = player_data.character.level
	character_stats.experience = player_data.character.experience
	character_stats.stat_points = player_data.character.stat_points
	character_stats.strength = player_data.character.strength
	character_stats.dexterity = player_data.character.dexterity
	character_stats.intelligence = player_data.character.intelligence
	character_stats.agility = player_data.character.agility
	character_stats.vitality = player_data.character.vitality
	character_stats.calculate_derived_stats()

func apply_to_equipment(equipment: Node):
	if not equipment:
		return

	# Deserialize and equip items from saved data
	var slots = ["head", "chest", "hands", "legs", "feet", "back", "ring_left", "ring_right", "pendant", "weapon_main", "weapon_off"]
	for slot in slots:
		if player_data.equipment.has(slot):
			var item_data = player_data.equipment[slot]
			if not item_data.is_empty():
				var item = deserialize_item(item_data)
				if item and slot in equipment:
					equipment.set(slot, item)

func serialize_equipment(equipment: Node) -> Dictionary:
	return {
		"head": serialize_item(equipment.head),
		"chest": serialize_item(equipment.chest),
		"hands": serialize_item(equipment.hands),
		"legs": serialize_item(equipment.legs),
		"feet": serialize_item(equipment.feet),
		"back": serialize_item(equipment.back),
		"ring_left": serialize_item(equipment.ring_left),
		"ring_right": serialize_item(equipment.ring_right),
		"pendant": serialize_item(equipment.pendant),
		"weapon_main": serialize_item(equipment.weapon_main),
		"weapon_off": serialize_item(equipment.weapon_off)
	}

func serialize_inventory(inventory: Array) -> Array:
	var serialized = []
	for item_data in inventory:
		serialized.append({
			"item": serialize_item(item_data.item),
			"quantity": item_data.quantity
		})
	return serialized

func serialize_item(item: Resource) -> Dictionary:
	if not item:
		return {}

	var data = {
		"name": item.item_name if "item_name" in item else "",
		"type": item.item_type if "item_type" in item else 0,
		"rarity": item.rarity if "rarity" in item else 0,
		"description": item.description if "description" in item else "",
		"stack_size": item.stack_size if "stack_size" in item else 1,
		"weight": item.weight if "weight" in item else 1.0,
		"value": item.value if "value" in item else 0,
		"level_requirement": item.level_requirement if "level_requirement" in item else 1,
	}

	# Weapon properties
	if "damage" in item:
		data["damage"] = item.damage
		data["damage_type"] = item.damage_type if "damage_type" in item else 0
		data["fire_rate"] = item.fire_rate if "fire_rate" in item else 0.1
		data["magazine_size"] = item.magazine_size if "magazine_size" in item else 30
		data["reload_time"] = item.reload_time if "reload_time" in item else 2.0
		data["weapon_range"] = item.weapon_range if "weapon_range" in item else 100.0
		data["accuracy"] = item.accuracy if "accuracy" in item else 1.0
		data["recoil"] = item.recoil if "recoil" in item else 1.0
		data["is_melee"] = item.is_melee if "is_melee" in item else false
		data["projectile_count"] = item.projectile_count if "projectile_count" in item else 1
		data["spread_angle"] = item.spread_angle if "spread_angle" in item else 0.0
		data["armor_penetration"] = item.armor_penetration if "armor_penetration" in item else 0.0

	# Armor properties
	if "armor_value" in item:
		data["armor_value"] = item.armor_value
		data["durability"] = item.durability if "durability" in item else 100.0
		data["max_durability"] = item.max_durability if "max_durability" in item else 100.0

	# Stat bonuses
	if "strength_bonus" in item:
		data["strength_bonus"] = item.strength_bonus
		data["dexterity_bonus"] = item.dexterity_bonus if "dexterity_bonus" in item else 0.0
		data["intelligence_bonus"] = item.intelligence_bonus if "intelligence_bonus" in item else 0.0
		data["agility_bonus"] = item.agility_bonus if "agility_bonus" in item else 0.0
		data["vitality_bonus"] = item.vitality_bonus if "vitality_bonus" in item else 0.0

	# Special bonuses
	if "crit_chance_bonus" in item:
		data["crit_chance_bonus"] = item.crit_chance_bonus
		data["crit_damage_bonus"] = item.crit_damage_bonus if "crit_damage_bonus" in item else 0.0
		data["headshot_bonus"] = item.headshot_bonus if "headshot_bonus" in item else 0.0
		data["health_bonus"] = item.health_bonus if "health_bonus" in item else 0.0
		data["stamina_bonus"] = item.stamina_bonus if "stamina_bonus" in item else 0.0

	# Upgrade/Socket system
	if "upgrade_tier" in item:
		data["upgrade_tier"] = item.upgrade_tier
		data["socket_count"] = item.socket_count if "socket_count" in item else 0
		data["max_sockets"] = item.max_sockets if "max_sockets" in item else 0

	# Serialize augments
	if "augments" in item and item.augments.size() > 0:
		var serialized_augments = []
		for augment in item.augments:
			serialized_augments.append(serialize_item(augment))
		data["augments"] = serialized_augments

	# Resistances
	if "fire_resistance" in item:
		data["fire_resistance"] = item.fire_resistance
		data["ice_resistance"] = item.ice_resistance if "ice_resistance" in item else 0.0
		data["poison_resistance"] = item.poison_resistance if "poison_resistance" in item else 0.0
		data["bleed_resistance"] = item.bleed_resistance if "bleed_resistance" in item else 0.0
		data["lightning_resistance"] = item.lightning_resistance if "lightning_resistance" in item else 0.0

	# Movement bonuses
	if "movement_speed_bonus" in item:
		data["movement_speed_bonus"] = item.movement_speed_bonus
		data["attack_speed_bonus"] = item.attack_speed_bonus if "attack_speed_bonus" in item else 0.0
		data["dodge_chance"] = item.dodge_chance if "dodge_chance" in item else 0.0

	# Equipment set
	if "equipment_set" in item and not item.equipment_set.is_empty():
		data["equipment_set"] = item.equipment_set

	# Consumable properties
	if "health_restore" in item:
		data["health_restore"] = item.health_restore
		data["stamina_restore"] = item.stamina_restore if "stamina_restore" in item else 0.0
		data["buff_duration"] = item.buff_duration if "buff_duration" in item else 0.0

	# Augment-specific properties
	if "augment_stat_type" in item:
		data["augment_stat_type"] = item.augment_stat_type
		data["augment_stat_value"] = item.augment_stat_value if "augment_stat_value" in item else 0.0

	return data

func deserialize_item(data: Dictionary) -> Resource:
	if data.is_empty():
		return null

	# Try to create ItemDataExtended first, fall back to ItemData
	var item: Resource = null
	var ItemDataExtendedClass = load("res://scripts/items/item_data_extended.gd")
	var ItemDataClass = load("res://scripts/items/item_data.gd")

	if ItemDataExtendedClass:
		item = ItemDataExtendedClass.new()
	elif ItemDataClass:
		item = ItemDataClass.new()
	else:
		return null

	# Apply basic properties
	if "name" in data: item.item_name = data.name
	if "type" in data: item.item_type = data.type
	if "rarity" in data and "rarity" in item: item.rarity = data.rarity
	if "description" in data: item.description = data.description
	if "stack_size" in data: item.stack_size = data.stack_size
	if "weight" in data: item.weight = data.weight
	if "value" in data: item.value = data.value
	if "level_requirement" in data and "level_requirement" in item: item.level_requirement = data.level_requirement

	# Weapon properties
	if "damage" in data: item.damage = data.damage
	if "damage_type" in data and "damage_type" in item: item.damage_type = data.damage_type
	if "fire_rate" in data: item.fire_rate = data.fire_rate
	if "magazine_size" in data: item.magazine_size = data.magazine_size
	if "reload_time" in data: item.reload_time = data.reload_time
	if "weapon_range" in data: item.weapon_range = data.weapon_range
	if "accuracy" in data and "accuracy" in item: item.accuracy = data.accuracy
	if "recoil" in data and "recoil" in item: item.recoil = data.recoil
	if "is_melee" in data and "is_melee" in item: item.is_melee = data.is_melee
	if "projectile_count" in data and "projectile_count" in item: item.projectile_count = data.projectile_count
	if "spread_angle" in data and "spread_angle" in item: item.spread_angle = data.spread_angle
	if "armor_penetration" in data and "armor_penetration" in item: item.armor_penetration = data.armor_penetration

	# Armor properties
	if "armor_value" in data: item.armor_value = data.armor_value
	if "durability" in data and "durability" in item: item.durability = data.durability
	if "max_durability" in data and "max_durability" in item: item.max_durability = data.max_durability

	# Stat bonuses
	if "strength_bonus" in data and "strength_bonus" in item: item.strength_bonus = data.strength_bonus
	if "dexterity_bonus" in data and "dexterity_bonus" in item: item.dexterity_bonus = data.dexterity_bonus
	if "intelligence_bonus" in data and "intelligence_bonus" in item: item.intelligence_bonus = data.intelligence_bonus
	if "agility_bonus" in data and "agility_bonus" in item: item.agility_bonus = data.agility_bonus
	if "vitality_bonus" in data and "vitality_bonus" in item: item.vitality_bonus = data.vitality_bonus

	# Special bonuses
	if "crit_chance_bonus" in data and "crit_chance_bonus" in item: item.crit_chance_bonus = data.crit_chance_bonus
	if "crit_damage_bonus" in data and "crit_damage_bonus" in item: item.crit_damage_bonus = data.crit_damage_bonus
	if "headshot_bonus" in data and "headshot_bonus" in item: item.headshot_bonus = data.headshot_bonus
	if "health_bonus" in data and "health_bonus" in item: item.health_bonus = data.health_bonus
	if "stamina_bonus" in data and "stamina_bonus" in item: item.stamina_bonus = data.stamina_bonus

	# Upgrade/Socket system
	if "upgrade_tier" in data and "upgrade_tier" in item: item.upgrade_tier = data.upgrade_tier
	if "socket_count" in data and "socket_count" in item: item.socket_count = data.socket_count
	if "max_sockets" in data and "max_sockets" in item: item.max_sockets = data.max_sockets

	# Deserialize augments
	if "augments" in data and "augments" in item:
		for augment_data in data.augments:
			var augment = deserialize_item(augment_data)
			if augment:
				item.augments.append(augment)

	# Resistances
	if "fire_resistance" in data and "fire_resistance" in item: item.fire_resistance = data.fire_resistance
	if "ice_resistance" in data and "ice_resistance" in item: item.ice_resistance = data.ice_resistance
	if "poison_resistance" in data and "poison_resistance" in item: item.poison_resistance = data.poison_resistance
	if "bleed_resistance" in data and "bleed_resistance" in item: item.bleed_resistance = data.bleed_resistance
	if "lightning_resistance" in data and "lightning_resistance" in item: item.lightning_resistance = data.lightning_resistance

	# Movement bonuses
	if "movement_speed_bonus" in data and "movement_speed_bonus" in item: item.movement_speed_bonus = data.movement_speed_bonus
	if "attack_speed_bonus" in data and "attack_speed_bonus" in item: item.attack_speed_bonus = data.attack_speed_bonus
	if "dodge_chance" in data and "dodge_chance" in item: item.dodge_chance = data.dodge_chance

	# Equipment set
	if "equipment_set" in data and "equipment_set" in item: item.equipment_set = data.equipment_set

	# Consumable properties
	if "health_restore" in data: item.health_restore = data.health_restore
	if "stamina_restore" in data and "stamina_restore" in item: item.stamina_restore = data.stamina_restore
	if "buff_duration" in data and "buff_duration" in item: item.buff_duration = data.buff_duration

	# Augment-specific properties
	if "augment_stat_type" in data and "augment_stat_type" in item: item.augment_stat_type = data.augment_stat_type
	if "augment_stat_value" in data and "augment_stat_value" in item: item.augment_stat_value = data.augment_stat_value

	return item

func add_currency(type: String, amount: int):
	if player_data.currency.has(type):
		player_data.currency[type] += amount

func spend_currency(type: String, amount: int) -> bool:
	if player_data.currency.has(type) and player_data.currency[type] >= amount:
		player_data.currency[type] -= amount
		return true
	return false

func get_currency(type: String) -> int:
	if player_data.currency.has(type):
		return player_data.currency[type]
	return 0

func add_stat(stat_name: String, value: int):
	if player_data.stats.has(stat_name):
		player_data.stats[stat_name] += value

func unlock_weapon(weapon_id: String):
	if not player_data.unlocks.weapons.has(weapon_id):
		player_data.unlocks.weapons.append(weapon_id)

func is_weapon_unlocked(weapon_id: String) -> bool:
	return player_data.unlocks.weapons.has(weapon_id)

func get_stats_summary() -> Dictionary:
	return player_data.stats.duplicate()

func reset_player_data():
	player_data = {
		"character": {
			"level": 1,
			"experience": 0,
			"stat_points": 0,
			"strength": 10.0,
			"dexterity": 10.0,
			"intelligence": 10.0,
			"agility": 10.0,
			"vitality": 10.0,
			"endurance": 10.0,
			"luck": 10.0
		},
		"currency": {
			"coins": 1000,  # Starting currency
			"tokens": 0,
			"scrap": 100,
			"sigils": 500  # Starting sigils
		},
		"materials": {
			"scrap_small": 20,  # Starting materials
			"scrap_medium": 5,
			"scrap_large": 0,
			"weapon_parts": 5,
			"rare_alloy": 0,
			"mythic_core": 0,
			"augment_crystal": 0
		},
		"stash": [],
		"equipped": {},
		"unlocks": {
			"weapons": ["pistol", "combat_knife"],  # Starting weapons
			"perks": [],
			"zones": ["arena_01"]
		},
		"stats": {
			"zombies_killed": 0,
			"waves_survived": 0,
			"items_looted": 0,
			"extractions": 0,
			"deaths": 0,
			"sigils_earned": 0,
			"sigils_spent": 0,
			"weapons_upgraded": 0
		},
		"settings": {
			"mouse_sensitivity": 0.003,
			"master_volume": 1.0,
			"psx_effects": true
		}
	}
	save_player_data()

func add_material(material_id: String, amount: int):
	"""Add crafting materials"""
	if not player_data.has("materials"):
		player_data["materials"] = {}

	if player_data.materials.has(material_id):
		player_data.materials[material_id] += amount
	else:
		player_data.materials[material_id] = amount

func spend_material(material_id: String, amount: int) -> bool:
	"""Spend crafting materials, returns true if successful"""
	if not player_data.has("materials"):
		return false

	if not player_data.materials.has(material_id):
		return false

	if player_data.materials[material_id] < amount:
		return false

	player_data.materials[material_id] -= amount
	return true

func get_material(material_id: String) -> int:
	"""Get current material count"""
	if player_data.has("materials") and player_data.materials.has(material_id):
		return player_data.materials[material_id]
	return 0

func get_all_materials() -> Dictionary:
	"""Get all materials"""
	if player_data.has("materials"):
		return player_data.materials.duplicate()
	return {}
