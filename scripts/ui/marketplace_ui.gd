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
	show_item_tooltip(shop_item.item, slot.global_position)

	# Highlight effect on slot
	var tween = create_tween()
	tween.tween_property(slot, "scale", Vector2(1.05, 1.05), 0.1)

	# Connect mouse exit to hide tooltip
	var button = slot.get_node_or_null("Button") as Button
	if button and not button.mouse_exited.is_connected(_on_shop_item_exit):
		button.mouse_exited.connect(_on_shop_item_exit.bind(slot))

func _on_shop_item_exit(slot: Panel):
	hide_item_tooltip()

	# Reset scale
	var tween = create_tween()
	tween.tween_property(slot, "scale", Vector2(1.0, 1.0), 0.1)

func show_item_tooltip(item: ItemDataExtended, position: Vector2):
	# Create tooltip if it doesn't exist
	var tooltip = get_node_or_null("ItemTooltip")
	if not tooltip:
		tooltip = create_tooltip_panel()
		add_child(tooltip)

	# Position tooltip
	tooltip.global_position = position + Vector2(130, 0)

	# Clamp to screen bounds
	var screen_size = get_viewport().get_visible_rect().size
	if tooltip.global_position.x + tooltip.size.x > screen_size.x:
		tooltip.global_position.x = position.x - tooltip.size.x - 10

	# Update tooltip content
	update_tooltip_content(tooltip, item)
	tooltip.visible = true

func create_tooltip_panel() -> Panel:
	var panel = Panel.new()
	panel.name = "ItemTooltip"
	panel.custom_minimum_size = Vector2(250, 200)
	panel.z_index = 100

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_color = Color(0.4, 0.4, 0.5)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)

	# Content container
	var vbox = VBoxContainer.new()
	vbox.name = "Content"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	vbox.offset_left = 10
	vbox.offset_top = 10
	vbox.offset_right = -10
	vbox.offset_bottom = -10
	panel.add_child(vbox)

	# Item name
	var name_label = RichTextLabel.new()
	name_label.name = "NameLabel"
	name_label.bbcode_enabled = true
	name_label.fit_content = true
	name_label.scroll_active = false
	vbox.add_child(name_label)

	# Item type/rarity
	var type_label = Label.new()
	type_label.name = "TypeLabel"
	type_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(type_label)

	# Separator
	var separator = HSeparator.new()
	vbox.add_child(separator)

	# Stats label
	var stats_label = RichTextLabel.new()
	stats_label.name = "StatsLabel"
	stats_label.bbcode_enabled = true
	stats_label.fit_content = true
	stats_label.scroll_active = false
	vbox.add_child(stats_label)

	# Description
	var desc_label = Label.new()
	desc_label.name = "DescLabel"
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(desc_label)

	return panel

func update_tooltip_content(tooltip: Panel, item: ItemDataExtended):
	var content = tooltip.get_node("Content")
	if not content:
		return

	var name_label = content.get_node_or_null("NameLabel") as RichTextLabel
	var type_label = content.get_node_or_null("TypeLabel") as Label
	var stats_label = content.get_node_or_null("StatsLabel") as RichTextLabel
	var desc_label = content.get_node_or_null("DescLabel") as Label

	if name_label:
		var color_hex = item.get_rarity_color().to_html()
		name_label.text = "[b][color=#%s]%s[/color][/b]" % [color_hex, item.item_name]

	if type_label:
		type_label.text = "%s %s" % [item.get_rarity_name(), ItemDataExtended.ItemType.keys()[item.item_type].capitalize()]
		type_label.add_theme_color_override("font_color", item.get_rarity_color())

	if stats_label:
		var stats_text = ""
		if item.item_type == ItemDataExtended.ItemType.WEAPON:
			stats_text += "[color=white]Damage:[/color] %.1f\n" % item.damage
			stats_text += "[color=white]Fire Rate:[/color] %.2f/s\n" % (1.0 / max(item.fire_rate, 0.01))
			stats_text += "[color=white]Magazine:[/color] %d\n" % item.magazine_size
			stats_text += "[color=white]Range:[/color] %.1fm\n" % item.weapon_range

		var all_stats = item.get_all_stats()
		if all_stats.size() > 0:
			stats_text += "\n[color=lime]Bonuses:[/color]\n"
			for stat_name in all_stats:
				stats_text += "[color=lime]+%.1f[/color] %s\n" % [all_stats[stat_name], stat_name.capitalize()]

		stats_label.text = stats_text

	if desc_label:
		desc_label.text = item.description

func hide_item_tooltip():
	var tooltip = get_node_or_null("ItemTooltip")
	if tooltip:
		tooltip.visible = false

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
	# Additional visual feedback - coin particles flying
	spawn_coin_particles(cost)

	# Play purchase sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("purchase")

func spawn_coin_particles(amount: int):
	# Spawn floating coin icons
	var num_coins = mini(amount // 10, 10)  # Max 10 coin particles

	for i in range(num_coins):
		var coin = Label.new()
		coin.text = "💰"
		coin.add_theme_font_size_override("font_size", 24)
		coin.position = size / 2 + Vector2(randf_range(-50, 50), randf_range(-20, 20))
		add_child(coin)

		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(coin, "position:y", coin.position.y - 80 - randf_range(0, 40), 0.8)
		tween.tween_property(coin, "modulate:a", 0.0, 0.8).set_delay(0.3)
		tween.tween_property(coin, "rotation", randf_range(-0.5, 0.5), 0.8)

		# Clean up after animation
		get_tree().create_timer(1.0).timeout.connect(coin.queue_free)

func _input(event):
	if is_open and event.is_action_pressed("ui_cancel"):
		close()
