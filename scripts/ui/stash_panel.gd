extends Control
class_name StashPanel

signal item_equipped(item: ItemDataExtended, slot: String)
signal item_unequipped(slot: String)
signal item_dropped(item: ItemDataExtended)

# Equipment slot references
@onready var first_slot: Panel = $EquipmentPanel/FirstSlot
@onready var second_slot: Panel = $EquipmentPanel/SecondSlot
@onready var pistol_slot: Panel = $EquipmentPanel/PistolSlot
@onready var head_slot: Panel = $EquipmentPanel/HeadSlot
@onready var face_slot: Panel = $EquipmentPanel/FaceSlot
@onready var backpack_slot: Panel = $EquipmentPanel/BackpackSlot
@onready var body_slot: Panel = $EquipmentPanel/BodySlot
@onready var pants_slot: Panel = $EquipmentPanel/PantsSlot
@onready var boots_slot: Panel = $EquipmentPanel/BootsSlot

# Stats panel
@onready var health_bar: ProgressBar = $StatsPanel/HealthBar
@onready var stamina_bar: ProgressBar = $StatsPanel/StaminaBar
@onready var player_name_label: Label = $StatsPanel/PlayerName
@onready var rank_label: Label = $StatsPanel/Rank

# Inventory grid
@onready var inventory_grid: GridContainer = $InventoryPanel/ScrollContainer/InventoryGrid

# Currency
@onready var money_label: Label = $BottomBar/MoneyLabel
@onready var weight_label: Label = $BottomBar/WeightLabel
@onready var craft_points_label: Label = $CraftPanel/PointsLabel

# Equipment data
var equipped_items: Dictionary = {
	"first_slot": null,
	"second_slot": null,
	"pistol": null,
	"head": null,
	"face": null,
	"backpack": null,
	"body": null,
	"pants": null,
	"boots": null,
	"device1": null,
	"qs1": null,
	"qs2": null,
	"qs3": null
}

# Inventory
var inventory_items: Array = []
var max_inventory_slots: int = 48
var current_weight: float = 0.0
var max_weight: float = 44.7

# Player stats
var player_stats: Dictionary = {
	"health": 100,
	"max_health": 100,
	"stamina": 100,
	"max_stamina": 100,
	"health_regen": 1.0,
	"stamina_regen": 1.5,
	"bulletproof_head": 0.1,
	"bulletproof_body": 29.7,
	"penetration_head": 0.0,
	"penetration_body": 19.8,
	"bleeding_resist": 3.0,
	"explosion_resist": 14.8,
	"fire_resist": 4.9,
	"cold_resist": 4.9,
	"shock_resist": 4.9,
	"chemical_resist": 4.9,
	"radiation_resist": 4.9
}

func _ready():
	_setup_inventory_grid()
	_setup_equipment_slots()
	_update_stats_display()
	_update_currency_display()

func _setup_inventory_grid():
	if not inventory_grid:
		return

	inventory_grid.columns = 8

	# Create inventory slots
	for i in range(max_inventory_slots):
		var slot = _create_inventory_slot(i)
		inventory_grid.add_child(slot)

func _create_inventory_slot(index: int) -> Panel:
	var slot = Panel.new()
	slot.name = "Slot_%d" % index
	slot.custom_minimum_size = Vector2(50, 50)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	style.border_color = Color(0.3, 0.3, 0.3)
	style.set_border_width_all(1)
	slot.add_theme_stylebox_override("panel", style)

	# Button for interaction
	var button = Button.new()
	button.name = "Button"
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.flat = true
	button.pressed.connect(_on_inventory_slot_clicked.bind(index))
	slot.add_child(button)

	# Icon texture
	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(icon)

	# Stack count
	var count_label = Label.new()
	count_label.name = "Count"
	count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	count_label.position = Vector2(-20, -20)
	count_label.add_theme_font_size_override("font_size", 10)
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(count_label)

	return slot

func _setup_equipment_slots():
	var equipment_slots = [
		["first_slot", first_slot],
		["second_slot", second_slot],
		["pistol", pistol_slot],
		["head", head_slot],
		["face", face_slot],
		["backpack", backpack_slot],
		["body", body_slot],
		["pants", pants_slot],
		["boots", boots_slot]
	]

	for slot_data in equipment_slots:
		var slot_name = slot_data[0]
		var slot_node = slot_data[1]
		if slot_node:
			_setup_equipment_slot(slot_node, slot_name)

func _setup_equipment_slot(slot: Panel, slot_name: String):
	var button = slot.get_node_or_null("Button")
	if not button:
		button = Button.new()
		button.name = "Button"
		button.set_anchors_preset(Control.PRESET_FULL_RECT)
		button.flat = true
		slot.add_child(button)

	button.pressed.connect(_on_equipment_slot_clicked.bind(slot_name))

