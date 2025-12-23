extends Node
class_name InventorySystem

signal inventory_changed
signal item_equipped(item: ItemData)
signal item_unequipped(item: ItemData)

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

func add_item(item: ItemData, quantity: int = 1) -> bool:
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

func remove_item(item: ItemData, quantity: int = 1) -> bool:
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

func get_item_count(item: ItemData) -> int:
	var count = 0
	for inv_item in inventory:
		if inv_item.item == item:
			count += inv_item.quantity
	return count

func equip_weapon(item: ItemData) -> bool:
	if item.item_type != ItemData.ItemType.WEAPON:
		return false

	if equipped_weapon:
		unequip_weapon()

	equipped_weapon = {"item": item, "quantity": 1, "current_ammo": item.magazine_size}
	item_equipped.emit(item)
	return true

func unequip_weapon():
	if equipped_weapon:
		item_unequipped.emit(equipped_weapon.item)
		equipped_weapon = {}

func equip_armor(item: ItemData) -> bool:
	if item.item_type != ItemData.ItemType.ARMOR:
		return false

	if equipped_armor:
		add_item(equipped_armor.item, 1)

	equipped_armor = {"item": item, "quantity": 1}
	item_equipped.emit(item)
	return true

func transfer_to_stash(item: ItemData, quantity: int = 1) -> bool:
	if remove_item(item, quantity):
		# Add to stash
		for i in range(stash.size()):
			if stash[i].item == item:
				stash[i].quantity += quantity
				return true
		stash.append({"item": item, "quantity": quantity})
		return true
	return false

func transfer_from_stash(item: ItemData, quantity: int = 1) -> bool:
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
