extends Control
class_name InventoryUI

## Tarkov-style grid inventory UI
## Supports drag-and-drop, rotation, and equipment

signal item_selected(item: InventorySystem.InventoryItem)
signal item_used(item: InventorySystem.InventoryItem)

const CELL_SIZE: int = 48
const GRID_COLOR := Color(0.2, 0.2, 0.2, 0.8)
const CELL_BORDER_COLOR := Color(0.3, 0.3, 0.3, 1.0)
const VALID_DROP_COLOR := Color(0.2, 0.5, 0.2, 0.5)
const INVALID_DROP_COLOR := Color(0.5, 0.2, 0.2, 0.5)

# Rarity colors
const RARITY_COLORS = {
	0: Color(0.7, 0.7, 0.7),      # Common
	1: Color(0.2, 0.8, 0.2),      # Uncommon
	2: Color(0.2, 0.4, 0.9),      # Rare
	3: Color(0.7, 0.2, 0.9),      # Epic
	4: Color(1.0, 0.6, 0.0)       # Legendary
}

@onready var backpack_grid: Control = $MainPanel/BackpackPanel/BackpackGrid
@onready var stash_grid: Control = $MainPanel/StashPanel/StashGrid
@onready var equipment_panel: Control = $MainPanel/EquipmentPanel
@onready var item_tooltip: Control = $ItemTooltip
@onready var currency_label: Label = $MainPanel/CurrencyPanel/GoldLabel

var inventory_system: InventorySystem = null
var dragging_item: InventorySystem.InventoryItem = null
var drag_offset: Vector2 = Vector2.ZERO
var drag_visual: Control = null
var highlighted_cells: Array = []
var source_container_id: String = ""

# Equipment slot positions
var equipment_slots: Dictionary = {}

func _ready():
	inventory_system = get_node_or_null("/root/InventorySystem")
	if inventory_system:
		inventory_system.container_updated.connect(_on_container_updated)
		inventory_system.item_equipped.connect(_on_item_equipped)
		inventory_system.item_unequipped.connect(_on_item_unequipped)
		inventory_system.currency_changed.connect(_on_currency_changed)
	
	_setup_equipment_slots()
	_setup_grids()
	visible = false

func _setup_equipment_slots():
	var slots = {
		"head": Vector2(120, 20),
		"pendant": Vector2(200, 30),
		"cape": Vector2(230, 80),
		"chest": Vector2(120, 80),
		"hands": Vector2(20, 100),
		"ring_left": Vector2(50, 200),
		"ring_right": Vector2(200, 200),
		"pants": Vector2(120, 180),
		"feet": Vector2(120, 280),
		"weapon_primary": Vector2(280, 50),
		"weapon_secondary": Vector2(280, 160),
		"weapon_melee": Vector2(280, 260)
	}
	
	for slot_name in slots:
		var size = InventorySystem.EQUIPMENT_SLOTS.get(slot_name, Vector2i(2, 2))
		var slot = _create_equipment_slot(slot_name, size, slots[slot_name])
		equipment_panel.add_child(slot)
		equipment_slots[slot_name] = slot

func _create_equipment_slot(slot_name: String, size: Vector2i, pos: Vector2) -> Control:
	var slot = Panel.new()
	slot.name = slot_name
	slot.position = pos
	slot.custom_minimum_size = Vector2(size.x * CELL_SIZE, size.y * CELL_SIZE)
	slot.size = slot.custom_minimum_size
	
	var label = Label.new()
	label.name = "Label"
	label.text = slot_name.replace("_", " ").capitalize()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = slot.size
	slot.add_child(label)
	
	var icon = TextureRect.new()
	icon.name = "ItemIcon"
	icon.visible = false
	icon.size = slot.size
	slot.add_child(icon)
	
	return slot

func _setup_grids():
	_setup_grid(backpack_grid, "backpack", 10, 8)
	_setup_grid(stash_grid, "stash", 14, 10)

