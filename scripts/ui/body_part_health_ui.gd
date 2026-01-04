extends Control
class_name BodyPartHealthUI

# Body Part Health UI
# Visual representation of body part health with healing functionality
# Shows a body silhouette with clickable limbs and status effects

signal heal_requested(part: int)

# Body part system reference
var body_part_health: BodyPartHealth = null

# UI Elements
var body_container: Control = null
var effect_container: HBoxContainer = null
var healing_overlay: Control = null
var healing_progress_bar: ProgressBar = null
var healing_label: Label = null

# Body part buttons/panels
var body_part_panels: Dictionary = {}  # BodyPart enum -> Panel

# Colors for health states
const COLOR_HEALTHY = Color(0.2, 0.8, 0.2)       # Green
const COLOR_DAMAGED = Color(0.9, 0.7, 0.1)       # Yellow
const COLOR_CRITICAL = Color(0.9, 0.3, 0.1)      # Orange
const COLOR_BLACKED_OUT = Color(0.1, 0.1, 0.1)   # Dark gray/black
const COLOR_BLEEDING = Color(0.8, 0.0, 0.0)      # Red

# Layout positions for body parts (relative to container center)
const PART_POSITIONS = {
	BodyPartHealth.BodyPart.HEAD: Vector2(0, -120),
	BodyPartHealth.BodyPart.CHEST: Vector2(0, -60),
	BodyPartHealth.BodyPart.THORAX: Vector2(0, 0),
	BodyPartHealth.BodyPart.LEFT_ARM: Vector2(-50, -50),
	BodyPartHealth.BodyPart.RIGHT_ARM: Vector2(50, -50),
	BodyPartHealth.BodyPart.LEFT_HAND: Vector2(-70, -10),
	BodyPartHealth.BodyPart.RIGHT_HAND: Vector2(70, -10),
	BodyPartHealth.BodyPart.LEFT_LEG: Vector2(-25, 60),
	BodyPartHealth.BodyPart.RIGHT_LEG: Vector2(25, 60),
	BodyPartHealth.BodyPart.LEFT_FOOT: Vector2(-30, 110),
	BodyPartHealth.BodyPart.RIGHT_FOOT: Vector2(30, 110)
}

# Part sizes
const PART_SIZES = {
	BodyPartHealth.BodyPart.HEAD: Vector2(35, 35),
	BodyPartHealth.BodyPart.CHEST: Vector2(50, 40),
	BodyPartHealth.BodyPart.THORAX: Vector2(45, 35),
	BodyPartHealth.BodyPart.LEFT_ARM: Vector2(20, 50),
	BodyPartHealth.BodyPart.RIGHT_ARM: Vector2(20, 50),
	BodyPartHealth.BodyPart.LEFT_HAND: Vector2(15, 20),
	BodyPartHealth.BodyPart.RIGHT_HAND: Vector2(15, 20),
	BodyPartHealth.BodyPart.LEFT_LEG: Vector2(22, 55),
	BodyPartHealth.BodyPart.RIGHT_LEG: Vector2(22, 55),
	BodyPartHealth.BodyPart.LEFT_FOOT: Vector2(18, 15),
	BodyPartHealth.BodyPart.RIGHT_FOOT: Vector2(18, 15)
}

# Effect icon references
var effect_icons: Dictionary = {}  # effect_name -> CircularEffectIcon

func _ready():
	# Create UI structure
	_create_ui_structure()

	# Wait a frame then find body part health system
	await get_tree().process_frame
	_find_body_part_health()

func _find_body_part_health():
	"""Find the BodyPartHealth node on the player"""
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_node("BodyPartHealth"):
		connect_to_body_part_health(player.get_node("BodyPartHealth"))
	else:
		# Create one if it doesn't exist
		if player:
			var bph = BodyPartHealth.new()
			bph.name = "BodyPartHealth"
			player.add_child(bph)
			connect_to_body_part_health(bph)

