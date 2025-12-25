extends Node
class_name GridInventorySystem

# Grid-based inventory system where items have different sizes
# Supports item sizes from 1x1 to 5x5, backpacks, and drag-drop

signal inventory_changed
signal item_added(item: Resource, grid_pos: Vector2i)
signal item_removed(item: Resource, grid_pos: Vector2i)
signal item_moved(item: Resource, from_pos: Vector2i, to_pos: Vector2i)
signal item_equipped(item: Resource, slot: String)
signal item_unequipped(item: Resource, slot: String)
signal weight_changed(current: float, max_weight: float)

# Grid configuration
const BASE_GRID_WIDTH: int = 10
const BASE_GRID_HEIGHT: int = 6
const CELL_SIZE: int = 50  # Pixels per cell

# Item size presets (width x height)
enum ItemSize {
	SIZE_1x1,  # Ammo, rings, augments
	SIZE_2x1,  # Pistols, small items
	SIZE_2x2,  # Helmets, chest pieces
	SIZE_3x2,  # Rifles, larger gear
	SIZE_3x3,  # Backpacks, large armor
	SIZE_4x2,  # Sniper rifles
	SIZE_4x4,  # Very large items
	SIZE_5x5   # Massive items (rare)
}

# Size lookup table
const SIZE_DIMENSIONS: Dictionary = {
	ItemSize.SIZE_1x1: Vector2i(1, 1),
	ItemSize.SIZE_2x1: Vector2i(2, 1),
	ItemSize.SIZE_2x2: Vector2i(2, 2),
	ItemSize.SIZE_3x2: Vector2i(3, 2),
	ItemSize.SIZE_3x3: Vector2i(3, 3),
	ItemSize.SIZE_4x2: Vector2i(4, 2),
	ItemSize.SIZE_4x4: Vector2i(4, 4),
	ItemSize.SIZE_5x5: Vector2i(5, 5)
}

# Grid data
var grid_width: int = BASE_GRID_WIDTH
var grid_height: int = BASE_GRID_HEIGHT
var grid: Array = []  # 2D array, null = empty, otherwise item reference
var items: Array[Dictionary] = []  # [{item, position, rotated}]

# Backpack expansion
var backpack_slots: Array[Dictionary] = []  # Additional grid sections from backpacks
var total_slots: int = 0

# Equipment slots
var equipment: Dictionary = {
	"helmet": null,
	"chest": null,
	"gloves": null,
	"boots": null,
	"ring_left": null,
	"ring_right": null,
	"amulet": null,
	"weapon_primary": null,
	"weapon_secondary": null,
	"backpack": null
}

# Weight system
var max_weight: float = 50.0
var current_weight: float = 0.0

# Stash (separate larger grid)
var stash_width: int = 12
var stash_height: int = 10
var stash_grid: Array = []
var stash_items: Array[Dictionary] = []

func _ready():
	_initialize_grid()
	_initialize_stash()

func _initialize_grid():
	grid.clear()
	for y in range(grid_height):
		var row = []
		for x in range(grid_width):
			row.append(null)
		grid.append(row)
	total_slots = grid_width * grid_height

func _initialize_stash():
	stash_grid.clear()
	for y in range(stash_height):
		var row = []
		for x in range(stash_width):
			row.append(null)
		stash_grid.append(row)

# ============================================
# ITEM SIZE HELPERS
# ============================================

static func get_item_size(item: Resource) -> Vector2i:
	"""Get the grid size of an item based on its type"""
	if not item:
		return Vector2i(1, 1)

	# Check for explicit size on item
	if "grid_size" in item:
		return item.grid_size as Vector2i
	if item.has_meta("grid_size"):
		return item.get_meta("grid_size") as Vector2i

	# Determine size based on item type
	var item_type = item.item_type if "item_type" in item else -1

	match item_type:
		# 1x1 items
		ItemDataExtended.ItemType.AMMO, ItemDataExtended.ItemType.AUGMENT:
			return Vector2i(1, 1)
		# 2x1 items
		ItemDataExtended.ItemType.RING:
			return Vector2i(1, 1)
		ItemDataExtended.ItemType.AMULET:
			return Vector2i(1, 2)
		ItemDataExtended.ItemType.CONSUMABLE, ItemDataExtended.ItemType.MATERIAL:
			return Vector2i(1, 1)
		# 2x2 items
		ItemDataExtended.ItemType.HELMET, ItemDataExtended.ItemType.GLOVES, ItemDataExtended.ItemType.BOOTS:
			return Vector2i(2, 2)
		# 3x3 items
		ItemDataExtended.ItemType.CHEST_ARMOR:
			return Vector2i(2, 3)
		# Weapons based on subtype
		ItemDataExtended.ItemType.WEAPON:
			return _get_weapon_size(item)

	return Vector2i(1, 1)

