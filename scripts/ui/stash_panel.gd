extends Control
class_name StashPanel

signal item_equipped(item: ItemDataExtended, slot: String)
signal item_unequipped(slot: String)
signal item_dropped(item: ItemDataExtended)
signal item_used(item: ItemDataExtended)
signal panel_closed

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

# Bottom bar
@onready var money_label: Label = $BottomBar/MoneyLabel
@onready var weight_label: Label = $BottomBar/WeightLabel
@onready var craft_points_label: Label = $CraftPanel/PointsLabel
@onready var sort_button: Button = $BottomBar/SortButton
@onready var drop_button: Button = $BottomBar/DropButton
@onready var use_button: Button = $BottomBar/UseButton
@onready var close_button: Button = $BottomBar/CloseButton

# Tooltip
@onready var item_tooltip: Panel = $ItemTooltip
@onready var tooltip_name: Label = $ItemTooltip/VBox/Name if item_tooltip else null
@onready var tooltip_desc: Label = $ItemTooltip/VBox/Description if item_tooltip else null
@onready var tooltip_stats: Label = $ItemTooltip/VBox/Stats if item_tooltip else null

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
var selected_slot_index: int = -1
var selected_equipment_slot: String = ""

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

# Sort modes
enum SortMode { NAME, RARITY, TYPE, VALUE, WEIGHT }
var current_sort_mode: int = SortMode.NAME

func _ready():
	_setup_inventory_grid()
	_setup_equipment_slots()
	_connect_signals()
	_load_player_data()
	_update_stats_display()
	_update_currency_display()

func _connect_signals():
	if sort_button:
		sort_button.pressed.connect(_on_sort_pressed)
	if drop_button:
		drop_button.pressed.connect(_on_drop_pressed)
	if use_button:
		use_button.pressed.connect(_on_use_pressed)
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

func _load_player_data():
	# Load from player persistence
	if has_node("/root/PlayerPersistence"):
		var persistence = get_node("/root/PlayerPersistence")
		if persistence.player_data:
			var loaded_stats = persistence.player_data.get("stats", {})
			# Merge loaded stats into player_stats
			for key in loaded_stats:
				player_stats[key] = loaded_stats[key]

	# Get player reference for live stats
	var player = get_tree().get_first_node_in_group("player")
	if player:
		if "current_health" in player:
			player_stats["health"] = player.current_health
		if "max_health" in player:
			player_stats["max_health"] = player.max_health
		if "current_stamina" in player:
			player_stats["stamina"] = player.current_stamina
		if "max_stamina" in player:
			player_stats["max_stamina"] = player.max_stamina

func _setup_inventory_grid():
	if not inventory_grid:
		return

	inventory_grid.columns = 8

	# Clear existing slots
	for child in inventory_grid.get_children():
		child.queue_free()

	# Create inventory slots
	for i in range(max_inventory_slots):
		var slot = _create_inventory_slot(i)
		inventory_grid.add_child(slot)

func _create_inventory_slot(index: int) -> Panel:
	var slot = Panel.new()
	slot.name = "Slot_%d" % index
	slot.custom_minimum_size = Vector2(50, 55)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	style.border_color = Color(0.3, 0.3, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	slot.add_theme_stylebox_override("panel", style)

	# VBox for layout
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.add_child(vbox)

	# Icon texture
	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(45, 40)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon)

	# Stack count
	var count_label = Label.new()
	count_label.name = "Count"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.add_theme_font_size_override("font_size", 10)
	count_label.add_theme_color_override("font_color", Color.WHITE)
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(count_label)

	# Button for interaction
	var button = Button.new()
	button.name = "Button"
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.flat = true
	button.pressed.connect(_on_inventory_slot_clicked.bind(index))
	button.mouse_entered.connect(_on_slot_hover.bind(slot, true, index))
	button.mouse_exited.connect(_on_slot_hover.bind(slot, false, index))
	slot.add_child(button)

	return slot