func connect_to_body_part_health(bph: BodyPartHealth):
	"""Connect to a BodyPartHealth instance"""
	body_part_health = bph

	# Connect signals
	if not body_part_health.body_part_damaged.is_connected(_on_body_part_damaged):
		body_part_health.body_part_damaged.connect(_on_body_part_damaged)
	if not body_part_health.body_part_healed.is_connected(_on_body_part_healed):
		body_part_health.body_part_healed.connect(_on_body_part_healed)
	if not body_part_health.body_part_blacked_out.is_connected(_on_body_part_blacked_out):
		body_part_health.body_part_blacked_out.connect(_on_body_part_blacked_out)
	if not body_part_health.body_part_restored.is_connected(_on_body_part_restored):
		body_part_health.body_part_restored.connect(_on_body_part_restored)
	if not body_part_health.bleeding_started.is_connected(_on_bleeding_started):
		body_part_health.bleeding_started.connect(_on_bleeding_started)
	if not body_part_health.bleeding_stopped.is_connected(_on_bleeding_stopped):
		body_part_health.bleeding_stopped.connect(_on_bleeding_stopped)
	if not body_part_health.healing_started.is_connected(_on_healing_started):
		body_part_health.healing_started.connect(_on_healing_started)
	if not body_part_health.healing_progress.is_connected(_on_healing_progress):
		body_part_health.healing_progress.connect(_on_healing_progress)
	if not body_part_health.healing_completed.is_connected(_on_healing_completed):
		body_part_health.healing_completed.connect(_on_healing_completed)
	if not body_part_health.healing_cancelled.is_connected(_on_healing_cancelled):
		body_part_health.healing_cancelled.connect(_on_healing_cancelled)
	if not body_part_health.status_effect_applied.is_connected(_on_effect_applied):
		body_part_health.status_effect_applied.connect(_on_effect_applied)
	if not body_part_health.status_effect_removed.is_connected(_on_effect_removed):
		body_part_health.status_effect_removed.connect(_on_effect_removed)

	# Initialize display
	_update_all_parts()

func _create_ui_structure():
	"""Create the full UI structure"""
	# Main container
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	custom_minimum_size = Vector2(200, 300)
	offset_left = 10
	offset_bottom = -10
	offset_right = 210
	offset_top = -310

	# Background panel
	var bg = Panel.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.15, 0.85)
	bg_style.corner_radius_top_left = 8
	bg_style.corner_radius_top_right = 8
	bg_style.corner_radius_bottom_left = 8
	bg_style.corner_radius_bottom_right = 8
	bg_style.border_width_left = 2
	bg_style.border_width_right = 2
	bg_style.border_width_top = 2
	bg_style.border_width_bottom = 2
	bg_style.border_color = Color(0.3, 0.3, 0.4)
	bg.add_theme_stylebox_override("panel", bg_style)
	add_child(bg)

	# Title label
	var title = Label.new()
	title.name = "Title"
	title.text = "HEALTH STATUS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 5
	title.offset_bottom = 25
	add_child(title)

	# Body container (centered area for body parts)
	body_container = Control.new()
	body_container.name = "BodyContainer"
	body_container.set_anchors_preset(Control.PRESET_CENTER)
	body_container.offset_left = -100
	body_container.offset_right = 100
	body_container.offset_top = -100
	body_container.offset_bottom = 100
	add_child(body_container)

	# Create body part panels
	for part in BodyPartHealth.BodyPart.values():
		_create_body_part_panel(part)

	# Effect icons container at bottom
	effect_container = HBoxContainer.new()
	effect_container.name = "EffectContainer"
	effect_container.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	effect_container.offset_top = -40
	effect_container.offset_bottom = -5
	effect_container.offset_left = 5
	effect_container.offset_right = -5
	effect_container.add_theme_constant_override("separation", 4)
	add_child(effect_container)

	# Healing overlay (shown when healing)
	_create_healing_overlay()

