extends Node

## Tarkov-style grid inventory system
## Items occupy grid cells based on their size
## Supports dragging, rotating, and stacking

signal item_added(item: InventoryItem, container_id: String, position: Vector2i)
signal item_removed(item: InventoryItem, container_id: String)
signal item_moved(item: InventoryItem, from_container: String, to_container: String, position: Vector2i)
signal item_rotated(item: InventoryItem)
signal item_used(item: InventoryItem)
signal item_equipped(item: InventoryItem, slot: String)
signal item_unequipped(item: InventoryItem, slot: String)
signal container_updated(container_id: String)
signal currency_changed(currency_type: String, amount: int)

# Item rarity
enum ItemRarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

# Item type
enum ItemType { WEAPON, ARMOR, CONSUMABLE, AMMO, ATTACHMENT, MATERIAL, KEY, QUEST, CURRENCY }

# Equipment slots
const EQUIPMENT_SLOTS = {
	"head": Vector2i(2, 2), "pendant": Vector2i(1, 1), "cape": Vector2i(2, 2),
	"chest": Vector2i(2, 3), "hands": Vector2i(2, 2), "ring_left": Vector2i(1, 1),
	"ring_right": Vector2i(1, 1), "pants": Vector2i(2, 2), "feet": Vector2i(2, 2),
	"weapon_primary": Vector2i(2, 5), "weapon_secondary": Vector2i(2, 4), "weapon_melee": Vector2i(1, 3)
}

var containers: Dictionary = {}
var equipped_items: Dictionary = {}
var currency: Dictionary = {"gold": 0, "gems": 0, "tokens": 0}
var item_database: Dictionary = {}
var network_manager: Node = null

class InventoryItem:
	var item_id: String = ""
	var instance_id: int = 0
	var display_name: String = ""
	var description: String = ""
	var icon_path: String = ""
	var item_type: int = 0
	var rarity: int = 0
	var grid_size: Vector2i = Vector2i(1, 1)
	var is_rotated: bool = false
	var grid_position: Vector2i = Vector2i(-1, -1)
	var container_id: String = ""
	var max_stack: int = 1
	var current_stack: int = 1
	var is_stackable: bool = false
	var equip_slot: String = ""
	var stats: Dictionary = {}
	var damage: float = 0.0
	var fire_rate: float = 0.0
	var ammo_type: String = ""
	var magazine_size: int = 0
	var armor_value: float = 0.0
	var armor_class: int = 0
	var use_time: float = 1.0
	var effects: Array = []
	var buy_price: int = 0
	var sell_price: int = 0
	var weight: float = 0.1
	static var _next_instance_id: int = 1
	
	func _init():
		instance_id = _next_instance_id
		_next_instance_id += 1
	
	func get_actual_size() -> Vector2i:
		return Vector2i(grid_size.y, grid_size.x) if is_rotated else grid_size
	
	func rotate():
		is_rotated = not is_rotated
	
	func to_dict() -> Dictionary:
		return {"item_id": item_id, "instance_id": instance_id, "display_name": display_name,
			"grid_size": [grid_size.x, grid_size.y], "is_rotated": is_rotated,
			"grid_position": [grid_position.x, grid_position.y], "container_id": container_id,
			"current_stack": current_stack, "stats": stats.duplicate(), "rarity": rarity, "item_type": item_type}
	
	static func from_dict(data: Dictionary) -> InventoryItem:
		var item = InventoryItem.new()
		item.item_id = data.get("item_id", "")
		item.instance_id = data.get("instance_id", item.instance_id)
		item.display_name = data.get("display_name", "Unknown")
		var size = data.get("grid_size", [1, 1])
		item.grid_size = Vector2i(size[0], size[1])
		item.is_rotated = data.get("is_rotated", false)
		var pos = data.get("grid_position", [-1, -1])
		item.grid_position = Vector2i(pos[0], pos[1])
		item.container_id = data.get("container_id", "")
		item.current_stack = data.get("current_stack", 1)
		item.stats = data.get("stats", {})
		item.rarity = data.get("rarity", 0)
		item.item_type = data.get("item_type", 0)
		return item

