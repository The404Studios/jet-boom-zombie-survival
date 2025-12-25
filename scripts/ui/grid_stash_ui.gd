extends Control
class_name GridStashUI

# Grid-based stash UI with larger grid storage
# Allows transfer between inventory and stash with drag-drop

@export var grid_inventory: GridInventorySystem

# UI panels
var stash_panel: Panel
var inventory_panel: Panel
var currency_panel: Panel
var tooltip_panel: Panel
var drag_preview: Control

# Grid configuration
const CELL_SIZE: int = 45
const PADDING: int = 10
const RARITY_COLORS: Dictionary = {
	0: Color(0.6, 0.6, 0.6),
	1: Color(0.2, 0.8, 0.2),
	2: Color(0.2, 0.4, 1.0),
	3: Color(0.6, 0.2, 0.8),
	4: Color(1.0, 0.6, 0.0),
	5: Color(1.0, 0.2, 0.2),
}

# State
var is_open: bool = false
var stash_cells: Array = []
var inventory_cells: Array = []
var dragging: bool = false
var drag_item: Dictionary = {}
var drag_from_stash: bool = false
var drag_offset: Vector2 = Vector2.ZERO

signal stash_opened
signal stash_closed
signal item_transferred

func _ready():
	visible = false
	_create_ui()

	await get_tree().create_timer(0.1).timeout
	_find_inventory_system()

	if grid_inventory:
		grid_inventory.inventory_changed.connect(_refresh_all)

func _find_inventory_system():
	if grid_inventory:
		return

	var player = get_tree().get_first_node_in_group("player")
	if player and "grid_inventory" in player:
		grid_inventory = player.grid_inventory
		return

	# Find existing system
	grid_inventory = get_tree().get_first_node_in_group("grid_inventory")
	if grid_inventory:
		return

	# Create new if needed
	grid_inventory = GridInventorySystem.new()
	grid_inventory.name = "GridInventorySystem"
	add_child(grid_inventory)

func _create_ui():
	# Background overlay
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# Main container
	var main = HBoxContainer.new()
	main.name = "MainContainer"
	main.set_anchors_preset(Control.PRESET_CENTER)
	main.add_theme_constant_override("separation", 30)
	add_child(main)

	# Stash panel (left - larger)
	stash_panel = _create_stash_panel()
	main.add_child(stash_panel)

	# Center divider with currency
	currency_panel = _create_currency_panel()
	main.add_child(currency_panel)

	# Inventory panel (right - smaller)
	inventory_panel = _create_inventory_panel()
	main.add_child(inventory_panel)

	# Drag preview
	drag_preview = _create_drag_preview()
	add_child(drag_preview)

	# Tooltip
	tooltip_panel = _create_tooltip()
	add_child(tooltip_panel)

func _create_stash_panel() -> Panel:
	var panel = Panel.new()
	panel.name = "StashPanel"

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.12, 0.98)
	style.border_color = Color(0.4, 0.6, 0.8)
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
	title.text = "STASH"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	header.add_child(title)

	header.add_spacer(false)

	var slots_label = Label.new()
	slots_label.name = "SlotsLabel"
	slots_label.text = "120 slots"
	slots_label.add_theme_font_size_override("font_size", 14)
	slots_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
	header.add_child(slots_label)

	# Grid container with scroll
	var scroll = ScrollContainer.new()
	scroll.name = "StashScroll"
	scroll.custom_minimum_size = Vector2(
		GridInventorySystem.new().stash_width * CELL_SIZE + 20,
		GridInventorySystem.new().stash_height * CELL_SIZE
	)
	vbox.add_child(scroll)

	var grid_container = Control.new()
	grid_container.name = "StashGridContainer"
	var stash_width = 12
	var stash_height = 10
	grid_container.custom_minimum_size = Vector2(stash_width * CELL_SIZE, stash_height * CELL_SIZE)
	scroll.add_child(grid_container)

	# Create cells
	_create_grid_cells(grid_container, stash_width, stash_height, true)

	panel.custom_minimum_size = Vector2(
		stash_width * CELL_SIZE + PADDING * 2 + 20,
		stash_height * CELL_SIZE + PADDING * 2 + 60
	)

	return panel