func _create_body_part_panel(part: int):
	"""Create a panel for a body part"""
	var panel = Panel.new()
	panel.name = BodyPartHealth.PART_NAMES[part].replace(" ", "_")

	# Position and size
	var pos = PART_POSITIONS.get(part, Vector2.ZERO)
	var size = PART_SIZES.get(part, Vector2(30, 30))

	panel.custom_minimum_size = size
	panel.size = size
	panel.position = pos - size / 2

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_HEALTHY
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.2, 0.2, 0.2)
	panel.add_theme_stylebox_override("panel", style)

	# Health label
	var hp_label = Label.new()
	hp_label.name = "HPLabel"
	hp_label.text = ""
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_label.add_theme_font_size_override("font_size", 9)
	hp_label.add_theme_color_override("font_color", Color(1, 1, 1))
	hp_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	hp_label.add_theme_constant_override("shadow_offset_x", 1)
	hp_label.add_theme_constant_override("shadow_offset_y", 1)
	panel.add_child(hp_label)

	# Make clickable
	var button = Button.new()
	button.name = "Button"
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.flat = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Store part index for click handling
	button.set_meta("part", part)
	button.pressed.connect(_on_part_clicked.bind(part))
	button.mouse_entered.connect(_on_part_hover.bind(part, true))
	button.mouse_exited.connect(_on_part_hover.bind(part, false))
	panel.add_child(button)

	body_container.add_child(panel)
	body_part_panels[part] = panel

func _create_healing_overlay():
	"""Create the healing progress overlay"""
	healing_overlay = Control.new()
	healing_overlay.name = "HealingOverlay"
	healing_overlay.set_anchors_preset(Control.PRESET_CENTER)
	healing_overlay.custom_minimum_size = Vector2(150, 60)
	healing_overlay.offset_left = -75
	healing_overlay.offset_right = 75
	healing_overlay.offset_top = -30
	healing_overlay.offset_bottom = 30
	healing_overlay.visible = false
	add_child(healing_overlay)

	# Background
	var overlay_bg = Panel.new()
	overlay_bg.name = "OverlayBG"
	overlay_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var overlay_style = StyleBoxFlat.new()
	overlay_style.bg_color = Color(0.15, 0.15, 0.2, 0.95)
	overlay_style.corner_radius_top_left = 6
	overlay_style.corner_radius_top_right = 6
	overlay_style.corner_radius_bottom_left = 6
	overlay_style.corner_radius_bottom_right = 6
	overlay_style.border_width_left = 2
	overlay_style.border_width_right = 2
	overlay_style.border_width_top = 2
	overlay_style.border_width_bottom = 2
	overlay_style.border_color = Color(0.3, 0.8, 0.3)
	overlay_bg.add_theme_stylebox_override("panel", overlay_style)
	healing_overlay.add_child(overlay_bg)

	# VBox for label and progress
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 10
	vbox.offset_right = -10
	vbox.offset_top = 8
	vbox.offset_bottom = -8
	vbox.add_theme_constant_override("separation", 4)
	healing_overlay.add_child(vbox)

	# Healing label
	healing_label = Label.new()
	healing_label.name = "HealingLabel"
	healing_label.text = "Healing..."
	healing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	healing_label.add_theme_font_size_override("font_size", 12)
	healing_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	vbox.add_child(healing_label)

	# Progress bar
	healing_progress_bar = ProgressBar.new()
	healing_progress_bar.name = "HealingProgress"
	healing_progress_bar.max_value = 100.0
	healing_progress_bar.value = 0.0
	healing_progress_bar.show_percentage = false
	healing_progress_bar.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(healing_progress_bar)

func _update_all_parts():
	"""Update all body part displays"""
	if not body_part_health:
		return

	for part in BodyPartHealth.BodyPart.values():
		_update_part_display(part)

