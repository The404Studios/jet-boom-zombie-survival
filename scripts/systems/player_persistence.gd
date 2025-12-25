extends Node
# Note: Do not use class_name here - this script is an autoload singleton
# Access via: PlayerPersistence (the autoload name)

const SAVE_FILE_PATH = "user://player_data.save"
const STASH_FILE_PATH = "user://stash_data.save"

signal data_loaded
signal data_saved

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
		return true
	else:
		print("Failed to save player data")
		return false

func load_player_data() -> bool:
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
	# Would need to deserialize and equip items

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

	return {
		"name": item.item_name,
		"type": item.item_type,
		"rarity": item.rarity,
		# Would save all item properties
	}

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