func _setup_grid(grid_control: Control, container_id: String, width: int, height: int):
	grid_control.custom_minimum_size = Vector2(width * CELL_SIZE, height * CELL_SIZE)
	grid_control.set_meta("container_id", container_id)
	grid_control.set_meta("width", width)
	grid_control.set_meta("height", height)

func toggle():
	visible = not visible
	if visible:
		refresh()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func refresh():
	if not inventory_system:
		return
	
	_draw_container_grid(backpack_grid, "backpack")
	_draw_container_grid(stash_grid, "stash")
	_update_equipment_display()
	_update_currency_display()

func _draw_container_grid(grid_control: Control, container_id: String):
	# Clear existing item visuals
	for child in grid_control.get_children():
		if child.name.begins_with("Item_"):
			child.queue_free()
	
	var container = inventory_system.get_container(container_id)
	if not container:
		return
	
	# Draw items
	for item in container.get_all_items():
		_create_item_visual(grid_control, item)

func _create_item_visual(grid_control: Control, item: InventorySystem.InventoryItem) -> Control:
	var visual = Panel.new()
	visual.name = "Item_%d" % item.instance_id
	
	var size = item.get_actual_size()
	visual.position = Vector2(item.grid_position.x * CELL_SIZE, item.grid_position.y * CELL_SIZE)
	visual.size = Vector2(size.x * CELL_SIZE, size.y * CELL_SIZE)
	
	# Rarity color border
	var rarity_color = RARITY_COLORS.get(item.rarity, Color.WHITE)
	visual.modulate = rarity_color
	
	# Item name label
	var label = Label.new()
	label.text = item.display_name
	label.size = visual.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	visual.add_child(label)
	
	# Stack count
	if item.current_stack > 1:
		var stack_label = Label.new()
		stack_label.text = "x%d" % item.current_stack
		stack_label.position = Vector2(visual.size.x - 30, visual.size.y - 20)
		visual.add_child(stack_label)
	
	visual.set_meta("item_instance_id", item.instance_id)
	visual.set_meta("container_id", item.container_id)
	
	grid_control.add_child(visual)
	return visual

func _update_equipment_display():
	if not inventory_system:
		return
	
	for slot_name in equipment_slots:
		var slot = equipment_slots[slot_name]
		var icon = slot.get_node_or_null("ItemIcon")
		var label = slot.get_node_or_null("Label")
		var item = inventory_system.get_equipped(slot_name)
		
		if item:
			if icon:
				icon.visible = true
			if label:
				label.text = item.display_name
		else:
			if icon:
				icon.visible = false
			if label:
				label.text = slot_name.replace("_", " ").capitalize()

func _update_currency_display():
	if inventory_system and currency_label:
		currency_label.text = "%d Gold" % inventory_system.get_currency("gold")

