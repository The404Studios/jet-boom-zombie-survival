extends Control
class_name RPGMenu

# Main RPG Menu Controller
# Manages character stats, skills, equipment, and inventory tabs

signal menu_closed

enum Tab {
	CHARACTER,
	SKILLS,
	INVENTORY,
	EQUIPMENT
}

var current_tab: Tab = Tab.CHARACTER
var is_open: bool = false

# Player references
var player: Node = null
var character_attributes: CharacterAttributes = null
var skill_tree: SkillTree = null
var equipment_system: EquipmentSystem = null
var inventory_system: Node = null
var player_conditions: PlayerConditions = null

# UI References
@onready var tab_bar: HBoxContainer = $TabBar
@onready var content_container: Control = $ContentContainer
@onready var character_panel: Control = $ContentContainer/CharacterPanel
@onready var skills_panel: Control = $ContentContainer/SkillsPanel
@onready var inventory_panel: Control = $ContentContainer/InventoryPanel
@onready var equipment_panel: Control = $ContentContainer/EquipmentPanel

func _ready():
	visible = false
	_setup_tabs()

func _input(event):
	if event.is_action_pressed("ui_cancel") and is_open:
		close_menu()
	elif event.is_action_pressed("character_menu"):
		toggle_menu()

func _setup_tabs():
	# Connect tab buttons
	if tab_bar:
		for i in tab_bar.get_child_count():
			var button = tab_bar.get_child(i)
			if button is Button:
				button.pressed.connect(_on_tab_pressed.bind(i))

func toggle_menu():
	if is_open:
		close_menu()
	else:
		open_menu()

func open_menu():
	# Find player and systems
	player = get_tree().get_first_node_in_group("player")
	if player:
		if player.has_node("CharacterAttributes"):
			character_attributes = player.get_node("CharacterAttributes")
		if player.has_node("SkillTree"):
			skill_tree = player.get_node("SkillTree")
		if player.has_node("EquipmentSystem"):
			equipment_system = player.get_node("EquipmentSystem")
		if player.has_node("InventorySystem"):
			inventory_system = player.get_node("InventorySystem")
		if player.has_node("PlayerConditions"):
			player_conditions = player.get_node("PlayerConditions")

	is_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Refresh current tab
	_show_tab(current_tab)

func close_menu():
	is_open = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	menu_closed.emit()

func _on_tab_pressed(tab_index: int):
	current_tab = tab_index as Tab
	_show_tab(current_tab)

func _show_tab(tab: Tab):
	# Hide all panels
	if character_panel:
		character_panel.visible = false
	if skills_panel:
		skills_panel.visible = false
	if inventory_panel:
		inventory_panel.visible = false
	if equipment_panel:
		equipment_panel.visible = false

	# Show selected panel and refresh
	match tab:
		Tab.CHARACTER:
			if character_panel:
				character_panel.visible = true
				_refresh_character_panel()
		Tab.SKILLS:
			if skills_panel:
				skills_panel.visible = true
				_refresh_skills_panel()
		Tab.INVENTORY:
			if inventory_panel:
				inventory_panel.visible = true
				_refresh_inventory_panel()
		Tab.EQUIPMENT:
			if equipment_panel:
				equipment_panel.visible = true
				_refresh_equipment_panel()

# ============================================
# CHARACTER PANEL
# ============================================

func _refresh_character_panel():
	if not character_panel or not character_attributes:
		return

	# Update attribute labels
	var attrs = character_attributes.get_all_attributes()
	var derived = character_attributes.get_derived_stats()

	# Find and update labels
	_set_label(character_panel, "StrengthValue", str(attrs.strength))
	_set_label(character_panel, "AgilityValue", str(attrs.agility))
	_set_label(character_panel, "VitalityValue", str(attrs.vitality))
	_set_label(character_panel, "IntelligenceValue", str(attrs.intelligence))
	_set_label(character_panel, "EnduranceValue", str(attrs.endurance))
	_set_label(character_panel, "LuckValue", str(attrs.luck))

	# Derived stats
	_set_label(character_panel, "HealthValue", "%.0f" % derived.max_health)
	_set_label(character_panel, "StaminaValue", "%.0f" % derived.max_stamina)
	_set_label(character_panel, "ArmorValue", "%.0f" % derived.armor)
	_set_label(character_panel, "DamageValue", "+%.0f" % derived.melee_damage)
	_set_label(character_panel, "CritChanceValue", "%.1f%%" % (derived.crit_chance * 100))
	_set_label(character_panel, "DodgeValue", "%.1f%%" % derived.dodge_chance)

	# Level and experience
	_set_label(character_panel, "LevelValue", str(character_attributes.level))
	_set_label(character_panel, "ExpValue", "%d / %d" % [character_attributes.experience, character_attributes.experience_to_next_level])
	_set_label(character_panel, "PointsValue", str(character_attributes.available_attribute_points))

	# Update experience bar if exists
	var exp_bar = character_panel.find_child("ExperienceBar")
	if exp_bar is ProgressBar:
		exp_bar.max_value = character_attributes.experience_to_next_level
		exp_bar.value = character_attributes.experience

	# Update attribute buttons
	_update_attribute_buttons()

