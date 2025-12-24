extends Node
class_name EquipmentSystem

# Equipment System with complete gear slots
# Handles equipping, unequipping, and stat bonuses from gear

signal equipment_changed
signal gear_equipped(slot: String, item: Resource)
signal gear_unequipped(slot: String, item: Resource)
signal stats_updated(total_bonuses: Dictionary)

# Equipment Slots
enum EquipSlot {
	HEAD,
	CHEST,
	HANDS,
	LEGS,
	FEET,
	BACK,
	RING_LEFT,
	RING_RIGHT,
	PENDANT,
	WEAPON_MAIN,
	WEAPON_OFF
}

# Gear Slots - Armor
var head: Resource = null
var chest: Resource = null
var hands: Resource = null
var legs: Resource = null
var feet: Resource = null
var back: Resource = null

# Accessories
var ring_left: Resource = null
var ring_right: Resource = null
var pendant: Resource = null

# Weapons
var weapon_main: Resource = null
var weapon_off: Resource = null

# Cached stat bonuses
var total_stat_bonuses: Dictionary = {}

# Reference to character stats
@onready var character_stats: Node = get_parent().get_node("CharacterStats") if get_parent() and get_parent().has_node("CharacterStats") else null
@onready var character_attributes: CharacterAttributes = get_parent().get_node("CharacterAttributes") if get_parent() and get_parent().has_node("CharacterAttributes") else null

func _ready():
	await get_tree().process_frame
	if get_parent():
		if get_parent().has_node("CharacterStats"):
			character_stats = get_parent().get_node("CharacterStats")
		if get_parent().has_node("CharacterAttributes"):
			character_attributes = get_parent().get_node("CharacterAttributes")

# ============================================
# EQUIPMENT MANAGEMENT
# ============================================

func equip_item(item: Resource, slot_name: String = "") -> Resource:
	"""
	Equip an item to the specified slot.
	Returns the previously equipped item (or null).
	"""
	if not item:
		return null

	# Auto-determine slot if not specified
	if slot_name == "":
		slot_name = _get_slot_for_item(item)

	if slot_name == "":
		push_warning("Cannot determine slot for item: %s" % item.item_name if "item_name" in item else "Unknown")
		return null

	# Store previous item
	var previous_item = get_item_in_slot(slot_name)

	# Remove stats from previous item
	if previous_item and character_stats and character_stats.has_method("remove_gear_stats"):
		if previous_item.has_method("get_all_stats"):
			character_stats.remove_gear_stats(previous_item.get_all_stats())

	# Set new item
	_set_item_in_slot(slot_name, item)

	# Apply stats from new item
	if character_stats and character_stats.has_method("apply_gear_stats"):
		if item.has_method("get_all_stats"):
			character_stats.apply_gear_stats(item.get_all_stats())

	# Recalculate bonuses
	_recalculate_stat_bonuses()

	# Update visual model
	_update_equipment_visual(slot_name, item)

	gear_equipped.emit(slot_name, item)
	equipment_changed.emit()

	return previous_item

func unequip_item(slot_name: String) -> Resource:
	"""Unequip item from slot, returns the item"""
	var item = get_item_in_slot(slot_name)
	if not item:
		return null

	# Remove stats
	if character_stats and character_stats.has_method("remove_gear_stats"):
		if item.has_method("get_all_stats"):
			character_stats.remove_gear_stats(item.get_all_stats())

	_set_item_in_slot(slot_name, null)

	# Recalculate bonuses
	_recalculate_stat_bonuses()

	# Update visual model
	_update_equipment_visual(slot_name, null)

	gear_unequipped.emit(slot_name, item)
	equipment_changed.emit()

	return item

func get_item_in_slot(slot_name: String) -> Resource:
	"""Get the item in a specific slot"""
	match slot_name.to_lower():
		"head", "helmet":
			return head
		"chest", "chest_armor":
			return chest
		"hands", "gloves":
			return hands
		"legs", "pants":
			return legs
		"feet", "boots":
			return feet
		"back", "cape", "cloak":
			return back
		"ring_left", "ring_1":
			return ring_left
		"ring_right", "ring_2":
			return ring_right
		"pendant", "amulet", "necklace":
			return pendant
		"weapon_main", "primary", "main_hand":
			return weapon_main
		"weapon_off", "secondary", "off_hand":
			return weapon_off
	return null

func _set_item_in_slot(slot_name: String, item: Resource):
	"""Set item in a specific slot"""
	match slot_name.to_lower():
		"head", "helmet":
			head = item
		"chest", "chest_armor":
			chest = item
		"hands", "gloves":
			hands = item
		"legs", "pants":
			legs = item
		"feet", "boots":
			feet = item
		"back", "cape", "cloak":
			back = item
		"ring_left", "ring_1":
			ring_left = item
		"ring_right", "ring_2":
			ring_right = item
		"pendant", "amulet", "necklace":
			pendant = item
		"weapon_main", "primary", "main_hand":
			weapon_main = item
		"weapon_off", "secondary", "off_hand":
			weapon_off = item