func _update_part_display(part: int):
	"""Update display for a specific body part"""
	if not body_part_health or not body_part_panels.has(part):
		return

	var panel = body_part_panels[part]
	var hp_label = panel.get_node_or_null("HPLabel")

	var current_hp = body_part_health.get_part_health(part)
	var max_hp = body_part_health.get_part_max_health(part)
	var is_blacked = body_part_health.is_part_blacked_out(part)
	var is_bleeding = body_part_health.is_part_bleeding(part)

	# Update HP text
	if hp_label:
		if is_blacked:
			hp_label.text = "X"
		else:
			hp_label.text = "%d" % int(current_hp)

	# Determine color based on state
	var color = COLOR_HEALTHY
	if is_blacked:
		color = COLOR_BLACKED_OUT
	elif is_bleeding:
		color = COLOR_BLEEDING
	else:
		var hp_percent = current_hp / max_hp if max_hp > 0 else 0
		if hp_percent < 0.25:
			color = COLOR_CRITICAL
		elif hp_percent < 0.6:
			color = COLOR_DAMAGED

	# Apply color with animation
	_animate_part_color(panel, color)

func _animate_part_color(panel: Panel, target_color: Color):
	"""Animate panel color change"""
	var style = panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		var new_style = style.duplicate()
		new_style.bg_color = target_color
		panel.add_theme_stylebox_override("panel", new_style)

# ============================================
# SIGNAL HANDLERS
# ============================================

func _on_body_part_damaged(part_name: String, _new_health: float, _max_health: float):
	var part = _get_part_from_name(part_name)
	if part >= 0:
		_update_part_display(part)
		_flash_part(part, Color.RED)

func _on_body_part_healed(part_name: String, _new_health: float, _max_health: float):
	var part = _get_part_from_name(part_name)
	if part >= 0:
		_update_part_display(part)
		_flash_part(part, Color.GREEN)

func _on_body_part_blacked_out(part_name: String):
	var part = _get_part_from_name(part_name)
	if part >= 0:
		_update_part_display(part)
		_pulse_part(part, COLOR_BLEEDING)

func _on_body_part_restored(part_name: String):
	var part = _get_part_from_name(part_name)
	if part >= 0:
		_update_part_display(part)

func _on_bleeding_started(part_name: String):
	var part = _get_part_from_name(part_name)
	if part >= 0:
		_start_bleeding_animation(part)

func _on_bleeding_stopped(part_name: String):
	var part = _get_part_from_name(part_name)
	if part >= 0:
		_stop_bleeding_animation(part)

func _on_healing_started(part_name: String):
	healing_overlay.visible = true
	healing_label.text = "Healing %s..." % part_name
	healing_progress_bar.value = 0

func _on_healing_progress(part_name: String, progress: float):
	healing_progress_bar.value = progress * 100.0
	healing_label.text = "Healing %s... %d%%" % [part_name, int(progress * 100)]

func _on_healing_completed(part_name: String):
	healing_overlay.visible = false
	var part = _get_part_from_name(part_name)
	if part >= 0:
		_update_part_display(part)
		_flash_part(part, Color.GREEN)

func _on_healing_cancelled(_part_name: String):
	healing_overlay.visible = false

func _on_effect_applied(effect_name: String, duration: float):
	"""Add effect icon to UI"""
	if effect_icons.has(effect_name):
		# Update existing
		effect_icons[effect_name].set_duration(duration)
		return

	# Create new effect icon
	var icon = CircularEffectIcon.new()
	icon.setup(effect_name, duration, _get_effect_type(effect_name))
	effect_container.add_child(icon)
	effect_icons[effect_name] = icon

func _on_effect_removed(effect_name: String):
	"""Remove effect icon from UI"""
	if effect_icons.has(effect_name):
		effect_icons[effect_name].queue_free()
		effect_icons.erase(effect_name)

func _get_effect_type(effect_name: String) -> String:
	"""Determine if effect is buff or debuff"""
	if effect_name.contains("Bleeding") or effect_name.contains("Poison"):
		return "debuff"
	elif effect_name.contains("Regen") or effect_name.contains("Shield"):
		return "buff"
	return "neutral"

