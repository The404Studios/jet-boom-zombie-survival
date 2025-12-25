extends Node
class_name MerchantSystem

signal shop_opened
signal shop_closed
signal item_purchased(item: ItemDataExtended, cost: int)
signal item_sold(item: ItemDataExtended, price: int)
signal shop_refreshed

enum CurrencyType {
	COINS,
	TOKENS,
	SCRAP
}

class ShopItem:
	var item: ItemDataExtended
	var cost: int
	var currency_type: CurrencyType
	var stock: int = -1  # -1 = infinite
	var sold_out: bool = false
	var unlock_required: String = ""

	func _init(itm: ItemDataExtended, price: int, curr: CurrencyType = CurrencyType.COINS, stk: int = -1):
		item = itm
		cost = price
		currency_type = curr
		stock = stk

var shop_inventory: Array = []
var player_persistence: Node  # PlayerPersistence autoload

@export var refresh_cost_coins: int = 100
@export var sell_value_multiplier: float = 0.6

func _ready():
	generate_shop_inventory()

func generate_shop_inventory():
	shop_inventory.clear()

	# Would load items from database/resources
	# Example items:
	# shop_inventory.append(ShopItem.new(pistol_item, 500, CurrencyType.COINS))
	# shop_inventory.append(ShopItem.new(health_pack, 50, CurrencyType.COINS, 10))

	shop_refreshed.emit()

func refresh_shop():
	if player_persistence and player_persistence.spend_currency("coins", refresh_cost_coins):
		generate_shop_inventory()
		return true
	return false

func can_afford(shop_item: ShopItem) -> bool:
	if not player_persistence:
		return false

	var currency_name = get_currency_name(shop_item.currency_type)
	return player_persistence.get_currency(currency_name) >= shop_item.cost

func purchase_item(shop_item: ShopItem, inventory_system: InventorySystem) -> bool:
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

func sell_item(item: ItemDataExtended, quantity: int, inventory_system: InventorySystem) -> bool:
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

func filter_shop_by_type(item_type: ItemDataExtended.ItemType) -> Array[ShopItem]:
	var filtered: Array[ShopItem] = []
	for shop_item in shop_inventory:
		if shop_item.item.item_type == item_type:
			filtered.append(shop_item)
	return filtered

func filter_shop_by_rarity(rarity: ItemDataExtended.ItemRarity) -> Array[ShopItem]:
	var filtered: Array[ShopItem] = []
	for shop_item in shop_inventory:
		if shop_item.item.rarity == rarity:
			filtered.append(shop_item)
	return filtered

func get_daily_deals() -> Array[ShopItem]:
	# Would generate special rotating deals
	var deals: Array[ShopItem] = []
	# Implementation here
	return deals

func add_shop_item(item: ItemDataExtended, cost: int, currency: CurrencyType = CurrencyType.COINS, stock: int = -1):
	shop_inventory.append(ShopItem.new(item, cost, currency, stock))
	shop_refreshed.emit()
