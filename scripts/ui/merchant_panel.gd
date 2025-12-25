extends Control
class_name MerchantPanel

signal item_purchased(item: ItemDataExtended, cost: int)
signal item_sold(item: ItemDataExtended, price: int)
signal craft_started(recipe: Dictionary)

# UI References
@onready var merchant_rep_label: Label = $TopBar/MerchantRep
@onready var currency_label: Label = $TopBar/Currency
@onready var selling_grid: GridContainer = $LeftPanel/SellingSection/Grid
@onready var crafting_grid: GridContainer = $LeftPanel/CraftingSection/Grid
@onready var stash_grid: GridContainer = $RightPanel/ScrollContainer/StashGrid

# Merchant data
var merchant_reputation: int = 0
var merchant_inventory: Array = []
var crafting_recipes: Array = []
var player_stash: Array = []
var player_currency: int = 0

func _ready():
	_setup_grids()
	_load_merchant_inventory()
	_update_display()

func _setup_grids():
	if selling_grid:
		selling_grid.columns = 3
		_populate_grid(selling_grid, 12)

	if crafting_grid:
		crafting_grid.columns = 3
		_populate_grid(crafting_grid, 6)

	if stash_grid:
		stash_grid.columns = 6
		_populate_grid(stash_grid, 24)

func _populate_grid(grid: GridContainer, count: int):
	for i in range(count):
		var slot = _create_slot(i)
		grid.add_child(slot)

func _create_slot(index: int) -> Panel:
	var slot = Panel.new()
	slot.name = "Slot_%d" % index
	slot.custom_minimum_size = Vector2(60, 60)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.95)
	style.border_color = Color(0.25, 0.25, 0.28)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("panel", style)

	var button = Button.new()
	button.name = "Button"
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.flat = true
	slot.add_child(button)

	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(icon)

	var price_label = Label.new()
	price_label.name = "Price"
	price_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	price_label.position = Vector2(2, -16)
	price_label.add_theme_font_size_override("font_size", 10)
	price_label.add_theme_color_override("font_color", Color.GOLD)
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(price_label)

	return slot

func _load_merchant_inventory():
	# Load merchant inventory from available resources
	merchant_inventory = []

	# Define merchant stock based on reputation level
	var base_items = [
		{"path": "res://resources/items/health_pack.tres", "price": 100, "min_rep": 0},
		{"path": "res://resources/items/ammo_box.tres", "price": 50, "min_rep": 0},
		{"path": "res://resources/weapons/pistol.tres", "price": 200, "min_rep": 0},
		{"path": "res://resources/weapons/shotgun.tres", "price": 500, "min_rep": 5},
		{"path": "res://resources/weapons/ak47.tres", "price": 800, "min_rep": 10},
		{"path": "res://resources/weapons/mp5.tres", "price": 600, "min_rep": 8},
		{"path": "res://resources/weapons/sniper_rifle.tres", "price": 1200, "min_rep": 15},
		{"path": "res://resources/armor/tactical_helmet.tres", "price": 400, "min_rep": 5},
		{"path": "res://resources/armor/combat_vest.tres", "price": 600, "min_rep": 10},
		{"path": "res://resources/armor/marksman_gloves.tres", "price": 300, "min_rep": 5},
		{"path": "res://resources/armor/sprint_boots.tres", "price": 350, "min_rep": 8},
		{"path": "res://resources/augments/damage_augment.tres", "price": 250, "min_rep": 15}
	]

	# Add items player has sufficient reputation for
	for item_data in base_items:
		if merchant_reputation >= item_data.min_rep:
			if ResourceLoader.exists(item_data.path):
				var item = load(item_data.path)
				if item:
					merchant_inventory.append({
						"item": item,
						"price": item_data.price
					})

	# Setup crafting recipes
	crafting_recipes = [
		{
			"name": "Enhanced Ammo",
			"result_icon": null,
			"materials": [
				{"item_name": "Ammo Box", "count": 2},
				{"item_name": "Scrap Metal", "count": 1}
			],
			"result": "Enhanced Ammo Box"
		},
		{
			"name": "Medkit",
			"result_icon": null,
			"materials": [
				{"item_name": "Health Pack", "count": 3}
			],
			"result": "Large Medkit"
		}
	]

