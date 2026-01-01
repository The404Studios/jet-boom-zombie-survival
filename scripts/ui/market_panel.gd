extends Control
class_name MarketPanel

signal item_listed(item, price: int)  # item: ItemDataExtended
signal item_purchased(listing_id: int)
signal trade_requested(player_id: int)
signal panel_closed

# Filter options
@onready var category_filter: OptionButton = get_node_or_null("FilterBar/CategoryFilter")
@onready var rarity_filter: OptionButton = get_node_or_null("FilterBar/RarityFilter")
@onready var type_filter: OptionButton = get_node_or_null("FilterBar/TypeFilter")
@onready var price_min: SpinBox = get_node_or_null("FilterBar/PriceMin")
@onready var price_max: SpinBox = get_node_or_null("FilterBar/PriceMax")
@onready var search_input: LineEdit = get_node_or_null("FilterBar/SearchInput")
@onready var search_button: Button = get_node_or_null("FilterBar/SearchButton")
@onready var back_button: Button = get_node_or_null("FilterBar/BackButton")
@onready var reset_button: Button = get_node_or_null("FilterBar/ResetButton")

# Market grid
@onready var market_grid: GridContainer = get_node_or_null("MarketContainer/ScrollContainer/MarketGrid")

# Player info
@onready var player_currency_label: Label = get_node_or_null("InfoBar/CurrencyLabel")
@onready var listing_count_label: Label = get_node_or_null("InfoBar/ListingCountLabel")

# Listing data
var market_listings: Array = []
var filtered_listings: Array = []
var player_currency: int = 0

# Filter values
var current_filters: Dictionary = {
	"category": "All",
	"rarity": "All",
	"type": "All",
	"price_min": 0,
	"price_max": 999999,
	"search": ""
}

# Selected item for purchase
var selected_listing: Dictionary = {}

# Backend integration
var backend: Node = null

func _ready():
	backend = get_node_or_null("/root/Backend")
	_setup_filters()
	_setup_market_grid()
	_connect_signals()
	_load_player_currency()

func _setup_filters():
	# Category filter
	if category_filter:
		category_filter.clear()
		category_filter.add_item("All")
		category_filter.add_item("Weapons")
		category_filter.add_item("Armor")
		category_filter.add_item("Consumables")
		category_filter.add_item("Materials")
		category_filter.add_item("Augments")

	# Rarity filter
	if rarity_filter:
		rarity_filter.clear()
		rarity_filter.add_item("All")
		rarity_filter.add_item("Common")
		rarity_filter.add_item("Uncommon")
		rarity_filter.add_item("Rare")
		rarity_filter.add_item("Epic")
		rarity_filter.add_item("Legendary")
		rarity_filter.add_item("Mythic")

	# Type filter (weapon types)
	if type_filter:
		type_filter.clear()
		type_filter.add_item("All")
		type_filter.add_item("Pistol")
		type_filter.add_item("Rifle")
		type_filter.add_item("Shotgun")
		type_filter.add_item("SMG")
		type_filter.add_item("Sniper")
		type_filter.add_item("Heavy")
		type_filter.add_item("Melee")

	# Price range
	if price_min:
		price_min.min_value = 0
		price_min.max_value = 999999
		price_min.value = 0
	if price_max:
		price_max.min_value = 0
		price_max.max_value = 999999
		price_max.value = 999999

func _setup_market_grid():
	if not market_grid:
		return

	market_grid.columns = 8

	# Create grid slots (8x6 = 48 slots)
	for i in range(48):
		var slot = _create_market_slot(i)
		market_grid.add_child(slot)