func _on_slot_hover(slot: Panel, hovering: bool, index: int):
	var style = slot.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		if hovering:
			style.border_color = Color(0.5, 0.7, 0.9)
			style.set_border_width_all(2)
			_show_item_tooltip(index)
		else:
			style.border_color = Color(0.3, 0.3, 0.3)
			style.set_border_width_all(1)
			_hide_item_tooltip()

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

	# Disconnect existing connections
	if button.pressed.is_connected(_on_equipment_slot_clicked):
		button.pressed.disconnect(_on_equipment_slot_clicked)

	button.pressed.connect(_on_equipment_slot_clicked.bind(slot_name))

func _update_stats_display():
	# Get player name from Steam or persistence
	var player_name = "Survivor"
	if has_node("/root/SteamManager"):
		var steam = get_node("/root/SteamManager")
		if steam.is_initialized() and "steam_username" in steam:
			player_name = steam.steam_username
	elif has_node("/root/AccountSystem"):
		var account = get_node("/root/AccountSystem")
		if account.has_method("get_username"):
			player_name = account.get_username()

	if player_name_label:
		player_name_label.text = player_name

	# Get rank from persistence
	var rank_text = "Novice"
	if has_node("/root/PlayerPersistence"):
		var persistence = get_node("/root/PlayerPersistence")
		if persistence.player_data:
			var rank = persistence.player_data.get("rank", 1)
			rank_text = _get_rank_name(rank)

	if rank_label:
		rank_label.text = rank_text

	if health_bar:
		health_bar.max_value = player_stats.get("max_health", 100)
		health_bar.value = player_stats.get("health", 100)

	if stamina_bar:
		stamina_bar.max_value = player_stats.get("max_stamina", 100)
		stamina_bar.value = player_stats.get("stamina", 100)

	# Update resistance labels
	_update_stat_label("BulletproofHead", "%.1f %%" % player_stats.get("bulletproof_head", 0.0))
	_update_stat_label("BulletproofBody", "%.1f %%" % player_stats.get("bulletproof_body", 0.0))
	_update_stat_label("PenetrationHead", "%.1f %%" % player_stats.get("penetration_head", 0.0))
	_update_stat_label("PenetrationBody", "%.1f %%" % player_stats.get("penetration_body", 0.0))
	_update_stat_label("BleedingResist", "%.1f %%" % player_stats.get("bleeding_resist", 0.0))
	_update_stat_label("ExplosionResist", "%.1f %%" % player_stats.get("explosion_resist", 0.0))
	_update_stat_label("FireResist", "%.1f %%" % player_stats.get("fire_resist", 0.0))
	_update_stat_label("ColdResist", "%.1f %%" % player_stats.get("cold_resist", 0.0))
	_update_stat_label("ShockResist", "%.1f %%" % player_stats.get("shock_resist", 0.0))
	_update_stat_label("ChemicalResist", "%.1f %%" % player_stats.get("chemical_resist", 0.0))
	_update_stat_label("RadiationResist", "%.1f %%" % player_stats.get("radiation_resist", 0.0))

func _get_rank_name(rank: int) -> String:
	match rank:
		1: return "Novice"
		2: return "Survivor"
		3: return "Veteran"
		4: return "Elite"
		5: return "Master"
		_: return "Rank %d" % rank

func _update_stat_label(label_name: String, value: String):
	var label = get_node_or_null("StatsPanel/Stats/" + label_name)
	if label:
		label.text = value

func _update_currency_display():
	var money = 0
	if has_node("/root/PointsSystem"):
		var ps = get_node("/root/PointsSystem")
		if ps.has_method("get_points"):
			money = ps.get_points()

	if money_label:
		money_label.text = "Money: $%d" % money

	if weight_label:
		weight_label.text = "Weight: %.1f/%.1f (%.0f%%)" % [current_weight, max_weight, (current_weight / max_weight) * 100]

	if craft_points_label:
		var craft_points = 0
		if has_node("/root/PlayerPersistence"):
			var persistence = get_node("/root/PlayerPersistence")
			if persistence.player_data:
				craft_points = persistence.player_data.get("craft_points", 0)
		craft_points_label.text = "%d CP" % craft_points