# ============================================
# INTERACTION
# ============================================

func _on_part_clicked(part: int):
	"""Handle click on body part for healing"""
	if body_part_health and body_part_health.can_heal_part(part):
		heal_requested.emit(part)
		body_part_health.start_healing(part)

func _on_part_hover(part: int, is_hovering: bool):
	"""Show tooltip on hover"""
	if not body_part_health or not body_part_panels.has(part):
		return

	var panel = body_part_panels[part]

	if is_hovering:
		# Highlight
		panel.modulate = Color(1.2, 1.2, 1.2)

		# Show tooltip
		var hp = body_part_health.get_part_health(part)
		var max_hp = body_part_health.get_part_max_health(part)
		var is_blacked = body_part_health.is_part_blacked_out(part)
		var part_name = BodyPartHealth.PART_NAMES[part]

		var tooltip_text = "%s\n%d / %d HP" % [part_name, int(hp), int(max_hp)]
		if is_blacked:
			tooltip_text = "%s\nBLACKED OUT - BLEEDING\nClick to heal" % part_name

		panel.tooltip_text = tooltip_text
	else:
		panel.modulate = Color.WHITE

func _get_part_from_name(part_name: String) -> int:
	"""Convert part name back to enum"""
	for part in BodyPartHealth.BodyPart.values():
		if BodyPartHealth.PART_NAMES[part] == part_name:
			return part
	return -1

# ============================================
# ANIMATIONS
# ============================================

func _flash_part(part: int, flash_color: Color):
	"""Flash a body part with a color"""
	if not body_part_panels.has(part):
		return

	var panel = body_part_panels[part]
	var tween = create_tween()
	tween.tween_property(panel, "modulate", flash_color, 0.1)
	tween.tween_property(panel, "modulate", Color.WHITE, 0.2)

func _pulse_part(part: int, pulse_color: Color):
	"""Continuous pulse animation for critical parts"""
	if not body_part_panels.has(part):
		return

	var panel = body_part_panels[part]
	var tween = create_tween()
	tween.set_loops(3)
	tween.tween_property(panel, "modulate", pulse_color, 0.2)
	tween.tween_property(panel, "modulate", Color.WHITE, 0.2)

func _start_bleeding_animation(part: int):
	"""Start bleeding pulse animation"""
	if not body_part_panels.has(part):
		return

	var panel = body_part_panels[part]

	# Create bleeding animation
	var tween = panel.create_tween()
	tween.set_loops()
	tween.tween_property(panel, "modulate", Color(1.3, 0.8, 0.8), 0.5)
	tween.tween_property(panel, "modulate", Color.WHITE, 0.5)

	panel.set_meta("bleeding_tween", tween)

func _stop_bleeding_animation(part: int):
	"""Stop bleeding pulse animation"""
	if not body_part_panels.has(part):
		return

	var panel = body_part_panels[part]

	if panel.has_meta("bleeding_tween"):
		var tween = panel.get_meta("bleeding_tween") as Tween
		if tween:
			tween.kill()
		panel.remove_meta("bleeding_tween")

	panel.modulate = Color.WHITE

# ============================================
# PROCESS (for updating effects)
# ============================================

func _process(_delta):
	# Update effect icons with current durations
	if body_part_health:
		var effects = body_part_health.get_active_effects()
		for effect_name in effect_icons.keys():
			if effects.has(effect_name):
				var effect = effects[effect_name]
				effect_icons[effect_name].update_progress(effect.duration, effect.max_duration)


# ============================================
# CIRCULAR EFFECT ICON CLASS
# ============================================

