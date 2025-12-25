extends RefCounted
class_name UITheme

# Centralized UI theme and styling for grid-based inventory system
# Provides consistent colors, fonts, and styles across all UI components

# ============================================
# COLOR PALETTE
# ============================================

# Primary colors
const COLOR_BG_DARK: Color = Color(0.06, 0.06, 0.08, 0.98)
const COLOR_BG_MEDIUM: Color = Color(0.1, 0.1, 0.12, 0.95)
const COLOR_BG_LIGHT: Color = Color(0.15, 0.15, 0.18, 0.9)
const COLOR_BG_HOVER: Color = Color(0.2, 0.22, 0.25, 0.95)
const COLOR_BG_SELECTED: Color = Color(0.25, 0.28, 0.32, 0.95)

# Border colors
const COLOR_BORDER_DEFAULT: Color = Color(0.25, 0.25, 0.3)
const COLOR_BORDER_HIGHLIGHT: Color = Color(0.4, 0.5, 0.6)
const COLOR_BORDER_ACTIVE: Color = Color(0.5, 0.7, 0.9)

# Text colors
const COLOR_TEXT_PRIMARY: Color = Color(0.9, 0.92, 0.95)
const COLOR_TEXT_SECONDARY: Color = Color(0.6, 0.62, 0.65)
const COLOR_TEXT_MUTED: Color = Color(0.4, 0.42, 0.45)
const COLOR_TEXT_HIGHLIGHT: Color = Color(1.0, 0.95, 0.8)

# Accent colors
const COLOR_ACCENT_PRIMARY: Color = Color(0.3, 0.6, 0.9)
const COLOR_ACCENT_SUCCESS: Color = Color(0.3, 0.8, 0.4)
const COLOR_ACCENT_WARNING: Color = Color(0.9, 0.7, 0.2)
const COLOR_ACCENT_DANGER: Color = Color(0.9, 0.3, 0.3)
const COLOR_ACCENT_GOLD: Color = Color(1.0, 0.85, 0.3)
const COLOR_ACCENT_SIGILS: Color = Color(0.4, 0.7, 1.0)

# Rarity colors
const RARITY_COLORS: Dictionary = {
	0: Color(0.65, 0.65, 0.65),     # Common - Gray
	1: Color(0.25, 0.85, 0.35),     # Uncommon - Green
	2: Color(0.3, 0.5, 1.0),        # Rare - Blue
	3: Color(0.7, 0.35, 0.9),       # Epic - Purple
	4: Color(1.0, 0.6, 0.15),       # Legendary - Orange
	5: Color(1.0, 0.25, 0.25),      # Mythic - Red
}

const RARITY_NAMES: Array[String] = [
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic"
]

# Status colors
const COLOR_HEALTH: Color = Color(0.85, 0.2, 0.2)
const COLOR_HEALTH_BG: Color = Color(0.3, 0.1, 0.1)
const COLOR_STAMINA: Color = Color(0.2, 0.7, 0.9)
const COLOR_STAMINA_BG: Color = Color(0.1, 0.2, 0.3)
const COLOR_ARMOR: Color = Color(0.5, 0.5, 0.6)
const COLOR_XP: Color = Color(0.6, 0.4, 1.0)

# Inventory slot states
const COLOR_SLOT_EMPTY: Color = Color(0.12, 0.12, 0.14, 0.8)
const COLOR_SLOT_HOVER: Color = Color(0.2, 0.22, 0.25, 0.9)
const COLOR_SLOT_VALID: Color = Color(0.15, 0.35, 0.15, 0.8)
const COLOR_SLOT_INVALID: Color = Color(0.35, 0.15, 0.15, 0.8)
const COLOR_SLOT_SELECTED: Color = Color(0.25, 0.35, 0.5, 0.9)

# ============================================
# FONT SIZES
# ============================================

const FONT_SIZE_TITLE: int = 24
const FONT_SIZE_HEADER: int = 20
const FONT_SIZE_SUBHEADER: int = 16
const FONT_SIZE_BODY: int = 14
const FONT_SIZE_SMALL: int = 12
const FONT_SIZE_TINY: int = 10

# ============================================
# SPACING & SIZING
# ============================================

const PADDING_SMALL: int = 4
const PADDING_MEDIUM: int = 8
const PADDING_LARGE: int = 16
const PADDING_XLARGE: int = 24

const BORDER_WIDTH_THIN: int = 1
const BORDER_WIDTH_NORMAL: int = 2
const BORDER_WIDTH_THICK: int = 3

const CORNER_RADIUS_SMALL: int = 4
const CORNER_RADIUS_MEDIUM: int = 6
const CORNER_RADIUS_LARGE: int = 10

const CELL_SIZE_SMALL: int = 40
const CELL_SIZE_MEDIUM: int = 50
const CELL_SIZE_LARGE: int = 60

# ============================================
# STYLE CREATORS
# ============================================