func _get_slot_for_item(item: Resource) -> String:
	"""Determine the appropriate slot for an item"""
	if not item:
		return ""

	# Check for equipment_slot property
	if "equipment_slot" in item:
		return item.equipment_slot

	# Check item_type enum
	if "item_type" in item:
		if item.item_type is int:
			# Handle ItemDataExtended enum
			match item.item_type:
				0: return "head"  # HELMET
				1: return "chest"  # CHEST_ARMOR
				2: return "hands"  # GLOVES
				3: return "feet"  # BOOTS
				4:  # RING
					if ring_left == null:
						return "ring_left"
					return "ring_right"
				5: return "pendant"  # AMULET
				6, 7: return "weapon_main"  # WEAPON

	return ""

func is_slot_empty(slot_name: String) -> bool:
	"""Check if a slot is empty"""
	return get_item_in_slot(slot_name) == null

# ============================================
# STAT BONUSES
# ============================================

func _recalculate_stat_bonuses():
	"""Recalculate all stat bonuses from equipped items"""
	total_stat_bonuses = {
		# Attributes
		"strength": 0,
		"agility": 0,
		"vitality": 0,
		"intelligence": 0,
		"endurance": 0,
		"luck": 0,
		# Derived Stats
		"health": 0.0,
		"stamina": 0.0,
		"mana": 0.0,
		"armor": 0.0,
		"melee_damage": 0.0,
		"ranged_damage": 0.0,
		"crit_chance": 0.0,
		"crit_damage": 0.0,
		"dodge_chance": 0.0,
		"movement_speed": 0.0,
		"attack_speed": 0.0,
		# Resistances
		"fire_resist": 0.0,
		"ice_resist": 0.0,
		"poison_resist": 0.0,
		"bleed_resist": 0.0
	}

	# Sum bonuses from all equipped items
	for item in get_all_equipped_items():
		if item.has_method("get_stat_bonuses"):
			var bonuses = item.get_stat_bonuses()
			for stat in bonuses:
				if total_stat_bonuses.has(stat):
					total_stat_bonuses[stat] += bonuses[stat]
		elif "armor_value" in item:
			total_stat_bonuses["armor"] += item.armor_value

	# Apply set bonuses
	_apply_set_bonuses()

	# Update character attributes if available
	if character_attributes:
		character_attributes.set_equipment_bonuses(total_stat_bonuses)

	stats_updated.emit(total_stat_bonuses)

func _apply_set_bonuses():
	"""Check and apply equipment set bonuses"""
	var set_counts: Dictionary = {}

	for item in get_all_equipped_items():
		if "equipment_set" in item and item.equipment_set != "":
			if not set_counts.has(item.equipment_set):
				set_counts[item.equipment_set] = 0
			set_counts[item.equipment_set] += 1

	# Apply set bonuses based on piece count
	for equip_set_name in set_counts:
		var count = set_counts[equip_set_name]
		var set_bonuses = _get_set_bonuses(equip_set_name, count)

		for stat in set_bonuses:
			if total_stat_bonuses.has(stat):
				total_stat_bonuses[stat] += set_bonuses[stat]

func _get_set_bonuses(equip_set_name: String, piece_count: int) -> Dictionary:
	"""Get bonuses for a specific set based on piece count"""
	var sets = {
		"Zombie Hunter": {
			2: {"ranged_damage": 10.0, "crit_chance": 0.05},
			4: {"ranged_damage": 25.0, "crit_damage": 0.3},
			6: {"ranged_damage": 50.0, "crit_chance": 0.15}
		},
		"Survivor": {
			2: {"health": 50.0, "armor": 10.0},
			4: {"health": 100.0},
			6: {"health": 200.0, "dodge_chance": 10.0}
		},
		"Berserker": {
			2: {"melee_damage": 15.0, "attack_speed": 5.0},
			4: {"melee_damage": 35.0, "strength": 5},
			6: {"melee_damage": 60.0, "crit_damage": 0.5}
		},
		"Shadow": {
			2: {"movement_speed": 10.0, "dodge_chance": 5.0},
			4: {"agility": 10, "crit_chance": 0.1},
			6: {"dodge_chance": 20.0, "movement_speed": 25.0}
		}
	}

	var bonuses = {}

	if sets.has(equip_set_name):
		var set_data = sets[equip_set_name]
		for threshold in set_data:
			if piece_count >= threshold:
				var tier_bonuses = set_data[threshold]
				for stat in tier_bonuses:
					bonuses[stat] = tier_bonuses[stat]

	return bonuses

func get_total_bonuses() -> Dictionary:
	"""Get current total stat bonuses"""
	return total_stat_bonuses.duplicate()

# ============================================
# QUERIES
# ============================================