func add_item_to_inventory(item: ItemDataExtended, count: int = 1) -> bool:
	if not item:
		return false

	# Find empty slot or stack with same item
	for i in range(inventory_items.size()):
		var inv_item = inventory_items[i]
		if inv_item and inv_item.item == item:
			if "stackable" in item and item.stackable:
				inv_item.count += count
				_update_weight()
				_refresh_inventory_display()
				return true

	# Find empty slot
	if inventory_items.size() < max_inventory_slots:
		inventory_items.append({"item": item, "count": count})
		_update_weight()
		_refresh_inventory_display()
		return true

	# Inventory full - find null slot
	for i in range(inventory_items.size()):
		if not inventory_items[i]:
			inventory_items[i] = {"item": item, "count": count}
			_update_weight()
			_refresh_inventory_display()
			return true

	return false

func remove_item_from_inventory(item: ItemDataExtended, count: int = 1) -> bool:
	if not item:
		return false

	for i in range(inventory_items.size()):
		var inv_item = inventory_items[i]
		if inv_item and inv_item.item == item:
			inv_item.count -= count
			if inv_item.count <= 0:
				inventory_items.remove_at(i)
			_update_weight()
			_refresh_inventory_display()
			return true
	return false

func _update_weight():
	current_weight = 0.0
	for inv_item in inventory_items:
		if inv_item and inv_item.item and "weight" in inv_item.item:
			current_weight += inv_item.item.weight * inv_item.count
	_update_currency_display()

func _refresh_inventory_display():
	if not inventory_grid:
		return

	for i in range(inventory_grid.get_child_count()):
		var slot = inventory_grid.get_child(i)
		if not slot:
			continue

		var vbox = slot.get_node_or_null("VBox")
		var icon = vbox.get_node_or_null("Icon") if vbox else slot.get_node_or_null("Icon")
		var count_label = vbox.get_node_or_null("Count") if vbox else slot.get_node_or_null("Count")

		if i < inventory_items.size() and inventory_items[i]:
			var inv_item = inventory_items[i]
			if icon and inv_item.item and "icon" in inv_item.item:
				icon.texture = inv_item.item.icon
			elif icon:
				icon.texture = null
			if count_label:
				count_label.text = str(inv_item.count) if inv_item.count > 1 else ""

			# Update border based on rarity
			var style = slot.get_theme_stylebox("panel") as StyleBoxFlat
			if style and inv_item.item:
				var rarity = inv_item.item.rarity if "rarity" in inv_item.item else 0
				style.border_color = _get_rarity_color(rarity)

			# Highlight selected
			if i == selected_slot_index:
				if style:
					style.set_border_width_all(3)
					style.border_color = Color.WHITE
		else:
			if icon:
				icon.texture = null
			if count_label:
				count_label.text = ""

			var style = slot.get_theme_stylebox("panel") as StyleBoxFlat
			if style:
				style.border_color = Color(0.3, 0.3, 0.3)
				style.set_border_width_all(1)

func _get_rarity_color(rarity: int) -> Color:
	match rarity:
		0: return Color(0.5, 0.5, 0.5)   # Common - gray
		1: return Color(0.2, 0.8, 0.2)   # Uncommon - green
		2: return Color(0.2, 0.4, 1.0)   # Rare - blue
		3: return Color(0.6, 0.2, 0.8)   # Epic - purple
		4: return Color(1.0, 0.6, 0.0)   # Legendary - orange
		5: return Color(1.0, 0.2, 0.2)   # Mythic - red
	return Color(0.3, 0.3, 0.3)