func _create_inventory_panel() -> Panel:
	var panel = Panel.new()
	panel.name = "InventoryPanel"

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.12, 0.98)
	style.border_color = Color(0.6, 0.5, 0.3)
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
	title.text = "INVENTORY"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	header.add_child(title)

	header.add_spacer(false)

	var weight_label = Label.new()
	weight_label.name = "WeightLabel"
	weight_label.text = "0 / 50"
	weight_label.add_theme_font_size_override("font_size", 14)
	header.add_child(weight_label)

	# Grid container
	var grid_container = Control.new()
	grid_container.name = "InventoryGridContainer"
	var inv_width = GridInventorySystem.BASE_GRID_WIDTH
	var inv_height = GridInventorySystem.BASE_GRID_HEIGHT
	grid_container.custom_minimum_size = Vector2(inv_width * CELL_SIZE, inv_height * CELL_SIZE)
	vbox.add_child(grid_container)

	# Create cells
	_create_grid_cells(grid_container, inv_width, inv_height, false)

	panel.custom_minimum_size = Vector2(
		inv_width * CELL_SIZE + PADDING * 2,
		inv_height * CELL_SIZE + PADDING * 2 + 50
	)

	return panel

func _create_currency_panel() -> Panel:
	var panel = Panel.new()
	panel.name = "CurrencyPanel"
	panel.custom_minimum_size = Vector2(150, 200)

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.14, 0.95)
	style.border_color = Color(0.5, 0.5, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 15)
	vbox.offset_left = 15
	vbox.offset_top = 15
	vbox.offset_right = -15
	vbox.offset_bottom = -15
	panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "CURRENCY"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Currencies
	var currencies = [
		{"name": "Sigils", "color": Color(0.4, 0.7, 1.0)},
		{"name": "Scrap", "color": Color(0.7, 0.5, 0.3)},
		{"name": "Coins", "color": Color(1.0, 0.85, 0.3)},
		{"name": "Tokens", "color": Color(0.8, 0.4, 0.8)},
	]

	for curr in currencies:
		var hbox = HBoxContainer.new()

		var icon = ColorRect.new()
		icon.custom_minimum_size = Vector2(16, 16)
		icon.color = curr.color
		hbox.add_child(icon)

		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(8, 0)
		hbox.add_child(spacer)

		var label = Label.new()
		label.text = curr.name + ":"
		label.custom_minimum_size = Vector2(60, 0)
		label.add_theme_font_size_override("font_size", 13)
		hbox.add_child(label)

		var value = Label.new()
		value.name = curr.name + "Value"
		value.text = "0"
		value.add_theme_font_size_override("font_size", 13)
		value.add_theme_color_override("font_color", curr.color)
		hbox.add_child(value)

		vbox.add_child(hbox)

	vbox.add_child(HSeparator.new())

	# Transfer buttons
	var btn_to_stash = Button.new()
	btn_to_stash.text = "All to Stash"
	btn_to_stash.pressed.connect(_transfer_all_to_stash)
	vbox.add_child(btn_to_stash)

	# Hints
	var hint = Label.new()
	hint.text = "[LMB] Drag\n[RMB] Quick Move\n[R] Rotate"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	vbox.add_child(hint)

	return panel

func _create_grid_cells(container: Control, width: int, height: int, is_stash: bool):
	var cells_array = stash_cells if is_stash else inventory_cells
	cells_array.clear()

	for y in range(height):
		var row = []
		for x in range(width):
			var cell = _create_cell(x, y, is_stash)
			cell.position = Vector2(x * CELL_SIZE, y * CELL_SIZE)
			container.add_child(cell)
			row.append(cell)
		cells_array.append(row)

