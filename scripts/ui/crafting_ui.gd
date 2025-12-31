extends Control
class_name CraftingUI

# Crafting UI with recipe display, material requirements, and crafting progress
# Includes smooth animations and intuitive controls

var crafting_system: CraftingSystem = null

# UI References
var category_tabs: TabContainer
var recipe_list: VBoxContainer
var recipe_details: Panel
var materials_list: VBoxContainer
var craft_button: Button
var progress_bar: ProgressBar
var search_bar: LineEdit

# State
var is_open: bool = false
var selected_recipe: Resource = null
var current_category: int = 0
var search_filter: String = ""

# Styling
const RARITY_COLORS = {
	0: Color(0.6, 0.6, 0.6),
	1: Color(0.2, 0.8, 0.2),
	2: Color(0.2, 0.4, 1.0),
	3: Color(0.6, 0.2, 0.8),
	4: Color(1.0, 0.6, 0.0),
	5: Color(1.0, 0.2, 0.2),
}

const CATEGORY_NAMES = ["Weapons", "Armor", "Consumables", "Materials", "Upgrades", "Special"]
const CATEGORY_ICONS = ["sword", "shield", "potion", "gem", "arrow_up", "star"]

signal crafting_opened
signal crafting_closed

func _ready():
	visible = false
	_find_crafting_system()
	_create_ui()

func _find_crafting_system():
	crafting_system = get_node_or_null("/root/CraftingSystem")
	if not crafting_system:
		# Create one
		crafting_system = CraftingSystem.new()
		crafting_system.name = "CraftingSystem"
		get_tree().root.add_child.call_deferred(crafting_system)

func _create_ui():
	# Main background
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0, 0, 0, 0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# Main container
	var main_panel = Panel.new()
	main_panel.name = "MainPanel"
	main_panel.custom_minimum_size = Vector2(800, 500)
	main_panel.set_anchors_preset(Control.PRESET_CENTER)
	main_panel.size = Vector2(800, 500)
	main_panel.position = Vector2(-400, -250)

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	panel_style.border_color = Color(0.3, 0.5, 0.7)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	main_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(main_panel)

	# Main layout
	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 15)
	hbox.offset_left = 15
	hbox.offset_top = 15
	hbox.offset_right = -15
	hbox.offset_bottom = -15
	main_panel.add_child(hbox)

	# Left side - Categories and recipes
	var left_panel = _create_left_panel()
	hbox.add_child(left_panel)

	# Right side - Recipe details
	recipe_details = _create_details_panel()
	hbox.add_child(recipe_details)

func _create_left_panel() -> Panel:
	var panel = Panel.new()
	panel.name = "LeftPanel"
	panel.custom_minimum_size = Vector2(350, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.9)
	style.border_color = Color(0.2, 0.3, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	vbox.offset_left = 10
	vbox.offset_top = 10
	vbox.offset_right = -10
	vbox.offset_bottom = -10
	panel.add_child(vbox)

	# Header
	var header = HBoxContainer.new()
	var title = Label.new()
	title.text = "CRAFTING"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	header.add_child(title)
	header.add_spacer(false)

	# Close button
	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)
	vbox.add_child(header)

	# Search bar
	search_bar = LineEdit.new()
	search_bar.placeholder_text = "Search recipes..."
	search_bar.text_changed.connect(_on_search_changed)
	var search_style = StyleBoxFlat.new()
	search_style.bg_color = Color(0.1, 0.1, 0.12)
	search_style.border_color = Color(0.3, 0.4, 0.5)
	search_style.set_border_width_all(1)
	search_style.set_corner_radius_all(4)
	search_bar.add_theme_stylebox_override("normal", search_style)
	vbox.add_child(search_bar)

	# Category tabs
	var tab_bar = HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 5)
	for i in range(CATEGORY_NAMES.size()):
		var tab = Button.new()
		tab.text = CATEGORY_NAMES[i]
		tab.toggle_mode = true
		tab.button_pressed = (i == 0)
		tab.custom_minimum_size = Vector2(50, 28)
		tab.add_theme_font_size_override("font_size", 11)
		tab.pressed.connect(_on_category_selected.bind(i))
		tab_bar.add_child(tab)
	vbox.add_child(tab_bar)

	# Recipe list
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	recipe_list = VBoxContainer.new()
	recipe_list.name = "RecipeList"
	recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_list.add_theme_constant_override("separation", 5)
	scroll.add_child(recipe_list)

	return panel