static func _get_weapon_size(item: Resource) -> Vector2i:
	"""Determine weapon size based on weapon properties"""
	if not item:
		return Vector2i(2, 1)

	var is_melee = item.is_melee if "is_melee" in item else false
	var is_pistol = item.item_name.to_lower().contains("pistol") if "item_name" in item else false
	var is_rifle = item.item_name.to_lower().contains("rifle") or item.item_name.to_lower().contains("ak") if "item_name" in item else false
	var is_shotgun = item.item_name.to_lower().contains("shotgun") if "item_name" in item else false
	var is_sniper = item.item_name.to_lower().contains("sniper") if "item_name" in item else false

	if is_melee:
		return Vector2i(1, 3)  # Melee weapons are tall
	elif is_pistol:
		return Vector2i(2, 1)
	elif is_sniper:
		return Vector2i(5, 1)
	elif is_rifle or is_shotgun:
		return Vector2i(4, 1)
	else:
		return Vector2i(3, 1)

# ============================================
# GRID OPERATIONS
# ============================================

func can_place_item(item: Resource, grid_pos: Vector2i, rotated: bool = false, use_stash: bool = false) -> bool:
	"""Check if an item can be placed at a grid position"""
	var size = get_item_size(item)
	if rotated:
		size = Vector2i(size.y, size.x)

	var target_grid = stash_grid if use_stash else grid
	var target_width = stash_width if use_stash else grid_width
	var target_height = stash_height if use_stash else grid_height

	# Check bounds
	if grid_pos.x < 0 or grid_pos.y < 0:
		return false
	if grid_pos.x + size.x > target_width:
		return false
	if grid_pos.y + size.y > target_height:
		return false

	# Check for overlapping items
	for y in range(grid_pos.y, grid_pos.y + size.y):
		for x in range(grid_pos.x, grid_pos.x + size.x):
			if target_grid[y][x] != null:
				return false

	# Check weight
	var item_weight = item.weight if "weight" in item else 1.0
	if not use_stash and current_weight + item_weight > max_weight:
		return false

	return true

func find_free_slot(item: Resource, use_stash: bool = false) -> Vector2i:
	"""Find first available slot for an item, returns (-1, -1) if none"""
	var size = get_item_size(item)
	var target_width = stash_width if use_stash else grid_width
	var target_height = stash_height if use_stash else grid_height

	# Try normal orientation
	for y in range(target_height - size.y + 1):
		for x in range(target_width - size.x + 1):
			if can_place_item(item, Vector2i(x, y), false, use_stash):
				return Vector2i(x, y)

	# Try rotated
	var rotated_size = Vector2i(size.y, size.x)
	for y in range(target_height - rotated_size.y + 1):
		for x in range(target_width - rotated_size.x + 1):
			if can_place_item(item, Vector2i(x, y), true, use_stash):
				return Vector2i(x, y)

	return Vector2i(-1, -1)

func add_item(item: Resource, quantity: int = 1, use_stash: bool = false) -> bool:
	"""Add an item to inventory at first available slot"""
	# For stackable items, try to stack first
	if _is_stackable(item):
		var stacked = _try_stack_item(item, quantity, use_stash)
		if stacked:
			return true

	# Find free slot
	var slot = find_free_slot(item, use_stash)
	if slot.x < 0:
		return false

	return place_item(item, slot, false, quantity, use_stash)