func _create_cell(x: int, y: int, is_stash: bool) -> Panel:
	var cell = Panel.new()
	cell.name = "Cell_%d_%d" % [x, y]
	cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	cell.size = Vector2(CELL_SIZE, CELL_SIZE)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.8) if is_stash else Color(0.15, 0.13, 0.1, 0.8)
	style.border_color = Color(0.2, 0.22, 0.25)
	style.set_border_width_all(1)
	cell.add_theme_stylebox_override("panel", style)

	cell.set_meta("grid_pos", Vector2i(x, y))
	cell.set_meta("is_stash", is_stash)

	cell.mouse_entered.connect(_on_cell_hover.bind(cell, x, y, is_stash))
	cell.mouse_exited.connect(_on_cell_exit.bind(cell))
	cell.gui_input.connect(_on_cell_input.bind(cell, x, y, is_stash))

	return cell

func _create_drag_preview() -> Control:
	var preview = Control.new()
	preview.name = "DragPreview"
	preview.visible = false
	preview.z_index = 100
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.3, 0.5, 0.7, 0.6)
	preview.add_child(bg)

	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(icon)

	return preview

func _create_tooltip() -> Panel:
	var panel = Panel.new()
	panel.name = "Tooltip"
	panel.custom_minimum_size = Vector2(220, 150)
	panel.visible = false
	panel.z_index = 101

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.98)
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

	var name_label = RichTextLabel.new()
	name_label.name = "NameLabel"
	name_label.bbcode_enabled = true
	name_label.fit_content = true
	name_label.scroll_active = false
	vbox.add_child(name_label)

	var type_label = Label.new()
	type_label.name = "TypeLabel"
	type_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(type_label)

	var size_label = Label.new()
	size_label.name = "SizeLabel"
	size_label.add_theme_font_size_override("font_size", 10)
	size_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	vbox.add_child(size_label)

	vbox.add_child(HSeparator.new())

	var stats_label = RichTextLabel.new()
	stats_label.name = "StatsLabel"
	stats_label.bbcode_enabled = true
	stats_label.fit_content = true
	stats_label.scroll_active = false
	vbox.add_child(stats_label)

	return panel

# ============================================
# INPUT
# ============================================

func _input(event):
	if not is_open:
		return

	if event.is_action_pressed("ui_cancel"):
		if dragging:
			_cancel_drag()
		else:
			close()
		get_viewport().set_input_as_handled()

	if dragging and event.is_action_pressed("reload"):
		_rotate_drag_item()
		get_viewport().set_input_as_handled()

	if dragging and event is InputEventMouseMotion:
		drag_preview.global_position = event.global_position - drag_offset

func _on_cell_hover(cell: Panel, x: int, y: int, is_stash: bool):
	if dragging:
		_highlight_drop_zone(x, y, is_stash)
	else:
		_show_item_tooltip(x, y, is_stash, cell)

	# Highlight cell
	var style = cell.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.bg_color = Color(0.25, 0.25, 0.3, 0.9)
	cell.add_theme_stylebox_override("panel", style)

func _on_cell_exit(cell: Panel):
	var is_stash = cell.get_meta("is_stash")
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.8) if is_stash else Color(0.15, 0.13, 0.1, 0.8)
	style.border_color = Color(0.2, 0.22, 0.25)
	style.set_border_width_all(1)
	cell.add_theme_stylebox_override("panel", style)

	if not dragging:
		_hide_tooltip()

func _on_cell_input(event: InputEvent, cell: Panel, x: int, y: int, is_stash: bool):
	if not grid_inventory:
		return

	if event is InputEventMouseButton and event.pressed:
		var pos = Vector2i(x, y)

		if event.button_index == MOUSE_BUTTON_LEFT:
			if dragging:
				_try_place_item(pos, is_stash)
			else:
				var item_entry = grid_inventory.get_item_at(pos, is_stash)
				if not item_entry.is_empty():
					_start_drag(item_entry, pos, is_stash)

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Quick transfer
			var item_entry = grid_inventory.get_item_at(pos, is_stash)
			if not item_entry.is_empty():
				_quick_transfer(item_entry, pos, is_stash)