func equip_item(item: ItemDataExtended, slot_name: String) -> bool:
	if not item:
		return false

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
	var equipment_slots = {
		"first_slot": first_slot,
		"second_slot": second_slot,
		"pistol": pistol_slot,
		"head": head_slot,
		"face": face_slot,
		"backpack": backpack_slot,
		"body": body_slot,
		"pants": pants_slot,
		"boots": boots_slot
	}

	for slot_name in equipment_slots:
		var slot_node = equipment_slots[slot_name]
		if not slot_node:
			continue

		var item = equipped_items.get(slot_name)
		var icon = slot_node.get_node_or_null("Icon") as TextureRect

		if icon:
			if item and "icon" in item:
				icon.texture = item.icon
			else:
				icon.texture = null

		# Update slot border color based on item rarity
		var style = slot_node.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			if item and "rarity" in item:
				style.border_color = _get_rarity_color(item.rarity)
			else:
				style.border_color = Color(0.3, 0.3, 0.3)

			# Highlight selected equipment slot
			if slot_name == selected_equipment_slot:
				style.set_border_width_all(3)
				style.border_color = Color.GOLD
			else:
				style.set_border_width_all(1)

func _recalculate_stats():
	# Reset to base stats
	player_stats["bulletproof_head"] = 0.0
	player_stats["bulletproof_body"] = 0.0
	player_stats["penetration_head"] = 0.0
	player_stats["penetration_body"] = 0.0
	player_stats["bleeding_resist"] = 0.0
	player_stats["explosion_resist"] = 0.0
	player_stats["fire_resist"] = 0.0
	player_stats["cold_resist"] = 0.0
	player_stats["shock_resist"] = 0.0
	player_stats["chemical_resist"] = 0.0
	player_stats["radiation_resist"] = 0.0

	# Add stats from equipment
	for slot_name in equipped_items:
		var item = equipped_items[slot_name]
		if not item:
			continue

		if "armor_value" in item:
			if slot_name == "head":
				player_stats["bulletproof_head"] += item.armor_value
			else:
				player_stats["bulletproof_body"] += item.armor_value

		# Add resistances
		if "fire_resist" in item:
			player_stats["fire_resist"] += item.fire_resist
		if "cold_resist" in item:
			player_stats["cold_resist"] += item.cold_resist
		if "bleed_resist" in item:
			player_stats["bleeding_resist"] += item.bleed_resist
		if "explosion_resist" in item:
			player_stats["explosion_resist"] += item.explosion_resist

	_update_stats_display()

func _show_item_tooltip(index: int):
	if index < 0 or index >= inventory_items.size() or not inventory_items[index]:
		return

	var inv_item = inventory_items[index]
	var item = inv_item.item
	if not item:
		return

	if item_tooltip:
		item_tooltip.visible = true

		# Update tooltip content
		if tooltip_name:
			tooltip_name.text = item.item_name if "item_name" in item else "Unknown"
			tooltip_name.add_theme_color_override("font_color", _get_rarity_color(item.rarity if "rarity" in item else 0))

		if tooltip_desc:
			tooltip_desc.text = item.description if "description" in item else ""

		if tooltip_stats:
			var stats_text = ""
			if "armor_value" in item:
				stats_text += "Armor: %.1f\n" % item.armor_value
			if "damage" in item:
				stats_text += "Damage: %.1f\n" % item.damage
			if "weight" in item:
				stats_text += "Weight: %.1f\n" % item.weight
			if "value" in item:
				stats_text += "Value: $%d\n" % item.value
			tooltip_stats.text = stats_text

func _hide_item_tooltip():
	if item_tooltip:
		item_tooltip.visible = false

func _on_inventory_slot_clicked(index: int):
	if index < 0:
		return

	# Clear equipment selection
	selected_equipment_slot = ""

	if index < inventory_items.size() and inventory_items[index]:
		selected_slot_index = index
		var item = inventory_items[index].item

		# Show context options or try to equip
		if use_button:
			use_button.disabled = not (item and "usable" in item and item.usable)
		if drop_button:
			drop_button.disabled = false
	else:
		selected_slot_index = -1
		if use_button:
			use_button.disabled = true
		if drop_button:
			drop_button.disabled = true

	_refresh_inventory_display()
	_refresh_equipment_display()

