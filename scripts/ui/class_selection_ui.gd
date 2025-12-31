extends Control
class_name ClassSelectionUI

# Class selection interface for pre-game lobby
# Shows available classes with stats and abilities

signal class_selected(class_id: String)
signal selection_confirmed
signal back_pressed

# References
@onready var class_list: VBoxContainer = $ClassList
@onready var class_details: Control = $ClassDetails
@onready var confirm_button: Button = $ConfirmButton

# System reference
var class_system: Node = null

# Selection
var selected_class: String = "survivor"
var class_buttons: Dictionary = {}  # class_id -> button

func _ready():
	class_system = get_node_or_null("/root/PlayerClassSystem")
	if not class_system:
		# Try to find it
		class_system = get_tree().get_first_node_in_group("class_system")

	# Build UI
	_create_ui()
	_populate_classes()

func _create_ui():
	# Main container
	var main_hbox = HBoxContainer.new()
	main_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_hbox.add_theme_constant_override("separation", 20)
	add_child(main_hbox)

	# Left side - Class list
	var left_panel = PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(300, 0)

	var left_style = StyleBoxFlat.new()
	left_style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	left_style.corner_radius_top_left = 8
	left_style.corner_radius_top_right = 8
	left_style.corner_radius_bottom_left = 8
	left_style.corner_radius_bottom_right = 8
	left_panel.add_theme_stylebox_override("panel", left_style)
	main_hbox.add_child(left_panel)

	var left_margin = MarginContainer.new()
	left_margin.add_theme_constant_override("margin_left", 15)
	left_margin.add_theme_constant_override("margin_right", 15)
	left_margin.add_theme_constant_override("margin_top", 15)
	left_margin.add_theme_constant_override("margin_bottom", 15)
	left_panel.add_child(left_margin)

	var left_vbox = VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 10)
	left_margin.add_child(left_vbox)

	# Title
	var title = Label.new()
	title.text = "SELECT CLASS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	left_vbox.add_child(title)

	# Scroll container for class list
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(scroll)

	class_list = VBoxContainer.new()
	class_list.add_theme_constant_override("separation", 8)
	scroll.add_child(class_list)

	# Right side - Class details
	var right_panel = PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var right_style = left_style.duplicate()
	right_panel.add_theme_stylebox_override("panel", right_style)
	main_hbox.add_child(right_panel)

	var right_margin = MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 20)
	right_margin.add_theme_constant_override("margin_right", 20)
	right_margin.add_theme_constant_override("margin_top", 20)
	right_margin.add_theme_constant_override("margin_bottom", 20)
	right_panel.add_child(right_margin)

	class_details = VBoxContainer.new()
	class_details.add_theme_constant_override("separation", 15)
	right_margin.add_child(class_details)

	# Bottom buttons
	var button_hbox = HBoxContainer.new()
	button_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	button_hbox.add_theme_constant_override("separation", 20)
	button_hbox.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	button_hbox.offset_top = -60
	button_hbox.offset_bottom = -10
	add_child(button_hbox)

	var back_btn = Button.new()
	back_btn.text = "BACK"
	back_btn.custom_minimum_size = Vector2(150, 45)
	back_btn.pressed.connect(func(): back_pressed.emit())
	button_hbox.add_child(back_btn)

	confirm_button = Button.new()
	confirm_button.text = "CONFIRM"
	confirm_button.custom_minimum_size = Vector2(150, 45)
	confirm_button.pressed.connect(_on_confirm_pressed)
	button_hbox.add_child(confirm_button)

func _populate_classes():
	if not class_system:
		return

	# Clear existing
	for child in class_list.get_children():
		child.queue_free()
	class_buttons.clear()

	# Get all classes
	var all_classes = class_system.get_all_classes()

	for class_data in all_classes:
		var btn = _create_class_button(class_data)
		class_list.add_child(btn)
		class_buttons[class_data.id] = btn

	# Select default
	_select_class("survivor")

func _create_class_button(class_data) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(250, 60)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	# Check if unlocked
	var is_unlocked = class_system.is_class_unlocked(class_data.id)

	# Button content
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)

	# Icon placeholder
	var icon = Label.new()
	icon.text = "[%s]" % class_data.display_name.substr(0, 1).to_upper()
	icon.custom_minimum_size = Vector2(40, 40)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 20)
	if is_unlocked:
		icon.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	else:
		icon.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	hbox.add_child(icon)

	# Name and lock status
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	var name_label = Label.new()
	name_label.text = class_data.display_name
	name_label.add_theme_font_size_override("font_size", 16)
	if not is_unlocked:
		name_label.text += " [LOCKED]"
		name_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(name_label)

	# Unlock requirement
	if not is_unlocked:
		var req_label = Label.new()
		req_label.text = "Unlock at Level %d" % class_data.unlock_level
		req_label.add_theme_font_size_override("font_size", 11)
		req_label.add_theme_color_override("font_color", Color(0.6, 0.4, 0.4))
		vbox.add_child(req_label)

	hbox.add_child(vbox)

	btn.add_child(hbox)
	btn.disabled = not is_unlocked

	# Connect
	btn.pressed.connect(func(): _select_class(class_data.id))

	return btn

