extends Control
class_name GridMerchantUI

# Grid-based merchant/market UI for buying and selling items
# Shows items with their sizes and supports grid preview for inventory placement

@export var grid_inventory: GridInventorySystem
@export var sigil_shop: SigilShop

# UI panels
var shop_panel: Panel
var preview_panel: Panel
var cart_panel: Panel
var tooltip_panel: Panel

# Grid configuration
const CELL_SIZE: int = 48
const PADDING: int = 12
const RARITY_COLORS: Dictionary = {
	0: Color(0.6, 0.6, 0.6),
	1: Color(0.2, 0.8, 0.2),
	2: Color(0.2, 0.4, 1.0),
	3: Color(0.6, 0.2, 0.8),
	4: Color(1.0, 0.6, 0.0),
	5: Color(1.0, 0.2, 0.2),
}

# Categories
enum Category { WEAPONS, ARMOR, CONSUMABLES, MATERIALS, AUGMENTS, SELL }
var current_category: Category = Category.WEAPONS
var category_buttons: Dictionary = {}

# State
var is_open: bool = false
var cart_items: Array[Dictionary] = []
var cart_total: int = 0
var selected_item: Dictionary = {}

signal merchant_opened
signal merchant_closed
signal purchase_made(item: Resource, price: int)
signal item_sold(item: Resource, price: int)

func _ready():
	visible = false
	_create_ui()

	await get_tree().create_timer(0.1).timeout
	_find_systems()

func _find_systems():
	if not grid_inventory:
		var player = get_tree().get_first_node_in_group("player")
		if player and "grid_inventory" in player:
			grid_inventory = player.grid_inventory

	if not sigil_shop:
		sigil_shop = get_tree().get_first_node_in_group("sigil_shop")

func _create_ui():
	# Background
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# Main container
	var main = HBoxContainer.new()
	main.name = "MainContainer"
	main.set_anchors_preset(Control.PRESET_CENTER)
	main.add_theme_constant_override("separation", 20)
	add_child(main)

	# Shop panel (left - shows available items)
	shop_panel = _create_shop_panel()
	main.add_child(shop_panel)

	# Preview panel (center - shows selected item details)
	preview_panel = _create_preview_panel()
	main.add_child(preview_panel)

	# Cart/inventory panel (right)
	cart_panel = _create_cart_panel()
	main.add_child(cart_panel)

	# Tooltip
	tooltip_panel = _create_tooltip()
	add_child(tooltip_panel)

