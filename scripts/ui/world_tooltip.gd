extends Control
class_name WorldTooltip

# World-space tooltip that displays above items and follows camera
# Provides detailed item information for ground items

@export var max_display_distance: float = 10.0
@export var fade_start_distance: float = 8.0
@export var vertical_offset: float = 0.8

var target_node: Node3D = null
var camera: Camera3D = null
var panel: PanelContainer
var content_label: RichTextLabel
var is_visible_tooltip: bool = false

const RARITY_COLORS: Dictionary = {
	0: Color(0.7, 0.7, 0.7),     # Common - Gray
	1: Color(0.2, 0.8, 0.2),     # Uncommon - Green
	2: Color(0.2, 0.4, 1.0),     # Rare - Blue
	3: Color(0.6, 0.2, 0.8),     # Epic - Purple
	4: Color(1.0, 0.6, 0.0),     # Legendary - Orange
	5: Color(1.0, 0.2, 0.2),     # Mythic - Red
}

func _ready():
	add_to_group("world_tooltip")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50

	_create_ui()

	# Find camera after scene is ready
	await get_tree().process_frame
	camera = get_viewport().get_camera_3d()

func _create_ui():
	panel = PanelContainer.new()
	panel.name = "Panel"
	add_child(panel)

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	style.border_color = Color(0.4, 0.5, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 3
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	content_label = RichTextLabel.new()
	content_label.name = "ContentLabel"
	content_label.bbcode_enabled = true
	content_label.fit_content = true
	content_label.scroll_active = false
	content_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_label.custom_minimum_size = Vector2(200, 0)
	margin.add_child(content_label)

func _process(_delta):
	if not is_visible_tooltip or not target_node or not camera:
		return

	if not is_instance_valid(target_node):
		hide_tooltip()
		return

	# Check distance
	var distance = camera.global_position.distance_to(target_node.global_position)
	if distance > max_display_distance:
		modulate.a = 0
		return

	# Calculate alpha based on distance
	var alpha = 1.0
	if distance > fade_start_distance:
		alpha = 1.0 - (distance - fade_start_distance) / (max_display_distance - fade_start_distance)
	modulate.a = alpha

	# Position tooltip above item
	var world_pos = target_node.global_position + Vector3(0, vertical_offset, 0)

	# Check if position is in front of camera
	var camera_forward = -camera.global_transform.basis.z
	var to_item = (world_pos - camera.global_position).normalized()
	if camera_forward.dot(to_item) < 0:
		visible = false
		return

	visible = true

	# Project to screen
	var screen_pos = camera.unproject_position(world_pos)

	# Center tooltip on position
	global_position = screen_pos - Vector2(panel.size.x / 2, panel.size.y)

func show_for_item(item_node: Node3D, item_data: Resource = null):
	"""Show tooltip for a world item"""
	if not item_node:
		return

	target_node = item_node

	# Generate tooltip text
	var text = ""

	if item_data:
		text = _generate_item_tooltip(item_data)
	elif item_node.has_method("get_item_data"):
		var data = item_node.get_item_data()
		if data:
			text = _generate_item_tooltip(data)
	else:
		# Fallback to basic info from node
		text = _generate_fallback_tooltip(item_node)

	content_label.text = text
	is_visible_tooltip = true
	visible = true

	# Force size update
	await get_tree().process_frame
	panel.size = Vector2.ZERO

func _generate_item_tooltip(item: Resource) -> String:
	var text = ""

	# Get rarity info
	var rarity = item.rarity if "rarity" in item else 0
	var rarity_color = RARITY_COLORS.get(rarity, RARITY_COLORS[0])
	var item_name = item.item_name if "item_name" in item else "Unknown Item"

	# Name with rarity color
	text += "[b][color=%s]%s[/color][/b]\n" % [rarity_color.to_html(), item_name]

	# Rarity name
	var rarity_name = _get_rarity_name(rarity)
	text += "[color=gray]%s[/color]\n" % rarity_name

	# Stats summary
	if item.has_method("get_compact_tooltip"):
		text += item.get_compact_tooltip()
	else:
		# Basic stats
		if "damage" in item and item.damage > 0:
			text += "[color=red]DMG: %.1f[/color]  " % item.damage
		if "armor_value" in item and item.armor_value > 0:
			text += "[color=cyan]Armor: %.1f[/color]  " % item.armor_value
		if "health_restore" in item and item.health_restore > 0:
			text += "[color=lime]+%.0f HP[/color]  " % item.health_restore

	# Value
	if "value" in item:
		text += "\n[color=gold]Value: %d[/color]" % item.value

	# Pickup hint
	text += "\n[color=silver][E] Pick up[/color]"

	return text

func _generate_fallback_tooltip(node: Node3D) -> String:
	var text = "[b]%s[/b]\n" % node.name.replace("_", " ").capitalize()

	# Check for loot_type metadata
	if node.has_meta("loot_type"):
		text += "[color=gray]%s[/color]\n" % node.get_meta("loot_type")

	# Check for LootItem specific data
	if node is LootItem:
		var loot = node as LootItem
		if loot.loot_type != "":
			text += "[color=gray]%s[/color]\n" % loot.loot_type.capitalize()
		if loot.loot_quantity > 1:
			text += "x%d\n" % loot.loot_quantity

	text += "[color=silver][E] Pick up[/color]"

	return text

func _get_rarity_name(rarity: int) -> String:
	match rarity:
		0: return "Common"
		1: return "Uncommon"
		2: return "Rare"
		3: return "Epic"
		4: return "Legendary"
		5: return "Mythic"
	return "Unknown"

func hide_tooltip():
	is_visible_tooltip = false
	visible = false
	target_node = null

func set_target(node: Node3D):
	target_node = node

# ============================================
# STATIC FACTORY
# ============================================

static func create_tooltip() -> WorldTooltip:
	var tooltip = WorldTooltip.new()
	tooltip.name = "WorldTooltip"
	return tooltip
