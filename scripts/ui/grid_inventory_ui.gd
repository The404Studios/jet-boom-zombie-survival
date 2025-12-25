extends Control
class_name GridInventoryUI

# Grid-based inventory UI with item sizes, drag-drop, and equipment slots
# Supports items from 1x1 to 5x5 in size

@export var grid_inventory: GridInventorySystem

# UI References
var grid_panel: Panel
var equipment_panel: Panel
var stats_panel: Panel
var backpack_panel: Panel
var item_tooltip: Panel
var drag_preview: Control

# Grid configuration
const CELL_SIZE: int = 50
const GRID_PADDING: int = 10
const RARITY_COLORS: Dictionary = {
	0: Color(0.6, 0.6, 0.6),     # Common - Gray
	1: Color(0.2, 0.8, 0.2),     # Uncommon - Green
	2: Color(0.2, 0.4, 1.0),     # Rare - Blue
	3: Color(0.6, 0.2, 0.8),     # Epic - Purple
	4: Color(1.0, 0.6, 0.0),     # Legendary - Orange
	5: Color(1.0, 0.2, 0.2),     # Mythic - Red
}

# State
var is_open: bool = false
var hovered_item: Dictionary = {}
var dragging: bool = false
var drag_item: Dictionary = {}
var drag_from_stash: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var grid_cells: Array = []
var equipment_slots: Dictionary = {}

signal inventory_opened
signal inventory_closed

func _ready():
	visible = false
	_create_ui()

	# Find or create inventory system
	await get_tree().create_timer(0.1).timeout
	_find_inventory_system()

	if grid_inventory:
		grid_inventory.inventory_changed.connect(_refresh_display)

func _find_inventory_system():
	if grid_inventory:
		return

	# Try to find existing system
	var player = get_tree().get_first_node_in_group("player")
	if player and "grid_inventory" in player:
		grid_inventory = player.grid_inventory
		return

	# Create new system
	grid_inventory = GridInventorySystem.new()
	grid_inventory.name = "GridInventorySystem"
	add_child(grid_inventory)

func _create_ui():
	# Main container
	var main_container = HBoxContainer.new()
	main_container.name = "MainContainer"
	main_container.set_anchors_preset(Control.PRESET_CENTER)
	main_container.add_theme_constant_override("separation", 20)
	add_child(main_container)

	# Semi-transparent background
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	move_child(bg, 0)

	# Equipment panel (left)
	equipment_panel = _create_equipment_panel()
	main_container.add_child(equipment_panel)

	# Main inventory grid (center)
	grid_panel = _create_grid_panel()
	main_container.add_child(grid_panel)

	# Stats panel (right)
	stats_panel = _create_stats_panel()
	main_container.add_child(stats_panel)

	# Create drag preview (invisible until dragging)
	drag_preview = _create_drag_preview()
	add_child(drag_preview)

	# Create tooltip
	item_tooltip = _create_tooltip_panel()
	add_child(item_tooltip)

	# Center the main container
	main_container.position = Vector2(
		(get_viewport_rect().size.x - main_container.size.x) / 2,
		(get_viewport_rect().size.y - main_container.size.y) / 2
	)