func _select_class(class_id: String):
	if not class_system:
		return

	var class_data = class_system.get_class_data(class_id)
	if not class_data:
		return

	selected_class = class_id

	# Update button visuals
	for cid in class_buttons:
		var btn = class_buttons[cid]
		if cid == class_id:
			btn.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
		else:
			btn.remove_theme_color_override("font_color")

	# Update details panel
	_show_class_details(class_data)

	class_selected.emit(class_id)

func _show_class_details(class_data):
	# Clear existing
	for child in class_details.get_children():
		child.queue_free()

	# Class name
	var name_label = Label.new()
	name_label.text = class_data.display_name.to_upper()
	name_label.add_theme_font_size_override("font_size", 32)
	name_label.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	class_details.add_child(name_label)

	# Description
	var desc = Label.new()
	desc.text = class_data.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	class_details.add_child(desc)

	# Separator
	var sep1 = HSeparator.new()
	class_details.add_child(sep1)

	# Stats section
	var stats_title = Label.new()
	stats_title.text = "STATS"
	stats_title.add_theme_font_size_override("font_size", 18)
	stats_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
	class_details.add_child(stats_title)

	var stats_grid = GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 30)
	stats_grid.add_theme_constant_override("v_separation", 8)
	class_details.add_child(stats_grid)

	_add_stat_bar(stats_grid, "Health", class_data.health_modifier)
	_add_stat_bar(stats_grid, "Speed", class_data.speed_modifier)
	_add_stat_bar(stats_grid, "Damage", class_data.damage_modifier)
	_add_stat_bar(stats_grid, "Reload", class_data.reload_speed_modifier)
	_add_stat_bar(stats_grid, "Stamina", class_data.stamina_modifier)
	_add_stat_bar(stats_grid, "Armor", class_data.armor_modifier)

	# Separator
	var sep2 = HSeparator.new()
	class_details.add_child(sep2)

	# Abilities section
	var abilities_title = Label.new()
	abilities_title.text = "ABILITIES"
	abilities_title.add_theme_font_size_override("font_size", 18)
	abilities_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
	class_details.add_child(abilities_title)

	if not class_data.passive_ability.is_empty():
		_add_ability_row(class_details, "Passive", class_data.passive_ability, Color(0.5, 0.8, 0.5))

	if not class_data.active_ability.is_empty():
		_add_ability_row(class_details, "Active", class_data.active_ability, Color(0.5, 0.7, 1))

	if not class_data.ultimate_ability.is_empty():
		_add_ability_row(class_details, "Ultimate", class_data.ultimate_ability, Color(1, 0.6, 0.8))

	# Starting equipment
	var sep3 = HSeparator.new()
	class_details.add_child(sep3)

	var equip_title = Label.new()
	equip_title.text = "STARTING EQUIPMENT"
	equip_title.add_theme_font_size_override("font_size", 18)
	equip_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
	class_details.add_child(equip_title)

	var equip_hbox = HBoxContainer.new()
	equip_hbox.add_theme_constant_override("separation", 10)
	class_details.add_child(equip_hbox)

	for weapon in class_data.starting_weapons:
		var weapon_label = Label.new()
		weapon_label.text = "[%s]" % weapon.capitalize()
		weapon_label.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
		equip_hbox.add_child(weapon_label)

	for item in class_data.starting_items:
		var item_label = Label.new()
		item_label.text = "[%s]" % item.capitalize()
		item_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1))
		equip_hbox.add_child(item_label)

	# Starting resources
	var resources_label = Label.new()
	resources_label.text = "Points: %d | Sigils: %d" % [class_data.starting_points, class_data.starting_sigils]
	resources_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	class_details.add_child(resources_label)

func _add_stat_bar(parent: Control, stat_name: String, modifier: float):
	# Name
	var name_label = Label.new()
	name_label.text = stat_name
	name_label.custom_minimum_size = Vector2(80, 0)
	parent.add_child(name_label)

	# Bar container
	var bar_hbox = HBoxContainer.new()
	bar_hbox.add_theme_constant_override("separation", 5)
	parent.add_child(bar_hbox)

	# Progress bar
	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(120, 16)
	bar.max_value = 2.0
	bar.value = modifier
	bar.show_percentage = false
	bar_hbox.add_child(bar)

	# Color based on modifier
	var color = Color(0.5, 0.5, 0.5)
	if modifier > 1.0:
		color = Color(0.3, 0.8, 0.3)  # Green for buffs
	elif modifier < 1.0:
		color = Color(0.8, 0.3, 0.3)  # Red for debuffs

	# Value label
	var value_label = Label.new()
	var percent = int((modifier - 1.0) * 100)
	if percent >= 0:
		value_label.text = "+%d%%" % percent
	else:
		value_label.text = "%d%%" % percent
	value_label.add_theme_color_override("font_color", color)
	bar_hbox.add_child(value_label)

func _add_ability_row(parent: Control, ability_type: String, ability_name: String, color: Color):
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	parent.add_child(hbox)

	var type_label = Label.new()
	type_label.text = "[%s]" % ability_type
	type_label.custom_minimum_size = Vector2(80, 0)
	type_label.add_theme_color_override("font_color", color)
	hbox.add_child(type_label)

	var name_label = Label.new()
	name_label.text = ability_name.replace("_", " ").capitalize()
	name_label.add_theme_color_override("font_color", Color.WHITE)
	hbox.add_child(name_label)

func _on_confirm_pressed():
	if class_system:
		class_system.select_class(selected_class)

	selection_confirmed.emit()

func get_selected_class() -> String:
	return selected_class

func refresh():
	_populate_classes()