func _create_details_panel() -> Panel:
	var panel = Panel.new()
	panel.name = "DetailsPanel"
	panel.custom_minimum_size = Vector2(380, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.9)
	style.border_color = Color(0.2, 0.3, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.name = "Content"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	vbox.offset_left = 15
	vbox.offset_top = 15
	vbox.offset_right = -15
	vbox.offset_bottom = -15
	panel.add_child(vbox)

	# Recipe name
	var name_label = Label.new()
	name_label.name = "RecipeName"
	name_label.text = "Select a Recipe"
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	vbox.add_child(name_label)

	# Description
	var desc_label = Label.new()
	desc_label.name = "Description"
	desc_label.text = ""
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	vbox.add_child(desc_label)

	vbox.add_child(HSeparator.new())

	# Materials header
	var mat_header = Label.new()
	mat_header.text = "REQUIRED MATERIALS"
	mat_header.add_theme_font_size_override("font_size", 14)
	mat_header.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	vbox.add_child(mat_header)

	# Materials list
	materials_list = VBoxContainer.new()
	materials_list.name = "MaterialsList"
	materials_list.add_theme_constant_override("separation", 6)
	vbox.add_child(materials_list)

	vbox.add_spacer(false)

	# Craft time
	var time_label = Label.new()
	time_label.name = "CraftTime"
	time_label.text = "Craft Time: --"
	time_label.add_theme_font_size_override("font_size", 12)
	time_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	vbox.add_child(time_label)

	# Progress bar
	progress_bar = ProgressBar.new()
	progress_bar.name = "ProgressBar"
	progress_bar.custom_minimum_size = Vector2(0, 20)
	progress_bar.value = 0
	progress_bar.show_percentage = false
	var bar_style = StyleBoxFlat.new()
	bar_style.bg_color = Color(0.15, 0.15, 0.18)
	bar_style.set_corner_radius_all(4)
	progress_bar.add_theme_stylebox_override("background", bar_style)
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(0.2, 0.6, 0.3)
	fill_style.set_corner_radius_all(4)
	progress_bar.add_theme_stylebox_override("fill", fill_style)
	progress_bar.visible = false
	vbox.add_child(progress_bar)

	# Craft button
	craft_button = Button.new()
	craft_button.name = "CraftButton"
	craft_button.text = "CRAFT"
	craft_button.custom_minimum_size = Vector2(0, 40)
	craft_button.disabled = true
	craft_button.pressed.connect(_on_craft_pressed)
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.15, 0.4, 0.25)
	btn_style.border_color = Color(0.3, 0.6, 0.4)
	btn_style.set_border_width_all(2)
	btn_style.set_corner_radius_all(6)
	craft_button.add_theme_stylebox_override("normal", btn_style)
	craft_button.add_theme_font_size_override("font_size", 16)
	vbox.add_child(craft_button)

	return panel

# ============================================
# RECIPE DISPLAY
# ============================================

func _populate_recipes():
	"""Populate recipe list for current category"""
	# Clear existing
	for child in recipe_list.get_children():
		child.queue_free()

	if not crafting_system:
		return

	var recipes = crafting_system.get_all_unlocked_recipes()
	var delay = 0.0

	for recipe in recipes:
		# Filter by category
		var cat = recipe.get_meta("category", 0)
		if cat != current_category:
			continue

		# Filter by search
		var recipe_name = recipe.get_meta("name", "")
		if not search_filter.is_empty():
			if not recipe_name.to_lower().contains(search_filter):
				continue

		var btn = _create_recipe_button(recipe)
		recipe_list.add_child(btn)

		# Stagger animation
		btn.modulate.a = 0
		btn.position.x = -20
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(btn, "modulate:a", 1.0, 0.2).set_delay(delay)
		tween.tween_property(btn, "position:x", 0.0, 0.2).set_delay(delay).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		delay += 0.03

func _create_recipe_button(recipe: Resource) -> Button:
	var btn = Button.new()
	btn.name = recipe.get_meta("name", "Recipe").replace(" ", "_")
	btn.text = recipe.get_meta("name", "Unknown Recipe")
	btn.custom_minimum_size = Vector2(0, 36)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	# Check if craftable
	var check = crafting_system.can_craft(recipe)
	if check.can_craft:
		btn.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	else:
		btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12)
	style.border_color = Color(0.2, 0.3, 0.4) if check.can_craft else Color(0.2, 0.2, 0.2)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = Color(0.15, 0.15, 0.18)
	hover_style.border_color = Color(0.3, 0.5, 0.7)
	btn.add_theme_stylebox_override("hover", hover_style)

	btn.pressed.connect(_on_recipe_selected.bind(recipe))

	return btn

func _update_recipe_details():
	"""Update the details panel for selected recipe"""
	var content = recipe_details.get_node_or_null("Content")
	if not content:
		return

	var name_label = content.get_node_or_null("RecipeName") as Label
	var desc_label = content.get_node_or_null("Description") as Label
	var time_label = content.get_node_or_null("CraftTime") as Label

	if not selected_recipe:
		if name_label:
			name_label.text = "Select a Recipe"
		if desc_label:
			desc_label.text = ""
		craft_button.disabled = true
		_clear_materials()
		return

	# Update name
	if name_label:
		name_label.text = selected_recipe.get_meta("name", "Unknown")

	# Update description
	if desc_label:
		desc_label.text = selected_recipe.get_meta("description", "")

	# Update craft time
	if time_label:
		var craft_time = selected_recipe.get_meta("craft_time", 1.0)
		time_label.text = "Craft Time: %.1fs" % craft_time

	# Update materials
	_update_materials()

	# Update craft button
	var check = crafting_system.can_craft(selected_recipe)
	craft_button.disabled = not check.can_craft
	craft_button.text = "CRAFT" if check.can_craft else "MISSING MATERIALS"