class InventoryContainer:
	var container_id: String = ""
	var display_name: String = ""
	var grid_width: int = 10
	var grid_height: int = 6
	var grid: Array = []
	var items: Dictionary = {}
	
	func _init(id: String = "", width: int = 10, height: int = 6):
		container_id = id
		grid_width = width
		grid_height = height
		_initialize_grid()
	
	func _initialize_grid():
		grid.clear()
		for y in range(grid_height):
			var row = []
			for x in range(grid_width):
				row.append(0)
			grid.append(row)
	
	func can_place_item(item: InventoryItem, position: Vector2i) -> bool:
		var size = item.get_actual_size()
		if position.x < 0 or position.y < 0: return false
		if position.x + size.x > grid_width: return false
		if position.y + size.y > grid_height: return false
		for y in range(size.y):
			for x in range(size.x):
				var cell_value = grid[position.y + y][position.x + x]
				if cell_value != 0 and cell_value != item.instance_id:
					return false
		return true
	
	func place_item(item: InventoryItem, position: Vector2i) -> bool:
		if not can_place_item(item, position): return false
		var size = item.get_actual_size()
		for y in range(size.y):
			for x in range(size.x):
				grid[position.y + y][position.x + x] = item.instance_id
		item.grid_position = position
		item.container_id = container_id
		items[item.instance_id] = item
		return true
	
	func remove_item(item: InventoryItem) -> bool:
		if not items.has(item.instance_id): return false
		var size = item.get_actual_size()
		var pos = item.grid_position
		for y in range(size.y):
			for x in range(size.x):
				if pos.y + y < grid_height and pos.x + x < grid_width:
					if grid[pos.y + y][pos.x + x] == item.instance_id:
						grid[pos.y + y][pos.x + x] = 0
		items.erase(item.instance_id)
		item.grid_position = Vector2i(-1, -1)
		item.container_id = ""
		return true
	
	func find_free_position(item: InventoryItem) -> Vector2i:
		var size = item.get_actual_size()
		for y in range(grid_height - size.y + 1):
			for x in range(grid_width - size.x + 1):
				if can_place_item(item, Vector2i(x, y)):
					return Vector2i(x, y)
		item.rotate()
		size = item.get_actual_size()
		for y in range(grid_height - size.y + 1):
			for x in range(grid_width - size.x + 1):
				if can_place_item(item, Vector2i(x, y)):
					return Vector2i(x, y)
		item.rotate()
		return Vector2i(-1, -1)
	
	func get_item_at(position: Vector2i) -> InventoryItem:
		if position.x < 0 or position.x >= grid_width: return null
		if position.y < 0 or position.y >= grid_height: return null
		var instance_id = grid[position.y][position.x]
		if instance_id == 0: return null
		return items.get(instance_id, null)
	
	func get_all_items() -> Array:
		return items.values()
	
	func to_dict() -> Dictionary:
		var items_data = {}
		for inst_id in items:
			items_data[str(inst_id)] = items[inst_id].to_dict()
		return {"container_id": container_id, "display_name": display_name,
			"grid_width": grid_width, "grid_height": grid_height, "items": items_data}

func _ready():
	network_manager = get_node_or_null("/root/NetworkManager")
	_initialize_containers()
	_load_item_database()

func _initialize_containers():
	create_container("backpack", "Backpack", 10, 8)
	create_container("stash", "Character Stash", 14, 10)
	create_container("secure", "Secure Container", 3, 3)
	create_container("pockets", "Pockets", 4, 1)