func _create_shop_panel() -> Panel:
	var panel = Panel.new()
	panel.name = "ShopPanel"
	panel.custom_minimum_size = Vector2(500, 550)

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	style.border_color = Color(0.5, 0.4, 0.2)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	vbox.offset_left = PADDING
	vbox.offset_top = PADDING
	vbox.offset_right = -PADDING
	vbox.offset_bottom = -PADDING
	panel.add_child(vbox)

	# Header
	var header = HBoxContainer.new()
	vbox.add_child(header)

	var title = Label.new()
	title.text = "MERCHANT"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	header.add_child(title)

	header.add_spacer(false)

	var currency_label = Label.new()
	currency_label.name = "CurrencyLabel"
	currency_label.text = "Sigils: 0"
	currency_label.add_theme_font_size_override("font_size", 16)
	currency_label.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
	header.add_child(currency_label)

	# Category tabs
	var tabs = HBoxContainer.new()
	tabs.name = "CategoryTabs"
	tabs.add_theme_constant_override("separation", 5)
	vbox.add_child(tabs)

	var categories = [
		{"id": Category.WEAPONS, "name": "Weapons", "icon": "weapon"},
		{"id": Category.ARMOR, "name": "Armor", "icon": "armor"},
		{"id": Category.CONSUMABLES, "name": "Consumables", "icon": "potion"},
		{"id": Category.MATERIALS, "name": "Materials", "icon": "material"},
		{"id": Category.AUGMENTS, "name": "Augments", "icon": "augment"},
		{"id": Category.SELL, "name": "Sell", "icon": "coin"},
	]

	for cat in categories:
		var btn = Button.new()
		btn.name = cat.name + "Tab"
		btn.text = cat.name
		btn.toggle_mode = true
		btn.button_pressed = cat.id == current_category
		btn.custom_minimum_size = Vector2(70, 30)
		btn.pressed.connect(_on_category_selected.bind(cat.id))
		tabs.add_child(btn)
		category_buttons[cat.id] = btn

	vbox.add_child(HSeparator.new())

	# Items scroll container
	var scroll = ScrollContainer.new()
	scroll.name = "ItemsScroll"
	scroll.custom_minimum_size = Vector2(0, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var items_grid = GridContainer.new()
	items_grid.name = "ItemsGrid"
	items_grid.columns = 4
	items_grid.add_theme_constant_override("h_separation", 8)
	items_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(items_grid)

	return panel

func _create_preview_panel() -> Panel:
	var panel = Panel.new()
	panel.name = "PreviewPanel"
	panel.custom_minimum_size = Vector2(280, 550)

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.98)
	style.border_color = Color(0.4, 0.4, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.name = "PreviewContent"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	vbox.offset_left = PADDING
	vbox.offset_top = PADDING
	vbox.offset_right = -PADDING
	vbox.offset_bottom = -PADDING
	panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "ITEM DETAILS"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Item icon display
	var icon_container = CenterContainer.new()
	icon_container.custom_minimum_size = Vector2(0, 120)
	vbox.add_child(icon_container)

	var icon_bg = Panel.new()
	icon_bg.name = "IconBackground"
	icon_bg.custom_minimum_size = Vector2(100, 100)
	var icon_style = StyleBoxFlat.new()
	icon_style.bg_color = Color(0.15, 0.15, 0.18)
	icon_style.border_color = Color(0.3, 0.3, 0.4)
	icon_style.set_border_width_all(2)
	icon_style.set_corner_radius_all(8)
	icon_bg.add_theme_stylebox_override("panel", icon_style)
	icon_container.add_child(icon_bg)

	var item_icon = TextureRect.new()
	item_icon.name = "ItemIcon"
	item_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	item_icon.offset_left = 10
	item_icon.offset_top = 10
	item_icon.offset_right = -10
	item_icon.offset_bottom = -10
	icon_bg.add_child(item_icon)

	# Item name
	var name_label = RichTextLabel.new()
	name_label.name = "ItemName"
	name_label.bbcode_enabled = true
	name_label.fit_content = true
	name_label.scroll_active = false
	name_label.text = "[center][b]Select an item[/b][/center]"
	vbox.add_child(name_label)

	# Item type/rarity
	var type_label = Label.new()
	type_label.name = "ItemType"
	type_label.text = ""
	type_label.add_theme_font_size_override("font_size", 12)
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(type_label)

	# Size indicator
	var size_label = Label.new()
	size_label.name = "ItemSize"
	size_label.text = "Size: -"
	size_label.add_theme_font_size_override("font_size", 11)
	size_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(size_label)

	vbox.add_child(HSeparator.new())

	# Stats
	var stats_label = RichTextLabel.new()
	stats_label.name = "ItemStats"
	stats_label.bbcode_enabled = true
	stats_label.fit_content = true
	stats_label.scroll_active = false
	stats_label.custom_minimum_size = Vector2(0, 100)
	vbox.add_child(stats_label)

	# Description
	var desc_label = Label.new()
	desc_label.name = "ItemDesc"
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(desc_label)

	vbox.add_spacer(false)

	# Price display
	var price_container = HBoxContainer.new()
	price_container.name = "PriceContainer"
	vbox.add_child(price_container)

	var price_label = Label.new()
	price_label.text = "Price:"
	price_label.add_theme_font_size_override("font_size", 16)
	price_container.add_child(price_label)

	price_container.add_spacer(false)

	var price_value = Label.new()
	price_value.name = "PriceValue"
	price_value.text = "0"
	price_value.add_theme_font_size_override("font_size", 18)
	price_value.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	price_container.add_child(price_value)

	var sigil_icon = Label.new()
	sigil_icon.text = " Sigils"
	sigil_icon.add_theme_font_size_override("font_size", 14)
	sigil_icon.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
	price_container.add_child(sigil_icon)

	# Buy button
	var buy_btn = Button.new()
	buy_btn.name = "BuyButton"
	buy_btn.text = "BUY"
	buy_btn.custom_minimum_size = Vector2(0, 40)
	buy_btn.pressed.connect(_on_buy_pressed)
	vbox.add_child(buy_btn)

	# Can't afford indicator
	var afford_label = Label.new()
	afford_label.name = "AffordLabel"
	afford_label.text = ""
	afford_label.add_theme_font_size_override("font_size", 11)
	afford_label.add_theme_color_override("font_color", Color.RED)
	afford_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(afford_label)

	return panel

func _create_cart_panel() -> Panel:
	var panel = Panel.new()
	panel.name = "CartPanel"
	panel.custom_minimum_size = Vector2(250, 550)

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.08, 0.98)
	style.border_color = Color(0.3, 0.5, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	vbox.offset_left = PADDING
	vbox.offset_top = PADDING
	vbox.offset_right = -PADDING
	vbox.offset_bottom = -PADDING
	panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "YOUR INVENTORY"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Weight/space info
	var info_label = Label.new()
	info_label.name = "InventoryInfo"
	info_label.text = "Weight: 0/50 | Space available"
	info_label.add_theme_font_size_override("font_size", 11)
	info_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.5))
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info_label)

	vbox.add_child(HSeparator.new())

	# Mini inventory grid preview
	var grid_preview = Control.new()
	grid_preview.name = "InventoryPreview"
	grid_preview.custom_minimum_size = Vector2(200, 120)
	vbox.add_child(grid_preview)

	_create_mini_grid(grid_preview)

	vbox.add_child(HSeparator.new())

	# Sellable items (when in sell mode)
	var sell_scroll = ScrollContainer.new()
	sell_scroll.name = "SellScroll"
	sell_scroll.custom_minimum_size = Vector2(0, 250)
	sell_scroll.visible = false
	vbox.add_child(sell_scroll)

	var sell_list = VBoxContainer.new()
	sell_list.name = "SellList"
	sell_list.add_theme_constant_override("separation", 4)
	sell_scroll.add_child(sell_list)

	# Cart summary
	var cart_summary = VBoxContainer.new()
	cart_summary.name = "CartSummary"
	vbox.add_child(cart_summary)

	var cart_title = Label.new()
	cart_title.text = "Recent Purchases"
	cart_title.add_theme_font_size_override("font_size", 12)
	cart_summary.add_child(cart_title)

	var cart_scroll = ScrollContainer.new()
	cart_scroll.custom_minimum_size = Vector2(0, 80)
	cart_summary.add_child(cart_scroll)

	var cart_list = VBoxContainer.new()
	cart_list.name = "CartList"
	cart_scroll.add_child(cart_list)

	vbox.add_spacer(false)

	# Hints
	var hints = Label.new()
	hints.text = "[LMB] Select | [RMB] Quick Buy"
	hints.add_theme_font_size_override("font_size", 10)
	hints.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hints)

	return panel