func place_item(item: Resource, grid_pos: Vector2i, rotated: bool = false, quantity: int = 1, use_stash: bool = false) -> bool:
	"""Place an item at a specific grid position"""
	if not can_place_item(item, grid_pos, rotated, use_stash):
		return false

	var size = get_item_size(item)
	if rotated:
		size = Vector2i(size.y, size.x)

	var target_grid = stash_grid if use_stash else grid
	var target_items = stash_items if use_stash else items

	# Create item entry
	var item_entry = {
		"item": item,
		"position": grid_pos,
		"rotated": rotated,
		"quantity": quantity
	}

	# Mark cells as occupied
	for y in range(grid_pos.y, grid_pos.y + size.y):
		for x in range(grid_pos.x, grid_pos.x + size.x):
			target_grid[y][x] = item_entry

	target_items.append(item_entry)

	# Update weight
	if not use_stash:
		var item_weight = item.weight if "weight" in item else 1.0
		current_weight += item_weight * quantity
		weight_changed.emit(current_weight, max_weight)

	item_added.emit(item, grid_pos)
	inventory_changed.emit()
	return true

func remove_item_at(grid_pos: Vector2i, use_stash: bool = false) -> Dictionary:
	"""Remove item at grid position, returns the item entry"""
	var target_grid = stash_grid if use_stash else grid
	var target_items = stash_items if use_stash else items

	if grid_pos.x < 0 or grid_pos.y < 0:
		return {}

	var target_height = stash_height if use_stash else grid_height
	var target_width = stash_width if use_stash else grid_width

	if grid_pos.y >= target_height or grid_pos.x >= target_width:
		return {}

	var item_entry = target_grid[grid_pos.y][grid_pos.x]
	if not item_entry:
		return {}

	var item = item_entry.item
	var size = get_item_size(item)
	if item_entry.rotated:
		size = Vector2i(size.y, size.x)

	var origin = item_entry.position

	# Clear cells
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			target_grid[y][x] = null

	# Remove from items list
	target_items.erase(item_entry)

	# Update weight
	if not use_stash:
		var item_weight = item.weight if "weight" in item else 1.0
		current_weight -= item_weight * item_entry.quantity
		current_weight = max(0, current_weight)
		weight_changed.emit(current_weight, max_weight)

	item_removed.emit(item, origin)
	inventory_changed.emit()
	return item_entry

func move_item(from_pos: Vector2i, to_pos: Vector2i, from_stash: bool = false, to_stash: bool = false) -> bool:
	"""Move an item from one position to another"""
	var item_entry = remove_item_at(from_pos, from_stash)
	if item_entry.is_empty():
		return false

	if place_item(item_entry.item, to_pos, item_entry.rotated, item_entry.quantity, to_stash):
		item_moved.emit(item_entry.item, from_pos, to_pos)
		return true

	# Failed to place, put it back
	place_item(item_entry.item, from_pos, item_entry.rotated, item_entry.quantity, from_stash)
	return false

func rotate_item(grid_pos: Vector2i, use_stash: bool = false) -> bool:
	"""Rotate an item at the given position"""
	var item_entry = remove_item_at(grid_pos, use_stash)
	if item_entry.is_empty():
		return false

	var new_rotated = not item_entry.rotated

	if place_item(item_entry.item, grid_pos, new_rotated, item_entry.quantity, use_stash):
		return true

	# Couldn't rotate, put it back
	place_item(item_entry.item, grid_pos, item_entry.rotated, item_entry.quantity, use_stash)
	return false

func get_item_at(grid_pos: Vector2i, use_stash: bool = false) -> Dictionary:
	"""Get item entry at grid position"""
	var target_grid = stash_grid if use_stash else grid
	var target_height = stash_height if use_stash else grid_height
	var target_width = stash_width if use_stash else grid_width

	if grid_pos.x < 0 or grid_pos.y < 0:
		return {}
	if grid_pos.y >= target_height or grid_pos.x >= target_width:
		return {}

	var entry = target_grid[grid_pos.y][grid_pos.x]
	return entry if entry else {}

# ============================================
# STACKING
# ============================================

func _is_stackable(item: Resource) -> bool:
	"""Check if an item can stack"""
	if not item:
		return false
	var stack_size = item.stack_size if "stack_size" in item else 1
	return stack_size > 1