func _create_market_slot(index: int) -> Panel:
	var slot = Panel.new()
	slot.name = "MarketSlot_%d" % index
	slot.custom_minimum_size = Vector2(80, 100)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.95)
	style.border_color = Color(0.2, 0.2, 0.25)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("panel", style)

	# Main container
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 2)
	slot.add_child(vbox)

	# Icon container
	var icon_container = PanelContainer.new()
	icon_container.custom_minimum_size = Vector2(70, 60)
	vbox.add_child(icon_container)

	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(icon)

	# Price label
	var price_label = Label.new()
	price_label.name = "Price"
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.add_theme_font_size_override("font_size", 10)
	price_label.add_theme_color_override("font_color", Color.GOLD)
	vbox.add_child(price_label)

	# Seller label
	var seller_label = Label.new()
	seller_label.name = "Seller"
	seller_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seller_label.add_theme_font_size_override("font_size", 8)
	seller_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(seller_label)

	# Button overlay for interaction
	var button = Button.new()
	button.name = "Button"
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.flat = true
	button.pressed.connect(_on_market_slot_clicked.bind(index))
	button.mouse_entered.connect(_on_slot_hover.bind(slot, true))
	button.mouse_exited.connect(_on_slot_hover.bind(slot, false))
	slot.add_child(button)

	return slot

func _on_slot_hover(slot: Panel, hovering: bool):
	var style = slot.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		if hovering:
			style.border_color = Color(0.4, 0.6, 0.8)
			style.set_border_width_all(2)
		else:
			style.border_color = Color(0.2, 0.2, 0.25)
			style.set_border_width_all(1)

