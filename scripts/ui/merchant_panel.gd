extends Control
class_name MerchantPanel

signal item_purchased(item, cost: int)  # item: ItemDataExtended
signal item_sold(item, price: int)  # item: ItemDataExtended
signal craft_started(recipe: Dictionary)
signal panel_closed

# UI References
@onready var merchant_rep_label: Label = get_node_or_null("TopBar/MerchantRep")
@onready var currency_label: Label = get_node_or_null("TopBar/Currency")
@onready var selling_grid: GridContainer = get_node_or_null("LeftPanel/SellingSection/Grid")
@onready var crafting_grid: GridContainer = get_node_or_null("LeftPanel/CraftingSection/Grid")
@onready var stash_grid: GridContainer = get_node_or_null("RightPanel/ScrollContainer/StashGrid")
@onready var buy_button: Button = get_node_or_null("BottomBar/BuyButton")
@onready var sell_button: Button = get_node_or_null("BottomBar/SellButton")
@onready var craft_button: Button = get_node_or_null("BottomBar/CraftButton")
@onready var back_button: Button = get_node_or_null("BottomBar/BackButton")
@onready var rep_progress: ProgressBar = get_node_or_null("TopBar/RepProgress")
@onready var item_tooltip: Panel = get_node_or_null("ItemTooltip")

# Merchant data
var merchant_reputation: int = 0
var max_reputation: int = 100
var merchant_inventory: Array = []
var crafting_recipes: Array = []
var player_stash: Array = []
var player_currency: int = 0

# Selection tracking
var selected_sell_index: int = -1
var selected_stash_index: int = -1
var selected_craft_index: int = -1

# Price modifiers based on reputation
const REP_DISCOUNT_THRESHOLDS = {
	25: 0.05,
	50: 0.10,
	75: 0.15,
	100: 0.20
}

func _ready():
	_setup_grids()
	_connect_signals()
	_load_merchant_inventory()
	_load_player_data()
	_update_display()

func _setup_grids():
	if selling_grid:
		selling_grid.columns = 3
		_populate_grid(selling_grid, 12, true)

	if crafting_grid:
		crafting_grid.columns = 3
		_populate_grid(crafting_grid, 6, false)

	if stash_grid:
		stash_grid.columns = 6
		_populate_grid(stash_grid, 24, false)

func _populate_grid(grid: GridContainer, count: int, is_merchant: bool):
	for i in range(count):
		var slot = _create_slot(i, is_merchant)
		grid.add_child(slot)

func _create_slot(index: int, is_merchant: bool) -> Panel:
	var slot = Panel.new()
	slot.name = "Slot_%d" % index
	slot.custom_minimum_size = Vector2(60, 70)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.95)
	style.border_color = Color(0.25, 0.25, 0.28)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("panel", style)

	# VBox for layout
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 2)
	slot.add_child(vbox)

	# Icon container
	var icon_container = PanelContainer.new()
	icon_container.custom_minimum_size = Vector2(55, 45)
	vbox.add_child(icon_container)

	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(icon)

	# Name label
	var name_label = Label.new()
	name_label.name = "Name"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 8)
	name_label.clip_text = true
	name_label.custom_minimum_size = Vector2(55, 0)
	vbox.add_child(name_label)

	# Price label
	var price_label = Label.new()
	price_label.name = "Price"
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.add_theme_font_size_override("font_size", 10)
	price_label.add_theme_color_override("font_color", Color.GOLD)
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(price_label)

	# Button for interaction
	var button = Button.new()
	button.name = "Button"
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.flat = true
	if is_merchant:
		button.pressed.connect(_on_sell_slot_clicked.bind(index))
	else:
		button.pressed.connect(_on_stash_slot_clicked.bind(index))
	button.mouse_entered.connect(_on_slot_hover.bind(slot, true, index, is_merchant))
	button.mouse_exited.connect(_on_slot_hover.bind(slot, false, index, is_merchant))
	slot.add_child(button)

	return slot

func _on_slot_hover(slot: Panel, hovering: bool, index: int, is_merchant: bool):
	var style = slot.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		if hovering:
			style.border_color = Color(0.5, 0.7, 0.9)
			style.set_border_width_all(2)
			_show_item_tooltip(index, is_merchant)
		else:
			style.border_color = Color(0.25, 0.25, 0.28)
			style.set_border_width_all(1)
			_hide_item_tooltip()

