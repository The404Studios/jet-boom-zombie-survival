extends Node
class_name EquipmentSystem

signal equipment_changed
signal gear_equipped(slot: String, item: ItemDataExtended)
signal gear_unequipped(slot: String, item: ItemDataExtended)

# Gear Slots
var helmet: ItemDataExtended = null
var chest_armor: ItemDataExtended = null
var gloves: ItemDataExtended = null
var boots: ItemDataExtended = null
var ring_1: ItemDataExtended = null
var ring_2: ItemDataExtended = null
var amulet: ItemDataExtended = null
var primary_weapon: ItemDataExtended = null
var secondary_weapon: ItemDataExtended = null

@onready var character_stats: CharacterStats = get_parent().get_node("CharacterStats") if get_parent().has_node("CharacterStats") else null

func equip_item(item: ItemDataExtended, slot: String = "") -> bool:
	if not item:
		return false

	# Auto-determine slot if not specified
	if slot == "":
		slot = get_slot_for_item_type(item.item_type)

	if slot == "":
		return false

	# Unequip current item in slot
	var current_item = get_item_in_slot(slot)
	if current_item:
		unequip_item(slot)

	# Equip new item
	set_item_in_slot(slot, item)

	# Apply stats
	if character_stats:
		character_stats.apply_gear_stats(item.get_all_stats())

	gear_equipped.emit(slot, item)
	equipment_changed.emit()
	return true

func unequip_item(slot: String) -> ItemDataExtended:
	var item = get_item_in_slot(slot)
	if not item:
		return null

	# Remove stats
	if character_stats:
		character_stats.remove_gear_stats(item.get_all_stats())

	set_item_in_slot(slot, null)

	gear_unequipped.emit(slot, item)
	equipment_changed.emit()
	return item

func get_item_in_slot(slot: String) -> ItemDataExtended:
	match slot:
		"helmet": return helmet
		"chest": return chest_armor
		"gloves": return gloves
		"boots": return boots
		"ring_1": return ring_1
		"ring_2": return ring_2
		"amulet": return amulet
		"primary": return primary_weapon
		"secondary": return secondary_weapon
	return null

func set_item_in_slot(slot: String, item: ItemDataExtended):
	match slot:
		"helmet": helmet = item
		"chest": chest_armor = item
		"gloves": gloves = item
		"boots": boots = item
		"ring_1": ring_1 = item
		"ring_2": ring_2 = item
		"amulet": amulet = item
		"primary": primary_weapon = item
		"secondary": secondary_weapon = item

func get_slot_for_item_type(type: ItemDataExtended.ItemType) -> String:
	match type:
		ItemDataExtended.ItemType.HELMET: return "helmet"
		ItemDataExtended.ItemType.CHEST_ARMOR: return "chest"
		ItemDataExtended.ItemType.GLOVES: return "gloves"
		ItemDataExtended.ItemType.BOOTS: return "boots"
		ItemDataExtended.ItemType.RING:
			if ring_1 == null: return "ring_1"
			if ring_2 == null: return "ring_2"
			return "ring_1"
		ItemDataExtended.ItemType.AMULET: return "amulet"
		ItemDataExtended.ItemType.WEAPON:
			if primary_weapon == null: return "primary"
			if secondary_weapon == null: return "secondary"
			return "primary"
	return ""

func get_all_equipped_items() -> Array[ItemDataExtended]:
	var items: Array[ItemDataExtended] = []
	if helmet: items.append(helmet)
	if chest_armor: items.append(chest_armor)
	if gloves: items.append(gloves)
	if boots: items.append(boots)
	if ring_1: items.append(ring_1)
	if ring_2: items.append(ring_2)
	if amulet: items.append(amulet)
	if primary_weapon: items.append(primary_weapon)
	if secondary_weapon: items.append(secondary_weapon)
	return items

func get_total_armor() -> float:
	var total = 0.0
	for item in get_all_equipped_items():
		total += item.armor_value
	return total

func get_equipment_summary() -> Dictionary:
	return {
		"helmet": helmet.item_name if helmet else "Empty",
		"chest": chest_armor.item_name if chest_armor else "Empty",
		"gloves": gloves.item_name if gloves else "Empty",
		"boots": boots.item_name if boots else "Empty",
		"ring_1": ring_1.item_name if ring_1 else "Empty",
		"ring_2": ring_2.item_name if ring_2 else "Empty",
		"amulet": amulet.item_name if amulet else "Empty",
		"primary": primary_weapon.item_name if primary_weapon else "Empty",
		"secondary": secondary_weapon.item_name if secondary_weapon else "Empty",
		"total_armor": get_total_armor()
	}
