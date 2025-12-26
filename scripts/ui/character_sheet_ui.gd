extends Control
class_name CharacterSheetUI

@export var character_stats: CharacterStats
@export var equipment_system: EquipmentSystem
var player_persistence: Node = null  # PlayerPersistence autoload - set in _ready

@onready var stats_container: VBoxContainer = $StatsPanel/StatsContainer
@onready var equipment_panel: Panel = $EquipmentPanel
@onready var augment_panel: Panel = $AugmentPanel
@onready var level_label: Label = $LevelLabel
@onready var exp_bar: ProgressBar = $ExpBar

var is_open: bool = false
var stat_buttons: Dictionary = {}

signal character_sheet_opened
signal character_sheet_closed
signal stat_increased(stat_name: String)

func _ready():
	visible = false

	# Get PlayerPersistence autoload singleton
	player_persistence = get_node_or_null("/root/PlayerPersistence")

	setup_ui()

	if character_stats:
		character_stats.stat_changed.connect(_on_stat_changed)
		character_stats.level_up.connect(_on_level_up)

func setup_ui():
	setup_stat_display()
	setup_equipment_display()

func setup_stat_display():
	if not stats_container:
		return

	# Create stat entries
	create_stat_entry("Strength", "strength")
	create_stat_entry("Dexterity", "dexterity")
	create_stat_entry("Intelligence", "intelligence")
	create_stat_entry("Agility", "agility")
	create_stat_entry("Vitality", "vitality")

	# Create separator
	var separator = HSeparator.new()
	stats_container.add_child(separator)

	# Derived stats display
	create_derived_stat_display("Health", "max_health")
	create_derived_stat_display("Stamina", "max_stamina")
	create_derived_stat_display("Armor", "armor")
	create_derived_stat_display("Crit Chance", "crit_chance", true)
	create_derived_stat_display("Crit Damage", "crit_damage")
	create_derived_stat_display("Move Speed", "move_speed_multiplier")

func create_stat_entry(display_name: String, stat_name: String):
	var hbox = HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 40)

	# Stat name
	var name_label = Label.new()
	name_label.text = display_name
	name_label.custom_minimum_size = Vector2(120, 0)
	name_label.add_theme_font_size_override("font_size", 16)
	hbox.add_child(name_label)

	# Stat value
	var value_label = Label.new()
	value_label.name = stat_name + "_value"
	value_label.text = "10"
	value_label.custom_minimum_size = Vector2(50, 0)
	value_label.add_theme_font_size_override("font_size", 16)
	value_label.add_theme_color_override("font_color", Color.GOLD)
	hbox.add_child(value_label)

	# Plus button
	var plus_button = Button.new()
	plus_button.text = "+"
	plus_button.custom_minimum_size = Vector2(30, 30)
	plus_button.pressed.connect(_on_stat_increase_pressed.bind(stat_name))
	hbox.add_child(plus_button)

	stat_buttons[stat_name] = plus_button
	stats_container.add_child(hbox)

func create_derived_stat_display(display_name: String, stat_name: String, is_percent: bool = false):
	var hbox = HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 30)

	var name_label = Label.new()
	name_label.text = display_name
	name_label.custom_minimum_size = Vector2(120, 0)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	hbox.add_child(name_label)

	var value_label = Label.new()
	value_label.name = stat_name + "_value"
	value_label.text = "0"
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.add_theme_color_override("font_color", Color.CYAN)
	hbox.add_child(value_label)

	stats_container.add_child(hbox)

func setup_equipment_display():
	if not equipment_panel:
		return

	# Create equipment slots
	var slots = [
		"helmet", "chest", "gloves", "boots",
		"ring_1", "ring_2", "amulet",
		"primary", "secondary"
	]

	for slot_name in slots:
		create_equipment_slot(slot_name)

func create_equipment_slot(slot_name: String) -> Panel:
	var slot = Panel.new()
	slot.name = slot_name + "_slot"
	slot.custom_minimum_size = Vector2(64, 64)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	style.border_color = Color(0.5, 0.5, 0.5)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	slot.add_theme_stylebox_override("panel", style)

	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.add_child(icon)

	var label = Label.new()
	label.text = slot_name.capitalize()
	label.position = Vector2(0, 0)
	label.add_theme_font_size_override("font_size", 10)
	slot.add_child(label)

	if equipment_panel:
		equipment_panel.add_child(slot)

	return slot