func _load_item_database():
	_define_item("rifle_m4", {"name": "M4A1 Rifle", "type": ItemType.WEAPON, "rarity": ItemRarity.RARE,
		"size": Vector2i(2, 5), "equip_slot": "weapon_primary", "damage": 35.0, "fire_rate": 700.0,
		"ammo_type": "5.56x45", "magazine_size": 30, "buy_price": 50000, "weight": 3.5})
	_define_item("smg_vector", {"name": "Kriss Vector", "type": ItemType.WEAPON, "rarity": ItemRarity.EPIC,
		"size": Vector2i(2, 4), "equip_slot": "weapon_primary", "damage": 28.0, "fire_rate": 1200.0,
		"ammo_type": ".45 ACP", "magazine_size": 25, "buy_price": 75000, "weight": 2.7})
	_define_item("pistol_glock", {"name": "Glock 17", "type": ItemType.WEAPON, "rarity": ItemRarity.COMMON,
		"size": Vector2i(1, 2), "equip_slot": "weapon_secondary", "damage": 20.0, "fire_rate": 400.0,
		"ammo_type": "9x19", "magazine_size": 17, "buy_price": 15000, "weight": 0.7})
	_define_item("knife_combat", {"name": "Combat Knife", "type": ItemType.WEAPON, "rarity": ItemRarity.UNCOMMON,
		"size": Vector2i(1, 2), "equip_slot": "weapon_melee", "damage": 50.0, "buy_price": 5000, "weight": 0.3})
	_define_item("helmet_tactical", {"name": "Tactical Helmet", "type": ItemType.ARMOR, "rarity": ItemRarity.UNCOMMON,
		"size": Vector2i(2, 2), "equip_slot": "head", "armor_value": 25.0, "armor_class": 3,
		"stats": {"damage_reduction": 0.15}, "buy_price": 25000, "weight": 1.5})
	_define_item("vest_plate", {"name": "Plate Carrier", "type": ItemType.ARMOR, "rarity": ItemRarity.RARE,
		"size": Vector2i(2, 3), "equip_slot": "chest", "armor_value": 50.0, "armor_class": 4,
		"stats": {"damage_reduction": 0.25, "max_health": 20.0}, "buy_price": 75000, "weight": 8.0})
	_define_item("medkit", {"name": "First Aid Kit", "type": ItemType.CONSUMABLE, "rarity": ItemRarity.COMMON,
		"size": Vector2i(2, 1), "is_stackable": true, "max_stack": 3, "use_time": 5.0,
		"effects": [{"type": "heal", "amount": 50.0}], "buy_price": 5000, "weight": 0.5})
	_define_item("bandage", {"name": "Bandage", "type": ItemType.CONSUMABLE, "rarity": ItemRarity.COMMON,
		"size": Vector2i(1, 1), "is_stackable": true, "max_stack": 5, "use_time": 2.0,
		"effects": [{"type": "heal", "amount": 20.0}], "buy_price": 1000, "weight": 0.1})
	_define_item("ammo_556", {"name": "5.56x45mm", "type": ItemType.AMMO, "rarity": ItemRarity.COMMON,
		"size": Vector2i(1, 1), "is_stackable": true, "max_stack": 120, "ammo_type": "5.56x45", "buy_price": 300, "weight": 0.4})
	_define_item("ammo_45acp", {"name": ".45 ACP", "type": ItemType.AMMO, "rarity": ItemRarity.COMMON,
		"size": Vector2i(1, 1), "is_stackable": true, "max_stack": 100, "ammo_type": ".45 ACP", "buy_price": 250, "weight": 0.3})
	_define_item("ammo_9mm", {"name": "9x19mm", "type": ItemType.AMMO, "rarity": ItemRarity.COMMON,
		"size": Vector2i(1, 1), "is_stackable": true, "max_stack": 150, "ammo_type": "9x19", "buy_price": 200, "weight": 0.25})
	_define_item("pendant_lucky", {"name": "Lucky Pendant", "type": ItemType.ARMOR, "rarity": ItemRarity.RARE,
		"size": Vector2i(1, 1), "equip_slot": "pendant", "stats": {"crit_chance": 0.05}, "buy_price": 50000, "weight": 0.1})
	_define_item("ring_vitality", {"name": "Ring of Vitality", "type": ItemType.ARMOR, "rarity": ItemRarity.UNCOMMON,
		"size": Vector2i(1, 1), "equip_slot": "ring_left", "stats": {"max_health": 15.0}, "buy_price": 30000, "weight": 0.05})
	_define_item("cape_warrior", {"name": "Warrior Cape", "type": ItemType.ARMOR, "rarity": ItemRarity.EPIC,
		"size": Vector2i(2, 2), "equip_slot": "cape", "stats": {"damage_mult": 0.1}, "buy_price": 100000, "weight": 0.5})
	_define_item("gloves_tactical", {"name": "Tactical Gloves", "type": ItemType.ARMOR, "rarity": ItemRarity.COMMON,
		"size": Vector2i(2, 2), "equip_slot": "hands", "stats": {"reload_speed": 0.05}, "buy_price": 8000, "weight": 0.3})
	_define_item("boots_combat", {"name": "Combat Boots", "type": ItemType.ARMOR, "rarity": ItemRarity.COMMON,
		"size": Vector2i(2, 2), "equip_slot": "feet", "stats": {"sprint_speed": 0.05}, "buy_price": 10000, "weight": 1.2})
	_define_item("pants_cargo", {"name": "Cargo Pants", "type": ItemType.ARMOR, "rarity": ItemRarity.COMMON,
		"size": Vector2i(2, 2), "equip_slot": "pants", "stats": {"carry_weight": 5.0}, "buy_price": 6000, "weight": 0.8})

