extends Node
# Note: Do not use class_name here - this script is an autoload singleton

signal inventory_changed
signal item_equipped(item)  # item: ItemData
signal item_unequipped(item)  # item: ItemData

var inventory: Array[Dictionary] = []
var stash: Array[Dictionary] = []
var equipped_weapon: Dictionary = {}
var equipped_armor: Dictionary = {}
var max_inventory_slots: int = 20
var max_weight: float = 100.0

func _ready():
	# Initialize inventory with empty state
	inventory = []
	stash = []
	equipped_weapon = {}
	equipped_armor = {}

	# Connect to game manager if available for persistence
	if has_node("/root/GameManager"):
		var game_manager = get_node("/root/GameManager")
		if game_manager.has_signal("game_started"):
			game_manager.game_started.connect(_on_game_started)

func _on_game_started():
	# Reset inventory state for new game
	clear_inventory()

func add_item(item, quantity: int = 1) -> bool:  # item: ItemData
	# Check if item can stack
	for i in range(inventory.size()):
		if inventory[i].item == item and inventory[i].quantity < item.stack_size:
			var space = item.stack_size - inventory[i].quantity
			var add_amount = min(space, quantity)
			inventory[i].quantity += add_amount
			quantity -= add_amount
			inventory_changed.emit()
			if quantity <= 0:
				return true

	# Add new stack
	while quantity > 0 and inventory.size() < max_inventory_slots:
		var add_amount = min(quantity, item.stack_size)
		inventory.append({
			"item": item,
			"quantity": add_amount
		})
		quantity -= add_amount
		inventory_changed.emit()

	return quantity <= 0

func remove_item(item, quantity: int = 1) -> bool:  # item: ItemData
	var remaining = quantity
	for i in range(inventory.size() - 1, -1, -1):
		if inventory[i].item == item:
			if inventory[i].quantity <= remaining:
				remaining -= inventory[i].quantity
				inventory.remove_at(i)
			else:
				inventory[i].quantity -= remaining
				remaining = 0

			if remaining <= 0:
				inventory_changed.emit()
				return true

	inventory_changed.emit()
	return false

func get_item_count(item) -> int:  # item: ItemData
	var count = 0
	for inv_item in inventory:
		if inv_item.item == item:
			count += inv_item.quantity
	return count

func equip_weapon(item) -> bool:  # item: ItemData
	if item.item_type != 0:  # ItemData.ItemType.WEAPON = 0
		return false

	if equipped_weapon:
		unequip_weapon()

	equipped_weapon = {"item": item, "quantity": 1, "current_ammo": item.magazine_size}
	item_equipped.emit(item)
	return true

func unequip_weapon():
	if equipped_weapon and not equipped_weapon.is_empty():
		var item = equipped_weapon.get("item")
		if item:
			item_unequipped.emit(item)
		equipped_weapon = {}

func equip_armor(item) -> bool:  # item: ItemData
	if item.item_type != 3:  # ItemData.ItemType.ARMOR = 3
		return false

	if equipped_armor and not equipped_armor.is_empty():
		var armor_item = equipped_armor.get("item")
		if armor_item:
			add_item(armor_item, 1)

	equipped_armor = {"item": item, "quantity": 1}
	item_equipped.emit(item)
	return true

func transfer_to_stash(item, quantity: int = 1) -> bool:  # item: ItemData
	if remove_item(item, quantity):
		# Add to stash
		for i in range(stash.size()):
			if stash[i].item == item:
				stash[i].quantity += quantity
				return true
		stash.append({"item": item, "quantity": quantity})
		return true
	return false

func transfer_from_stash(item, quantity: int = 1) -> bool:  # item: ItemData
	# Remove from stash
	var remaining = quantity
	for i in range(stash.size() - 1, -1, -1):
		if stash[i].item == item:
			if stash[i].quantity <= remaining:
				remaining -= stash[i].quantity
				stash.remove_at(i)
			else:
				stash[i].quantity -= remaining
				remaining = 0

			if remaining <= 0:
				return add_item(item, quantity)
	return false

func get_current_weight() -> float:
	var weight = 0.0
	for inv_item in inventory:
		weight += inv_item.item.weight * inv_item.quantity
	return weight

func clear_inventory():
	inventory.clear()
	equipped_weapon = {}
	equipped_armor = {}
	inventory_changed.emit()