static func create_panel_style(bg_color: Color = COLOR_BG_MEDIUM, border_color: Color = COLOR_BORDER_DEFAULT, border_width: int = BORDER_WIDTH_NORMAL, corner_radius: int = CORNER_RADIUS_MEDIUM) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	return style

static func create_button_style(bg_color: Color = COLOR_BG_LIGHT, border_color: Color = COLOR_BORDER_DEFAULT) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(BORDER_WIDTH_NORMAL)
	style.set_corner_radius_all(CORNER_RADIUS_SMALL)
	style.content_margin_left = PADDING_MEDIUM
	style.content_margin_right = PADDING_MEDIUM
	style.content_margin_top = PADDING_SMALL
	style.content_margin_bottom = PADDING_SMALL
	return style

static func create_button_hover_style() -> StyleBoxFlat:
	var style = create_button_style(COLOR_BG_HOVER, COLOR_BORDER_HIGHLIGHT)
	return style

static func create_button_pressed_style() -> StyleBoxFlat:
	var style = create_button_style(COLOR_BG_SELECTED, COLOR_ACCENT_PRIMARY)
	return style

static func create_slot_style(bg_color: Color = COLOR_SLOT_EMPTY, rarity: int = -1) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = COLOR_BORDER_DEFAULT if rarity < 0 else get_rarity_color(rarity)
	style.set_border_width_all(BORDER_WIDTH_THIN)
	return style

static func create_tooltip_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_BG_DARK
	style.border_color = COLOR_BORDER_HIGHLIGHT
	style.set_border_width_all(BORDER_WIDTH_NORMAL)
	style.set_corner_radius_all(CORNER_RADIUS_MEDIUM)
	style.content_margin_left = PADDING_MEDIUM
	style.content_margin_right = PADDING_MEDIUM
	style.content_margin_top = PADDING_MEDIUM
	style.content_margin_bottom = PADDING_MEDIUM
	return style

static func create_progress_bar_bg_style(color: Color = COLOR_BG_DARK) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(CORNER_RADIUS_SMALL)
	return style

static func create_progress_bar_fill_style(color: Color = COLOR_ACCENT_PRIMARY) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(CORNER_RADIUS_SMALL)
	return style

# ============================================
# RARITY HELPERS
# ============================================

static func get_rarity_color(rarity: int) -> Color:
	return RARITY_COLORS.get(clamp(rarity, 0, 5), RARITY_COLORS[0])

static func get_rarity_name(rarity: int) -> String:
	return RARITY_NAMES[clamp(rarity, 0, 5)]

static func get_rarity_color_darkened(rarity: int, amount: float = 0.3) -> Color:
	return get_rarity_color(rarity).darkened(amount)

static func get_rarity_color_lightened(rarity: int, amount: float = 0.2) -> Color:
	return get_rarity_color(rarity).lightened(amount)

# ============================================
# LABEL HELPERS
# ============================================

static func style_title_label(label: Label):
	label.add_theme_font_size_override("font_size", FONT_SIZE_TITLE)
	label.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)

static func style_header_label(label: Label):
	label.add_theme_font_size_override("font_size", FONT_SIZE_HEADER)
	label.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)

static func style_body_label(label: Label):
	label.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
	label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)

static func style_small_label(label: Label):
	label.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)

static func style_value_label(label: Label, color: Color = COLOR_ACCENT_SUCCESS):
	label.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
	label.add_theme_color_override("font_color", color)

static func style_currency_label(label: Label):
	label.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
	label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)

static func style_rarity_label(label: Label, rarity: int):
	label.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", get_rarity_color(rarity))

# ============================================
# ANIMATION HELPERS
# ============================================

static func animate_panel_open(panel: Control) -> Tween:
	panel.modulate.a = 0
	panel.scale = Vector2(0.9, 0.9)

	var tween = panel.create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.25).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tween

static func animate_panel_close(panel: Control) -> Tween:
	var tween = panel.create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", 0.0, 0.15)
	tween.tween_property(panel, "scale", Vector2(0.95, 0.95), 0.15)
	return tween

static func animate_slot_hover(slot: Control) -> Tween:
	var tween = slot.create_tween()
	tween.tween_property(slot, "scale", Vector2(1.05, 1.05), 0.1).set_trans(Tween.TRANS_CUBIC)
	return tween

static func animate_slot_unhover(slot: Control) -> Tween:
	var tween = slot.create_tween()
	tween.tween_property(slot, "scale", Vector2(1.0, 1.0), 0.1)
	return tween

static func animate_item_pickup(item: Control) -> Tween:
	var tween = item.create_tween()
	tween.tween_property(item, "modulate:a", 0.7, 0.1)
	tween.parallel().tween_property(item, "scale", Vector2(1.1, 1.1), 0.1)
	return tween

static func animate_item_place(item: Control) -> Tween:
	item.scale = Vector2(1.1, 1.1)
	var tween = item.create_tween()
	tween.tween_property(item, "modulate:a", 1.0, 0.1)
	tween.parallel().tween_property(item, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_BACK)
	return tween

