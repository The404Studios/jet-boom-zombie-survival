extends Control
class_name MarketplaceUI

@export var merchant_system: MerchantSystem
@export var inventory_system: InventorySystem
@export var player_persistence: PlayerPersistence

@onready var shop_panel: Panel = $ShopPanel
@onready var shop_grid: GridContainer = $ShopPanel/ScrollContainer/ShopGrid
@onready var currency_panel: Panel = $CurrencyPanel
@onready var filter_tabs: TabContainer = $FilterTabs
@onready var purchase_button: Button = $PurchaseButton
@onready var sell_button: Button = $SellButton
@onready var refresh_button: Button = $RefreshButton

var shop_slots: Array[Control] = []
var selected_shop_item: MerchantSystem.ShopItem = null
var is_open: bool = false

signal marketplace_opened
signal marketplace_closed

func _ready():
	visible = false
	setup_ui()

	if merchant_system:
		merchant_system.shop_refreshed.connect(_on_shop_refreshed)
		merchant_system.item_purchased.connect(_on_item_purchased)

	if refresh_button:
		refresh_button.pressed.connect(_on_refresh_pressed)

func setup_ui():
	# Setup shop grid
	if shop_grid:
		shop_grid.columns = 4

	# Setup currency display
	setup_currency_display()

	# Setup filter tabs
	setup_filters()

func setup_currency_display():
	if not currency_panel:
		return

	# Create currency labels with icons
	var coins_label = create_currency_label("💰", "coins")
	var tokens_label = create_currency_label("🎫", "tokens")
	var scrap_label = create_currency_label("🔧", "scrap")

	currency_panel.add_child(coins_label)
	currency_panel.add_child(tokens_label)
	currency_panel.add_child(scrap_label)

func create_currency_label(icon: String, currency_type: String) -> Label:
	var label = Label.new()
	label.name = currency_type.capitalize() + "Label"
	label.text = "%s 0" % icon
	label.add_theme_font_size_override("font_size", 18)
	return label

func setup_filters():
	if not filter_tabs:
		return

	# Add filter tabs for item types
	var all_tab = create_filter_tab("All")
	var weapons_tab = create_filter_tab("Weapons")
	var armor_tab = create_filter_tab("Armor")
	var consumables_tab = create_filter_tab("Consumables")

	filter_tabs.add_child(all_tab)
	filter_tabs.add_child(weapons_tab)
	filter_tabs.add_child(armor_tab)
	filter_tabs.add_child(consumables_tab)

func create_filter_tab(tab_name: String) -> Control:
	var container = VBoxContainer.new()
	container.name = tab_name
	return container

func open():
	is_open = true
	visible = true
	animate_open()
	refresh_shop_display()
	refresh_currency_display()
	marketplace_opened.emit()

func close():
	is_open = false
	animate_close()
	await get_tree().create_timer(0.3).timeout
	visible = false
	marketplace_closed.emit()