func _connect_signals():
	if search_button:
		search_button.pressed.connect(_on_search_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	if reset_button:
		reset_button.pressed.connect(_on_reset_pressed)
	if search_input:
		search_input.text_submitted.connect(func(_text): _on_search_pressed())
	if category_filter:
		category_filter.item_selected.connect(func(_idx): _on_filter_changed())
	if rarity_filter:
		rarity_filter.item_selected.connect(func(_idx): _on_filter_changed())
	if type_filter:
		type_filter.item_selected.connect(func(_idx): _on_filter_changed())

func _load_player_currency():
	# Get player currency from backend first
	if backend and backend.is_authenticated:
		var profile = backend.current_player
		if profile:
			player_currency = profile.get("currency", 0)
			_update_currency_display()
			return

	# Fallback to local systems
	if has_node("/root/PointsSystem"):
		var ps = get_node("/root/PointsSystem")
		if ps.has_method("get_points"):
			player_currency = ps.get_points()
	elif has_node("/root/AccountSystem"):
		var acc = get_node("/root/AccountSystem")
		if "currency" in acc:
			player_currency = acc.currency

	_update_currency_display()

func _update_currency_display():
	if player_currency_label:
		player_currency_label.text = "Currency: $%d" % player_currency
	if listing_count_label:
		listing_count_label.text = "Listings: %d" % filtered_listings.size()

func _load_market_listings():
	market_listings = []

	# Fetch from backend shop API
	if backend and backend.is_authenticated:
		backend.get_shop_items(func(response):
			if response.success and response.has("items"):
				_populate_from_backend(response.items)
			else:
				_load_sample_listings()
		)
	else:
		_load_sample_listings()

func _populate_from_backend(items: Array):
	market_listings = []

	for item in items:
		market_listings.append({
			"id": item.get("id", 0),
			"item_name": item.get("name", "Unknown"),
			"category": item.get("category", "Misc"),
			"type": item.get("itemType", ""),
			"rarity": item.get("rarity", 0),
			"price": item.get("price", 0),
			"seller_name": "Shop",
			"icon": null,
			"backend_item": true,
			"timestamp": Time.get_unix_time_from_system()
		})

	_apply_filters()

func _load_sample_listings():
	# Fallback sample items for testing
	var sample_items = [
		{"name": "AK-47", "category": "Weapons", "type": "Rifle", "rarity": 2, "price": 800, "seller": "ProSeller"},
		{"name": "Shotgun", "category": "Weapons", "type": "Shotgun", "rarity": 1, "price": 500, "seller": "GunShop"},
		{"name": "Combat Vest", "category": "Armor", "type": "", "rarity": 2, "price": 600, "seller": "ArmorPro"},
		{"name": "Health Pack", "category": "Consumables", "type": "", "rarity": 0, "price": 100, "seller": "MedStore"},
		{"name": "Ammo Box", "category": "Consumables", "type": "", "rarity": 0, "price": 50, "seller": "AmmoDepo"},
		{"name": "Damage Augment", "category": "Augments", "type": "", "rarity": 3, "price": 1500, "seller": "RareFinds"},
		{"name": "Sniper Rifle", "category": "Weapons", "type": "Sniper", "rarity": 3, "price": 1200, "seller": "EliteArms"},
		{"name": "Tactical Helmet", "category": "Armor", "type": "", "rarity": 1, "price": 400, "seller": "GearUp"}
	]

	for i in range(sample_items.size()):
		var item = sample_items[i]
		market_listings.append({
			"id": i,
			"item_name": item.name,
			"category": item.category,
			"type": item.type,
			"rarity": item.rarity,
			"price": item.price,
			"seller_name": item.seller,
			"icon": null,
			"timestamp": Time.get_unix_time_from_system()
		})

	_apply_filters()

func _on_filter_changed():
	_update_filters_from_ui()
	_apply_filters()

func _update_filters_from_ui():
	if category_filter:
		current_filters.category = category_filter.get_item_text(category_filter.selected)
	if rarity_filter:
		current_filters.rarity = rarity_filter.get_item_text(rarity_filter.selected)
	if type_filter:
		current_filters.type = type_filter.get_item_text(type_filter.selected)
	if price_min:
		current_filters.price_min = int(price_min.value)
	if price_max:
		current_filters.price_max = int(price_max.value)
	if search_input:
		current_filters.search = search_input.text.to_lower()

func _apply_filters():
	filtered_listings = []

	for listing in market_listings:
		var passes_filter = true

		# Category filter
		if current_filters.category != "All":
			if listing.get("category", "") != current_filters.category:
				passes_filter = false

		# Rarity filter
		if current_filters.rarity != "All" and passes_filter:
			var rarity_names = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]
			var listing_rarity = listing.get("rarity", 0)
			if listing_rarity < rarity_names.size():
				if rarity_names[listing_rarity] != current_filters.rarity:
					passes_filter = false

		# Type filter
		if current_filters.type != "All" and passes_filter:
			if listing.get("type", "") != current_filters.type:
				passes_filter = false

		# Price range filter
		var price = listing.get("price", 0)
		if price < current_filters.price_min or price > current_filters.price_max:
			passes_filter = false

		# Search filter
		if current_filters.search != "" and passes_filter:
			var item_name = listing.get("item_name", "").to_lower()
			if not item_name.contains(current_filters.search):
				passes_filter = false

		if passes_filter:
			filtered_listings.append(listing)

	_refresh_market_display()
	_update_currency_display()

func _refresh_market_display():
	if not market_grid:
		return

	for i in range(market_grid.get_child_count()):
		var slot = market_grid.get_child(i)
		var icon = slot.get_node_or_null("Icon") as TextureRect
		if not icon:
			# Icon might be nested in container
			var container = slot.get_node_or_null("VBoxContainer/PanelContainer")
			if container:
				icon = container.get_node_or_null("Icon") as TextureRect
		var price_label = slot.get_node_or_null("Price") as Label
		if not price_label:
			var vbox = slot.get_node_or_null("VBoxContainer")
			if vbox:
				price_label = vbox.get_node_or_null("Price") as Label
		var seller_label = slot.get_node_or_null("Seller") as Label
		if not seller_label:
			var vbox = slot.get_node_or_null("VBoxContainer")
			if vbox:
				seller_label = vbox.get_node_or_null("Seller") as Label

		if i < filtered_listings.size():
			var listing = filtered_listings[i]
			if icon:
				icon.texture = listing.get("icon")
			if price_label:
				price_label.text = "$%d" % listing.price
			if seller_label:
				seller_label.text = listing.seller_name

			# Update border color based on rarity
			var style = slot.get_theme_stylebox("panel") as StyleBoxFlat
			if style:
				var rarity = listing.get("rarity", 0)
				var rarity_color = _get_rarity_color(rarity)
				style.border_color = rarity_color
		else:
			if icon:
				icon.texture = null
			if price_label:
				price_label.text = ""
			if seller_label:
				seller_label.text = ""

			var style = slot.get_theme_stylebox("panel") as StyleBoxFlat
			if style:
				style.border_color = Color(0.2, 0.2, 0.25)

