extends Node
class_name MerchantSystem

signal shop_opened
signal shop_closed
signal item_purchased(item, cost: int)  # item is ItemDataExtended
signal item_sold(item, price: int)  # item is ItemDataExtended
signal shop_refreshed

enum CurrencyType {
	COINS,
	TOKENS,
	SCRAP
}

class ShopItem:
	var item  # ItemDataExtended - type hint removed for load order compatibility
	var cost: int
	var currency_type: int  # CurrencyType enum
	var stock: int = -1  # -1 = infinite
	var sold_out: bool = false
	var unlock_required: String = ""

	func _init(itm, price: int, curr: int = 0, stk: int = -1):  # CurrencyType.COINS = 0
		item = itm
		cost = price
		currency_type = curr
		stock = stk

var shop_inventory: Array = []
var player_persistence: Node  # PlayerPersistence autoload

@export var refresh_cost_coins: int = 100
@export var sell_value_multiplier: float = 0.6

func _ready():
	# Try to find PlayerPersistence autoload
	player_persistence = get_node_or_null("/root/PlayerPersistence")
	generate_shop_inventory()

func generate_shop_inventory():
	shop_inventory.clear()

	# Load item data class
	var ItemDataExtendedClass = load("res://scripts/items/item_data_extended.gd")
	if not ItemDataExtendedClass:
		shop_refreshed.emit()
		return

	# Generate default shop inventory with varied items
	_add_weapon_items(ItemDataExtendedClass)
	_add_armor_items(ItemDataExtendedClass)
	_add_consumable_items(ItemDataExtendedClass)

	shop_refreshed.emit()

func _add_weapon_items(ItemClass):
	# Pistol
	var pistol = ItemClass.new()
	pistol.item_name = "Combat Pistol"
	pistol.item_type = 0  # WEAPON
	pistol.rarity = 0  # COMMON
	pistol.damage = 15.0
	pistol.fire_rate = 0.15
	pistol.magazine_size = 12
	pistol.reload_time = 1.5
	pistol.weapon_range = 50.0
	pistol.value = 500
	shop_inventory.append(ShopItem.new(pistol, 500, CurrencyType.COINS))

	# Shotgun
	var shotgun = ItemClass.new()
	shotgun.item_name = "Pump Shotgun"
	shotgun.item_type = 0
	shotgun.rarity = 1  # UNCOMMON
	shotgun.damage = 80.0
	shotgun.fire_rate = 0.8
	shotgun.magazine_size = 6
	shotgun.reload_time = 3.0
	shotgun.weapon_range = 25.0
	shotgun.projectile_count = 8
	shotgun.spread_angle = 15.0
	shotgun.value = 1200
	shop_inventory.append(ShopItem.new(shotgun, 1200, CurrencyType.COINS))

	# Assault Rifle
	var rifle = ItemClass.new()
	rifle.item_name = "M4 Assault Rifle"
	rifle.item_type = 0
	rifle.rarity = 1
	rifle.damage = 25.0
	rifle.fire_rate = 0.1
	rifle.magazine_size = 30
	rifle.reload_time = 2.5
	rifle.weapon_range = 80.0
	rifle.value = 2000
	shop_inventory.append(ShopItem.new(rifle, 2000, CurrencyType.COINS))

	# SMG
	var smg = ItemClass.new()
	smg.item_name = "MP5 Submachine Gun"
	smg.item_type = 0
	smg.rarity = 1
	smg.damage = 18.0
	smg.fire_rate = 0.07
	smg.magazine_size = 25
	smg.reload_time = 2.0
	smg.weapon_range = 40.0
	smg.value = 1500
	shop_inventory.append(ShopItem.new(smg, 1500, CurrencyType.COINS))

	# Sniper
	var sniper = ItemClass.new()
	sniper.item_name = "Hunting Rifle"
	sniper.item_type = 0
	sniper.rarity = 2  # RARE
	sniper.damage = 150.0
	sniper.fire_rate = 1.5
	sniper.magazine_size = 5
	sniper.reload_time = 3.5
	sniper.weapon_range = 200.0
	sniper.headshot_bonus = 1.5
	sniper.value = 3500
	shop_inventory.append(ShopItem.new(sniper, 3500, CurrencyType.COINS))