func _create_mini_grid(container: Control):
	var cell_size = 20
	var width = 10
	var height = 6

	for y in range(height):
		for x in range(width):
			var cell = ColorRect.new()
			cell.name = "MiniCell_%d_%d" % [x, y]
			cell.custom_minimum_size = Vector2(cell_size, cell_size)
			cell.size = Vector2(cell_size, cell_size)
			cell.position = Vector2(x * cell_size, y * cell_size)
			cell.color = Color(0.15, 0.18, 0.15, 0.8)
			container.add_child(cell)

func _create_tooltip() -> Panel:
	var panel = Panel.new()
	panel.name = "Tooltip"
	panel.custom_minimum_size = Vector2(200, 120)
	panel.visible = false
	panel.z_index = 100

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.98)
	style.border_color = Color(0.4, 0.4, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.name = "Content"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 8
	vbox.offset_top = 8
	vbox.offset_right = -8
	vbox.offset_bottom = -8
	panel.add_child(vbox)

	var name_label = Label.new()
	name_label.name = "Name"
	name_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(name_label)

	var price_label = Label.new()
	price_label.name = "Price"
	price_label.add_theme_font_size_override("font_size", 11)
	price_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(price_label)

	return panel

# ============================================
# CATEGORY HANDLING
# ============================================

func _on_category_selected(category: Category):
	current_category = category

	# Update button states
	for cat_id in category_buttons:
		category_buttons[cat_id].button_pressed = cat_id == current_category

	# Toggle sell mode UI
	_toggle_sell_mode(category == Category.SELL)

	_refresh_items()

func _toggle_sell_mode(sell_mode: bool):
	var sell_scroll = cart_panel.get_node_or_null("SellScroll")
	var cart_summary = cart_panel.get_node_or_null("CartSummary")

	if not sell_scroll or not cart_summary:
		for child in cart_panel.get_children():
			if child is VBoxContainer:
				sell_scroll = child.get_node_or_null("SellScroll")
				cart_summary = child.get_node_or_null("CartSummary")
				break

	if sell_scroll:
		sell_scroll.visible = sell_mode
	if cart_summary:
		cart_summary.visible = not sell_mode

	if sell_mode:
		_populate_sell_list()

	# Update preview panel for selling
	var buy_btn = _get_node_recursive(preview_panel, "BuyButton")
	if buy_btn:
		buy_btn.text = "SELL" if sell_mode else "BUY"

func _populate_sell_list():
	if not grid_inventory:
		return

	var sell_list = _get_node_recursive(cart_panel, "SellList")
	if not sell_list:
		return

	# Clear existing
	for child in sell_list.get_children():
		child.queue_free()

	# Add sellable items
	var items = grid_inventory.get_all_items(false)
	for entry in items:
		var item = entry.item
		if not item:
			continue

		var sell_entry = _create_sell_entry(entry)
		sell_list.add_child(sell_entry)

func _create_sell_entry(entry: Dictionary) -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var item = entry.item
	var rarity = item.rarity if "rarity" in item else 0
	var rarity_color = RARITY_COLORS.get(rarity, RARITY_COLORS[0])

	# Item name
	var name_label = Label.new()
	var item_name = item.item_name if "item_name" in item else "Unknown"
	name_label.text = item_name
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", rarity_color)
	name_label.custom_minimum_size = Vector2(100, 0)
	hbox.add_child(name_label)

	hbox.add_spacer(false)

	# Sell price
	var price = _get_sell_price(item)
	var price_label = Label.new()
	price_label.text = str(price)
	price_label.add_theme_font_size_override("font_size", 11)
	price_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	hbox.add_child(price_label)

	# Sell button
	var sell_btn = Button.new()
	sell_btn.text = "Sell"
	sell_btn.custom_minimum_size = Vector2(40, 24)
	sell_btn.pressed.connect(_on_sell_item.bind(entry))
	hbox.add_child(sell_btn)

	return hbox

func _get_sell_price(item: Resource) -> int:
	var base_price = item.price if "price" in item else 10
	var rarity = item.rarity if "rarity" in item else 0
	# Sell for 50% of buy price, modified by rarity
	return int(base_price * 0.5 * (1.0 + rarity * 0.1))

func _on_sell_item(entry: Dictionary):
	if not grid_inventory or not sigil_shop:
		return

	var item = entry.item
	var price = _get_sell_price(item)

	# Remove from inventory
	grid_inventory.remove_item_at(entry.position, false)

	# Add currency
	sigil_shop.add_sigils(price, "Sold " + (item.item_name if "item_name" in item else "item"))

	item_sold.emit(item, price)

	# Refresh
	_populate_sell_list()
	_refresh_currency()
	_refresh_mini_grid()

# ============================================
# ITEMS DISPLAY
# ============================================

func _refresh_items():
	var items_grid = _get_node_recursive(shop_panel, "ItemsGrid")
	if not items_grid:
		return

	# Clear existing items
	for child in items_grid.get_children():
		child.queue_free()

	# Get items for current category
	var items = _get_items_for_category(current_category)

	for item_data in items:
		var item_card = _create_item_card(item_data)
		items_grid.add_child(item_card)

func _get_items_for_category(category: Category) -> Array:
	if not sigil_shop:
		return []

	var all_items = []

	# Get items from sigil shop
	if sigil_shop.has_method("get_shop_items"):
		all_items = sigil_shop.get_shop_items()
	elif "shop_items" in sigil_shop:
		for key in sigil_shop.shop_items:
			all_items.append(sigil_shop.shop_items[key])

	# Filter by category
	var filtered = []
	for item_data in all_items:
		var item = item_data.item_data if "item_data" in item_data else item_data
		if not item:
			continue

		var item_type = item.item_type if "item_type" in item else -1

		match category:
			Category.WEAPONS:
				if item_type == ItemDataExtended.ItemType.WEAPON:
					filtered.append(item_data)
			Category.ARMOR:
				if item_type in [
					ItemDataExtended.ItemType.HELMET,
					ItemDataExtended.ItemType.CHEST_ARMOR,
					ItemDataExtended.ItemType.GLOVES,
					ItemDataExtended.ItemType.BOOTS
				]:
					filtered.append(item_data)
			Category.CONSUMABLES:
				if item_type == ItemDataExtended.ItemType.CONSUMABLE:
					filtered.append(item_data)
			Category.MATERIALS:
				if item_type == ItemDataExtended.ItemType.MATERIAL:
					filtered.append(item_data)
			Category.AUGMENTS:
				if item_type == ItemDataExtended.ItemType.AUGMENT:
					filtered.append(item_data)

	return filtered

func _create_item_card(item_data: Dictionary) -> Panel:
	var card = Panel.new()
	card.custom_minimum_size = Vector2(100, 120)

	var item = item_data.item_data if "item_data" in item_data else item_data
	var price = item_data.price if "price" in item_data else (item.price if item and "price" in item else 100)
	var rarity = item.rarity if item and "rarity" in item else 0
	var rarity_color = RARITY_COLORS.get(rarity, RARITY_COLORS[0])

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.95)
	style.border_color = rarity_color.darkened(0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	vbox.offset_left = 4
	vbox.offset_top = 4
	vbox.offset_right = -4
	vbox.offset_bottom = -4
	card.add_child(vbox)

	# Icon
	var icon_container = CenterContainer.new()
	icon_container.custom_minimum_size = Vector2(0, 60)
	vbox.add_child(icon_container)

	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(50, 50)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if item and "icon" in item:
		icon.texture = item.icon
	icon_container.add_child(icon)

	# Name (truncated)
	var name_label = Label.new()
	var item_name = item.item_name if item and "item_name" in item else "Unknown"
	name_label.text = item_name.substr(0, 12) + ("..." if item_name.length() > 12 else "")
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", rarity_color)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	# Size indicator
	var size = GridInventorySystem.get_item_size(item) if item else Vector2i(1, 1)
	var size_label = Label.new()
	size_label.text = "%dx%d" % [size.x, size.y]
	size_label.add_theme_font_size_override("font_size", 9)
	size_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(size_label)

	# Price
	var price_label = Label.new()
	price_label.text = str(price) + " S"
	price_label.add_theme_font_size_override("font_size", 11)
	price_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(price_label)

	# Rarity bar
	var bar = ColorRect.new()
	bar.color = rarity_color
	bar.custom_minimum_size = Vector2(0, 3)
	vbox.add_child(bar)

	# Click handlers
	card.set_meta("item_data", item_data)
	card.gui_input.connect(_on_item_card_input.bind(card, item_data))
	card.mouse_entered.connect(_on_item_card_hover.bind(card, item_data))
	card.mouse_exited.connect(_on_item_card_exit.bind(card))

	return card

func _on_item_card_input(event: InputEvent, card: Panel, item_data: Dictionary):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_select_item(item_data)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Quick buy
			_select_item(item_data)
			_on_buy_pressed()

func _on_item_card_hover(card: Panel, item_data: Dictionary):
	# Highlight
	var style = card.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.bg_color = Color(0.18, 0.18, 0.22, 0.98)
	card.add_theme_stylebox_override("panel", style)

func _on_item_card_exit(card: Panel):
	var item_data = card.get_meta("item_data")
	var item = item_data.item_data if "item_data" in item_data else item_data
	var rarity = item.rarity if item and "rarity" in item else 0
	var rarity_color = RARITY_COLORS.get(rarity, RARITY_COLORS[0])

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.95)
	style.border_color = rarity_color.darkened(0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", style)

# ============================================
# ITEM SELECTION & PURCHASE
# ============================================

func _select_item(item_data: Dictionary):
	selected_item = item_data
	_update_preview(item_data)

func _update_preview(item_data: Dictionary):
	var item = item_data.item_data if "item_data" in item_data else item_data
	var price = item_data.price if "price" in item_data else (item.price if item and "price" in item else 100)

	var name_label = _get_node_recursive(preview_panel, "ItemName") as RichTextLabel
	var type_label = _get_node_recursive(preview_panel, "ItemType") as Label
	var size_label = _get_node_recursive(preview_panel, "ItemSize") as Label
	var stats_label = _get_node_recursive(preview_panel, "ItemStats") as RichTextLabel
	var desc_label = _get_node_recursive(preview_panel, "ItemDesc") as Label
	var price_value = _get_node_recursive(preview_panel, "PriceValue") as Label
	var afford_label = _get_node_recursive(preview_panel, "AffordLabel") as Label
	var icon = _get_node_recursive(preview_panel, "ItemIcon") as TextureRect
	var icon_bg = _get_node_recursive(preview_panel, "IconBackground") as Panel

	if not item:
		return

	var rarity = item.rarity if "rarity" in item else 0
	var rarity_color = RARITY_COLORS.get(rarity, RARITY_COLORS[0])
	var item_name = item.item_name if "item_name" in item else "Unknown"

	if name_label:
		name_label.text = "[center][b][color=#%s]%s[/color][/b][/center]" % [rarity_color.to_html(), item_name]

	if type_label:
		var rarity_names = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]
		type_label.text = rarity_names[min(rarity, 5)]
		type_label.add_theme_color_override("font_color", rarity_color)

	if size_label:
		var size = GridInventorySystem.get_item_size(item)
		size_label.text = "Size: %dx%d" % [size.x, size.y]

	if stats_label:
		var text = ""
		if "damage" in item and item.damage > 0:
			text += "[color=red]Damage: %.0f[/color]\n" % item.damage
		if "fire_rate" in item and item.fire_rate > 0:
			text += "Fire Rate: %.2f/s\n" % (1.0 / max(item.fire_rate, 0.01))
		if "magazine_size" in item and item.magazine_size > 0:
			text += "Magazine: %d\n" % item.magazine_size
		if "armor_value" in item and item.armor_value > 0:
			text += "[color=cyan]Armor: %.0f[/color]\n" % item.armor_value
		if "health_bonus" in item and item.health_bonus > 0:
			text += "[color=lime]+%.0f Health[/color]\n" % item.health_bonus
		stats_label.text = text

	if desc_label:
		desc_label.text = item.description if "description" in item else ""

	if price_value:
		price_value.text = str(price)

	if icon and "icon" in item:
		icon.texture = item.icon

	if icon_bg:
		var style = icon_bg.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		style.border_color = rarity_color
		icon_bg.add_theme_stylebox_override("panel", style)

	# Check affordability
	var can_afford = true
	if sigil_shop and "sigils" in sigil_shop:
		can_afford = sigil_shop.sigils >= price

	if afford_label:
		afford_label.text = "" if can_afford else "Not enough Sigils!"
		afford_label.visible = not can_afford

	# Check inventory space
	var has_space = true
	if grid_inventory:
		has_space = grid_inventory.has_space_for(item)

	if afford_label and not has_space:
		afford_label.text = "No inventory space!"
		afford_label.visible = true

