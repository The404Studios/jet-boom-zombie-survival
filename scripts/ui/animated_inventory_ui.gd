extends Control
class_name AnimatedInventoryUI

@export var inventory_system: InventorySystem
@export var equipment_system: EquipmentSystem
@export var character_stats: CharacterStats

@onready var inventory_panel: Panel = $InventoryPanel
@onready var inventory_grid: GridContainer = $InventoryPanel/ScrollContainer/InventoryGrid
@onready var equipment_panel: Panel = $EquipmentPanel
@onready var stats_panel: Panel = $StatsPanel
@onready var item_tooltip: Panel = $ItemTooltip

var is_open: bool = false
var selected_item: ItemDataExtended = null
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
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	slot.add_child(count_label)

	return slot

func setup_equipment_slots():
	# Equipment slots would be set up here
	pass

func setup_stats_display():
	# Stats display would be set up here
	pass

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
			var item: ItemDataExtended = item_data.item
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
	if not character_stats or not stats_panel:
		return

	# Update stats display
	var stats = character_stats.get_stat_summary()
	# Would populate UI elements with stats

func _on_inventory_changed():
	if is_open:
		refresh_inventory()

func _on_slot_mouse_entered(slot: Control, index: int):
	if index < inventory_system.inventory.size():
		var item: ItemDataExtended = inventory_system.inventory[index].item
		show_tooltip(item, slot.global_position)

func _on_slot_mouse_exited(slot: Control):
	hide_tooltip()

func show_tooltip(item: ItemDataExtended, position: Vector2):
	if item_tooltip:
		# Set tooltip text and position
		item_tooltip.visible = true
		item_tooltip.global_position = position + Vector2(70, 0)

func hide_tooltip():
	if item_tooltip:
		item_tooltip.visible = false

func _input(event):
	if event.is_action_pressed("inventory"):
		toggle()