# ============================================
# INPUT HANDLING
# ============================================

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_drag(event.position)
			else:
				_end_drag(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_right_click(event.position)
	
	elif event is InputEventMouseMotion:
		if dragging_item:
			_update_drag(event.position)
		else:
			_update_tooltip(event.position)
	
	elif event is InputEventKey:
		if event.pressed and event.keycode == KEY_R and dragging_item:
			_rotate_dragged_item()

func _start_drag(pos: Vector2):
	var item = _get_item_at_position(pos)
	if not item:
		return
	
	dragging_item = item
	source_container_id = item.container_id
	drag_offset = pos - Vector2(item.grid_position.x * CELL_SIZE, item.grid_position.y * CELL_SIZE)
	
	# Create drag visual
	drag_visual = Panel.new()
	drag_visual.modulate = Color(1, 1, 1, 0.7)
	var size = item.get_actual_size()
	drag_visual.size = Vector2(size.x * CELL_SIZE, size.y * CELL_SIZE)
	add_child(drag_visual)

func _update_drag(pos: Vector2):
	if drag_visual:
		drag_visual.position = pos - drag_offset

func _end_drag(pos: Vector2):
	if not dragging_item:
		return
	
	var target_container_id = _get_container_at_position(pos)
	var grid_pos = _get_grid_position_at(pos, target_container_id)
	
	if target_container_id and grid_pos.x >= 0:
		inventory_system.move_item(dragging_item, target_container_id, grid_pos)
	
	# Cleanup
	if drag_visual:
		drag_visual.queue_free()
		drag_visual = null
	dragging_item = null
	source_container_id = ""
	
	refresh()

func _rotate_dragged_item():
	if dragging_item and inventory_system:
		dragging_item.rotate()
		if drag_visual:
			var size = dragging_item.get_actual_size()
			drag_visual.size = Vector2(size.x * CELL_SIZE, size.y * CELL_SIZE)

func _right_click(pos: Vector2):
	var item = _get_item_at_position(pos)
	if not item:
		return
	
	# Context menu or quick actions
	if item.item_type == InventorySystem.ItemType.CONSUMABLE:
		inventory_system.use_item(item)
		refresh()
	elif not item.equip_slot.is_empty():
		inventory_system.equip_item(item)
		refresh()

func _update_tooltip(pos: Vector2):
	var item = _get_item_at_position(pos)
	if item and item_tooltip:
		item_tooltip.visible = true
		item_tooltip.position = pos + Vector2(20, 20)
		_populate_tooltip(item)
	elif item_tooltip:
		item_tooltip.visible = false

func _populate_tooltip(item: InventorySystem.InventoryItem):
	# Update tooltip content
	var tooltip_label = item_tooltip.get_node_or_null("Label")
	if tooltip_label:
		var text = item.display_name + "\n"
		text += "Rarity: %s\n" % ["Common", "Uncommon", "Rare", "Epic", "Legendary"][item.rarity]
		if item.damage > 0:
			text += "Damage: %.0f\n" % item.damage
		if item.armor_value > 0:
			text += "Armor: %.0f\n" % item.armor_value
		for stat in item.stats:
			text += "%s: +%.2f\n" % [stat, item.stats[stat]]
		tooltip_label.text = text

# ============================================
# HELPERS
# ============================================

func _get_item_at_position(pos: Vector2) -> InventorySystem.InventoryItem:
	# Check backpack
	var bp_pos = backpack_grid.get_global_rect()
	if bp_pos.has_point(pos):
		var local_pos = pos - bp_pos.position
		var grid_pos = Vector2i(int(local_pos.x / CELL_SIZE), int(local_pos.y / CELL_SIZE))
		var container = inventory_system.get_container("backpack")
		if container:
			return container.get_item_at(grid_pos)
	
	# Check stash
	var stash_pos = stash_grid.get_global_rect()
	if stash_pos.has_point(pos):
		var local_pos = pos - stash_pos.position
		var grid_pos = Vector2i(int(local_pos.x / CELL_SIZE), int(local_pos.y / CELL_SIZE))
		var container = inventory_system.get_container("stash")
		if container:
			return container.get_item_at(grid_pos)
	
	return null

func _get_container_at_position(pos: Vector2) -> String:
	if backpack_grid.get_global_rect().has_point(pos):
		return "backpack"
	if stash_grid.get_global_rect().has_point(pos):
		return "stash"
	return ""

func _get_grid_position_at(pos: Vector2, container_id: String) -> Vector2i:
	var grid_control = backpack_grid if container_id == "backpack" else stash_grid
	if not grid_control:
		return Vector2i(-1, -1)
	
	var rect = grid_control.get_global_rect()
	if not rect.has_point(pos):
		return Vector2i(-1, -1)
	
	var local_pos = pos - rect.position
	return Vector2i(int(local_pos.x / CELL_SIZE), int(local_pos.y / CELL_SIZE))

# ============================================
# SIGNAL HANDLERS
# ============================================

func _on_container_updated(_container_id: String):
	if visible:
		refresh()

func _on_item_equipped(_item, _slot: String):
	if visible:
		_update_equipment_display()

func _on_item_unequipped(_item, _slot: String):
	if visible:
		_update_equipment_display()

func _on_currency_changed(_type: String, _amount: int):
	if visible:
		_update_currency_display()
