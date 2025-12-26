extends Control
class_name StashUI

var player_persistence: Node = null  # PlayerPersistence autoload - set in _ready
@export var inventory_system: InventorySystem

@onready var stash_panel: Panel = $StashPanel
@onready var stash_grid: GridContainer = $StashPanel/StashGrid
@onready var inventory_grid: GridContainer = $InventoryPanel/InventoryGrid
@onready var currency_label: Label = $CurrencyPanel/CurrencyLabel
@onready var weight_label: Label = $WeightLabel

var stash_slots: Array[Control] = []
var inventory_slots: Array[Control] = []
var is_open: bool = false

signal stash_opened
signal stash_closed
signal item_transferred

func _ready():
	visible = false

	# Get PlayerPersistence autoload singleton
	player_persistence = get_node_or_null("/root/PlayerPersistence")

	setup_ui()

func setup_ui():
	# Setup stash grid (larger than inventory)
	if stash_grid:
		stash_grid.columns = 8
		for i in range(64):  # 64 stash slots
			var slot = create_slot(i, true)
			stash_grid.add_child(slot)
			stash_slots.append(slot)

	# Setup inventory grid
	if inventory_grid:
		inventory_grid.columns = 5
		for i in range(20):  # 20 inventory slots
			var slot = create_slot(i, false)
			inventory_grid.add_child(slot)
			inventory_slots.append(slot)

func create_slot(index: int, is_stash: bool) -> Panel:
	var slot = Panel.new()
	slot.custom_minimum_size = Vector2(60, 60)

	# Style based on rarity when item is present
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	style.border_color = Color(0.4, 0.4, 0.4)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	slot.add_theme_stylebox_override("panel", style)

	# Icon
	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 4
	icon.offset_top = 4
	icon.offset_right = -4
	icon.offset_bottom = -4
	slot.add_child(icon)

	# Quantity label
	var count = Label.new()
	count.name = "Count"
	count.add_theme_font_size_override("font_size", 12)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	count.offset_left = -30
	count.offset_top = -20
	slot.add_child(count)

	# Rarity indicator
	var rarity_bar = ColorRect.new()
	rarity_bar.name = "RarityBar"
	rarity_bar.size = Vector2(60, 3)
	rarity_bar.position = Vector2(0, 57)
	slot.add_child(rarity_bar)

	# Click handler
	var button = Button.new()
	button.name = "Button"
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.flat = true
	button.pressed.connect(_on_slot_clicked.bind(index, is_stash))
	button.mouse_entered.connect(_on_slot_hover.bind(index, is_stash))
	slot.add_child(button)

	return slot

func open():
	is_open = true
	visible = true
	animate_open()
	refresh_all()
	stash_opened.emit()

func close():
	is_open = false
	animate_close()
	await get_tree().create_timer(0.3).timeout
	visible = false
	stash_closed.emit()

func animate_open():
	modulate.a = 0
	scale = Vector2(0.9, 0.9)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func animate_close():
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_property(self, "scale", Vector2(0.9, 0.9), 0.2)

func refresh_all():
	refresh_stash()
	refresh_inventory()
	refresh_currency()
	refresh_weight()

func refresh_stash():
	if not player_persistence:
		return

	var stash_items = player_persistence.player_data.stash

	for i in range(stash_slots.size()):
		var slot = stash_slots[i]
		if i < stash_items.size():
			update_slot(slot, stash_items[i].item, stash_items[i].quantity)
		else:
			clear_slot(slot)

func refresh_inventory():
	if not inventory_system:
		return

	for i in range(inventory_slots.size()):
		var slot = inventory_slots[i]
		if i < inventory_system.inventory.size():
			var item_data = inventory_system.inventory[i]
			update_slot(slot, item_data.item, item_data.quantity)
		else:
			clear_slot(slot)

func update_slot(slot: Panel, item, quantity: int):  # item: ItemDataExtended
	if not item:
		clear_slot(slot)
		return

	var icon = slot.get_node("Icon") as TextureRect
	var count = slot.get_node("Count") as Label
	var rarity_bar = slot.get_node("RarityBar") as ColorRect

	if icon and item.icon:
		icon.texture = item.icon

	if count:
		count.text = str(quantity) if quantity > 1 else ""

	if rarity_bar:
		rarity_bar.color = item.get_rarity_color()

	# Update border color based on rarity
	var style = slot.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		style.border_color = item.get_rarity_color()

func clear_slot(slot: Panel):
	var icon = slot.get_node("Icon") as TextureRect
	var count = slot.get_node("Count") as Label
	var rarity_bar = slot.get_node("RarityBar") as ColorRect

	if icon:
		icon.texture = null
	if count:
		count.text = ""
	if rarity_bar:
		rarity_bar.color = Color.TRANSPARENT

func refresh_currency():
	if not player_persistence or not currency_label:
		return

	var coins = player_persistence.get_currency("coins")
	var tokens = player_persistence.get_currency("tokens")
	var scrap = player_persistence.get_currency("scrap")

	currency_label.text = "Coins: %d | Tokens: %d | Scrap: %d" % [coins, tokens, scrap]

func refresh_weight():
	if not inventory_system or not weight_label:
		return

	var current = inventory_system.get_current_weight()
	var max_weight = 100.0  # Would get from character stats

	weight_label.text = "Weight: %.1f / %.1f" % [current, max_weight]

	# Color code based on weight
	var percent = current / max_weight
	if percent >= 1.0:
		weight_label.add_theme_color_override("font_color", Color.RED)
	elif percent >= 0.8:
		weight_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		weight_label.add_theme_color_override("font_color", Color.WHITE)