func _try_stack_item(item: Resource, quantity: int, use_stash: bool = false) -> bool:
	"""Try to add item to existing stacks"""
	var target_items = stash_items if use_stash else items
	var stack_size = item.stack_size if "stack_size" in item else 1

	for entry in target_items:
		if entry.item == item and entry.quantity < stack_size:
			var space = stack_size - entry.quantity
			var add_amount = min(space, quantity)
			entry.quantity += add_amount
			quantity -= add_amount
			inventory_changed.emit()
			if quantity <= 0:
				return true

	return quantity <= 0

func get_item_count(item: Resource, use_stash: bool = false) -> int:
	"""Count total quantity of an item"""
	var target_items = stash_items if use_stash else items
	var count = 0
	for entry in target_items:
		if entry.item == item:
			count += entry.quantity
	return count

# ============================================
# EQUIPMENT
# ============================================

func equip_item(item: Resource, slot: String = "") -> bool:
	"""Equip an item to the appropriate slot"""
	if not item:
		return false

	# Determine slot from item type if not specified
	if slot.is_empty():
		slot = _get_slot_for_item(item)
		if slot.is_empty():
			return false

	if not equipment.has(slot):
		return false

	# Unequip current item if any
	if equipment[slot]:
		unequip_item(slot)

	# Remove from inventory
	for entry in items:
		if entry.item == item:
			remove_item_at(entry.position)
			break

	equipment[slot] = item
	item_equipped.emit(item, slot)
	inventory_changed.emit()
	return true

func unequip_item(slot: String) -> Resource:
	"""Unequip item from slot, returns the item"""
	if not equipment.has(slot) or not equipment[slot]:
		return null

	var item = equipment[slot]
	equipment[slot] = null

	# Try to add back to inventory
	if not add_item(item):
		# Inventory full, item lost or dropped
		push_warning("Could not unequip item - inventory full")

	item_unequipped.emit(item, slot)
	inventory_changed.emit()
	return item

func get_equipped(slot: String) -> Resource:
	"""Get item equipped in slot"""
	return equipment.get(slot, null)

func _get_slot_for_item(item: Resource) -> String:
	"""Determine equipment slot based on item type"""
	var item_type = item.item_type if "item_type" in item else -1

	match item_type:
		ItemDataExtended.ItemType.HELMET:
			return "helmet"
		ItemDataExtended.ItemType.CHEST_ARMOR:
			return "chest"
		ItemDataExtended.ItemType.GLOVES:
			return "gloves"
		ItemDataExtended.ItemType.BOOTS:
			return "boots"
		ItemDataExtended.ItemType.RING:
			if not equipment["ring_left"]:
				return "ring_left"
			return "ring_right"
		ItemDataExtended.ItemType.AMULET:
			return "amulet"
		ItemDataExtended.ItemType.WEAPON:
			if not equipment["weapon_primary"]:
				return "weapon_primary"
			return "weapon_secondary"

	return ""

# ============================================
# BACKPACKS
# ============================================

func equip_backpack(backpack: Resource) -> bool:
	"""Equip a backpack to expand inventory"""
	if not backpack:
		return false

	# Check if backpack has expansion properties
	var extra_width = backpack.extra_width if backpack.has_meta("extra_width") else 0
	var extra_height = backpack.extra_height if backpack.has_meta("extra_height") else 2

	if extra_width <= 0 and extra_height <= 0:
		extra_height = 2  # Default expansion

	# Unequip current backpack
	if equipment["backpack"]:
		unequip_backpack()

	equipment["backpack"] = backpack

	# Expand grid
	_expand_grid(extra_height)

	inventory_changed.emit()
	return true

func unequip_backpack() -> Resource:
	"""Remove backpack and shrink inventory"""
	if not equipment["backpack"]:
		return null

	var backpack = equipment["backpack"]
	equipment["backpack"] = null

	# Check if items would be lost
	var items_in_expansion = _get_items_in_expansion()
	for entry in items_in_expansion:
		# Try to move to main inventory
		var new_pos = find_free_slot(entry.item)
		if new_pos.x >= 0:
			move_item(entry.position, new_pos)
		else:
			# Drop item or move to stash
			var stash_pos = find_free_slot(entry.item, true)
			if stash_pos.x >= 0:
				move_item(entry.position, stash_pos, false, true)
			else:
				# Item lost
				remove_item_at(entry.position)

	# Shrink grid back to base
	_shrink_grid()

	inventory_changed.emit()
	return backpack

