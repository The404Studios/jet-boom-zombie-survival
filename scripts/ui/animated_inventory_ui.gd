extends Control
class_name AnimatedInventoryUI

@export var inventory_system: Node  # InventorySystem
@export var equipment_system: Node  # EquipmentSystem
@export var character_stats: Node  # CharacterStats

@onready var inventory_panel: Panel = $InventoryPanel
@onready var inventory_grid: GridContainer = $InventoryPanel/ScrollContainer/InventoryGrid
@onready var equipment_panel: Panel = $EquipmentPanel
@onready var stats_panel: Panel = $StatsPanel
@onready var item_tooltip: Panel = $ItemTooltip

var is_open: bool = false
var selected_item = null  # ItemDataExtended
var inventory_slots: Array[Control] = []

const SLOT_SCENE = preload("res://scenes/ui/inventory_slot.tscn")

signal inventory_ui_opened
signal inventory_ui_closed

func _ready():
	visible = false
	setup_ui()

	if inventory_system:
		inventory_system.inventory_changed.connect(_on_inventory_changed)

func setup_ui():
	# Setup inventory grid
	if inventory_grid:
		inventory_grid.columns = 5
		for i in range(20):  # 20 slots
			var slot = create_inventory_slot(i)
			inventory_grid.add_child(slot)
			inventory_slots.append(slot)

	# Setup equipment slots
	setup_equipment_slots()

	# Setup stats display
	setup_stats_display()

func create_inventory_slot(index: int) -> Control:
	var slot = Panel.new()
	slot.custom_minimum_size = Vector2(64, 64)
	slot.mouse_entered.connect(_on_slot_mouse_entered.bind(slot, index))
	slot.mouse_exited.connect(_on_slot_mouse_exited.bind(slot))

	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.add_child(icon)

	var count_label = Label.new()
	count_label.name = "Count"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT as HorizontalAlignment
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM as VerticalAlignment
	count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	slot.add_child(count_label)

	return slot

func setup_equipment_slots():
	if not equipment_panel:
		return

	# Create equipment slot layout
	var vbox = VBoxContainer.new()
	vbox.name = "EquipmentSlots"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	vbox.offset_left = 10
	vbox.offset_top = 10
	vbox.offset_right = -10
	vbox.offset_bottom = -10
	equipment_panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Equipment"
	title.add_theme_font_size_override("font_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER as HorizontalAlignment
	vbox.add_child(title)

	# Equipment slots with labels
	var slots_data = [
		{"name": "weapon", "label": "Weapon"},
		{"name": "helmet", "label": "Helmet"},
		{"name": "chest", "label": "Chest"},
		{"name": "gloves", "label": "Gloves"},
		{"name": "boots", "label": "Boots"},
		{"name": "ring", "label": "Ring"},
		{"name": "amulet", "label": "Amulet"}
	]

	for slot_data in slots_data:
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)

		var label = Label.new()
		label.text = slot_data.label + ":"
		label.custom_minimum_size = Vector2(60, 0)
		label.add_theme_font_size_override("font_size", 12)
		hbox.add_child(label)

		var slot = create_equipment_slot(slot_data.name)
		hbox.add_child(slot)

		vbox.add_child(hbox)

func create_equipment_slot(slot_name: String) -> Panel:
	var slot = Panel.new()
	slot.name = slot_name.capitalize() + "Slot"
	slot.custom_minimum_size = Vector2(48, 48)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.9)
	style.border_color = Color(0.4, 0.4, 0.4)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("panel", style)

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

	# Click handler for equipping items
	var button = Button.new()
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.flat = true
	button.pressed.connect(_on_equipment_slot_clicked.bind(slot_name))
	button.mouse_entered.connect(_on_equipment_slot_hover.bind(slot_name))
	button.mouse_exited.connect(hide_tooltip)
	slot.add_child(button)

	return slot

func _on_equipment_slot_clicked(slot_name: String):
	# Unequip item from slot
	if not equipment_system:
		return

	match slot_name:
		"weapon":
			if inventory_system and inventory_system.equipped_weapon:
				inventory_system.unequip_weapon()
				refresh_equipment()
				refresh_inventory()

func _on_equipment_slot_hover(slot_name: String):
	if not equipment_system:
		return

	var item = null  # ItemDataExtended
	match slot_name:
		"weapon":
			if inventory_system and inventory_system.equipped_weapon and inventory_system.equipped_weapon.has("item"):
				item = inventory_system.equipped_weapon.get("item")

	if item:
		var slot = equipment_panel.get_node_or_null("EquipmentSlots/" + slot_name.capitalize() + "Slot")
		if slot:
			show_tooltip(item, slot.global_position)