func _add_armor_items(ItemClass):
	# Basic Helmet
	var helmet = ItemClass.new()
	helmet.item_name = "Combat Helmet"
	helmet.item_type = 6  # HELMET
	helmet.rarity = 0
	helmet.armor_value = 10.0
	helmet.durability = 100.0
	helmet.max_durability = 100.0
	helmet.value = 300
	shop_inventory.append(ShopItem.new(helmet, 300, CurrencyType.COINS))

	# Body Armor
	var armor = ItemClass.new()
	armor.item_name = "Kevlar Vest"
	armor.item_type = 7  # CHEST_ARMOR
	armor.rarity = 1
	armor.armor_value = 25.0
	armor.durability = 150.0
	armor.max_durability = 150.0
	armor.value = 800
	shop_inventory.append(ShopItem.new(armor, 800, CurrencyType.COINS))

	# Combat Boots
	var boots = ItemClass.new()
	boots.item_name = "Steel-Toe Boots"
	boots.item_type = 10  # BOOTS
	boots.rarity = 0
	boots.armor_value = 5.0
	boots.movement_speed_bonus = 0.05
	boots.value = 400
	shop_inventory.append(ShopItem.new(boots, 400, CurrencyType.COINS))

func _add_consumable_items(ItemClass):
	# Health Pack
	var health = ItemClass.new()
	health.item_name = "First Aid Kit"
	health.item_type = 12  # CONSUMABLE
	health.rarity = 0
	health.health_restore = 50.0
	health.stack_size = 5
	health.value = 100
	shop_inventory.append(ShopItem.new(health, 100, CurrencyType.COINS, 10))

	# Large Health Pack
	var large_health = ItemClass.new()
	large_health.item_name = "Medical Kit"
	large_health.item_type = 12
	large_health.rarity = 1
	large_health.health_restore = 100.0
	large_health.stack_size = 3
	large_health.value = 250
	shop_inventory.append(ShopItem.new(large_health, 250, CurrencyType.COINS, 5))

	# Stamina Drink
	var stamina = ItemClass.new()
	stamina.item_name = "Energy Drink"
	stamina.item_type = 12
	stamina.rarity = 0
	stamina.stamina_restore = 50.0
	stamina.stack_size = 10
	stamina.value = 50
	shop_inventory.append(ShopItem.new(stamina, 50, CurrencyType.COINS, 20))

	# Grenade
	var grenade = ItemClass.new()
	grenade.item_name = "Frag Grenade"
	grenade.item_type = 12
	grenade.rarity = 1
	grenade.damage = 100.0
	grenade.stack_size = 3
	grenade.value = 200
	shop_inventory.append(ShopItem.new(grenade, 200, CurrencyType.COINS, 5))

func refresh_shop():
	if player_persistence and player_persistence.spend_currency("coins", refresh_cost_coins):
		generate_shop_inventory()
		return true
	return false

func can_afford(shop_item) -> bool:  # shop_item: ShopItem
	if not player_persistence:
		return false

	var currency_name = get_currency_name(shop_item.currency_type)
	return player_persistence.get_currency(currency_name) >= shop_item.cost

func purchase_item(shop_item, inventory_system) -> bool:  # shop_item: ShopItem, inventory_system: InventorySystem
	if not can_afford(shop_item):
		return false

	if shop_item.sold_out or shop_item.stock == 0:
		return false

	# Check unlock requirements
	if shop_item.unlock_required != "" and player_persistence:
		if not player_persistence.is_weapon_unlocked(shop_item.unlock_required):
			return false

	# Deduct currency
	var currency_name = get_currency_name(shop_item.currency_type)
	if player_persistence and player_persistence.spend_currency(currency_name, shop_item.cost):
		# Add to inventory
		if inventory_system and inventory_system.add_item(shop_item.item, 1):
			# Update stock
			if shop_item.stock > 0:
				shop_item.stock -= 1
				if shop_item.stock == 0:
					shop_item.sold_out = true

			item_purchased.emit(shop_item.item, shop_item.cost)
			return true

	return false

func sell_item(item, quantity: int, inventory_system) -> bool:  # item: ItemDataExtended, inventory_system: InventorySystem
	if not inventory_system or not player_persistence:
		return false

	# Calculate sell price
	var sell_price = int(item.value * sell_value_multiplier * quantity)

	# Remove from inventory
	if inventory_system.remove_item(item, quantity):
		# Add currency
		player_persistence.add_currency("coins", sell_price)
		item_sold.emit(item, sell_price)
		return true

	return false