func _clear_materials():
	"""Clear materials list"""
	for child in materials_list.get_children():
		child.queue_free()

func _update_materials():
	"""Update materials list for selected recipe"""
	_clear_materials()

	if not selected_recipe or not crafting_system:
		return

	var materials_needed = selected_recipe.get_meta("materials", {})
	var player_materials = crafting_system.get_player_materials()

	for material_id in materials_needed:
		var needed = materials_needed[material_id]
		var have = player_materials.get(material_id, 0)
		var sufficient = have >= needed

		var hbox = HBoxContainer.new()

		var mat_name = Label.new()
		mat_name.text = material_id.capitalize().replace("_", " ")
		mat_name.custom_minimum_size = Vector2(150, 0)
		mat_name.add_theme_font_size_override("font_size", 13)
		mat_name.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9) if sufficient else Color(0.9, 0.4, 0.4))
		hbox.add_child(mat_name)

		var count_label = Label.new()
		count_label.text = "%d / %d" % [have, needed]
		count_label.add_theme_font_size_override("font_size", 13)
		count_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5) if sufficient else Color(1.0, 0.4, 0.4))
		hbox.add_child(count_label)

		# Checkmark or X
		var status = Label.new()
		status.text = " [OK]" if sufficient else " [X]"
		status.add_theme_font_size_override("font_size", 12)
		status.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5) if sufficient else Color(1.0, 0.4, 0.4))
		hbox.add_child(status)

		materials_list.add_child(hbox)

# ============================================
# INPUT HANDLERS
# ============================================

func _on_category_selected(category: int):
	current_category = category

	# Update tab visuals
	var left_panel = get_node_or_null("MainPanel/LeftPanel") if has_node("MainPanel/LeftPanel") else null
	if left_panel:
		for vbox in left_panel.get_children():
			if vbox is VBoxContainer:
				for child in vbox.get_children():
					if child is HBoxContainer:
						var idx = 0
						for btn in child.get_children():
							if btn is Button and btn.toggle_mode:
								btn.button_pressed = (idx == category)
								idx += 1

	_populate_recipes()

func _on_recipe_selected(recipe: Resource):
	selected_recipe = recipe
	_update_recipe_details()

	# Animate selection
	var tween = create_tween()
	tween.tween_property(recipe_details, "scale", Vector2(1.02, 1.02), 0.1)
	tween.tween_property(recipe_details, "scale", Vector2.ONE, 0.1)

func _on_search_changed(new_text: String):
	search_filter = new_text.to_lower()
	_populate_recipes()

func _on_craft_pressed():
	if not selected_recipe or not crafting_system:
		return

	if crafting_system.start_crafting(selected_recipe):
		_start_crafting_animation()

func _start_crafting_animation():
	"""Show crafting in progress"""
	progress_bar.visible = true
	progress_bar.value = 0
	craft_button.disabled = true
	craft_button.text = "CRAFTING..."

	# Connect to completion if not already
	if not crafting_system.crafting_completed.is_connected(_on_crafting_completed):
		crafting_system.crafting_completed.connect(_on_crafting_completed)

func _process(delta):
	# Update progress bar
	if progress_bar.visible and crafting_system and crafting_system.is_crafting:
		progress_bar.value = crafting_system.get_crafting_progress() * 100

func _on_crafting_completed(_recipe: Resource, _item: Resource):
	"""Handle crafting completion"""
	progress_bar.visible = false
	_update_recipe_details()
	_populate_recipes()

	# Success animation
	_show_craft_success()

func _show_craft_success():
	"""Show crafting success feedback"""
	var label = Label.new()
	label.text = "CRAFTED!"
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER)
	add_child(label)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2(1.5, 1.5), 0.3).from(Vector2(0.5, 0.5)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.5)
	tween.tween_callback(label.queue_free).set_delay(1.0)

# ============================================
# OPEN/CLOSE
# ============================================

func _input(event):
	if event.is_action_pressed("crafting") or (is_open and event.is_action_pressed("ui_cancel")):
		if is_open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()

func toggle():
	if is_open:
		close()
	else:
		open()

func open():
	is_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_animate_open()
	_populate_recipes()
	_update_recipe_details()
	crafting_opened.emit()

func close():
	is_open = false
	_animate_close()
	await get_tree().create_timer(0.25).timeout
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	crafting_closed.emit()

func _animate_open():
	modulate.a = 0
	scale = Vector2(0.9, 0.9)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.25)
	tween.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _animate_close():
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_property(self, "scale", Vector2(0.95, 0.95), 0.2)