func _update_stats_display():
	if player_name_label:
		player_name_label.text = "Blindz"  # Would come from player data

	if rank_label:
		rank_label.text = "Novice"

	if health_bar:
		health_bar.max_value = player_stats.max_health
		health_bar.value = player_stats.health

	if stamina_bar:
		stamina_bar.max_value = player_stats.max_stamina
		stamina_bar.value = player_stats.stamina

	# Update resistance labels
	_update_stat_label("BulletproofHead", "%.1f %%" % player_stats.bulletproof_head)
	_update_stat_label("BulletproofBody", "%.1f %%" % player_stats.bulletproof_body)
	_update_stat_label("PenetrationHead", "%.1f %%" % player_stats.penetration_head)
	_update_stat_label("PenetrationBody", "%.1f %%" % player_stats.penetration_body)
	_update_stat_label("BleedingResist", "%.1f %%" % player_stats.bleeding_resist)
	_update_stat_label("ExplosionResist", "%.1f %%" % player_stats.explosion_resist)
	_update_stat_label("FireResist", "%.1f %%" % player_stats.fire_resist)
	_update_stat_label("ColdResist", "%.1f %%" % player_stats.cold_resist)
	_update_stat_label("ShockResist", "%.1f %%" % player_stats.shock_resist)
	_update_stat_label("ChemicalResist", "%.1f %%" % player_stats.chemical_resist)
	_update_stat_label("RadiationResist", "%.1f %%" % player_stats.radiation_resist)

func _update_stat_label(label_name: String, value: String):
	var label = get_node_or_null("StatsPanel/Stats/" + label_name)
	if label:
		label.text = value

func _update_currency_display():
	if money_label:
		money_label.text = "Money: 0"

	if weight_label:
		weight_label.text = "Weight: %.3f/%.5f (%.1f %%)" % [current_weight, max_weight, (current_weight / max_weight) * 100]

	if craft_points_label:
		craft_points_label.text = "500/0"

func add_item_to_inventory(item: ItemDataExtended, count: int = 1) -> bool:
	# Find empty slot or stack
	for i in range(inventory_items.size()):
		var inv_item = inventory_items[i]
		if inv_item and inv_item.item == item and item.stackable:
			inv_item.count += count
			_refresh_inventory_display()
			return true

	# Find empty slot
	if inventory_items.size() < max_inventory_slots:
		inventory_items.append({"item": item, "count": count})
		_refresh_inventory_display()
		return true

	return false

func remove_item_from_inventory(item: ItemDataExtended, count: int = 1) -> bool:
	for i in range(inventory_items.size()):
		var inv_item = inventory_items[i]
		if inv_item and inv_item.item == item:
			inv_item.count -= count
			if inv_item.count <= 0:
				inventory_items.remove_at(i)
			_refresh_inventory_display()
			return true
	return false

func _refresh_inventory_display():
	for i in range(max_inventory_slots):
		var slot = inventory_grid.get_node_or_null("Slot_%d" % i)
		if not slot:
			continue

		var icon = slot.get_node_or_null("Icon") as TextureRect
		var count_label = slot.get_node_or_null("Count") as Label

		if i < inventory_items.size() and inventory_items[i]:
			var inv_item = inventory_items[i]
			if icon:
				icon.texture = inv_item.item.icon
			if count_label:
				count_label.text = str(inv_item.count) if inv_item.count > 1 else ""
		else:
			if icon:
				icon.texture = null
			if count_label:
				count_label.text = ""

func equip_item(item: ItemDataExtended, slot_name: String) -> bool:
	if equipped_items.has(slot_name):
		# Unequip current item if any
		if equipped_items[slot_name]:
			add_item_to_inventory(equipped_items[slot_name])

		equipped_items[slot_name] = item
		_refresh_equipment_display()
		_recalculate_stats()
		item_equipped.emit(item, slot_name)
		return true
	return false

func unequip_item(slot_name: String) -> ItemDataExtended:
	if equipped_items.has(slot_name) and equipped_items[slot_name]:
		var item = equipped_items[slot_name]
		equipped_items[slot_name] = null
		add_item_to_inventory(item)
		_refresh_equipment_display()
		_recalculate_stats()
		item_unequipped.emit(slot_name)
		return item
	return null

func _refresh_equipment_display():
	# Update each equipment slot visual
	pass

func _recalculate_stats():
	# Recalculate player stats based on equipped items
	_update_stats_display()

func _on_inventory_slot_clicked(index: int):
	if index < inventory_items.size() and inventory_items[index]:
		var item = inventory_items[index].item
		# Show item context menu or try to equip
		print("Clicked inventory slot %d with item: %s" % [index, item.item_name])

func _on_equipment_slot_clicked(slot_name: String):
	if equipped_items.has(slot_name) and equipped_items[slot_name]:
		# Unequip item
		unequip_item(slot_name)
	else:
		# Show equippable items for this slot
		print("Clicked empty equipment slot: %s" % slot_name)

func open():
	visible = true
	_refresh_inventory_display()
	_refresh_equipment_display()

func close():
	visible = false