# ============================================
# DRAG AND DROP
# ============================================

func _start_drag(item_entry: Dictionary, from_pos: Vector2i, from_stash: bool):
	dragging = true
	drag_item = item_entry.duplicate()
	drag_from_stash = from_stash

	grid_inventory.remove_item_at(from_pos, from_stash)

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
	_refresh_all()

func _try_place_item(grid_pos: Vector2i, to_stash: bool):
	if grid_inventory.place_item(drag_item.item, grid_pos, drag_item.rotated, drag_item.quantity, to_stash):
		_end_drag()
		item_transferred.emit()
		_refresh_all()

func _rotate_drag_item():
	if drag_item.is_empty():
		return

	drag_item.rotated = not drag_item.rotated
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

	grid_inventory.add_item(drag_item.item, drag_item.quantity, drag_from_stash)
	_end_drag()
	_refresh_all()

func _end_drag():
	dragging = false
	drag_item = {}
	drag_preview.visible = false

func _highlight_drop_zone(x: int, y: int, is_stash: bool):
	if drag_item.is_empty():
		return

	var size = GridInventorySystem.get_item_size(drag_item.item)
	if drag_item.rotated:
		size = Vector2i(size.y, size.x)

	var can_place = grid_inventory.can_place_item(drag_item.item, Vector2i(x, y), drag_item.rotated, is_stash)
	var color = Color(0.2, 0.6, 0.2, 0.5) if can_place else Color(0.6, 0.2, 0.2, 0.5)

	var cells = stash_cells if is_stash else inventory_cells

	for dy in range(size.y):
		for dx in range(size.x):
			var cy = y + dy
			var cx = x + dx
			if cy < cells.size() and cx < cells[cy].size():
				var cell = cells[cy][cx] as Panel
				var style = cell.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
				style.bg_color = color
				cell.add_theme_stylebox_override("panel", style)

func _quick_transfer(item_entry: Dictionary, from_pos: Vector2i, from_stash: bool):
	"""Transfer item to the other storage"""
	var to_stash = not from_stash

	# Remove from source
	grid_inventory.remove_item_at(from_pos, from_stash)

	# Try to add to destination
	if grid_inventory.add_item(item_entry.item, item_entry.quantity, to_stash):
		item_transferred.emit()
		_animate_transfer(from_stash)
	else:
		# Put it back
		grid_inventory.place_item(item_entry.item, from_pos, item_entry.rotated, item_entry.quantity, from_stash)

	_refresh_all()

func _transfer_all_to_stash():
	if not grid_inventory:
		return

	var items_to_transfer = grid_inventory.get_all_items(false)
	for entry in items_to_transfer:
		grid_inventory.remove_item_at(entry.position, false)
		if not grid_inventory.add_item(entry.item, entry.quantity, true):
			# Put back if stash is full
			grid_inventory.add_item(entry.item, entry.quantity, false)

	item_transferred.emit()
	_refresh_all()

func _animate_transfer(to_inventory: bool):
	var label = Label.new()
	label.text = ">>>" if to_inventory else "<<<"
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	label.position = currency_panel.position + currency_panel.size / 2
	add_child(label)

	var tween = create_tween()
	tween.tween_property(label, "position:y", label.position.y - 40, 0.4)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.4)
	await tween.finished
	label.queue_free()

# ============================================
# DISPLAY
# ============================================

func _refresh_all():
	if not grid_inventory or not is_open:
		return

	_clear_displays()
	_draw_stash_items()
	_draw_inventory_items()
	_refresh_currency()
	_refresh_weight()