func _on_buy_pressed():
	if selected_item.is_empty():
		return

	var item = selected_item.item_data if "item_data" in selected_item else selected_item
	var price = selected_item.price if "price" in selected_item else (item.price if item and "price" in item else 100)

	if current_category == Category.SELL:
		# Handled by individual sell buttons
		return

	if not sigil_shop or not grid_inventory:
		return

	# Check affordability
	var sigils = sigil_shop.sigils if "sigils" in sigil_shop else 0
	if sigils < price:
		_show_message("Not enough Sigils!")
		return

	# Check inventory space
	if not grid_inventory.has_space_for(item):
		_show_message("No inventory space!")
		return

	# Make purchase
	if sigil_shop.has_method("spend_sigils"):
		sigil_shop.spend_sigils(price)
	else:
		sigil_shop.sigils -= price

	grid_inventory.add_item(item, 1, false)

	# Add to cart history
	_add_to_cart(item, price)

	purchase_made.emit(item, price)

	# Refresh displays
	_refresh_currency()
	_refresh_mini_grid()
	_update_preview(selected_item)

func _add_to_cart(item: Resource, price: int):
	cart_items.append({"item": item, "price": price})
	cart_total += price

	# Update cart list
	var cart_list = _get_node_recursive(cart_panel, "CartList")
	if cart_list:
		var entry = HBoxContainer.new()

		var name_label = Label.new()
		var item_name = item.item_name if "item_name" in item else "Item"
		name_label.text = item_name
		name_label.add_theme_font_size_override("font_size", 10)
		name_label.custom_minimum_size = Vector2(120, 0)
		entry.add_child(name_label)

		entry.add_spacer(false)

		var price_label = Label.new()
		price_label.text = "-" + str(price)
		price_label.add_theme_font_size_override("font_size", 10)
		price_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
		entry.add_child(price_label)

		cart_list.add_child(entry)

		# Keep only last 5 entries
		while cart_list.get_child_count() > 5:
			cart_list.get_child(0).queue_free()