func _create_grid_panel() -> Panel:
	var panel = Panel.new()
	panel.name = "GridPanel"

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	style.border_color = Color(0.3, 0.5, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	vbox.offset_left = GRID_PADDING
	vbox.offset_top = GRID_PADDING
	vbox.offset_right = -GRID_PADDING
	vbox.offset_bottom = -GRID_PADDING
	panel.add_child(vbox)

	# Header
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	var title = Label.new()
	title.text = "INVENTORY"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	header.add_child(title)

	header.add_spacer(false)

	var weight_label = Label.new()
	weight_label.name = "WeightLabel"
	weight_label.text = "Weight: 0 / 50"
	weight_label.add_theme_font_size_override("font_size", 14)
	header.add_child(weight_label)

	# Grid container
	var grid_container = Control.new()
	grid_container.name = "GridContainer"
	var grid_width = GridInventorySystem.BASE_GRID_WIDTH
	var grid_height = GridInventorySystem.BASE_GRID_HEIGHT
	grid_container.custom_minimum_size = Vector2(
		grid_width * CELL_SIZE,
		grid_height * CELL_SIZE
	)
	vbox.add_child(grid_container)

	# Create grid cells
	_create_grid_cells(grid_container, grid_width, grid_height)

	panel.custom_minimum_size = Vector2(
		grid_width * CELL_SIZE + GRID_PADDING * 2,
		grid_height * CELL_SIZE + GRID_PADDING * 2 + 50
	)

	return panel

func _create_grid_cells(container: Control, width: int, height: int):
	grid_cells.clear()

	for y in range(height):
		var row = []
		for x in range(width):
			var cell = _create_grid_cell(x, y)
			cell.position = Vector2(x * CELL_SIZE, y * CELL_SIZE)
			container.add_child(cell)
			row.append(cell)
		grid_cells.append(row)

func _create_grid_cell(x: int, y: int) -> Panel:
	var cell = Panel.new()
	cell.name = "Cell_%d_%d" % [x, y]
	cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	cell.size = Vector2(CELL_SIZE, CELL_SIZE)

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.18, 0.8)
	style.border_color = Color(0.25, 0.25, 0.3)
	style.set_border_width_all(1)
	cell.add_theme_stylebox_override("panel", style)

	# Set metadata for grid position
	cell.set_meta("grid_pos", Vector2i(x, y))

	# Mouse events
	cell.mouse_entered.connect(_on_cell_mouse_entered.bind(cell, x, y))
	cell.mouse_exited.connect(_on_cell_mouse_exited.bind(cell))
	cell.gui_input.connect(_on_cell_gui_input.bind(cell, x, y))

	return cell

func _create_equipment_panel() -> Panel:
	var panel = Panel.new()
	panel.name = "EquipmentPanel"
	panel.custom_minimum_size = Vector2(200, 400)

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	style.border_color = Color(0.3, 0.5, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	vbox.offset_left = 10
	vbox.offset_top = 10
	vbox.offset_right = -10
	vbox.offset_bottom = -10
	panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "EQUIPMENT"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Equipment slots layout
	var slots_data = [
		{"id": "helmet", "label": "Helmet", "size": Vector2i(2, 2)},
		{"id": "weapon_primary", "label": "Primary", "size": Vector2i(4, 1)},
		{"id": "chest", "label": "Chest", "size": Vector2i(2, 3)},
		{"id": "weapon_secondary", "label": "Secondary", "size": Vector2i(3, 1)},
		{"id": "gloves", "label": "Gloves", "size": Vector2i(2, 2)},
		{"id": "boots", "label": "Boots", "size": Vector2i(2, 2)},
		{"id": "ring_left", "label": "Ring L", "size": Vector2i(1, 1)},
		{"id": "ring_right", "label": "Ring R", "size": Vector2i(1, 1)},
		{"id": "amulet", "label": "Amulet", "size": Vector2i(1, 2)},
		{"id": "backpack", "label": "Backpack", "size": Vector2i(3, 3)},
	]

	for slot_data in slots_data:
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)

		var label = Label.new()
		label.text = slot_data.label + ":"
		label.custom_minimum_size = Vector2(70, 0)
		label.add_theme_font_size_override("font_size", 12)
		hbox.add_child(label)

		var slot = _create_equipment_slot(slot_data.id, slot_data.size)
		hbox.add_child(slot)
		equipment_slots[slot_data.id] = slot

		vbox.add_child(hbox)

	return panel