func _get_rarity_color(rarity: int) -> Color:
	match rarity:
		0: return Color(0.5, 0.5, 0.5)   # Common - gray
		1: return Color(0.2, 0.8, 0.2)   # Uncommon - green
		2: return Color(0.2, 0.4, 1.0)   # Rare - blue
		3: return Color(0.6, 0.2, 0.8)   # Epic - purple
		4: return Color(1.0, 0.6, 0.0)   # Legendary - orange
		5: return Color(1.0, 0.2, 0.2)   # Mythic - red
	return Color(0.3, 0.3, 0.3)

func _on_market_slot_clicked(index: int):
	if index >= filtered_listings.size():
		return

	selected_listing = filtered_listings[index]
	_show_purchase_dialog()

func _show_purchase_dialog():
	if selected_listing.is_empty():
		return

	var dialog = AcceptDialog.new()
	dialog.title = "Purchase Item"

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	# Item name
	var name_label = Label.new()
	name_label.text = selected_listing.get("item_name", "Unknown")
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", _get_rarity_color(selected_listing.get("rarity", 0)))
	vbox.add_child(name_label)

	# Category
	var cat_label = Label.new()
	cat_label.text = "Category: %s" % selected_listing.get("category", "Unknown")
	cat_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(cat_label)

	# Seller
	var seller_label = Label.new()
	seller_label.text = "Seller: %s" % selected_listing.get("seller_name", "Unknown")
	seller_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(seller_label)

	# Price
	var price = selected_listing.get("price", 0)
	var price_label = Label.new()
	price_label.text = "Price: $%d" % price
	price_label.add_theme_color_override("font_color", Color.GOLD)
	price_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(price_label)

	# Your balance
	var balance_label = Label.new()
	balance_label.text = "Your Balance: $%d" % player_currency
	if player_currency >= price:
		balance_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		balance_label.add_theme_color_override("font_color", Color.RED)
	vbox.add_child(balance_label)

	# After purchase balance
	var after_label = Label.new()
	var after_balance = player_currency - price
	after_label.text = "After Purchase: $%d" % after_balance
	if after_balance >= 0:
		after_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	else:
		after_label.add_theme_color_override("font_color", Color.RED)
	vbox.add_child(after_label)

	dialog.add_child(vbox)

	# Add buttons
	dialog.ok_button_text = "Purchase"
	dialog.add_cancel_button("Cancel")

	# Disable purchase if not enough currency
	if player_currency < price:
		dialog.get_ok_button().disabled = true
		var warning = Label.new()
		warning.text = "Insufficient funds!"
		warning.add_theme_color_override("font_color", Color.RED)
		vbox.add_child(warning)

	dialog.confirmed.connect(_confirm_purchase.bind(selected_listing.get("id", -1)))

	add_child(dialog)
	dialog.popup_centered(Vector2i(300, 280))

func _confirm_purchase(listing_id: int):
	if listing_id < 0:
		return

	var listing = null
	for l in market_listings:
		if l.id == listing_id:
			listing = l
			break

	if not listing:
		_show_message("Purchase Failed", "Listing no longer available.")
		return

	var price = listing.get("price", 0)

	if player_currency < price:
		_show_message("Purchase Failed", "Insufficient funds.")
		return

	# If backend item, purchase through backend API
	if listing.get("backend_item", false) and backend:
		var item_id = listing.get("backend_id", str(listing_id))
		backend.purchase_item(str(item_id), func(response):
			if response.success:
				_on_backend_purchase_success(listing, price)
			else:
				_show_message("Purchase Failed", response.get("error", "Unknown error"))
		)
		return

	# Local purchase
	_complete_local_purchase(listing, price)