static func flash_invalid(control: Control) -> Tween:
	var original_modulate = control.modulate
	var tween = control.create_tween()
	tween.tween_property(control, "modulate", Color(1.5, 0.5, 0.5), 0.1)
	tween.tween_property(control, "modulate", original_modulate, 0.1)
	return tween

static func flash_success(control: Control) -> Tween:
	var original_modulate = control.modulate
	var tween = control.create_tween()
	tween.tween_property(control, "modulate", Color(0.5, 1.5, 0.5), 0.1)
	tween.tween_property(control, "modulate", original_modulate, 0.1)
	return tween

# ============================================
# RICH TEXT FORMATTING
# ============================================

static func format_item_name(name: String, rarity: int) -> String:
	var color = get_rarity_color(rarity)
	return "[b][color=#%s]%s[/color][/b]" % [color.to_html(), name]

static func format_stat_bonus(stat_name: String, value: float, is_percent: bool = false) -> String:
	var formatted_value = ""
	if is_percent:
		formatted_value = "+%.1f%%" % (value * 100) if value > 0 else "%.1f%%" % (value * 100)
	else:
		formatted_value = "+%.0f" % value if value > 0 else "%.0f" % value

	var color = COLOR_ACCENT_SUCCESS if value > 0 else COLOR_ACCENT_DANGER
	return "[color=#%s]%s %s[/color]" % [color.to_html(), formatted_value, stat_name]

static func format_damage(damage: float) -> String:
	return "[color=#%s]Damage: %.0f[/color]" % [COLOR_ACCENT_DANGER.to_html(), damage]

static func format_armor(armor: float) -> String:
	return "[color=#%s]Armor: %.0f[/color]" % [COLOR_ARMOR.to_html(), armor]

static func format_price(price: int, can_afford: bool = true) -> String:
	var color = COLOR_ACCENT_GOLD if can_afford else COLOR_ACCENT_DANGER
	return "[color=#%s]%d Sigils[/color]" % [color.to_html(), price]

static func format_weight(current: float, max_weight: float) -> String:
	var percent = current / max_weight if max_weight > 0 else 0
	var color = COLOR_ACCENT_DANGER if percent >= 1.0 else (COLOR_ACCENT_WARNING if percent >= 0.8 else COLOR_TEXT_SECONDARY)
	return "[color=#%s]%.1f / %.1f[/color]" % [color.to_html(), current, max_weight]

static func format_size(width: int, height: int) -> String:
	return "[color=#%s]%dx%d[/color]" % [COLOR_TEXT_MUTED.to_html(), width, height]

# ============================================
# TOOLTIP CONTENT BUILDER
# ============================================

static func build_tooltip_content(item: Resource) -> String:
	if not item:
		return ""

	var lines: Array[String] = []

	# Name with rarity
	var item_name = item.item_name if "item_name" in item else "Unknown"
	var rarity = item.rarity if "rarity" in item else 0
	lines.append(format_item_name(item_name, rarity))

	# Rarity and type
	var type_name = "Item"
	if "item_type" in item:
		type_name = _get_item_type_display_name(item.item_type)
	lines.append("[color=#%s]%s %s[/color]" % [get_rarity_color(rarity).to_html(), get_rarity_name(rarity), type_name])

	# Size
	var size = Vector2i(1, 1)
	if "grid_size" in item:
		size = item.grid_size
	elif item.has_meta("grid_size"):
		size = item.get_meta("grid_size")
	lines.append(format_size(size.x, size.y))

	lines.append("")  # Separator

	# Stats
	if "damage" in item and item.damage > 0:
		lines.append(format_damage(item.damage))
	if "armor_value" in item and item.armor_value > 0:
		lines.append(format_armor(item.armor_value))
	if "health_bonus" in item and item.health_bonus > 0:
		lines.append(format_stat_bonus("Health", item.health_bonus))
	if "crit_chance_bonus" in item and item.crit_chance_bonus > 0:
		lines.append(format_stat_bonus("Crit Chance", item.crit_chance_bonus, true))
	if "movement_speed_bonus" in item and item.movement_speed_bonus != 0:
		lines.append(format_stat_bonus("Move Speed", item.movement_speed_bonus, true))

	# Description
	if "description" in item and item.description != "":
		lines.append("")
		lines.append("[color=#%s]%s[/color]" % [COLOR_TEXT_MUTED.to_html(), item.description])

	return "\n".join(lines)

static func _get_item_type_display_name(item_type: int) -> String:
	match item_type:
		0: return "Weapon"  # WEAPON
		1: return "Ammo"
		2: return "Helmet"
		3: return "Chest Armor"
		4: return "Gloves"
		5: return "Boots"
		6: return "Ring"
		7: return "Amulet"
		8: return "Consumable"
		9: return "Material"
		10: return "Augment"
		_: return "Item"