func _create_equipment_slot(slot_id: String, slot_size: Vector2i) -> Panel:
	var slot = Panel.new()
	slot.name = slot_id + "_slot"
	slot.custom_minimum_size = Vector2(slot_size.x * 25, slot_size.y * 25)

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.9)
	style.border_color = Color(0.4, 0.4, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("panel", style)

	# Icon
	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 2
	icon.offset_top = 2
	icon.offset_right = -2
	icon.offset_bottom = -2
	slot.add_child(icon)

	# Set metadata
	slot.set_meta("slot_id", slot_id)

	# Click handler
	slot.gui_input.connect(_on_equipment_slot_input.bind(slot, slot_id))
	slot.mouse_entered.connect(_on_equipment_slot_hover.bind(slot, slot_id))
	slot.mouse_exited.connect(_hide_tooltip)

	return slot

func _create_stats_panel() -> Panel:
	var panel = Panel.new()
	panel.name = "StatsPanel"
	panel.custom_minimum_size = Vector2(180, 400)

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	style.border_color = Color(0.3, 0.5, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.name = "StatsContainer"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	vbox.offset_left = 10
	vbox.offset_top = 10
	vbox.offset_right = -10
	vbox.offset_bottom = -10
	panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "CHARACTER"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Stats
	var stats = [
		{"name": "Health", "icon": "health"},
		{"name": "Armor", "icon": "armor"},
		{"name": "Damage", "icon": "damage"},
		{"name": "Crit %", "icon": "crit"},
		{"name": "Speed", "icon": "speed"},
	]

	for stat in stats:
		var hbox = HBoxContainer.new()

		var label = Label.new()
		label.text = stat.name + ":"
		label.custom_minimum_size = Vector2(80, 0)
		label.add_theme_font_size_override("font_size", 13)
		hbox.add_child(label)

		var value = Label.new()
		value.name = stat.name.replace(" ", "").replace("%", "") + "Value"
		value.text = "0"
		value.add_theme_font_size_override("font_size", 13)
		value.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		hbox.add_child(value)

		vbox.add_child(hbox)

	vbox.add_child(HSeparator.new())

	# Currency section
	var currency_title = Label.new()
	currency_title.text = "CURRENCY"
	currency_title.add_theme_font_size_override("font_size", 14)
	currency_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vbox.add_child(currency_title)

	var currencies = ["Sigils", "Scrap", "Coins"]
	for curr in currencies:
		var hbox = HBoxContainer.new()

		var label = Label.new()
		label.text = curr + ":"
		label.custom_minimum_size = Vector2(60, 0)
		label.add_theme_font_size_override("font_size", 12)
		hbox.add_child(label)

		var value = Label.new()
		value.name = curr + "Value"
		value.text = "0"
		value.add_theme_font_size_override("font_size", 12)
		value.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		hbox.add_child(value)

		vbox.add_child(hbox)

	return panel

func _create_drag_preview() -> Control:
	var preview = Control.new()
	preview.name = "DragPreview"
	preview.visible = false
	preview.z_index = 100
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.2, 0.4, 0.6, 0.6)
	preview.add_child(bg)

	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(icon)

	return preview

func _create_tooltip_panel() -> Panel:
	var panel = Panel.new()
	panel.name = "ItemTooltip"
	panel.custom_minimum_size = Vector2(250, 180)
	panel.visible = false
	panel.z_index = 101

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	style.border_color = Color(0.4, 0.4, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.name = "Content"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	vbox.offset_left = 10
	vbox.offset_top = 10
	vbox.offset_right = -10
	vbox.offset_bottom = -10
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

	# Size indicator
	var size_label = Label.new()
	size_label.name = "SizeLabel"
	size_label.add_theme_font_size_override("font_size", 10)
	size_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	vbox.add_child(size_label)

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
	desc_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(desc_label)

	# Hints
	var hint_label = Label.new()
	hint_label.name = "HintLabel"
	hint_label.text = "[LMB] Move  |  [R] Rotate  |  [RMB] Use"
	hint_label.add_theme_font_size_override("font_size", 9)
	hint_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	vbox.add_child(hint_label)

	return panel

# ============================================
# INPUT HANDLING
# ============================================

func _input(event):
	if event.is_action_pressed("inventory"):
		toggle()
		get_viewport().set_input_as_handled()

	if not is_open:
		return

	if event.is_action_pressed("ui_cancel"):
		if dragging:
			_cancel_drag()
		else:
			close()
		get_viewport().set_input_as_handled()

	# Rotate item while dragging
	if dragging and event.is_action_pressed("reload"):  # R key
		_rotate_drag_item()
		get_viewport().set_input_as_handled()

	# Update drag preview position
	if dragging and event is InputEventMouseMotion:
		drag_preview.global_position = event.global_position - drag_offset

func _on_cell_mouse_entered(cell: Panel, x: int, y: int):
	if dragging:
		_highlight_placement(x, y)
	else:
		_show_item_at_cell(x, y)

	# Highlight cell
	var style = cell.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.bg_color = Color(0.25, 0.25, 0.3, 0.9)
	cell.add_theme_stylebox_override("panel", style)

func _on_cell_mouse_exited(cell: Panel):
	# Reset cell style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.18, 0.8)
	style.border_color = Color(0.25, 0.25, 0.3)
	style.set_border_width_all(1)
	cell.add_theme_stylebox_override("panel", style)

	if not dragging:
		_hide_tooltip()

func _on_cell_gui_input(event: InputEvent, cell: Panel, x: int, y: int):
	if not grid_inventory:
		return

	if event is InputEventMouseButton and event.pressed:
		var grid_pos = Vector2i(x, y)

		if event.button_index == MOUSE_BUTTON_LEFT:
			if dragging:
				# Try to place item
				_try_place_drag_item(grid_pos)
			else:
				# Start dragging item
				var item_entry = grid_inventory.get_item_at(grid_pos)
				if not item_entry.is_empty():
					_start_drag(item_entry, grid_pos, false)

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Use/equip item
			var item_entry = grid_inventory.get_item_at(grid_pos)
			if not item_entry.is_empty():
				_use_item(item_entry)

func _on_equipment_slot_input(event: InputEvent, slot: Panel, slot_id: String):
	if not grid_inventory:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var equipped = grid_inventory.get_equipped(slot_id)
		if equipped:
			# Unequip
			grid_inventory.unequip_item(slot_id)
			_refresh_display()
		elif dragging:
			# Try to equip dragged item
			if grid_inventory.equip_item(drag_item.item, slot_id):
				_end_drag()
				_refresh_display()

func _on_equipment_slot_hover(slot: Panel, slot_id: String):
	if not grid_inventory:
		return

	var equipped = grid_inventory.get_equipped(slot_id)
	if equipped:
		_show_tooltip(equipped, slot.global_position)

# ============================================
# DRAG AND DROP
# ============================================

func _start_drag(item_entry: Dictionary, from_pos: Vector2i, from_stash: bool):
	dragging = true
	drag_item = item_entry.duplicate()
	drag_from_stash = from_stash

	# Remove from grid temporarily
	grid_inventory.remove_item_at(from_pos, from_stash)

	# Setup preview
	var size = GridInventorySystem.get_item_size(drag_item.item)
	if drag_item.rotated:
		size = Vector2i(size.y, size.x)

	drag_preview.size = Vector2(size.x * CELL_SIZE, size.y * CELL_SIZE)
	var bg = drag_preview.get_node("Background") as ColorRect
	bg.size = drag_preview.size

	var icon = drag_preview.get_node("Icon") as TextureRect
	icon.size = drag_preview.size
	if drag_item.item and "icon" in drag_item.item:
		icon.texture = drag_item.item.icon

	drag_offset = Vector2(size.x * CELL_SIZE / 2, size.y * CELL_SIZE / 2)
	drag_preview.global_position = get_global_mouse_position() - drag_offset
	drag_preview.visible = true

	_hide_tooltip()
	_refresh_display()

func _try_place_drag_item(grid_pos: Vector2i):
	if not grid_inventory:
		return

	if grid_inventory.place_item(drag_item.item, grid_pos, drag_item.rotated, drag_item.quantity, false):
		_end_drag()
		_refresh_display()
	# Item snaps back if placement fails (handled by cancel)

func _rotate_drag_item():
	if not drag_item.is_empty():
		drag_item.rotated = not drag_item.rotated

		# Update preview size
		var size = GridInventorySystem.get_item_size(drag_item.item)
		if drag_item.rotated:
			size = Vector2i(size.y, size.x)

		drag_preview.size = Vector2(size.x * CELL_SIZE, size.y * CELL_SIZE)
		var bg = drag_preview.get_node("Background") as ColorRect
		bg.size = drag_preview.size
		var icon = drag_preview.get_node("Icon") as TextureRect
		icon.size = drag_preview.size
		drag_offset = Vector2(size.x * CELL_SIZE / 2, size.y * CELL_SIZE / 2)

func _cancel_drag():
	if drag_item.is_empty():
		return

	# Put item back where it was
	var placed = grid_inventory.add_item(drag_item.item, drag_item.quantity, drag_from_stash)
	if not placed:
		push_warning("Failed to return dragged item to inventory")

	_end_drag()
	_refresh_display()

func _end_drag():
	dragging = false
	drag_item = {}
	drag_preview.visible = false

func _highlight_placement(x: int, y: int):
	if drag_item.is_empty():
		return

	var size = GridInventorySystem.get_item_size(drag_item.item)
	if drag_item.rotated:
		size = Vector2i(size.y, size.x)

	var can_place = grid_inventory.can_place_item(drag_item.item, Vector2i(x, y), drag_item.rotated, false)
	var color = Color(0.2, 0.6, 0.2, 0.5) if can_place else Color(0.6, 0.2, 0.2, 0.5)

	# Highlight affected cells
	for dy in range(size.y):
		for dx in range(size.x):
			var cx = x + dx
			var cy = y + dy
			if cy < grid_cells.size() and cx < grid_cells[cy].size():
				var cell = grid_cells[cy][cx] as Panel
				var style = cell.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
				style.bg_color = color
				cell.add_theme_stylebox_override("panel", style)

# ============================================
# ITEM INTERACTIONS
# ============================================

func _use_item(item_entry: Dictionary):
	var item = item_entry.item
	if not item:
		return

	var item_type = item.item_type if "item_type" in item else -1

	# Equippable items
	if item_type in [
		ItemDataExtended.ItemType.WEAPON,
		ItemDataExtended.ItemType.HELMET,
		ItemDataExtended.ItemType.CHEST_ARMOR,
		ItemDataExtended.ItemType.GLOVES,
		ItemDataExtended.ItemType.BOOTS,
		ItemDataExtended.ItemType.RING,
		ItemDataExtended.ItemType.AMULET
	]:
		grid_inventory.equip_item(item)
		_refresh_display()

	# Consumables
	elif item_type == ItemDataExtended.ItemType.CONSUMABLE:
		_consume_item(item_entry)

func _consume_item(item_entry: Dictionary):
	var item = item_entry.item
	if not item:
		return

	# Apply consumable effect
	var player = get_tree().get_first_node_in_group("player")
	if player:
		if "health_restore" in item and item.health_restore > 0:
			if player.has_method("heal"):
				player.heal(item.health_restore)
		if "stamina_restore" in item and item.stamina_restore > 0:
			if "current_stamina" in player and "max_stamina" in player:
				player.current_stamina = min(player.current_stamina + item.stamina_restore, player.max_stamina)

	# Remove consumed item
	grid_inventory.remove_item_at(item_entry.position, false)
	_refresh_display()

# ============================================
# DISPLAY
# ============================================

func _refresh_display():
	if not grid_inventory or not is_open:
		return

	_clear_item_displays()
	_draw_items()
	_refresh_equipment()
	_refresh_stats()
	_refresh_weight()

func _clear_item_displays():
	# Clear grid cell item overlays
	var grid_container = grid_panel.get_node_or_null("GridContainer")
	if not grid_container:
		for child in grid_panel.get_children():
			if child is VBoxContainer:
				grid_container = child.get_node_or_null("GridContainer")
				break

	if grid_container:
		for child in grid_container.get_children():
			if child.name.begins_with("ItemDisplay"):
				child.queue_free()

func _draw_items():
	if not grid_inventory:
		return

	var grid_container: Control = null
	for child in grid_panel.get_children():
		if child is VBoxContainer:
			grid_container = child.get_node_or_null("GridContainer")
			break

	if not grid_container:
		return

	var items = grid_inventory.get_all_items(false)
	for entry in items:
		var item = entry.item
		var pos = entry.position as Vector2i
		var rotated = entry.rotated as bool
		var quantity = entry.quantity as int

		var size = GridInventorySystem.get_item_size(item)
		if rotated:
			size = Vector2i(size.y, size.x)

		# Create item display
		var display = _create_item_display(item, size, quantity)
		display.name = "ItemDisplay_%d_%d" % [pos.x, pos.y]
		display.position = Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
		display.set_meta("item_entry", entry)
		grid_container.add_child(display)

func _create_item_display(item: Resource, size: Vector2i, quantity: int) -> Control:
	var display = Panel.new()
	display.custom_minimum_size = Vector2(size.x * CELL_SIZE - 2, size.y * CELL_SIZE - 2)
	display.size = display.custom_minimum_size

	# Get rarity color
	var rarity = item.rarity if "rarity" in item else 0
	var rarity_color = RARITY_COLORS.get(rarity, RARITY_COLORS[0])

	# Style with rarity border
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	style.border_color = rarity_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	display.add_theme_stylebox_override("panel", style)

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
	if item and "icon" in item:
		icon.texture = item.icon
	display.add_child(icon)

	# Quantity label (for stackable items)
	if quantity > 1:
		var count_label = Label.new()
		count_label.text = str(quantity)
		count_label.add_theme_font_size_override("font_size", 11)
		count_label.add_theme_color_override("font_color", Color.WHITE)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		count_label.offset_left = -30
		count_label.offset_top = -18
		count_label.offset_right = -4
		count_label.offset_bottom = -2
		display.add_child(count_label)

	# Rarity indicator bar
	var rarity_bar = ColorRect.new()
	rarity_bar.color = rarity_color
	rarity_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	rarity_bar.offset_top = -4
	display.add_child(rarity_bar)

	return display

func _refresh_equipment():
	if not grid_inventory:
		return

	for slot_id in equipment_slots:
		var slot = equipment_slots[slot_id] as Panel
		var icon = slot.get_node_or_null("Icon") as TextureRect
		var equipped = grid_inventory.get_equipped(slot_id)

		if icon:
			if equipped and "icon" in equipped:
				icon.texture = equipped.icon
			else:
				icon.texture = null

		# Update border color based on equipped item rarity
		var style = slot.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		if equipped and "rarity" in equipped:
			var rarity_color = RARITY_COLORS.get(equipped.rarity, RARITY_COLORS[0])
			style.border_color = rarity_color
		else:
			style.border_color = Color(0.4, 0.4, 0.5)
		slot.add_theme_stylebox_override("panel", style)

func _refresh_stats():
	if not stats_panel:
		return

	var stats_container = stats_panel.get_node_or_null("StatsContainer")
	if not stats_container:
		return

	# Calculate stats from equipment
	var stats = {
		"Health": 100,
		"Armor": 0,
		"Damage": 10,
		"Crit": 5,
		"Speed": 100
	}

	if grid_inventory:
		for slot_id in grid_inventory.equipment:
			var item = grid_inventory.equipment[slot_id]
			if not item:
				continue

			if "health_bonus" in item:
				stats["Health"] += item.health_bonus
			if "armor_value" in item:
				stats["Armor"] += item.armor_value
			if "damage" in item:
				stats["Damage"] += item.damage
			if "crit_chance_bonus" in item:
				stats["Crit"] += item.crit_chance_bonus
			if "movement_speed_bonus" in item:
				stats["Speed"] += item.movement_speed_bonus

	# Update labels
	for child in stats_container.get_children():
		if child is HBoxContainer:
			for label in child.get_children():
				if label is Label and label.name.ends_with("Value"):
					var stat_name = label.name.replace("Value", "")
					if stats.has(stat_name):
						var value = stats[stat_name]
						if stat_name == "Crit":
							label.text = "%.1f%%" % value
						else:
							label.text = str(int(value))

func _refresh_weight():
	var weight_label = grid_panel.get_node_or_null("WeightLabel")
	if not weight_label:
		# Search in children
		for child in grid_panel.get_children():
			if child is VBoxContainer:
				for c2 in child.get_children():
					if c2 is HBoxContainer:
						weight_label = c2.get_node_or_null("WeightLabel")
						if weight_label:
							break

	if weight_label and grid_inventory:
		var info = grid_inventory.get_weight_info()
		weight_label.text = "Weight: %.1f / %.1f" % [info.current, info.max]

		# Color code
		if info.percent >= 1.0:
			weight_label.add_theme_color_override("font_color", Color.RED)
		elif info.percent >= 0.8:
			weight_label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			weight_label.add_theme_color_override("font_color", Color.WHITE)

# ============================================
# TOOLTIP
# ============================================

func _show_item_at_cell(x: int, y: int):
	if not grid_inventory:
		return

	var item_entry = grid_inventory.get_item_at(Vector2i(x, y))
	if not item_entry.is_empty():
		var cell = grid_cells[y][x] if y < grid_cells.size() and x < grid_cells[y].size() else null
		if cell:
			_show_tooltip(item_entry.item, cell.global_position)

func _show_tooltip(item: Resource, position: Vector2):
	if not item or not item_tooltip:
		return

	var content = item_tooltip.get_node_or_null("Content")
	if not content:
		return

	# Update content
	var name_label = content.get_node_or_null("NameLabel") as RichTextLabel
	var type_label = content.get_node_or_null("TypeLabel") as Label
	var size_label = content.get_node_or_null("SizeLabel") as Label
	var stats_label = content.get_node_or_null("StatsLabel") as RichTextLabel
	var desc_label = content.get_node_or_null("DescLabel") as Label

	if name_label:
		var rarity = item.rarity if "rarity" in item else 0
		var color = RARITY_COLORS.get(rarity, RARITY_COLORS[0])
		var item_name = item.item_name if "item_name" in item else "Unknown"
		name_label.text = "[b][color=#%s]%s[/color][/b]" % [color.to_html(), item_name]

	if type_label:
		var rarity_name = _get_rarity_name(item.rarity if "rarity" in item else 0)
		var type_name = _get_item_type_name(item.item_type if "item_type" in item else 0)
		type_label.text = "%s %s" % [rarity_name, type_name]
		type_label.add_theme_color_override("font_color", RARITY_COLORS.get(item.rarity if "rarity" in item else 0, RARITY_COLORS[0]))

	if size_label:
		var size = GridInventorySystem.get_item_size(item)
		size_label.text = "Size: %dx%d" % [size.x, size.y]

	if stats_label:
		var stats_text = ""
		if "damage" in item and item.damage > 0:
			stats_text += "[color=red]Damage: %.1f[/color]\n" % item.damage
		if "fire_rate" in item and item.fire_rate > 0:
			stats_text += "Fire Rate: %.2f/s\n" % (1.0 / max(item.fire_rate, 0.01))
		if "magazine_size" in item and item.magazine_size > 0:
			stats_text += "Magazine: %d\n" % item.magazine_size
		if "armor_value" in item and item.armor_value > 0:
			stats_text += "[color=cyan]Armor: %.1f[/color]\n" % item.armor_value
		if "health_bonus" in item and item.health_bonus > 0:
			stats_text += "[color=lime]+%.0f Health[/color]\n" % item.health_bonus
		if "crit_chance_bonus" in item and item.crit_chance_bonus > 0:
			stats_text += "[color=yellow]+%.1f%% Crit Chance[/color]\n" % item.crit_chance_bonus
		stats_label.text = stats_text

	if desc_label:
		var description = item.description if "description" in item else ""
		desc_label.text = description
		desc_label.visible = description != ""

	# Position tooltip
	item_tooltip.global_position = position + Vector2(CELL_SIZE + 10, 0)

	# Clamp to screen
	var screen_size = get_viewport().get_visible_rect().size
	if item_tooltip.global_position.x + item_tooltip.size.x > screen_size.x:
		item_tooltip.global_position.x = position.x - item_tooltip.size.x - 10
	if item_tooltip.global_position.y + item_tooltip.size.y > screen_size.y:
		item_tooltip.global_position.y = screen_size.y - item_tooltip.size.y - 10

	item_tooltip.visible = true

func _hide_tooltip():
	if item_tooltip:
		item_tooltip.visible = false

func _get_rarity_name(rarity: int) -> String:
	match rarity:
		0: return "Common"
		1: return "Uncommon"
		2: return "Rare"
		3: return "Epic"
		4: return "Legendary"
		5: return "Mythic"
		_: return "Unknown"

func _get_item_type_name(item_type: int) -> String:
	match item_type:
		ItemDataExtended.ItemType.WEAPON: return "Weapon"
		ItemDataExtended.ItemType.AMMO: return "Ammo"
		ItemDataExtended.ItemType.HELMET: return "Helmet"
		ItemDataExtended.ItemType.CHEST_ARMOR: return "Chest Armor"
		ItemDataExtended.ItemType.GLOVES: return "Gloves"
		ItemDataExtended.ItemType.BOOTS: return "Boots"
		ItemDataExtended.ItemType.RING: return "Ring"
		ItemDataExtended.ItemType.AMULET: return "Amulet"
		ItemDataExtended.ItemType.CONSUMABLE: return "Consumable"
		ItemDataExtended.ItemType.MATERIAL: return "Material"
		ItemDataExtended.ItemType.AUGMENT: return "Augment"
		_: return "Item"

# ============================================
# OPEN/CLOSE
# ============================================

func toggle():
	if is_open:
		close()
	else:
		open()

func open():
	is_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	inventory_opened.emit()
	_refresh_display()
	_animate_open()

func close():
	if dragging:
		_cancel_drag()

	is_open = false
	_animate_close()
	await get_tree().create_timer(0.25).timeout
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	inventory_closed.emit()

func _animate_open():
	modulate.a = 0
	scale = Vector2(0.9, 0.9)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.25)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _animate_close():
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_property(self, "scale", Vector2(0.95, 0.95), 0.2)