func _define_item(id: String, data: Dictionary):
	item_database[id] = {"id": id, "name": data.get("name", "Unknown"), "type": data.get("type", ItemType.MATERIAL),
		"rarity": data.get("rarity", ItemRarity.COMMON), "size": data.get("size", Vector2i(1, 1)),
		"equip_slot": data.get("equip_slot", ""), "is_stackable": data.get("is_stackable", false),
		"max_stack": data.get("max_stack", 1), "damage": data.get("damage", 0.0), "fire_rate": data.get("fire_rate", 0.0),
		"ammo_type": data.get("ammo_type", ""), "magazine_size": data.get("magazine_size", 0),
		"armor_value": data.get("armor_value", 0.0), "armor_class": data.get("armor_class", 0),
		"stats": data.get("stats", {}), "use_time": data.get("use_time", 1.0), "effects": data.get("effects", []),
		"buy_price": data.get("buy_price", 0), "sell_price": data.get("sell_price", 0), "weight": data.get("weight", 0.1)}

func create_container(id: String, cname: String, width: int, height: int) -> InventoryContainer:
	var container = InventoryContainer.new(id, width, height)
	container.display_name = cname
	containers[id] = container
	return container

func get_container(container_id: String) -> InventoryContainer:
	return containers.get(container_id, null)

func create_item(item_id: String, stack: int = 1) -> InventoryItem:
	if not item_database.has(item_id): return null
	var def = item_database[item_id]
	var item = InventoryItem.new()
	item.item_id = item_id
	item.display_name = def.name
	item.item_type = def.type
	item.rarity = def.rarity
	item.grid_size = def.size
	item.equip_slot = def.equip_slot
	item.is_stackable = def.is_stackable
	item.max_stack = def.max_stack
	item.current_stack = min(stack, def.max_stack)
	item.damage = def.damage
	item.fire_rate = def.fire_rate
	item.ammo_type = def.ammo_type
	item.magazine_size = def.magazine_size
	item.armor_value = def.armor_value
	item.armor_class = def.armor_class
	item.stats = def.stats.duplicate()
	item.use_time = def.use_time
	item.effects = def.effects.duplicate()
	item.buy_price = def.buy_price
	item.sell_price = def.get("sell_price", def.buy_price / 2)
	item.weight = def.weight
	return item

func add_item(item: InventoryItem, container_id: String, position: Vector2i = Vector2i(-1, -1)) -> bool:
	var container = get_container(container_id)
	if not container: return false
	if position.x < 0:
		position = container.find_free_position(item)
		if position.x < 0: return false
	if container.place_item(item, position):
		item_added.emit(item, container_id, position)
		container_updated.emit(container_id)
		return true
	return false

func remove_item(item: InventoryItem) -> bool:
	if item.container_id.is_empty(): return false
	var container = get_container(item.container_id)
	if not container: return false
	var cid = item.container_id
	if container.remove_item(item):
		item_removed.emit(item, cid)
		container_updated.emit(cid)
		return true
	return false

func move_item(item: InventoryItem, to_cid: String, pos: Vector2i) -> bool:
	var from_cid = item.container_id
	var from_container = get_container(from_cid)
	var to_container = get_container(to_cid)
	if not to_container: return false
	if from_container: from_container.remove_item(item)
	if not to_container.can_place_item(item, pos):
		if from_container:
			from_container.place_item(item, item.grid_position)
		return false
	to_container.place_item(item, pos)
	item_moved.emit(item, from_cid, to_cid, pos)
	container_updated.emit(from_cid)
	container_updated.emit(to_cid)
	return true

func rotate_item(item: InventoryItem) -> bool:
	if item.container_id.is_empty():
		item.rotate()
		item_rotated.emit(item)
		return true
	var container = get_container(item.container_id)
	if not container: return false
	var pos = item.grid_position
	container.remove_item(item)
	item.rotate()
	if container.can_place_item(item, pos):
		container.place_item(item, pos)
		item_rotated.emit(item)
		container_updated.emit(item.container_id)
		return true
	item.rotate()
	container.place_item(item, pos)
	return false