func _on_equipment_slot_clicked(slot_name: String):
	# Clear inventory selection
	selected_slot_index = -1

	if equipped_items.has(slot_name) and equipped_items[slot_name]:
		selected_equipment_slot = slot_name
		# Could show context menu to unequip
	else:
		selected_equipment_slot = slot_name
		# Show equippable items for this slot

	_refresh_inventory_display()
	_refresh_equipment_display()

func _on_sort_pressed():
	# Cycle through sort modes
	current_sort_mode = (current_sort_mode + 1) % 5

	# Sort inventory
	inventory_items.sort_custom(_compare_items)

	_refresh_inventory_display()

func _compare_items(a, b) -> bool:
	if not a or not b:
		return a != null

	var item_a = a.item if a.has("item") else a
	var item_b = b.item if b.has("item") else b

	if not item_a or not item_b:
		return item_a != null

	match current_sort_mode:
		SortMode.NAME:
			var name_a = item_a.item_name if "item_name" in item_a else ""
			var name_b = item_b.item_name if "item_name" in item_b else ""
			return name_a < name_b
		SortMode.RARITY:
			var rarity_a = item_a.rarity if "rarity" in item_a else 0
			var rarity_b = item_b.rarity if "rarity" in item_b else 0
			return rarity_a > rarity_b  # Higher rarity first
		SortMode.TYPE:
			var type_a = item_a.item_type if "item_type" in item_a else 0
			var type_b = item_b.item_type if "item_type" in item_b else 0
			return type_a < type_b
		SortMode.VALUE:
			var value_a = item_a.value if "value" in item_a else 0
			var value_b = item_b.value if "value" in item_b else 0
			return value_a > value_b  # Higher value first
		SortMode.WEIGHT:
			var weight_a = item_a.weight if "weight" in item_a else 0
			var weight_b = item_b.weight if "weight" in item_b else 0
			return weight_a < weight_b  # Lighter first

	return false

func _on_drop_pressed():
	if selected_slot_index < 0 or selected_slot_index >= inventory_items.size():
		return

	var inv_item = inventory_items[selected_slot_index]
	if not inv_item:
		return

	var dialog = ConfirmationDialog.new()
	var item_name = inv_item.item.item_name if inv_item.item and "item_name" in inv_item.item else "Item"
	dialog.dialog_text = "Drop %s?" % item_name
	dialog.confirmed.connect(_confirm_drop)
	add_child(dialog)
	dialog.popup_centered()

func _confirm_drop():
	if selected_slot_index < 0 or selected_slot_index >= inventory_items.size():
		return

	var inv_item = inventory_items[selected_slot_index]
	if inv_item and inv_item.item:
		item_dropped.emit(inv_item.item)

	inventory_items.remove_at(selected_slot_index)
	selected_slot_index = -1
	_update_weight()
	_refresh_inventory_display()

func _on_use_pressed():
	if selected_slot_index < 0 or selected_slot_index >= inventory_items.size():
		return

	var inv_item = inventory_items[selected_slot_index]
	if not inv_item or not inv_item.item:
		return

	var item = inv_item.item
	if "usable" in item and item.usable:
		# Use the item
		item_used.emit(item)

		# Reduce count or remove
		inv_item.count -= 1
		if inv_item.count <= 0:
			inventory_items.remove_at(selected_slot_index)
			selected_slot_index = -1

		_update_weight()
		_refresh_inventory_display()

func _on_close_pressed():
	close()
	panel_closed.emit()

func open():
	visible = true
	_load_player_data()
	_refresh_inventory_display()
	_refresh_equipment_display()
	_update_stats_display()
	_update_currency_display()

func close():
	visible = false
	selected_slot_index = -1
	selected_equipment_slot = ""
	_hide_item_tooltip()

func get_equipped_items() -> Dictionary:
	return equipped_items.duplicate()

func set_inventory(items: Array):
	inventory_items = items
	_update_weight()
	_refresh_inventory_display()
