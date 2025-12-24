extends Control
class_name MarketPanel

signal item_listed(item: ItemDataExtended, price: int)
signal item_purchased(listing_id: int)
signal trade_requested(player_id: int)

# Filter options
@onready var utility_filter: OptionButton = $FilterBar/UtilityFilter
@onready var gear_filter: OptionButton = $FilterBar/GearFilter
@onready var weapon_filter: OptionButton = $FilterBar/WeaponFilter
@onready var primary_attr_filter: OptionButton = $FilterBar/PrimaryAttrFilter
@onready var secondary_attr_filter: OptionButton = $FilterBar/SecondaryAttrFilter
@onready var search_button: Button = $FilterBar/SearchButton
@onready var back_button: Button = $FilterBar/BackButton
@onready var reset_button: Button = $FilterBar/ResetButton

# Market grid
@onready var market_grid: GridContainer = $MarketContainer/ScrollContainer/MarketGrid

# Listing data
var market_listings: Array = []
var filtered_listings: Array = []

# Filter values
var current_filters: Dictionary = {
	"utility": "Option A",
	"gear": "Option A",
	"weapon": "Option A",
	"primary_attr": "Option A",
	"secondary_attr": "Option A"
}

func _ready():
	_setup_filters()
	_setup_market_grid()
	_connect_signals()
	_load_market_listings()

func _setup_filters():
	var filter_options = ["Option A", "Option B", "Option C", "Any"]

	for filter in [utility_filter, gear_filter, weapon_filter, primary_attr_filter, secondary_attr_filter]:
		if filter:
			filter.clear()
			for option in filter_options:
				filter.add_item(option)

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
	slot.custom_minimum_size = Vector2(80, 80)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.95)
	style.border_color = Color(0.2, 0.2, 0.25)
	style.set_border_width_all(1)
	slot.add_theme_stylebox_override("panel", style)

	var button = Button.new()
	button.name = "Button"
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.flat = true
	button.pressed.connect(_on_market_slot_clicked.bind(index))
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
	price_label.offset_top = -18
	price_label.offset_left = 2
	price_label.add_theme_font_size_override("font_size", 10)
	price_label.add_theme_color_override("font_color", Color.GOLD)
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(price_label)

	var seller_label = Label.new()
	seller_label.name = "Seller"
	seller_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	seller_label.offset_top = 2
	seller_label.offset_left = 2
	seller_label.add_theme_font_size_override("font_size", 8)
	seller_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	seller_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(seller_label)

	return slot

func _connect_signals():
	if search_button:
		search_button.pressed.connect(_on_search_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	if reset_button:
		reset_button.pressed.connect(_on_reset_pressed)

func _load_market_listings():
	# Would load from server/network
	# For now, empty
	market_listings = []
	_apply_filters()

func _apply_filters():
	filtered_listings = []

	for listing in market_listings:
		var passes_filter = true

		# Apply each filter
		if current_filters.utility != "Any" and current_filters.utility != "Option A":
			# Check utility type
			pass

		if current_filters.gear != "Any" and current_filters.gear != "Option A":
			# Check gear type
			pass

		if current_filters.weapon != "Any" and current_filters.weapon != "Option A":
			# Check weapon type
			pass

		if passes_filter:
			filtered_listings.append(listing)

	_refresh_market_display()

func _refresh_market_display():
	if not market_grid:
		return

	for i in range(market_grid.get_child_count()):
		var slot = market_grid.get_child(i)
		var icon = slot.get_node_or_null("Icon") as TextureRect
		var price_label = slot.get_node_or_null("Price") as Label
		var seller_label = slot.get_node_or_null("Seller") as Label

		if i < filtered_listings.size():
			var listing = filtered_listings[i]
			if icon:
				icon.texture = listing.item.icon if listing.item else null
			if price_label:
				price_label.text = "$%d" % listing.price
			if seller_label:
				seller_label.text = listing.seller_name
		else:
			if icon:
				icon.texture = null
			if price_label:
				price_label.text = ""
			if seller_label:
				seller_label.text = ""

func list_item(item: ItemDataExtended, price: int, seller_name: String) -> int:
	var listing = {
		"id": market_listings.size(),
		"item": item,
		"price": price,
		"seller_name": seller_name,
		"timestamp": Time.get_unix_time_from_system()
	}
	market_listings.append(listing)
	item_listed.emit(item, price)
	_apply_filters()
	return listing.id

func purchase_listing(listing_id: int) -> bool:
	for i in range(market_listings.size()):
		if market_listings[i].id == listing_id:
			var listing = market_listings[i]
			market_listings.remove_at(i)
			item_purchased.emit(listing_id)
			_apply_filters()
			return true
	return false

func _on_market_slot_clicked(index: int):
	if index < filtered_listings.size():
		var listing = filtered_listings[index]
		# Show purchase confirmation dialog
		print("Clicked listing: %s for $%d" % [listing.item.item_name if listing.item else "Unknown", listing.price])

func _on_search_pressed():
	# Update filters from UI
	if utility_filter:
		current_filters.utility = utility_filter.get_item_text(utility_filter.selected)
	if gear_filter:
		current_filters.gear = gear_filter.get_item_text(gear_filter.selected)
	if weapon_filter:
		current_filters.weapon = weapon_filter.get_item_text(weapon_filter.selected)
	if primary_attr_filter:
		current_filters.primary_attr = primary_attr_filter.get_item_text(primary_attr_filter.selected)
	if secondary_attr_filter:
		current_filters.secondary_attr = secondary_attr_filter.get_item_text(secondary_attr_filter.selected)

	_apply_filters()

func _on_back_pressed():
	close()

func _on_reset_pressed():
	current_filters = {
		"utility": "Option A",
		"gear": "Option A",
		"weapon": "Option A",
		"primary_attr": "Option A",
		"secondary_attr": "Option A"
	}

	# Reset UI
	if utility_filter:
		utility_filter.select(0)
	if gear_filter:
		gear_filter.select(0)
	if weapon_filter:
		weapon_filter.select(0)
	if primary_attr_filter:
		primary_attr_filter.select(0)
	if secondary_attr_filter:
		secondary_attr_filter.select(0)

	_apply_filters()

func open():
	visible = true
	_load_market_listings()

func close():
	visible = false