func _expand_grid(extra_rows: int):
	"""Add rows to the inventory grid"""
	var old_height = grid_height
	grid_height += extra_rows

	for i in range(extra_rows):
		var row = []
		for x in range(grid_width):
			row.append(null)
		grid.append(row)

	total_slots = grid_width * grid_height
	max_weight += extra_rows * 5  # Each row adds 5 weight capacity

func _shrink_grid():
	"""Remove expansion rows from grid"""
	grid_height = BASE_GRID_HEIGHT
	while grid.size() > grid_height:
		grid.pop_back()
	total_slots = grid_width * grid_height
	max_weight = 50.0

func _get_items_in_expansion() -> Array[Dictionary]:
	"""Get items that are in the expansion area"""
	var result: Array[Dictionary] = []
	for entry in items:
		if entry.position.y >= BASE_GRID_HEIGHT:
			result.append(entry)
	return result

# ============================================
# UTILITY
# ============================================

func get_all_items(use_stash: bool = false) -> Array[Dictionary]:
	"""Get all items in inventory or stash"""
	return stash_items.duplicate() if use_stash else items.duplicate()

func clear_inventory():
	"""Clear all items from inventory"""
	items.clear()
	_initialize_grid()
	current_weight = 0.0
	weight_changed.emit(current_weight, max_weight)
	inventory_changed.emit()

func clear_stash():
	"""Clear all items from stash"""
	stash_items.clear()
	_initialize_stash()
	inventory_changed.emit()

func get_weight_info() -> Dictionary:
	"""Get current weight information"""
	return {
		"current": current_weight,
		"max": max_weight,
		"percent": current_weight / max_weight if max_weight > 0 else 0.0
	}

func get_grid_info(use_stash: bool = false) -> Dictionary:
	"""Get grid dimensions"""
	return {
		"width": stash_width if use_stash else grid_width,
		"height": stash_height if use_stash else grid_height,
		"cell_size": CELL_SIZE
	}

func has_space_for(item: Resource, use_stash: bool = false) -> bool:
	"""Check if there's space for an item"""
	var slot = find_free_slot(item, use_stash)
	return slot.x >= 0

# ============================================
# SAVE/LOAD
# ============================================

func get_save_data() -> Dictionary:
	var save_items = []
	for entry in items:
		save_items.append({
			"item_path": entry.item.resource_path if entry.item else "",
			"position": {"x": entry.position.x, "y": entry.position.y},
			"rotated": entry.rotated,
			"quantity": entry.quantity
		})

	var save_stash = []
	for entry in stash_items:
		save_stash.append({
			"item_path": entry.item.resource_path if entry.item else "",
			"position": {"x": entry.position.x, "y": entry.position.y},
			"rotated": entry.rotated,
			"quantity": entry.quantity
		})

	var save_equipment = {}
	for slot in equipment:
		if equipment[slot]:
			save_equipment[slot] = equipment[slot].resource_path

	return {
		"items": save_items,
		"stash": save_stash,
		"equipment": save_equipment,
		"grid_height": grid_height,
		"max_weight": max_weight
	}

func load_save_data(data: Dictionary):
	clear_inventory()
	clear_stash()

	# Restore grid size
	if data.has("grid_height"):
		var extra = data.grid_height - BASE_GRID_HEIGHT
		if extra > 0:
			_expand_grid(extra)

	if data.has("max_weight"):
		max_weight = data.max_weight

	# Load items
	if data.has("items"):
		for item_data in data.items:
			if item_data.item_path and ResourceLoader.exists(item_data.item_path):
				var item = load(item_data.item_path)
				var pos = Vector2i(item_data.position.x, item_data.position.y)
				place_item(item, pos, item_data.rotated, item_data.quantity)

	# Load stash
	if data.has("stash"):
		for item_data in data.stash:
			if item_data.item_path and ResourceLoader.exists(item_data.item_path):
				var item = load(item_data.item_path)
				var pos = Vector2i(item_data.position.x, item_data.position.y)
				place_item(item, pos, item_data.rotated, item_data.quantity, true)

	# Load equipment
	if data.has("equipment"):
		for slot in data.equipment:
			var item_path = data.equipment[slot]
			if item_path and ResourceLoader.exists(item_path):
				equipment[slot] = load(item_path)

	inventory_changed.emit()