func _clear_displays():
	# Clear stash displays
	var stash_container = stash_panel.get_node_or_null("StashScroll/StashGridContainer")
	if not stash_container:
		for child in stash_panel.get_children():
			if child is VBoxContainer:
				var scroll = child.get_node_or_null("StashScroll")
				if scroll:
					stash_container = scroll.get_node_or_null("StashGridContainer")
					break

	if stash_container:
		for child in stash_container.get_children():
			if child.name.begins_with("ItemDisplay"):
				child.queue_free()

	# Clear inventory displays
	var inv_container = inventory_panel.get_node_or_null("InventoryGridContainer")
	if not inv_container:
		for child in inventory_panel.get_children():
			if child is VBoxContainer:
				inv_container = child.get_node_or_null("InventoryGridContainer")
				break

	if inv_container:
		for child in inv_container.get_children():
			if child.name.begins_with("ItemDisplay"):
				child.queue_free()

func _draw_stash_items():
	var container = _get_stash_container()
	if not container:
		return

	var items = grid_inventory.get_all_items(true)
	for entry in items:
		_draw_item(container, entry, true)

func _draw_inventory_items():
	var container = _get_inventory_container()
	if not container:
		return

	var items = grid_inventory.get_all_items(false)
	for entry in items:
		_draw_item(container, entry, false)

func _draw_item(container: Control, entry: Dictionary, is_stash: bool):
	var item = entry.item
	var pos = entry.position as Vector2i
	var rotated = entry.rotated as bool
	var quantity = entry.quantity as int

	var size = GridInventorySystem.get_item_size(item)
	if rotated:
		size = Vector2i(size.y, size.x)

	var display = _create_item_display(item, size, quantity)
	display.name = "ItemDisplay_%d_%d" % [pos.x, pos.y]
	display.position = Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
	display.set_meta("item_entry", entry)
	display.set_meta("is_stash", is_stash)
	container.add_child(display)

func _create_item_display(item: Resource, size: Vector2i, quantity: int) -> Control:
	var display = Panel.new()
	display.custom_minimum_size = Vector2(size.x * CELL_SIZE - 2, size.y * CELL_SIZE - 2)
	display.size = display.custom_minimum_size

	var rarity = item.rarity if "rarity" in item else 0
	var rarity_color = RARITY_COLORS.get(rarity, RARITY_COLORS[0])

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	style.border_color = rarity_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	display.add_theme_stylebox_override("panel", style)

	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 3
	icon.offset_top = 3
	icon.offset_right = -3
	icon.offset_bottom = -3
	if item and "icon" in item:
		icon.texture = item.icon
	display.add_child(icon)

	if quantity > 1:
		var count = Label.new()
		count.text = str(quantity)
		count.add_theme_font_size_override("font_size", 10)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		count.offset_left = -25
		count.offset_top = -15
		count.offset_right = -2
		count.offset_bottom = -2
		display.add_child(count)

	var bar = ColorRect.new()
	bar.color = rarity_color
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -3
	display.add_child(bar)

	return display

func _get_stash_container() -> Control:
	for child in stash_panel.get_children():
		if child is VBoxContainer:
			var scroll = child.get_node_or_null("StashScroll")
			if scroll:
				return scroll.get_node_or_null("StashGridContainer")
	return null

func _get_inventory_container() -> Control:
	for child in inventory_panel.get_children():
		if child is VBoxContainer:
			return child.get_node_or_null("InventoryGridContainer")
	return null

func _refresh_currency():
	if not currency_panel:
		return

	# Get currency values from player persistence or sigil shop
	var sigils = 0
	var scrap = 0
	var coins = 0
	var tokens = 0

	var sigil_shop = get_tree().get_first_node_in_group("sigil_shop")
	if sigil_shop and "sigils" in sigil_shop:
		sigils = sigil_shop.sigils
	if sigil_shop and "scrap" in sigil_shop:
		scrap = sigil_shop.scrap

	var persistence = get_node_or_null("/root/PlayerPersistence")
	if persistence and persistence.has_method("get_currency"):
		coins = persistence.get_currency("coins")
		tokens = persistence.get_currency("tokens")

	# Update labels
	var content = currency_panel.get_node_or_null("VBoxContainer") if currency_panel.has_node("VBoxContainer") else null
	if not content:
		for child in currency_panel.get_children():
			if child is VBoxContainer:
				content = child
				break

	if content:
		var sigils_label = content.get_node_or_null("SigilsValue")
		var scrap_label = content.get_node_or_null("ScrapValue")
		var coins_label = content.get_node_or_null("CoinsValue")
		var tokens_label = content.get_node_or_null("TokensValue")

		# Search in HBoxContainers
		for child in content.get_children():
			if child is HBoxContainer:
				for c in child.get_children():
					if c is Label:
						if c.name == "SigilsValue":
							c.text = str(sigils)
						elif c.name == "ScrapValue":
							c.text = str(scrap)
						elif c.name == "CoinsValue":
							c.text = str(coins)
						elif c.name == "TokensValue":
							c.text = str(tokens)