func animate_open():
	modulate.a = 0
	position.y += 50

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	tween.tween_property(self, "position:y", position.y - 50, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Stagger shop items
	await get_tree().create_timer(0.1).timeout
	for i in range(shop_slots.size()):
		var slot = shop_slots[i]
		slot.modulate.a = 0
		var item_tween = create_tween()
		item_tween.tween_property(slot, "modulate:a", 1.0, 0.2).set_delay(i * 0.05)

func animate_close():
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_property(self, "position:y", position.y + 30, 0.2)

func refresh_shop_display():
	if not merchant_system or not shop_grid:
		return

	# Clear existing slots
	for slot in shop_slots:
		slot.queue_free()
	shop_slots.clear()

	# Create slots for each shop item
	for shop_item in merchant_system.shop_inventory:
		var slot = create_shop_slot(shop_item)
		shop_grid.add_child(slot)
		shop_slots.append(slot)

func create_shop_slot(shop_item: MerchantSystem.ShopItem) -> Panel:
	var slot = Panel.new()
	slot.custom_minimum_size = Vector2(120, 140)

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.9)
	style.border_color = shop_item.item.get_rarity_color()
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	slot.add_theme_stylebox_override("panel", style)

	# Icon
	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.texture = shop_item.item.icon
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(10, 10)
	icon.size = Vector2(100, 80)
	slot.add_child(icon)

	# Item name
	var name_label = Label.new()
	name_label.text = shop_item.item.item_name
	name_label.position = Vector2(5, 95)
	name_label.size = Vector2(110, 20)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", shop_item.item.get_rarity_color())
	slot.add_child(name_label)

	# Price
	var price_label = Label.new()
	var currency_icon = merchant_system.get_currency_icon(shop_item.currency_type)
	price_label.text = "%s %d" % [currency_icon, shop_item.cost]
	price_label.position = Vector2(5, 115)
	price_label.size = Vector2(110, 20)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.add_theme_font_size_override("font_size", 14)
	price_label.add_theme_color_override("font_color", Color.GOLD)
	slot.add_child(price_label)

	# Stock indicator
	if shop_item.stock > 0:
		var stock_label = Label.new()
		stock_label.text = "Stock: %d" % shop_item.stock
		stock_label.position = Vector2(5, 3)
		stock_label.add_theme_font_size_override("font_size", 10)
		stock_label.add_theme_color_override("font_color", Color.YELLOW)
		slot.add_child(stock_label)

	# Sold out overlay
	if shop_item.sold_out:
		var sold_out = Label.new()
		sold_out.text = "SOLD OUT"
		sold_out.position = Vector2(10, 50)
		sold_out.rotation = -0.3
		sold_out.add_theme_font_size_override("font_size", 20)
		sold_out.add_theme_color_override("font_color", Color.RED)
		slot.add_child(sold_out)

	# Button
	var button = Button.new()
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.flat = true
	button.pressed.connect(_on_shop_item_clicked.bind(shop_item))
	button.mouse_entered.connect(_on_shop_item_hover.bind(shop_item, slot))
	slot.add_child(button)

	return slot

func refresh_currency_display():
	if not player_persistence or not currency_panel:
		return

	var coins_label = currency_panel.get_node_or_null("CoinsLabel") as Label
	var tokens_label = currency_panel.get_node_or_null("TokensLabel") as Label
	var scrap_label = currency_panel.get_node_or_null("ScrapLabel") as Label

	if coins_label:
		coins_label.text = "💰 %d" % player_persistence.get_currency("coins")
	if tokens_label:
		tokens_label.text = "🎫 %d" % player_persistence.get_currency("tokens")
	if scrap_label:
		scrap_label.text = "🔧 %d" % player_persistence.get_currency("scrap")

func _on_shop_item_clicked(shop_item: MerchantSystem.ShopItem):
	selected_shop_item = shop_item

	# Attempt purchase
	if merchant_system and inventory_system:
		if merchant_system.purchase_item(shop_item, inventory_system):
			# Success!
			animate_purchase_success()
			refresh_shop_display()
			refresh_currency_display()
		else:
			animate_purchase_failed()

func _on_shop_item_hover(shop_item: MerchantSystem.ShopItem, slot: Panel):
	# Show tooltip with item details
	# Could expand this to show full tooltip
	pass

func animate_purchase_success():
	# Visual feedback for successful purchase
	var label = Label.new()
	label.text = "PURCHASED!"
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color.GREEN)
	label.position = size / 2
	add_child(label)

	var tween = create_tween()
	tween.tween_property(label, "position:y", label.position.y - 100, 1.0)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.0)
	await tween.finished
	label.queue_free()

func animate_purchase_failed():
	# Shake effect for failed purchase
	var original_pos = position
	var shake_amount = 10.0

	for i in range(3):
		var tween = create_tween()
		tween.tween_property(self, "position:x", original_pos.x + shake_amount, 0.05)
		tween.tween_property(self, "position:x", original_pos.x - shake_amount, 0.05)
		tween.tween_property(self, "position:x", original_pos.x, 0.05)
		await tween.finished

func _on_refresh_pressed():
	if merchant_system and merchant_system.refresh_shop():
		refresh_shop_display()
		refresh_currency_display()

func _on_shop_refreshed():
	refresh_shop_display()

func _on_item_purchased(item: ItemDataExtended, cost: int):
	# Additional visual feedback
	pass

func _input(event):
	if is_open and event.is_action_pressed("ui_cancel"):
		close()