func _connect_signals():
	if buy_button:
		buy_button.pressed.connect(_on_buy_pressed)
	if sell_button:
		sell_button.pressed.connect(_on_sell_pressed)
	if craft_button:
		craft_button.pressed.connect(_on_craft_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

	# Connect crafting slots
	if crafting_grid:
		for i in range(crafting_grid.get_child_count()):
			var slot = crafting_grid.get_child(i)
			var btn = slot.get_node_or_null("Button")
			if btn:
				btn.pressed.connect(_on_craft_slot_clicked.bind(i))

func _load_player_data():
	# Get player currency
	if has_node("/root/PointsSystem"):
		var ps = get_node("/root/PointsSystem")
		if ps.has_method("get_points"):
			player_currency = ps.get_points()

	# Get player inventory
	if has_node("/root/InventorySystem"):
		var inv = get_node("/root/InventorySystem")
		if inv.has_method("get_items"):
			player_stash = inv.get_items()
		elif "items" in inv:
			player_stash = inv.items

	# Load reputation from persistence
	if has_node("/root/PlayerPersistence"):
		var persistence = get_node("/root/PlayerPersistence")
		if persistence.player_data:
			merchant_reputation = persistence.player_data.get("merchant_reputation", 0)

func _load_merchant_inventory():
	merchant_inventory = []

	# Define merchant stock based on reputation level
	var base_items = [
		{"path": "res://resources/items/health_pack.tres", "price": 100, "min_rep": 0, "name": "Health Pack"},
		{"path": "res://resources/items/ammo_box.tres", "price": 50, "min_rep": 0, "name": "Ammo Box"},
		{"path": "res://resources/weapons/pistol.tres", "price": 200, "min_rep": 0, "name": "Pistol"},
		{"path": "res://resources/weapons/shotgun.tres", "price": 500, "min_rep": 25, "name": "Shotgun"},
		{"path": "res://resources/weapons/ak47.tres", "price": 800, "min_rep": 50, "name": "AK-47"},
		{"path": "res://resources/weapons/mp5.tres", "price": 600, "min_rep": 35, "name": "MP5"},
		{"path": "res://resources/weapons/sniper_rifle.tres", "price": 1200, "min_rep": 75, "name": "Sniper Rifle"},
		{"path": "res://resources/armor/tactical_helmet.tres", "price": 400, "min_rep": 25, "name": "Tactical Helmet"},
		{"path": "res://resources/armor/combat_vest.tres", "price": 600, "min_rep": 50, "name": "Combat Vest"},
		{"path": "res://resources/armor/marksman_gloves.tres", "price": 300, "min_rep": 25, "name": "Marksman Gloves"},
		{"path": "res://resources/armor/sprint_boots.tres", "price": 350, "min_rep": 35, "name": "Sprint Boots"},
		{"path": "res://resources/augments/damage_augment.tres", "price": 250, "min_rep": 75, "name": "Damage Augment"}
	]

	# Add items player has sufficient reputation for
	for item_data in base_items:
		if merchant_reputation >= item_data.min_rep:
			var item = null
			if ResourceLoader.exists(item_data.path):
				item = load(item_data.path)

			var adjusted_price = _get_buy_price(item_data.price)
			merchant_inventory.append({
				"item": item,
				"base_price": item_data.price,
				"buy_price": adjusted_price,
				"name": item_data.name,
				"rarity": 0 if item_data.min_rep < 25 else 1 if item_data.min_rep < 50 else 2 if item_data.min_rep < 75 else 3
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
			"result": "Enhanced Ammo Box",
			"craft_cost": 50
		},
		{
			"name": "Medkit",
			"result_icon": null,
			"materials": [
				{"item_name": "Health Pack", "count": 3}
			],
			"result": "Large Medkit",
			"craft_cost": 75
		},
		{
			"name": "Armor Patch",
			"result_icon": null,
			"materials": [
				{"item_name": "Scrap Metal", "count": 3},
				{"item_name": "Cloth", "count": 2}
			],
			"result": "Armor Patch Kit",
			"craft_cost": 100
		}
	]

func _get_buy_price(base_price: int) -> int:
	# Apply reputation discount
	var discount = 0.0
	for threshold in REP_DISCOUNT_THRESHOLDS:
		if merchant_reputation >= threshold:
			discount = REP_DISCOUNT_THRESHOLDS[threshold]

	return int(base_price * (1.0 - discount))

func _get_sell_price(base_price: int) -> int:
	# Merchants typically pay 50% of base price, up to 70% with max rep
	var base_ratio = 0.5
	var rep_bonus = (float(merchant_reputation) / max_reputation) * 0.2
	return int(base_price * (base_ratio + rep_bonus))

func _update_display():
	if merchant_rep_label:
		var rep_level = "Stranger"
		if merchant_reputation >= 75:
			rep_level = "Trusted"
		elif merchant_reputation >= 50:
			rep_level = "Friendly"
		elif merchant_reputation >= 25:
			rep_level = "Known"
		merchant_rep_label.text = "Rep: %s (%d%%)" % [rep_level, int(float(merchant_reputation) / max_reputation * 100)]

	if rep_progress:
		rep_progress.max_value = max_reputation
		rep_progress.value = merchant_reputation

	if currency_label:
		currency_label.text = "$%d" % player_currency

	_update_selling_display()
	_update_crafting_display()
	_refresh_stash_display()

func refresh_merchant_stock():
	_load_merchant_inventory()
	_update_display()

func _update_selling_display():
	if not selling_grid:
		return

	for i in range(selling_grid.get_child_count()):
		var slot = selling_grid.get_child(i)
		var vbox = slot.get_node_or_null("VBox")
		if not vbox:
			continue

		var icon_container = vbox.get_node_or_null("PanelContainer")
		var icon = icon_container.get_node_or_null("Icon") if icon_container else null
		var name_label = vbox.get_node_or_null("Name") as Label
		var price_label = vbox.get_node_or_null("Price") as Label

		if i < merchant_inventory.size():
			var item_data = merchant_inventory[i]
			if icon and item_data.item:
				icon.texture = item_data.item.icon if "icon" in item_data.item else null
			if name_label:
				name_label.text = item_data.get("name", "?")
			if price_label:
				price_label.text = "$%d" % item_data.get("buy_price", 0)

			# Update border color based on rarity
			var style = slot.get_theme_stylebox("panel") as StyleBoxFlat
			if style:
				style.border_color = _get_rarity_color(item_data.get("rarity", 0))

			# Highlight selected
			if i == selected_sell_index:
				style.set_border_width_all(3)
				style.border_color = Color.WHITE
		else:
			if icon:
				icon.texture = null
			if name_label:
				name_label.text = ""
			if price_label:
				price_label.text = ""

func _update_crafting_display():
	if not crafting_grid:
		return

	for i in range(crafting_grid.get_child_count()):
		var slot = crafting_grid.get_child(i)
		var vbox = slot.get_node_or_null("VBox")
		if not vbox:
			continue

		var icon_container = vbox.get_node_or_null("PanelContainer")
		var icon = icon_container.get_node_or_null("Icon") if icon_container else null
		var name_label = vbox.get_node_or_null("Name") as Label
		var price_label = vbox.get_node_or_null("Price") as Label

		if i < crafting_recipes.size():
			var recipe = crafting_recipes[i]
			if icon and recipe.has("result_icon"):
				icon.texture = recipe.result_icon
			if name_label:
				name_label.text = recipe.get("name", "?")
			if price_label:
				price_label.text = "$%d" % recipe.get("craft_cost", 0)

			# Highlight selected
			var style = slot.get_theme_stylebox("panel") as StyleBoxFlat
			if style and i == selected_craft_index:
				style.set_border_width_all(3)
				style.border_color = Color.CYAN
		else:
			if icon:
				icon.texture = null
			if name_label:
				name_label.text = ""
			if price_label:
				price_label.text = ""

func update_player_stash(items: Array):
	player_stash = items
	_refresh_stash_display()

func _refresh_stash_display():
	if not stash_grid:
		return

	for i in range(stash_grid.get_child_count()):
		var slot = stash_grid.get_child(i)
		var vbox = slot.get_node_or_null("VBox")
		if not vbox:
			continue

		var icon_container = vbox.get_node_or_null("PanelContainer")
		var icon = icon_container.get_node_or_null("Icon") if icon_container else null
		var name_label = vbox.get_node_or_null("Name") as Label
		var price_label = vbox.get_node_or_null("Price") as Label

		if i < player_stash.size() and player_stash[i]:
			var stash_item = player_stash[i]
			var item = stash_item.get("item") if stash_item is Dictionary else stash_item
			if icon and item and "icon" in item:
				icon.texture = item.icon
			if name_label:
				var item_name = item.item_name if item and "item_name" in item else str(stash_item)
				name_label.text = item_name
			if price_label:
				var base = item.value if item and "value" in item else 100
				price_label.text = "$%d" % _get_sell_price(base)

			# Highlight selected
			var style = slot.get_theme_stylebox("panel") as StyleBoxFlat
			if style and i == selected_stash_index:
				style.set_border_width_all(3)
				style.border_color = Color.GREEN
		else:
			if icon:
				icon.texture = null
			if name_label:
				name_label.text = ""
			if price_label:
				price_label.text = ""

func _get_rarity_color(rarity: int) -> Color:
	match rarity:
		0: return Color(0.5, 0.5, 0.5)
		1: return Color(0.2, 0.8, 0.2)
		2: return Color(0.2, 0.4, 1.0)
		3: return Color(0.6, 0.2, 0.8)
		4: return Color(1.0, 0.6, 0.0)
	return Color(0.3, 0.3, 0.3)

func _on_sell_slot_clicked(index: int):
	if index >= merchant_inventory.size():
		return
	selected_sell_index = index
	selected_stash_index = -1
	selected_craft_index = -1
	_update_display()

func _on_stash_slot_clicked(index: int):
	if index >= player_stash.size():
		return
	selected_stash_index = index
	selected_sell_index = -1
	selected_craft_index = -1
	_update_display()

func _on_craft_slot_clicked(index: int):
	if index >= crafting_recipes.size():
		return
	selected_craft_index = index
	selected_sell_index = -1
	selected_stash_index = -1
	_update_display()

func _on_buy_pressed():
	if selected_sell_index < 0 or selected_sell_index >= merchant_inventory.size():
		_show_message("Select Item", "Please select an item to buy.")
		return

	var item_data = merchant_inventory[selected_sell_index]
	var price = item_data.get("buy_price", 0)

	if player_currency < price:
		_show_message("Cannot Buy", "Insufficient funds!")
		return

	# Confirm purchase
	var dialog = ConfirmationDialog.new()
	dialog.dialog_text = "Buy %s for $%d?" % [item_data.get("name", "Item"), price]
	dialog.confirmed.connect(_confirm_purchase.bind(selected_sell_index, price))
	add_child(dialog)
	dialog.popup_centered()

func _confirm_purchase(index: int, price: int):
	var item_data = merchant_inventory[index]

	# Deduct currency
	player_currency -= price
	if has_node("/root/PointsSystem"):
		var ps = get_node("/root/PointsSystem")
		if ps.has_method("spend_points"):
			ps.spend_points(price, item_data.get("name", "Merchant Item"))

	# Add to player stash
	player_stash.append({"item": item_data.item, "count": 1})

	# Gain reputation
	_add_reputation(2)

	# Emit signal
	if item_data.item:
		item_purchased.emit(item_data.item, price)

	selected_sell_index = -1
	_update_display()
	_show_message("Purchased!", "Added to your inventory.")

func _on_sell_pressed():
	if selected_stash_index < 0 or selected_stash_index >= player_stash.size():
		_show_message("Select Item", "Please select an item to sell.")
		return

	var stash_item = player_stash[selected_stash_index]
	var item = stash_item.get("item") if stash_item is Dictionary else stash_item
	var base_price = item.value if item and "value" in item else 100
	var sell_price = _get_sell_price(base_price)
	var item_name = item.item_name if item and "item_name" in item else "Item"

	# Confirm sale
	var dialog = ConfirmationDialog.new()
	dialog.dialog_text = "Sell %s for $%d?" % [item_name, sell_price]
	dialog.confirmed.connect(_confirm_sale.bind(selected_stash_index, sell_price))
	add_child(dialog)
	dialog.popup_centered()

func _confirm_sale(index: int, sell_price: int):
	var stash_item = player_stash[index]
	var item = stash_item.get("item") if stash_item is Dictionary else stash_item

	# Add currency
	player_currency += sell_price
	if has_node("/root/PointsSystem"):
		var ps = get_node("/root/PointsSystem")
		if ps.has_method("add_points"):
			ps.add_points(sell_price, "Sold item")

	# Remove from stash
	player_stash.remove_at(index)

	# Gain reputation
	_add_reputation(1)

	# Emit signal
	if item:
		item_sold.emit(item, sell_price)

	selected_stash_index = -1
	_update_display()
	_show_message("Sold!", "You received $%d." % sell_price)

func _on_craft_pressed():
	if selected_craft_index < 0 or selected_craft_index >= crafting_recipes.size():
		_show_message("Select Recipe", "Please select a recipe to craft.")
		return

	var recipe = crafting_recipes[selected_craft_index]
	var craft_cost = recipe.get("craft_cost", 0)

	if player_currency < craft_cost:
		_show_message("Cannot Craft", "Insufficient funds!")
		return

	# Check materials
	if not _has_materials(recipe):
		_show_message("Cannot Craft", "Missing required materials!")
		return

	# Confirm crafting
	var dialog = ConfirmationDialog.new()
	dialog.dialog_text = "Craft %s for $%d?" % [recipe.get("name", "Item"), craft_cost]
	dialog.confirmed.connect(_confirm_craft.bind(selected_craft_index))
	add_child(dialog)
	dialog.popup_centered()

func _has_materials(recipe: Dictionary) -> bool:
	for craft_mat in recipe.get("materials", []):
		var material_name = craft_mat.get("item_name", "")
		var required_count = craft_mat.get("count", 1)
		var found_count = 0

		for stash_item in player_stash:
			if stash_item and stash_item.has("item"):
				var item = stash_item.item
				if item and "item_name" in item and item.item_name == material_name:
					found_count += stash_item.get("count", 1)

		if found_count < required_count:
			return false
	return true

func _confirm_craft(recipe_index: int):
	var recipe = crafting_recipes[recipe_index]
	var craft_cost = recipe.get("craft_cost", 0)

	# Deduct currency
	player_currency -= craft_cost
	if has_node("/root/PointsSystem"):
		var ps = get_node("/root/PointsSystem")
		if ps.has_method("spend_points"):
			ps.spend_points(craft_cost, "Crafting: " + recipe.get("name", ""))

	# Remove materials
	for craft_mat in recipe.get("materials", []):
		var material_name = craft_mat.get("item_name", "")
		var required_count = craft_mat.get("count", 1)
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

	# Add crafted item (would create proper resource in real implementation)
	player_stash.append({"item": null, "count": 1, "name": recipe.get("result", "Crafted Item")})

	# Gain reputation
	_add_reputation(3)

	craft_started.emit(recipe)
	selected_craft_index = -1
	_update_display()
	_show_message("Crafted!", "Created: %s" % recipe.get("result", "Item"))

func _add_reputation(amount: int):
	merchant_reputation = mini(merchant_reputation + amount, max_reputation)

	# Save reputation
	if has_node("/root/PlayerPersistence"):
		var persistence = get_node("/root/PlayerPersistence")
		if persistence.player_data:
			persistence.player_data["merchant_reputation"] = merchant_reputation

func _show_item_tooltip(index: int, is_merchant: bool):
	if not item_tooltip:
		return

	var item_data: Dictionary = {}
	if is_merchant and index < merchant_inventory.size():
		item_data = merchant_inventory[index]
	elif not is_merchant and index < player_stash.size():
		var stash_item = player_stash[index]
		if stash_item is Dictionary:
			item_data = stash_item
		else:
			item_data = {"name": str(stash_item)}

	if item_data.is_empty():
		return

	# Update tooltip content (would be expanded in full implementation)
	item_tooltip.visible = true

func _hide_item_tooltip():
	if item_tooltip:
		item_tooltip.visible = false

func _show_message(title: String, message: String):
	var dialog = AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered()

func _on_back_pressed():
	close()
	panel_closed.emit()

func purchase_item(index: int) -> bool:
	if index >= merchant_inventory.size():
		return false

	var item_data = merchant_inventory[index]
	if player_currency < item_data.get("buy_price", 0):
		return false

	player_currency -= item_data.get("buy_price", 0)
	if item_data.item:
		item_purchased.emit(item_data.item, item_data.get("buy_price", 0))
	_update_display()
	return true

func sell_item(item) -> int:  # item: ItemDataExtended
	if not item:
		return 0
	var sell_price = _get_sell_price(item.value if "value" in item else 100)
	player_currency += sell_price
	item_sold.emit(item, sell_price)
	_update_display()
	return sell_price

func craft_item(recipe_index: int) -> bool:
	if recipe_index >= crafting_recipes.size():
		return false

	selected_craft_index = recipe_index
	_on_craft_pressed()
	return true

func open():
	visible = true
	_load_player_data()
	refresh_merchant_stock()
	_refresh_stash_display()

func close():
	visible = false
	selected_sell_index = -1
	selected_stash_index = -1
	selected_craft_index = -1