func _refresh_weight():
	if not grid_inventory:
		return

	var info = grid_inventory.get_weight_info()
	var weight_label: Label = null

	for child in inventory_panel.get_children():
		if child is VBoxContainer:
			for c in child.get_children():
				if c is HBoxContainer:
					weight_label = c.get_node_or_null("WeightLabel")
					if weight_label:
						break

	if weight_label:
		weight_label.text = "%.1f / %.1f" % [info.current, info.max]
		if info.percent >= 1.0:
			weight_label.add_theme_color_override("font_color", Color.RED)
		elif info.percent >= 0.8:
			weight_label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			weight_label.add_theme_color_override("font_color", Color.WHITE)

# ============================================
# TOOLTIP
# ============================================

func _show_item_tooltip(x: int, y: int, is_stash: bool, cell: Panel):
	if not grid_inventory:
		return

	var item_entry = grid_inventory.get_item_at(Vector2i(x, y), is_stash)
	if item_entry.is_empty():
		return

	var item = item_entry.item
	var content = tooltip_panel.get_node_or_null("Content")
	if not content:
		return

	var name_label = content.get_node_or_null("NameLabel") as RichTextLabel
	var type_label = content.get_node_or_null("TypeLabel") as Label
	var size_label = content.get_node_or_null("SizeLabel") as Label
	var stats_label = content.get_node_or_null("StatsLabel") as RichTextLabel

	if name_label:
		var rarity = item.rarity if "rarity" in item else 0
		var color = RARITY_COLORS.get(rarity, RARITY_COLORS[0])
		var item_name = item.item_name if "item_name" in item else "Unknown"
		name_label.text = "[b][color=#%s]%s[/color][/b]" % [color.to_html(), item_name]

	if type_label:
		var rarity_names = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]
		var rarity = item.rarity if "rarity" in item else 0
		type_label.text = rarity_names[min(rarity, 5)]
		type_label.add_theme_color_override("font_color", RARITY_COLORS.get(rarity, RARITY_COLORS[0]))

	if size_label:
		var size = GridInventorySystem.get_item_size(item)
		size_label.text = "Size: %dx%d" % [size.x, size.y]

	if stats_label:
		var text = ""
		if "damage" in item and item.damage > 0:
			text += "[color=red]Damage: %.0f[/color]\n" % item.damage
		if "armor_value" in item and item.armor_value > 0:
			text += "[color=cyan]Armor: %.0f[/color]\n" % item.armor_value
		stats_label.text = text

	tooltip_panel.global_position = cell.global_position + Vector2(CELL_SIZE + 10, 0)
	var screen_size = get_viewport().get_visible_rect().size
	if tooltip_panel.global_position.x + tooltip_panel.size.x > screen_size.x:
		tooltip_panel.global_position.x = cell.global_position.x - tooltip_panel.size.x - 10

	tooltip_panel.visible = true

func _hide_tooltip():
	if tooltip_panel:
		tooltip_panel.visible = false

# ============================================
# OPEN/CLOSE
# ============================================

func open():
	is_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	stash_opened.emit()
	_refresh_all()
	_animate_open()

func close():
	if dragging:
		_cancel_drag()

	is_open = false
	_animate_close()
	await get_tree().create_timer(0.25).timeout
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	stash_closed.emit()

func _animate_open():
	modulate.a = 0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.2)

func _animate_close():
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