func refresh_equipment():
	if not equipment_panel or not inventory_system:
		return

	var weapon_slot = equipment_panel.get_node_or_null("EquipmentSlots/WeaponSlot")
	if weapon_slot:
		var icon = weapon_slot.get_node_or_null("Icon") as TextureRect
		if icon:
			if inventory_system.equipped_weapon and inventory_system.equipped_weapon.has("item"):
				var weapon_item = inventory_system.equipped_weapon.get("item")
				if weapon_item:
					icon.texture = weapon_item.icon
			else:
				icon.texture = null

func setup_stats_display():
	if not stats_panel:
		return

	var vbox = VBoxContainer.new()
	vbox.name = "StatsContainer"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	vbox.offset_left = 10
	vbox.offset_top = 10
	vbox.offset_right = -10
	vbox.offset_bottom = -10
	stats_panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Character Stats"
	title.add_theme_font_size_override("font_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER as HorizontalAlignment
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Create stat labels
	var stats_to_show = [
		"Health", "Stamina", "Armor",
		"Strength", "Dexterity", "Intelligence",
		"Agility", "Vitality",
		"Crit Chance", "Crit Damage"
	]

	for stat_name in stats_to_show:
		var hbox = HBoxContainer.new()

		var label = Label.new()
		label.text = stat_name + ":"
		label.custom_minimum_size = Vector2(100, 0)
		label.add_theme_font_size_override("font_size", 12)
		hbox.add_child(label)

		var value_label = Label.new()
		value_label.name = stat_name.replace(" ", "") + "Value"
		value_label.text = "0"
		value_label.add_theme_font_size_override("font_size", 12)
		value_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
		hbox.add_child(value_label)

		vbox.add_child(hbox)

func toggle():
	if is_open:
		close()
	else:
		open()

func open():
	is_open = true
	visible = true
	animate_open()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	inventory_ui_opened.emit()
	refresh_inventory()
	refresh_stats()

func close():
	is_open = false
	animate_close()
	await get_tree().create_timer(0.3).timeout
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	inventory_ui_closed.emit()

func animate_open():
	if inventory_panel:
		inventory_panel.modulate.a = 0
		inventory_panel.scale = Vector2(0.8, 0.8)

		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(inventory_panel, "modulate:a", 1.0, 0.3)
		tween.tween_property(inventory_panel, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if equipment_panel:
		equipment_panel.modulate.a = 0
		equipment_panel.position.x -= 50

		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(equipment_panel, "modulate:a", 1.0, 0.3).set_delay(0.1)
		tween.tween_property(equipment_panel, "position:x", equipment_panel.position.x + 50, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.1)

	if stats_panel:
		stats_panel.modulate.a = 0
		stats_panel.position.x += 50

		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(stats_panel, "modulate:a", 1.0, 0.3).set_delay(0.2)
		tween.tween_property(stats_panel, "position:x", stats_panel.position.x - 50, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.2)

func animate_close():
	if inventory_panel:
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(inventory_panel, "modulate:a", 0.0, 0.2)
		tween.tween_property(inventory_panel, "scale", Vector2(0.8, 0.8), 0.2)

func refresh_inventory():
	if not inventory_system:
		return

	for i in range(inventory_slots.size()):
		var slot = inventory_slots[i]
		var icon = slot.get_node("Icon") as TextureRect
		var count_label = slot.get_node("Count") as Label

		if i < inventory_system.inventory.size():
			var item_data = inventory_system.inventory[i]
			var item = item_data.item  # ItemDataExtended
			if icon and item.icon:
				icon.texture = item.icon
			if count_label:
				if item_data.quantity > 1:
					count_label.text = str(item_data.quantity)
				else:
					count_label.text = ""
		else:
			if icon:
				icon.texture = null
			if count_label:
				count_label.text = ""

func refresh_stats():
	if not stats_panel:
		return

	var stats_container = stats_panel.get_node_or_null("StatsContainer")
	if not stats_container:
		return

	# Get stats from character_stats or calculate from equipment
	var stats = {}
	if character_stats and character_stats.has_method("get_stat_summary"):
		stats = character_stats.get_stat_summary()
	else:
		# Calculate base stats
		stats = {
			"Health": 100.0,
			"Stamina": 100.0,
			"Armor": 0.0,
			"Strength": 10.0,
			"Dexterity": 10.0,
			"Intelligence": 10.0,
			"Agility": 10.0,
			"Vitality": 10.0,
			"CritChance": 5.0,
			"CritDamage": 150.0
		}

		# Add bonuses from equipped items
		if inventory_system:
			if inventory_system.equipped_weapon and inventory_system.equipped_weapon.has("item"):
				var weapon = inventory_system.equipped_weapon.get("item")  # ItemDataExtended
				if weapon:
					stats["Strength"] += weapon.strength_bonus
					stats["Dexterity"] += weapon.dexterity_bonus
					stats["CritChance"] += weapon.crit_chance_bonus
					stats["CritDamage"] += weapon.crit_damage_bonus

			if inventory_system.equipped_armor and inventory_system.equipped_armor.has("item"):
				var armor = inventory_system.equipped_armor.get("item")  # ItemDataExtended
				if armor:
					stats["Armor"] += armor.armor_value
					stats["Vitality"] += armor.vitality_bonus
					stats["Health"] += armor.health_bonus

	# Update UI labels
	for stat_name in stats:
		var clean_name = stat_name.replace(" ", "")
		var value_label = stats_container.get_node_or_null(clean_name + "Value")
		if not value_label:
			# Try finding in HBoxContainers
			for child in stats_container.get_children():
				if child is HBoxContainer:
					var label = child.get_node_or_null(clean_name + "Value")
					if label:
						value_label = label
						break

		if value_label:
			var value = stats[stat_name]
			if stat_name in ["CritChance", "CritDamage"]:
				value_label.text = "%.1f%%" % value
			else:
				value_label.text = "%.0f" % value

func _on_inventory_changed():
	if is_open:
		refresh_inventory()

func _on_slot_mouse_entered(slot: Control, index: int):
	if inventory_system and index < inventory_system.inventory.size():
		var item = inventory_system.inventory[index].item  # ItemDataExtended
		show_tooltip(item, slot.global_position)

func _on_slot_mouse_exited(slot: Control):
	hide_tooltip()

func show_tooltip(item, position: Vector2):  # item: ItemDataExtended
	# Create tooltip if it doesn't exist
	if not item_tooltip:
		item_tooltip = create_tooltip_panel()
		add_child(item_tooltip)

	# Position tooltip
	item_tooltip.global_position = position + Vector2(70, 0)

	# Clamp to screen bounds
	var screen_size = get_viewport().get_visible_rect().size
	if item_tooltip.global_position.x + item_tooltip.size.x > screen_size.x:
		item_tooltip.global_position.x = position.x - item_tooltip.size.x - 10
	if item_tooltip.global_position.y + item_tooltip.size.y > screen_size.y:
		item_tooltip.global_position.y = screen_size.y - item_tooltip.size.y - 10

	update_tooltip_content(item)
	item_tooltip.visible = true

func create_tooltip_panel() -> Panel:
	var panel = Panel.new()
	panel.name = "ItemTooltip"
	panel.custom_minimum_size = Vector2(220, 160)
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

	# Item name
	var name_label = RichTextLabel.new()
	name_label.name = "NameLabel"
	name_label.bbcode_enabled = true
	name_label.fit_content = true
	name_label.scroll_active = false
	vbox.add_child(name_label)

	# Rarity/Type
	var type_label = Label.new()
	type_label.name = "TypeLabel"
	type_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(type_label)

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

	return panel

func update_tooltip_content(item):  # item: ItemDataExtended
	if not item_tooltip:
		return

	var content = item_tooltip.get_node_or_null("Content")
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
		var type_name = _get_item_type_name(item.item_type)
		type_label.text = "%s %s" % [item.get_rarity_name(), type_name]
		type_label.add_theme_color_override("font_color", item.get_rarity_color())

	if stats_label:
		var stats_text = ""
		if item.item_type == 0:  # WEAPON
			stats_text += "Damage: %.1f\n" % item.damage
			stats_text += "Fire Rate: %.2f/s\n" % (1.0 / max(item.fire_rate, 0.01))
			stats_text += "Magazine: %d\n" % item.magazine_size

		if item.armor_value > 0:
			stats_text += "Armor: %.1f\n" % item.armor_value

		var all_stats = item.get_all_stats()
		for stat_name in all_stats:
			stats_text += "[color=lime]+%.1f %s[/color]\n" % [all_stats[stat_name], stat_name.capitalize()]

		stats_label.text = stats_text

	if desc_label:
		if item.description != "":
			desc_label.text = item.description
			desc_label.visible = true
		else:
			desc_label.visible = false

func hide_tooltip():
	if item_tooltip:
		item_tooltip.visible = false

func _input(event):
	if event.is_action_pressed("inventory"):
		toggle()

func _get_item_type_name(item_type: int) -> String:
	# Convert ItemType enum value to display name
	# Uses integers to avoid parse-time class reference
	match item_type:
		0:  # WEAPON
			return "Weapon"
		1:  # AMMO
			return "Ammo"
		2:  # HELMET
			return "Helmet"
		3:  # CHEST_ARMOR
			return "Chest Armor"
		4:  # GLOVES
			return "Gloves"
		5:  # BOOTS
			return "Boots"
		6:  # RING
			return "Ring"
		7:  # AMULET
			return "Amulet"
		8:  # CONSUMABLE
			return "Consumable"
		9:  # MATERIAL
			return "Material"
		10:  # AUGMENT
			return "Augment"
		_:
			return "Unknown"