func _on_slot_clicked(index: int, is_stash: bool):
	if is_stash:
		transfer_from_stash(index)
	else:
		transfer_to_stash(index)

func transfer_to_stash(inventory_index: int):
	if not inventory_system or inventory_index >= inventory_system.inventory.size():
		return

	var item_data = inventory_system.inventory[inventory_index]
	if inventory_system.transfer_to_stash(item_data.item, item_data.quantity):
		item_transferred.emit()
		refresh_all()
		animate_item_transfer(false)

func transfer_from_stash(stash_index: int):
	if not player_persistence or not inventory_system:
		return

	var stash_items = player_persistence.player_data.stash
	if stash_index >= stash_items.size():
		return

	var item_data = stash_items[stash_index]
	if inventory_system.transfer_from_stash(item_data.item, item_data.quantity):
		item_transferred.emit()
		refresh_all()
		animate_item_transfer(true)

func animate_item_transfer(to_inventory: bool):
	# Visual feedback for item transfer
	var label = Label.new()
	label.text = "→" if to_inventory else "←"
	label.add_theme_font_size_override("font_size", 32)
	label.modulate = Color(1, 1, 0)
	add_child(label)
	label.position = size / 2

	var tween = create_tween()
	tween.tween_property(label, "position:y", label.position.y - 50, 0.5)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.5)
	await tween.finished
	label.queue_free()

func _on_slot_hover(index: int, is_stash: bool):
	# Get item data based on source
	var item = null  # ItemDataExtended
	var slot: Panel = null

	if is_stash:
		if player_persistence and index < player_persistence.player_data.stash.size():
			item = player_persistence.player_data.stash[index].item
		if index < stash_slots.size():
			slot = stash_slots[index]
	else:
		if inventory_system and index < inventory_system.inventory.size():
			item = inventory_system.inventory[index].item
		if index < inventory_slots.size():
			slot = inventory_slots[index]

	if item and slot:
		show_tooltip(item, slot.global_position)

		# Connect mouse exit
		var button = slot.get_node_or_null("Button") as Button
		if button and not button.mouse_exited.is_connected(_on_slot_exit):
			button.mouse_exited.connect(_on_slot_exit)

func _on_slot_exit():
	hide_tooltip()

func show_tooltip(item, position: Vector2):  # item: ItemDataExtended
	var tooltip = get_node_or_null("ItemTooltip")
	if not tooltip:
		tooltip = create_tooltip()
		add_child(tooltip)

	# Position tooltip
	tooltip.global_position = position + Vector2(70, 0)

	# Clamp to screen bounds
	var screen_size = get_viewport().get_visible_rect().size
	if tooltip.global_position.x + tooltip.size.x > screen_size.x:
		tooltip.global_position.x = position.x - tooltip.size.x - 10
	if tooltip.global_position.y + tooltip.size.y > screen_size.y:
		tooltip.global_position.y = screen_size.y - tooltip.size.y - 10

	update_tooltip(tooltip, item)
	tooltip.visible = true

func create_tooltip() -> Panel:
	var panel = Panel.new()
	panel.name = "ItemTooltip"
	panel.custom_minimum_size = Vector2(220, 180)
	panel.z_index = 100

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_color = Color(0.4, 0.4, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.name = "Content"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	vbox.offset_left = 8
	vbox.offset_top = 8
	vbox.offset_right = -8
	vbox.offset_bottom = -8
	panel.add_child(vbox)

	# Name
	var name_label = RichTextLabel.new()
	name_label.name = "NameLabel"
	name_label.bbcode_enabled = true
	name_label.fit_content = true
	name_label.scroll_active = false
	vbox.add_child(name_label)

	# Type/Rarity
	var type_label = Label.new()
	type_label.name = "TypeLabel"
	type_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(type_label)

	# Separator
	vbox.add_child(HSeparator.new())

	# Stats
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
	desc_label.add_theme_font_size_override("font_size", 10)
	desc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(desc_label)

	# Click hint
	var hint_label = Label.new()
	hint_label.name = "HintLabel"
	hint_label.text = "Click to transfer"
	hint_label.add_theme_font_size_override("font_size", 10)
	hint_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint_label)

	return panel

func update_tooltip(tooltip: Panel, item):  # item: ItemDataExtended
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
		type_label.text = "%s %s" % [item.get_rarity_name(), ItemDataExtended.ItemType.keys()[item.item_type].capitalize().replace("_", " ")]
		type_label.add_theme_color_override("font_color", item.get_rarity_color())

	if stats_label:
		var stats_text = ""
		if item.item_type == ItemDataExtended.ItemType.WEAPON:
			stats_text += "Damage: %.1f\n" % item.damage
			stats_text += "Fire Rate: %.2f/s\n" % (1.0 / max(item.fire_rate, 0.01))

		if item.armor_value > 0:
			stats_text += "Armor: %.1f\n" % item.armor_value

		var all_stats = item.get_all_stats()
		for stat_name in all_stats:
			stats_text += "[color=lime]+%.1f %s[/color]\n" % [all_stats[stat_name], stat_name.capitalize()]

		stats_label.text = stats_text

	if desc_label and item.description != "":
		desc_label.text = item.description
		desc_label.visible = true
	elif desc_label:
		desc_label.visible = false

func hide_tooltip():
	var tooltip = get_node_or_null("ItemTooltip")
	if tooltip:
		tooltip.visible = false

func _input(event):
	if is_open and event.is_action_pressed("ui_cancel"):
		close()