func _update_display():
	if merchant_rep_label:
		merchant_rep_label.text = "merchant rep"

	if currency_label:
		currency_label.text = "currency"

func refresh_merchant_stock():
	# Refresh available items based on reputation and game state
	_update_selling_display()
	_update_crafting_display()

func _update_selling_display():
	if not selling_grid:
		return

	for i in range(selling_grid.get_child_count()):
		var slot = selling_grid.get_child(i)
		var icon = slot.get_node_or_null("Icon") as TextureRect
		var price_label = slot.get_node_or_null("Price") as Label

		if i < merchant_inventory.size():
			var item_data = merchant_inventory[i]
			if icon:
				icon.texture = item_data.item.icon if item_data.item else null
			if price_label:
				price_label.text = "$%d" % item_data.price if item_data else ""
		else:
			if icon:
				icon.texture = null
			if price_label:
				price_label.text = ""

func _update_crafting_display():
	if not crafting_grid:
		return

	for i in range(crafting_grid.get_child_count()):
		var slot = crafting_grid.get_child(i)
		var icon = slot.get_node_or_null("Icon") as TextureRect

		if i < crafting_recipes.size():
			var recipe = crafting_recipes[i]
			if icon and recipe.has("result_icon"):
				icon.texture = recipe.result_icon
		else:
			if icon:
				icon.texture = null

func update_player_stash(items: Array):
	player_stash = items
	_refresh_stash_display()

func _refresh_stash_display():
	if not stash_grid:
		return

	for i in range(stash_grid.get_child_count()):
		var slot = stash_grid.get_child(i)
		var icon = slot.get_node_or_null("Icon") as TextureRect

		if i < player_stash.size() and player_stash[i]:
			if icon:
				icon.texture = player_stash[i].item.icon if player_stash[i].item else null
		else:
			if icon:
				icon.texture = null

func purchase_item(index: int) -> bool:
	if index >= merchant_inventory.size():
		return false

	var item_data = merchant_inventory[index]
	if player_currency < item_data.price:
		return false

	player_currency -= item_data.price
	item_purchased.emit(item_data.item, item_data.price)
	_update_display()
	return true

func sell_item(item: ItemDataExtended) -> int:
	var sell_price = int(item.value * 0.6)  # 60% of base value
	player_currency += sell_price
	item_sold.emit(item, sell_price)
	_update_display()
	return sell_price

func craft_item(recipe_index: int) -> bool:
	if recipe_index >= crafting_recipes.size():
		return false

	var recipe = crafting_recipes[recipe_index]

	# Check if player has required materials
	for material in recipe.materials:
		var material_name = material.get("item_name", "")
		var required_count = material.get("count", 1)
		var found_count = 0

		# Count matching materials in player stash
		for stash_item in player_stash:
			if stash_item and stash_item.has("item"):
				var item = stash_item.item
				if item and "item_name" in item and item.item_name == material_name:
					found_count += stash_item.get("count", 1)

		if found_count < required_count:
			# Not enough materials
			print("Missing material: %s (need %d, have %d)" % [material_name, required_count, found_count])
			return false

	# Remove materials from stash
	for material in recipe.materials:
		var material_name = material.get("item_name", "")
		var required_count = material.get("count", 1)
		var removed = 0

		for i in range(player_stash.size() - 1, -1, -1):
			if removed >= required_count:
				break
			var stash_item = player_stash[i]
			if stash_item and stash_item.has("item"):
				var item = stash_item.item
				if item and "item_name" in item and item.item_name == material_name:
					var take = mini(stash_item.get("count", 1), required_count - removed)
					stash_item["count"] = stash_item.get("count", 1) - take
					removed += take
					if stash_item.get("count", 0) <= 0:
						player_stash.remove_at(i)

	craft_started.emit(recipe)
	_refresh_stash_display()
	return true

func open():
	visible = true
	refresh_merchant_stock()
	_refresh_stash_display()

func close():
	visible = false
