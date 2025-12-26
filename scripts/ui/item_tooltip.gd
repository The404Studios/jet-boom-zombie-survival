extends PanelContainer
class_name ItemTooltip

# Reusable item tooltip component
# Displays detailed item information with proper formatting

@onready var content_label: RichTextLabel = $MarginContainer/ContentLabel

var current_item: Resource = null
var follow_mouse: bool = true
var offset: Vector2 = Vector2(20, 20)

func _ready():
	visible = false
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Create content label if not present
	if not has_node("MarginContainer"):
		var margin = MarginContainer.new()
		margin.name = "MarginContainer"
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_top", 10)
		margin.add_theme_constant_override("margin_bottom", 10)
		add_child(margin)

		content_label = RichTextLabel.new()
		content_label.name = "ContentLabel"
		content_label.bbcode_enabled = true
		content_label.fit_content = true
		content_label.scroll_active = false
		content_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(content_label)

	# Style the panel
	_apply_style()

func _apply_style():
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	style.set_border_width_all(1)
	style.border_color = Color(0.4, 0.4, 0.5)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 4
	add_theme_stylebox_override("panel", style)

func _process(_delta):
	if visible and follow_mouse:
		_position_tooltip()

func _position_tooltip():
	var mouse_pos = get_viewport().get_mouse_position()
	var viewport_size = get_viewport_rect().size

	# Calculate position
	var tooltip_pos = mouse_pos + offset

	# Keep on screen
	if tooltip_pos.x + size.x > viewport_size.x:
		tooltip_pos.x = mouse_pos.x - size.x - offset.x
	if tooltip_pos.y + size.y > viewport_size.y:
		tooltip_pos.y = viewport_size.y - size.y - 10

	global_position = tooltip_pos

func show_item(item: Resource):
	"""Show tooltip for an item resource"""
	if not item:
		hide_tooltip()
		return

	current_item = item

	# Get tooltip text
	var text = ""
	if item.has_method("get_tooltip_text"):
		text = item.get_tooltip_text()
	else:
		text = _generate_basic_tooltip(item)

	_set_content(text)
	visible = true

func show_text(text: String):
	"""Show tooltip with custom text"""
	current_item = null
	_set_content(text)
	visible = true

func hide_tooltip():
	visible = false
	current_item = null

func _set_content(text: String):
	if content_label and is_instance_valid(content_label):
		content_label.text = text
		# Force size update
		await get_tree().process_frame
		if not is_instance_valid(self) or not is_inside_tree():
			return
		custom_minimum_size = Vector2(250, 0)
		size = Vector2.ZERO

func _generate_basic_tooltip(item: Resource) -> String:
	var text = ""

	# Item name
	if "item_name" in item:
		var color = Color.WHITE
		if "rarity" in item and item.has_method("get_rarity_color"):
			color = item.get_rarity_color()
		text += "[b][color=%s]%s[/color][/b]\n" % [color.to_html(), item.item_name]

	# Rarity
	if item.has_method("get_rarity_name"):
		text += "[color=gray]%s[/color]\n\n" % item.get_rarity_name()

	# Basic stats
	if "damage" in item and item.damage > 0:
		text += "Damage: %.1f\n" % item.damage
	if "armor_value" in item and item.armor_value > 0:
		text += "Armor: %.1f\n" % item.armor_value
	if "fire_rate" in item and item.fire_rate > 0:
		text += "Fire Rate: %.1f/s\n" % (1.0 / item.fire_rate)
	if "magazine_size" in item and item.magazine_size > 0:
		text += "Magazine: %d\n" % item.magazine_size

	# Description
	if "description" in item and item.description != "":
		text += "\n[i]%s[/i]" % item.description

	# Value
	if "value" in item:
		text += "\n[color=gold]Value: %d[/color]" % item.value

	return text

# ============================================
# COMPARISON TOOLTIP
# ============================================

func show_comparison(new_item: Resource, equipped_item: Resource):
	"""Show tooltip comparing two items"""
	if not new_item:
		hide_tooltip()
		return

	var text = ""

	# New item header
	text += _generate_basic_tooltip(new_item)

	# Comparison section
	if equipped_item:
		text += "\n\n[color=yellow]--- COMPARISON ---[/color]\n"
		text += _generate_comparison_text(new_item, equipped_item)

	_set_content(text)
	visible = true

func _generate_comparison_text(new_item: Resource, old_item: Resource) -> String:
	var text = ""

	# Compare damage
	if "damage" in new_item and "damage" in old_item:
		var diff = new_item.damage - old_item.damage
		if diff != 0:
			var color = "lime" if diff > 0 else "red"
			var sign = "+" if diff > 0 else ""
			text += "Damage: [color=%s]%s%.1f[/color]\n" % [color, sign, diff]

	# Compare armor
	if "armor_value" in new_item and "armor_value" in old_item:
		var diff = new_item.armor_value - old_item.armor_value
		if diff != 0:
			var color = "lime" if diff > 0 else "red"
			var sign = "+" if diff > 0 else ""
			text += "Armor: [color=%s]%s%.1f[/color]\n" % [color, sign, diff]

	# Compare fire rate (lower is better)
	if "fire_rate" in new_item and "fire_rate" in old_item:
		var new_rate = 1.0 / new_item.fire_rate if new_item.fire_rate > 0 else 0
		var old_rate = 1.0 / old_item.fire_rate if old_item.fire_rate > 0 else 0
		var diff = new_rate - old_rate
		if abs(diff) > 0.01:
			var color = "lime" if diff > 0 else "red"
			var sign = "+" if diff > 0 else ""
			text += "Fire Rate: [color=%s]%s%.1f/s[/color]\n" % [color, sign, diff]

	# Compare crit chance
	if "crit_chance_bonus" in new_item and "crit_chance_bonus" in old_item:
		var diff = new_item.crit_chance_bonus - old_item.crit_chance_bonus
		if abs(diff) > 0.001:
			var color = "lime" if diff > 0 else "red"
			var sign = "+" if diff > 0 else ""
			text += "Crit Chance: [color=%s]%s%.1f%%[/color]\n" % [color, sign, diff * 100]

	if text == "":
		text = "[color=gray]No significant differences[/color]\n"

	return text

# ============================================
# STATIC HELPER
# ============================================

static func create_tooltip() -> ItemTooltip:
	"""Factory method to create a new tooltip instance"""
	var tooltip = ItemTooltip.new()
	tooltip.name = "ItemTooltip"
	tooltip.custom_minimum_size = Vector2(250, 0)
	return tooltip