func get_currency_name(type: CurrencyType) -> String:
	match type:
		CurrencyType.COINS: return "coins"
		CurrencyType.TOKENS: return "tokens"
		CurrencyType.SCRAP: return "scrap"
	return "coins"

func get_currency_icon(type: CurrencyType) -> String:
	match type:
		CurrencyType.COINS: return "💰"
		CurrencyType.TOKENS: return "🎫"
		CurrencyType.SCRAP: return "🔧"
	return "💰"

func filter_shop_by_type(item_type: int) -> Array:  # item_type: ItemDataExtended.ItemType
	var filtered: Array = []
	for shop_item in shop_inventory:
		if shop_item.item.item_type == item_type:
			filtered.append(shop_item)
	return filtered

func filter_shop_by_rarity(rarity: int) -> Array:  # rarity: ItemDataExtended.ItemRarity
	var filtered: Array = []
	for shop_item in shop_inventory:
		if shop_item.item.rarity == rarity:
			filtered.append(shop_item)
	return filtered

func get_daily_deals() -> Array:
	# Generate special rotating deals based on current day
	var deals: Array = []

	# Use day of year as seed for consistent daily deals
	var date = Time.get_datetime_dict_from_system()
	var day_seed = date.year * 1000 + date.month * 31 + date.day

	# Load item data class
	var ItemDataExtendedClass = load("res://scripts/items/item_data_extended.gd")
	if not ItemDataExtendedClass:
		return deals

	# Generate 3 daily deal items with discounts
	var rng = RandomNumberGenerator.new()
	rng.seed = day_seed

	# Daily deal 1: Discounted rare weapon
	var deal_weapon = ItemDataExtendedClass.new()
	var weapon_types = ["Tactical SMG", "Combat Shotgun", "Battle Rifle", "Auto Pistol"]
	deal_weapon.item_name = weapon_types[rng.randi() % weapon_types.size()]
	deal_weapon.item_type = 0  # WEAPON
	deal_weapon.rarity = 2  # RARE
	deal_weapon.damage = 30.0 + rng.randf() * 20.0
	deal_weapon.fire_rate = 0.08 + rng.randf() * 0.1
	deal_weapon.magazine_size = 20 + rng.randi() % 15
	deal_weapon.value = 2000 + rng.randi() % 1000
	var weapon_deal = ShopItem.new(deal_weapon, int(deal_weapon.value * 0.7), CurrencyType.COINS, 1)
	deals.append(weapon_deal)

	# Daily deal 2: Discounted armor piece
	var deal_armor = ItemDataExtendedClass.new()
	var armor_names = ["Tactical Vest", "Heavy Helmet", "Combat Gloves", "Reinforced Boots"]
	var armor_types = [7, 6, 8, 10]  # CHEST, HELMET, GLOVES, BOOTS
	var armor_idx = rng.randi() % armor_names.size()
	deal_armor.item_name = armor_names[armor_idx]
	deal_armor.item_type = armor_types[armor_idx]
	deal_armor.rarity = 2
	deal_armor.armor_value = 15.0 + rng.randf() * 15.0
	deal_armor.durability = 150.0
	deal_armor.max_durability = 150.0
	deal_armor.value = 1000 + rng.randi() % 500
	var armor_deal = ShopItem.new(deal_armor, int(deal_armor.value * 0.6), CurrencyType.COINS, 1)
	deals.append(armor_deal)

	# Daily deal 3: Discounted consumable bundle
	var deal_consumable = ItemDataExtendedClass.new()
	deal_consumable.item_name = "Survival Pack"
	deal_consumable.item_type = 12  # CONSUMABLE
	deal_consumable.rarity = 1
	deal_consumable.health_restore = 75.0
	deal_consumable.stamina_restore = 50.0
	deal_consumable.stack_size = 5
	deal_consumable.value = 400
	var consumable_deal = ShopItem.new(deal_consumable, 250, CurrencyType.COINS, 3)
	deals.append(consumable_deal)

	return deals

func add_shop_item(item, cost: int, currency: int = 0, stock: int = -1):  # item: ItemDataExtended, currency: CurrencyType
	shop_inventory.append(ShopItem.new(item, cost, currency, stock))
	shop_refreshed.emit()