func get_all_equipped_items() -> Array:
	"""Get array of all equipped items"""
	var items = []
	if head: items.append(head)
	if chest: items.append(chest)
	if hands: items.append(hands)
	if legs: items.append(legs)
	if feet: items.append(feet)
	if back: items.append(back)
	if ring_left: items.append(ring_left)
	if ring_right: items.append(ring_right)
	if pendant: items.append(pendant)
	if weapon_main: items.append(weapon_main)
	if weapon_off: items.append(weapon_off)
	return items

func get_total_armor() -> float:
	"""Get total armor value from all equipped items"""
	var total = 0.0
	for item in get_all_equipped_items():
		if "armor_value" in item:
			total += item.armor_value
	return total

func get_equipment_summary() -> Dictionary:
	"""Get summary of all equipped items"""
	return {
		"head": head.item_name if head and "item_name" in head else "Empty",
		"chest": chest.item_name if chest and "item_name" in chest else "Empty",
		"hands": hands.item_name if hands and "item_name" in hands else "Empty",
		"legs": legs.item_name if legs and "item_name" in legs else "Empty",
		"feet": feet.item_name if feet and "item_name" in feet else "Empty",
		"back": back.item_name if back and "item_name" in back else "Empty",
		"ring_left": ring_left.item_name if ring_left and "item_name" in ring_left else "Empty",
		"ring_right": ring_right.item_name if ring_right and "item_name" in ring_right else "Empty",
		"pendant": pendant.item_name if pendant and "item_name" in pendant else "Empty",
		"weapon_main": weapon_main.item_name if weapon_main and "item_name" in weapon_main else "Empty",
		"weapon_off": weapon_off.item_name if weapon_off and "item_name" in weapon_off else "Empty",
		"total_armor": get_total_armor()
	}

func get_all_slots() -> Array:
	"""Get list of all slot names"""
	return [
		"head", "chest", "hands", "legs", "feet", "back",
		"ring_left", "ring_right", "pendant",
		"weapon_main", "weapon_off"
	]

# ============================================
# VISUAL UPDATES
# ============================================

func _update_equipment_visual(slot_name: String, item: Resource):
	"""Update the visual representation of equipment on player"""
	var player = get_parent()
	if not player:
		return

	# Find viewmodel
	var viewmodel = null
	if player.has_node("Camera3D/Viewmodel"):
		viewmodel = player.get_node("Camera3D/Viewmodel")

	# Update based on slot
	match slot_name.to_lower():
		"hands", "gloves":
			_update_gloves_visual(viewmodel, item)
		"weapon_main", "primary":
			_update_weapon_visual(viewmodel, item)

func _update_gloves_visual(viewmodel: Node3D, item: Resource):
	"""Update glove appearance on viewmodel hands"""
	if not viewmodel or not viewmodel.has_node("Arms"):
		return

	var arms = viewmodel.get_node("Arms")

	if item and "visual_material" in item:
		for arm in arms.get_children():
			if arm is MeshInstance3D:
				arm.material_override = item.visual_material

func _update_weapon_visual(viewmodel: Node3D, item: Resource):
	"""Update weapon in viewmodel"""
	if not viewmodel or not viewmodel.has_method("equip_weapon"):
		return

	if item and "mesh_scene" in item:
		viewmodel.equip_weapon(item.mesh_scene, item)

# ============================================
# SAVE/LOAD
# ============================================

func get_save_data() -> Dictionary:
	var data = {}
	var slots = get_all_slots()
	for slot_name in slots:
		var item = get_item_in_slot(slot_name)
		if item and "resource_path" in item:
			data[slot_name] = item.resource_path
	return data

func load_save_data(data: Dictionary):
	for slot_name in data:
		var item_path = data[slot_name]
		if ResourceLoader.exists(item_path):
			var item = load(item_path)
			equip_item(item, slot_name)

# ============================================
# SLOT DISPLAY HELPERS
# ============================================

static func get_slot_display_name(slot_name: String) -> String:
	"""Get human-readable slot name"""
	match slot_name.to_lower():
		"head", "helmet":
			return "Head"
		"chest", "chest_armor":
			return "Chest"
		"hands", "gloves":
			return "Hands"
		"legs", "pants":
			return "Legs"
		"feet", "boots":
			return "Feet"
		"back", "cape":
			return "Back"
		"ring_left":
			return "Left Ring"
		"ring_right":
			return "Right Ring"
		"pendant", "amulet":
			return "Pendant"
		"weapon_main", "primary":
			return "Main Weapon"
		"weapon_off", "secondary":
			return "Off-hand"
	return slot_name.capitalize()

static func get_slot_icon(slot_name: String) -> String:
	"""Get icon character for slot"""
	match slot_name.to_lower():
		"head", "helmet":
			return "[H]"
		"chest":
			return "[C]"
		"hands", "gloves":
			return "[G]"
		"legs":
			return "[L]"
		"feet", "boots":
			return "[F]"
		"back":
			return "[B]"
		"ring_left", "ring_right":
			return "[R]"
		"pendant", "amulet":
			return "[P]"
		"weapon_main", "primary":
			return "[W]"
		"weapon_off", "secondary":
			return "[O]"
	return "[?]"