func _update_attribute_buttons():
	if not character_panel or not character_attributes:
		return

	var has_points = character_attributes.available_attribute_points > 0

	var attrs = ["Strength", "Agility", "Vitality", "Intelligence", "Endurance", "Luck"]
	for attr in attrs:
		var button = character_panel.find_child(attr + "Plus")
		if button is Button:
			button.disabled = not has_points

func _on_attribute_plus_pressed(attribute_name: String):
	if character_attributes and character_attributes.spend_attribute_point(attribute_name):
		_refresh_character_panel()

# ============================================
# SKILLS PANEL
# ============================================

func _refresh_skills_panel():
	if not skills_panel or not skill_tree:
		return

	# Update skill points display
	_set_label(skills_panel, "SkillPointsValue", str(skill_tree.skill_points))

	# Update each skill display
	var skill_container = skills_panel.find_child("SkillGrid")
	if not skill_container:
		return

	# Clear existing skill nodes
	for child in skill_container.get_children():
		child.queue_free()

	# Add skill nodes by category
	var categories = [SkillTree.SkillCategory.COMBAT, SkillTree.SkillCategory.SURVIVAL,
					  SkillTree.SkillCategory.UTILITY, SkillTree.SkillCategory.SPECIAL]

	for category in categories:
		var skills = skill_tree.get_skills_by_category(category)
		for skill_id in skills:
			var skill_node = _create_skill_node(skill_id)
			if skill_node:
				skill_container.add_child(skill_node)

func _create_skill_node(skill_id: String) -> Control:
	var info = skill_tree.get_skill_info(skill_id)
	if info.is_empty():
		return null

	var container = VBoxContainer.new()
	container.custom_minimum_size = Vector2(120, 80)

	# Skill name
	var name_label = Label.new()
	name_label.text = info.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(name_label)

	# Level display
	var level_label = Label.new()
	level_label.text = "%d / %d" % [info.current_level, info.max_level]
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(level_label)

	# Upgrade button
	var button = Button.new()
	button.text = "+" if info.can_unlock else "Locked"
	button.disabled = not info.can_unlock
	button.pressed.connect(_on_skill_upgrade_pressed.bind(skill_id))
	container.add_child(button)

	return container

func _on_skill_upgrade_pressed(skill_id: String):
	if skill_tree and skill_tree.unlock_skill(skill_id):
		_refresh_skills_panel()

# ============================================
# INVENTORY PANEL
# ============================================

func _refresh_inventory_panel():
	if not inventory_panel:
		return

	var grid = inventory_panel.find_child("InventoryGrid")
	if not grid:
		return

	# Clear existing slots
	for child in grid.get_children():
		child.queue_free()

	# Get inventory items
	if inventory_system and "inventory" in inventory_system:
		for i in range(20):  # 20 slots
			var slot = _create_inventory_slot(i)
			grid.add_child(slot)

			if i < inventory_system.inventory.size():
				var item_data = inventory_system.inventory[i]
				_fill_slot(slot, item_data)

func _create_inventory_slot(index: int) -> Control:
	var slot = Button.new()
	slot.custom_minimum_size = Vector2(64, 64)
	slot.text = ""
	slot.name = "Slot%d" % index
	return slot

func _fill_slot(slot: Control, item_data: Dictionary):
	if not slot is Button:
		return

	if "item" in item_data and item_data.item:
		var item = item_data.item
		slot.text = item.item_name if "item_name" in item else "Item"
		slot.tooltip_text = _get_item_tooltip(item)

func _get_item_tooltip(item: Resource) -> String:
	var tooltip = ""
	if "item_name" in item:
		tooltip += item.item_name + "\n"
	if "description" in item:
		tooltip += item.description + "\n"
	if "rarity" in item:
		tooltip += "Rarity: " + str(item.rarity) + "\n"
	return tooltip

# ============================================
# EQUIPMENT PANEL
# ============================================

func _refresh_equipment_panel():
	if not equipment_panel or not equipment_system:
		return

	# Update each equipment slot
	var slots = equipment_system.get_all_slots()
	for slot_name in slots:
		var item = equipment_system.get_item_in_slot(slot_name)
		var slot_button = equipment_panel.find_child(slot_name.capitalize() + "Slot")
		if slot_button is Button:
			if item and "item_name" in item:
				slot_button.text = item.item_name
			else:
				slot_button.text = EquipmentSystem.get_slot_display_name(slot_name)

	# Update total stats display
	var _bonuses = equipment_system.get_total_bonuses()
	_set_label(equipment_panel, "TotalArmorValue", "%.0f" % equipment_system.get_total_armor())

	# Display active conditions
	_refresh_conditions_display()

func _refresh_conditions_display():
	if not equipment_panel or not player_conditions:
		return

	var conditions_container = equipment_panel.find_child("ConditionsContainer")
	if not conditions_container:
		return

	# Clear existing
	for child in conditions_container.get_children():
		child.queue_free()

	# Add active conditions
	var conditions = player_conditions.get_active_conditions_display()
	for cond in conditions:
		var label = Label.new()
		label.text = "%s x%d (%.1fs)" % [cond.name, cond.stacks, cond.time_remaining]
		label.add_theme_color_override("font_color", cond.color)
		conditions_container.add_child(label)

# ============================================
# UTILITY
# ============================================

func _set_label(parent: Control, label_name: String, text: String):
	var label = parent.find_child(label_name)
	if label is Label:
		label.text = text

func is_menu_open() -> bool:
	return is_open