func open():
	is_open = true
	visible = true
	animate_open()
	refresh_all()
	character_sheet_opened.emit()

func close():
	is_open = false
	animate_close()
	await get_tree().create_timer(0.3).timeout
	visible = false
	character_sheet_closed.emit()

func animate_open():
	modulate.a = 0
	scale = Vector2(0.8, 0.8)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func animate_close():
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_property(self, "scale", Vector2(0.8, 0.8), 0.2)

func refresh_all():
	refresh_stats()
	refresh_equipment()
	refresh_level()

func refresh_stats():
	if not character_stats:
		return

	var stats = character_stats.get_stat_summary()

	for stat_name in ["strength", "dexterity", "intelligence", "agility", "vitality"]:
		var value_label = stats_container.get_node_or_null(stat_name + "_value") as Label
		if value_label:
			value_label.text = "%.0f" % stats[stat_name]

	# Derived stats
	update_derived_stat("max_health", stats.max_health)
	update_derived_stat("max_stamina", stats.max_stamina)
	update_derived_stat("armor", stats.armor)
	update_derived_stat("crit_chance", stats.crit_chance * 100, true)
	update_derived_stat("crit_damage", stats.crit_damage * 100, true)
	update_derived_stat("move_speed_multiplier", stats.move_speed * 100, true)

	# Update stat point availability
	for button in stat_buttons.values():
		button.disabled = character_stats.stat_points <= 0

func update_derived_stat(stat_name: String, value: float, is_percent: bool = false):
	var value_label = stats_container.get_node_or_null(stat_name + "_value") as Label
	if value_label:
		if is_percent:
			value_label.text = "%.1f%%" % value
		else:
			value_label.text = "%.0f" % value

func refresh_equipment():
	if not equipment_system or not equipment_panel:
		return

	var equipped = equipment_system.get_equipment_summary()
	for slot_name in equipped.keys():
		if slot_name == "total_armor":
			continue

		var slot = equipment_panel.get_node_or_null(slot_name + "_slot") as Panel
		if slot:
			var item = equipment_system.get_item_in_slot(slot_name)
			var icon = slot.get_node("Icon") as TextureRect
			if icon and item and item.icon:
				icon.texture = item.icon
			elif icon:
				icon.texture = null

func refresh_level():
	if not character_stats:
		return

	if level_label:
		level_label.text = "Level %d" % character_stats.level

	if exp_bar:
		exp_bar.max_value = character_stats.experience_to_next_level
		exp_bar.value = character_stats.experience

		# Add exp text
		var exp_text = "%d / %d" % [character_stats.experience, character_stats.experience_to_next_level]
		exp_bar.set_meta("exp_text", exp_text)

func _on_stat_increase_pressed(stat_name: String):
	if character_stats and character_stats.increase_stat(stat_name):
		refresh_stats()
		animate_stat_increase(stat_name)
		stat_increased.emit(stat_name)

func animate_stat_increase(stat_name: String):
	var value_label = stats_container.get_node_or_null(stat_name + "_value") as Label
	if value_label:
		var original_scale = value_label.scale
		var tween = create_tween()
		tween.tween_property(value_label, "scale", original_scale * 1.5, 0.1)
		tween.tween_property(value_label, "scale", original_scale, 0.1)

		# Flash color
		var original_color = value_label.get_theme_color("font_color", "Label")
		value_label.add_theme_color_override("font_color", Color.GREEN)
		await get_tree().create_timer(0.5).timeout
		value_label.add_theme_color_override("font_color", original_color)

func _on_stat_changed(stat_name: String, old_value: float, new_value: float):
	refresh_stats()

func _on_level_up(new_level: int):
	# Show level up animation
	var label = Label.new()
	label.text = "LEVEL UP!\n%d" % new_level
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", Color.GOLD)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = size / 2
	add_child(label)

	var tween = create_tween()
	tween.tween_property(label, "scale", Vector2(2, 2), 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.0).set_delay(1.0)
	await tween.finished
	label.queue_free()

	refresh_all()

func _input(event):
	if is_open and event.is_action_pressed("ui_cancel"):
		close()