func _on_backend_purchase_success(listing: Dictionary, price: int):
	player_currency -= price

	# Refresh player data from backend
	if backend:
		backend.get_profile(func(response):
			if response.success and response.has("player"):
				player_currency = response.player.get("currency", player_currency)
				_update_currency_display()
		)

	# Remove from local list
	market_listings.erase(listing)

	# Add to inventory
	_add_item_to_inventory(listing)

	# Emit signal
	item_purchased.emit(listing.get("id", -1))

	# Refresh display
	_apply_filters()
	_update_currency_display()

	_show_message("Purchase Successful", "You bought %s for $%d" % [listing.get("item_name", "Item"), price])

func _complete_local_purchase(listing: Dictionary, price: int):
	# Deduct currency
	player_currency -= price
	if has_node("/root/PointsSystem"):
		var ps = get_node("/root/PointsSystem")
		if ps.has_method("spend_points"):
			ps.spend_points(price, listing.get("item_name", "Market Item"))

	# Remove listing
	market_listings.erase(listing)

	# Add item to player inventory
	_add_item_to_inventory(listing)

	# Emit signal
	item_purchased.emit(listing.get("id", -1))

	# Refresh display
	_apply_filters()
	_update_currency_display()

	_show_message("Purchase Successful", "You bought %s for $%d" % [listing.get("item_name", "Item"), price])

func _add_item_to_inventory(listing: Dictionary):
	# Add purchased item to player inventory
	# Would integrate with inventory/stash system
	if has_node("/root/InventorySystem"):
		var inv = get_node("/root/InventorySystem")
		if inv.has_method("add_item"):
			# Would create proper item resource here
			inv.add_item(listing.get("item_name", "Unknown"), 1)

func _show_message(title: String, message: String):
	var dialog = AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered()

func list_item(item, price: int, seller_name: String) -> int:  # item: ItemDataExtended
	var listing = {
		"id": market_listings.size(),
		"item": item,
		"item_name": item.item_name if item and "item_name" in item else "Unknown",
		"category": _get_item_category(item),
		"rarity": item.rarity if item and "rarity" in item else 0,
		"price": price,
		"seller_name": seller_name,
		"icon": item.icon if item and "icon" in item else null,
		"timestamp": Time.get_unix_time_from_system()
	}
	market_listings.append(listing)
	item_listed.emit(item, price)
	_apply_filters()
	return listing.id

func _get_item_category(item) -> String:
	if not item:
		return "Unknown"
	if "item_category" in item:
		return item.item_category
	if "item_type" in item:
		match item.item_type:
			0, 1, 2, 3: return "Armor"
			6, 7: return "Weapons"
	return "Misc"

func purchase_listing(listing_id: int) -> bool:
	for i in range(market_listings.size()):
		if market_listings[i].id == listing_id:
			var listing = market_listings[i]
			market_listings.remove_at(i)
			item_purchased.emit(listing_id)
			_apply_filters()
			return true
	return false

func _on_search_pressed():
	_update_filters_from_ui()
	_apply_filters()

func _on_back_pressed():
	close()
	panel_closed.emit()

func _on_reset_pressed():
	current_filters = {
		"category": "All",
		"rarity": "All",
		"type": "All",
		"price_min": 0,
		"price_max": 999999,
		"search": ""
	}

	# Reset UI
	if category_filter:
		category_filter.select(0)
	if rarity_filter:
		rarity_filter.select(0)
	if type_filter:
		type_filter.select(0)
	if price_min:
		price_min.value = 0
	if price_max:
		price_max.value = 999999
	if search_input:
		search_input.text = ""

	_apply_filters()

func open():
	visible = true
	_load_player_currency()
	_load_market_listings()

func close():
	visible = false
	selected_listing = {}

func refresh():
	_load_player_currency()
	_load_market_listings()