func _show_message(text: String):
	var afford_label = _get_node_recursive(preview_panel, "AffordLabel") as Label
	if afford_label:
		afford_label.text = text
		afford_label.visible = true

# ============================================
# REFRESH
# ============================================

func _refresh_currency():
	var currency_label = _get_node_recursive(shop_panel, "CurrencyLabel") as Label
	if currency_label and sigil_shop:
		var sigils = sigil_shop.sigils if "sigils" in sigil_shop else 0
		currency_label.text = "Sigils: " + str(sigils)

func _refresh_mini_grid():
	if not grid_inventory:
		return

	var preview = _get_node_recursive(cart_panel, "InventoryPreview")
	if not preview:
		return

	# Reset all cells
	for child in preview.get_children():
		if child is ColorRect:
			child.color = Color(0.15, 0.18, 0.15, 0.8)

	# Mark occupied cells
	var items = grid_inventory.get_all_items(false)
	for entry in items:
		var pos = entry.position as Vector2i
		var item = entry.item
		var size = GridInventorySystem.get_item_size(item)
		if entry.rotated:
			size = Vector2i(size.y, size.x)

		var rarity = item.rarity if "rarity" in item else 0
		var color = RARITY_COLORS.get(rarity, RARITY_COLORS[0]).darkened(0.3)

		for dy in range(size.y):
			for dx in range(size.x):
				var cell = preview.get_node_or_null("MiniCell_%d_%d" % [pos.x + dx, pos.y + dy])
				if cell:
					cell.color = color

	# Update info label
	var info_label = _get_node_recursive(cart_panel, "InventoryInfo") as Label
	if info_label:
		var weight = grid_inventory.get_weight_info()
		info_label.text = "Weight: %.0f/%.0f" % [weight.current, weight.max]

# ============================================
# UTILITIES
# ============================================

func _get_node_recursive(parent: Node, node_name: String) -> Node:
	var node = parent.get_node_or_null(node_name)
	if node:
		return node

	for child in parent.get_children():
		node = _get_node_recursive(child, node_name)
		if node:
			return node

	return null

# ============================================
# OPEN/CLOSE
# ============================================

func _input(event):
	if not is_open:
		return

	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func open():
	is_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	merchant_opened.emit()

	_find_systems()
	_refresh_currency()
	_refresh_items()
	_refresh_mini_grid()

	# Animation
	modulate.a = 0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.2)

func close():
	is_open = false

	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	await tween.finished

	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	merchant_closed.emit()