func equip_item(item: InventoryItem) -> bool:
	if item.equip_slot.is_empty(): return false
	var slot = item.equip_slot
	if slot.begins_with("ring"):
		if equipped_items.has("ring_left") and equipped_items.has("ring_right"):
			unequip_item("ring_left")
		elif equipped_items.has("ring_left"):
			slot = "ring_right"
		else:
			slot = "ring_left"
	if equipped_items.has(slot): unequip_item(slot)
	remove_item(item)
	equipped_items[slot] = item
	item_equipped.emit(item, slot)
	return true

func unequip_item(slot: String) -> InventoryItem:
	if not equipped_items.has(slot): return null
	var item = equipped_items[slot]
	equipped_items.erase(slot)
	if not add_item(item, "backpack"):
		if not add_item(item, "stash"):
			push_warning("No space for unequipped item")
	item_unequipped.emit(item, slot)
	return item

func get_equipped(slot: String) -> InventoryItem:
	return equipped_items.get(slot, null)

func get_equipment_stats() -> Dictionary:
	var stats = {}
	for slot in equipped_items:
		var item = equipped_items[slot]
		for stat in item.stats:
			if not stats.has(stat): stats[stat] = 0.0
			stats[stat] += item.stats[stat]
	return stats

func use_item(item: InventoryItem) -> bool:
	if item.item_type != ItemType.CONSUMABLE: return false
	for effect in item.effects:
		_apply_effect(effect)
	item_used.emit(item)
	item.current_stack -= 1
	if item.current_stack <= 0: remove_item(item)
	return true

func _apply_effect(effect: Dictionary):
	var player = _get_local_player()
	if not player: return
	match effect.get("type", ""):
		"heal":
			if player.has_method("heal"): player.heal(effect.get("amount", 0.0))
		"restore_stamina":
			if "stamina" in player: player.stamina = min(player.max_stamina, player.stamina + effect.get("amount", 0.0))

func _get_local_player() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p.get_multiplayer_authority() == multiplayer.get_unique_id(): return p
	return null

func add_currency(ctype: String, amount: int):
	if not currency.has(ctype): currency[ctype] = 0
	currency[ctype] += amount
	currency_changed.emit(ctype, currency[ctype])

func remove_currency(ctype: String, amount: int) -> bool:
	if not currency.has(ctype) or currency[ctype] < amount: return false
	currency[ctype] -= amount
	currency_changed.emit(ctype, currency[ctype])
	return true

func get_currency(ctype: String) -> int:
	return currency.get(ctype, 0)

func get_total_weight() -> float:
	var weight = 0.0
	for cid in containers:
		for item in containers[cid].get_all_items():
			weight += item.weight * item.current_stack
	for slot in equipped_items:
		weight += equipped_items[slot].weight
	return weight

func has_item(item_id: String, count: int = 1) -> bool:
	return count_item(item_id) >= count

func count_item(item_id: String) -> int:
	var found = 0
	for cid in containers:
		for item in containers[cid].get_all_items():
			if item.item_id == item_id:
				found += item.current_stack
	return found

func add_item_by_id(item_id: String, container_id: String = "backpack", quantity: int = 1) -> InventoryItem:
	"""Create an item from database and add it to specified container"""
	var item = create_item(item_id, quantity)
	if not item:
		return null
	if add_item(item, container_id):
		return item
	# Try stash if backpack full
	if container_id == "backpack" and add_item(item, "stash"):
		return item
	return null

func find_item_by_id(item_id: String) -> InventoryItem:
	"""Find first item matching ID in any container"""
	for cid in containers:
		for item in containers[cid].get_all_items():
			if item.item_id == item_id:
				return item
	return null

func remove_item_by_id(item_id: String, quantity: int = 1) -> bool:
	"""Remove specified quantity of item from inventory"""
	var remaining = quantity
	for cid in containers:
		for item in containers[cid].get_all_items():
			if item.item_id == item_id:
				if item.current_stack <= remaining:
					remaining -= item.current_stack
					remove_item(item)
				else:
					item.current_stack -= remaining
					remaining = 0
				if remaining <= 0:
					return true
	return remaining <= 0