class CircularEffectIcon extends Control:
	"""Circular icon with progress ring for status effects"""

	var effect_name: String = ""
	var duration: float = 0.0
	var max_duration: float = 0.0
	var effect_type: String = "neutral"  # "buff", "debuff", "neutral"

	var progress_ring: Control = null
	var icon_label: Label = null
	var duration_label: Label = null

	func _init():
		custom_minimum_size = Vector2(36, 44)

	func _ready():
		_create_structure()

	func _create_structure():
		# Progress ring background
		var ring_bg = ColorRect.new()
		ring_bg.name = "RingBG"
		ring_bg.color = Color(0.2, 0.2, 0.25)
		ring_bg.custom_minimum_size = Vector2(32, 32)
		ring_bg.position = Vector2(2, 0)
		add_child(ring_bg)

		# Progress ring (drawn in _draw)
		progress_ring = Control.new()
		progress_ring.name = "ProgressRing"
		progress_ring.custom_minimum_size = Vector2(32, 32)
		progress_ring.position = Vector2(2, 0)
		progress_ring.draw.connect(_draw_progress_ring)
		add_child(progress_ring)

		# Icon/text in center
		icon_label = Label.new()
		icon_label.name = "IconLabel"
		icon_label.text = _get_icon_text()
		icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon_label.add_theme_font_size_override("font_size", 10)
		icon_label.add_theme_color_override("font_color", _get_effect_color())
		icon_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		icon_label.offset_top = 6
		icon_label.offset_bottom = 26
		add_child(icon_label)

		# Duration text below
		duration_label = Label.new()
		duration_label.name = "DurationLabel"
		duration_label.text = ""
		duration_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		duration_label.add_theme_font_size_override("font_size", 8)
		duration_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		duration_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		duration_label.offset_top = 32
		duration_label.offset_bottom = 44
		add_child(duration_label)

	func setup(p_name: String, p_duration: float, p_type: String):
		effect_name = p_name
		duration = p_duration
		max_duration = p_duration
		effect_type = p_type

		if icon_label:
			icon_label.text = _get_icon_text()
			icon_label.add_theme_color_override("font_color", _get_effect_color())

		tooltip_text = effect_name

	func set_duration(new_duration: float):
		duration = new_duration
		if new_duration > max_duration:
			max_duration = new_duration

	func update_progress(current: float, maximum: float):
		duration = current
		max_duration = maximum

		# Update duration label
		if duration_label:
			if duration < 0:
				duration_label.text = ""  # Infinite
			elif duration < 60:
				duration_label.text = "%ds" % int(duration)
			else:
				duration_label.text = "%dm" % int(duration / 60)

		# Redraw progress ring
		if progress_ring:
			progress_ring.queue_redraw()

	func _get_icon_text() -> String:
		if effect_name.contains("Bleed"):
			return "B"
		elif effect_name.contains("Poison"):
			return "P"
		elif effect_name.contains("Regen"):
			return "R"
		elif effect_name.contains("Shield"):
			return "S"
		elif effect_name.contains("Speed"):
			return "+"
		else:
			return effect_name.substr(0, 1).to_upper()

	func _get_effect_color() -> Color:
		match effect_type:
			"buff":
				return Color(0.3, 0.9, 0.3)  # Green
			"debuff":
				return Color(0.9, 0.3, 0.3)  # Red
			_:
				return Color(0.7, 0.7, 0.9)  # Blue-ish

	func _draw_progress_ring():
		if not progress_ring:
			return

		var center = Vector2(16, 16)
		var radius = 14.0
		var width = 3.0

		# Background circle
		progress_ring.draw_arc(center, radius, 0, TAU, 32, Color(0.3, 0.3, 0.35), width, true)

		# Progress arc
		if max_duration > 0 and duration >= 0:
			var progress = duration / max_duration
			var arc_angle = progress * TAU
			var start_angle = -PI / 2  # Start from top
			progress_ring.draw_arc(center, radius, start_angle, start_angle + arc_angle, 32, _get_effect_color(), width, true)
		elif duration < 0:
			# Infinite - full circle
			progress_ring.draw_arc(center, radius, 0, TAU, 32, _get_effect_color(), width, true)
