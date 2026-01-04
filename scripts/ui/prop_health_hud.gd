extends Control
class_name PropHealthHUD

## HUD overlay showing health bars for nearby props/barricades
## Also shows repair prompts and phase-through status

signal repair_started(prop: Node)
signal repair_stopped(prop: Node)

# UI Elements
var health_bars: Dictionary = {}  # Barricade -> HealthBarUI
var repair_prompt: Label = null
var phase_indicator: Panel = null

# Settings
@export var max_display_distance: float = 15.0
@export var bar_width: float = 80.0
@export var bar_height: float = 8.0
@export var show_owner_name: bool = true

# State
var local_player: Node = null
var prop_manager: Node = null
var is_phasing: bool = false

# Health bar container
var bars_container: Control = null

class HealthBarUI:
	var container: Control
	var background: ColorRect
	var fill: ColorRect
	var name_label: Label
	var hp_label: Label
	var repair_icon: TextureRect
	var barricade: Barricade
	var screen_position: Vector2

func _ready():
	# Create containers
	_create_ui_elements()

	# Get references
	prop_manager = get_node_or_null("/root/PropManager")

	# Connect signals
	if prop_manager:
		prop_manager.prop_placed.connect(_on_prop_placed)
		prop_manager.prop_destroyed.connect(_on_prop_destroyed)

func _process(_delta):
	# Find local player
	if not local_player:
		local_player = get_tree().get_first_node_in_group("local_player")
		if not local_player:
			local_player = get_tree().get_first_node_in_group("players")

	# Update health bars
	_update_health_bars()

	# Update repair prompt
	_update_repair_prompt()

	# Update phase indicator
	_update_phase_indicator()

func _create_ui_elements():
	# Container for health bars
	bars_container = Control.new()
	bars_container.name = "BarsContainer"
	bars_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bars_container)

	# Repair prompt
	repair_prompt = Label.new()
	repair_prompt.name = "RepairPrompt"
	repair_prompt.text = "[E] Hold to Repair"
	repair_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	repair_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	repair_prompt.add_theme_font_size_override("font_size", 16)
	repair_prompt.add_theme_color_override("font_color", Color.WHITE)
	repair_prompt.add_theme_color_override("font_shadow_color", Color.BLACK)
	repair_prompt.add_theme_constant_override("shadow_offset_x", 1)
	repair_prompt.add_theme_constant_override("shadow_offset_y", 1)
	repair_prompt.visible = false
	add_child(repair_prompt)

	# Phase indicator
	phase_indicator = Panel.new()
	phase_indicator.name = "PhaseIndicator"
	phase_indicator.custom_minimum_size = Vector2(200, 40)
	phase_indicator.visible = false

	var phase_label = Label.new()
	phase_label.name = "Label"
	phase_label.text = "PHASING - 50% Speed"
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	phase_label.anchors_preset = Control.PRESET_FULL_RECT
	phase_label.add_theme_color_override("font_color", Color.CYAN)
	phase_indicator.add_child(phase_label)

	# Position at bottom center
	phase_indicator.anchor_left = 0.5
	phase_indicator.anchor_right = 0.5
	phase_indicator.anchor_top = 1.0
	phase_indicator.anchor_bottom = 1.0
	phase_indicator.offset_left = -100
	phase_indicator.offset_right = 100
	phase_indicator.offset_top = -60
	phase_indicator.offset_bottom = -20

	add_child(phase_indicator)

func _update_health_bars():
	if not local_player:
		return

	var camera = get_viewport().get_camera_3d()
	if not camera:
		return

	var player_pos = local_player.global_position

	# Get all barricades
	var barricades = get_tree().get_nodes_in_group("barricades")

	# Track which barricades we've seen
	var seen_barricades: Array = []

	for barricade in barricades:
		if not is_instance_valid(barricade):
			continue

		var barricade_node = barricade as Barricade
		if not barricade_node:
			continue

		# Check distance
		var distance = player_pos.distance_to(barricade_node.global_position)
		if distance > max_display_distance:
			# Remove bar if too far
			if health_bars.has(barricade_node):
				_remove_health_bar(barricade_node)
			continue

		# Check if visible on screen
		if not camera.is_position_in_frustum(barricade_node.global_position):
			if health_bars.has(barricade_node):
				health_bars[barricade_node].container.visible = false
			continue

		seen_barricades.append(barricade_node)

		# Create or update health bar
		if not health_bars.has(barricade_node):
			_create_health_bar(barricade_node)

		_update_health_bar(barricade_node, camera)

	# Remove bars for barricades no longer visible
	var to_remove = []
	for barricade in health_bars:
		if barricade not in seen_barricades:
			to_remove.append(barricade)

	for barricade in to_remove:
		_remove_health_bar(barricade)

func _create_health_bar(barricade: Barricade) -> HealthBarUI:
	var bar_ui = HealthBarUI.new()
	bar_ui.barricade = barricade

	# Container
	bar_ui.container = Control.new()
	bar_ui.container.custom_minimum_size = Vector2(bar_width, bar_height + 20)
	bar_ui.container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Background
	bar_ui.background = ColorRect.new()
	bar_ui.background.color = Color(0.1, 0.1, 0.1, 0.8)
	bar_ui.background.custom_minimum_size = Vector2(bar_width, bar_height)
	bar_ui.background.position = Vector2(0, 12)
	bar_ui.container.add_child(bar_ui.background)

	# Fill
	bar_ui.fill = ColorRect.new()
	bar_ui.fill.color = Color.GREEN
	bar_ui.fill.custom_minimum_size = Vector2(bar_width - 2, bar_height - 2)
	bar_ui.fill.position = Vector2(1, 13)
	bar_ui.container.add_child(bar_ui.fill)

	# Name label
	bar_ui.name_label = Label.new()
	bar_ui.name_label.text = barricade.get_type_name()
	bar_ui.name_label.add_theme_font_size_override("font_size", 10)
	bar_ui.name_label.position = Vector2(0, 0)
	bar_ui.container.add_child(bar_ui.name_label)

	# HP label
	bar_ui.hp_label = Label.new()
	bar_ui.hp_label.text = "%d/%d" % [int(barricade.current_health), int(barricade.max_health)]
	bar_ui.hp_label.add_theme_font_size_override("font_size", 8)
	bar_ui.hp_label.position = Vector2(0, bar_height + 14)
	bar_ui.container.add_child(bar_ui.hp_label)

	bars_container.add_child(bar_ui.container)
	health_bars[barricade] = bar_ui

	# Connect to health changes
	barricade.health_changed.connect(_on_barricade_health_changed.bind(barricade))

	return bar_ui

func _update_health_bar(barricade: Barricade, camera: Camera3D):
	if not health_bars.has(barricade):
		return

	var bar_ui = health_bars[barricade] as HealthBarUI
	if not bar_ui:
		return

	# Calculate screen position
	var world_pos = barricade.global_position + Vector3(0, 1.5, 0)
	var screen_pos = camera.unproject_position(world_pos)

	# Check if behind camera
	var to_barricade = world_pos - camera.global_position
	if camera.global_transform.basis.z.dot(to_barricade) > 0:
		bar_ui.container.visible = false
		return

	bar_ui.container.visible = true
	bar_ui.container.position = screen_pos - Vector2(bar_width / 2, 0)

	# Update health bar
	var health_percent = barricade.get_health_percent()
	bar_ui.fill.size.x = (bar_width - 2) * health_percent

	# Color based on health
	if health_percent > 0.6:
		bar_ui.fill.color = Color.GREEN
	elif health_percent > 0.3:
		bar_ui.fill.color = Color.YELLOW
	else:
		bar_ui.fill.color = Color.RED

	# Update HP text
	bar_ui.hp_label.text = "%d/%d" % [int(barricade.current_health), int(barricade.max_health)]

	# Show repair indicator
	if barricade.is_being_repaired:
		bar_ui.name_label.text = barricade.get_type_name() + " [REPAIRING]"
		bar_ui.name_label.add_theme_color_override("font_color", Color.CYAN)
	else:
		bar_ui.name_label.text = barricade.get_type_name()
		bar_ui.name_label.remove_theme_color_override("font_color")

	# Fade based on distance
	if local_player:
		var distance = local_player.global_position.distance_to(barricade.global_position)
		var alpha = 1.0 - (distance / max_display_distance) * 0.5
		bar_ui.container.modulate.a = alpha

func _remove_health_bar(barricade: Barricade):
	if not health_bars.has(barricade):
		return

	var bar_ui = health_bars[barricade] as HealthBarUI
	if bar_ui and bar_ui.container:
		bar_ui.container.queue_free()

	health_bars.erase(barricade)

func _on_barricade_health_changed(_current: float, _max_hp: float, barricade: Barricade = null):
	if barricade:
		_update_health_bar(barricade, get_viewport().get_camera_3d())

func _on_prop_placed(prop: Node, _owner_id: int):
	if prop is Barricade and local_player:
		var distance = local_player.global_position.distance_to(prop.global_position)
		if distance <= max_display_distance:
			_create_health_bar(prop as Barricade)

func _on_prop_destroyed(prop: Node):
	if prop is Barricade:
		_remove_health_bar(prop as Barricade)

# ============================================
# REPAIR PROMPT
# ============================================

func _update_repair_prompt():
	if not local_player or not repair_prompt:
		return

	var camera = get_viewport().get_camera_3d()
	if not camera:
		return

	# Raycast to find prop player is looking at
	var from = camera.global_position
	var direction = -camera.global_transform.basis.z
	var to = from + direction * 3.0

	var space_state = get_tree().current_scene.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 8  # Props layer

	var result = space_state.intersect_ray(query)

	if result and result.collider is Barricade:
		var barricade = result.collider as Barricade
		if barricade.can_repair():
			repair_prompt.visible = true
			repair_prompt.text = "[E] Hold to Repair (%d%%)" % int(barricade.get_health_percent() * 100)

			# Position prompt near crosshair
			var viewport_size = get_viewport().get_visible_rect().size
			repair_prompt.position = Vector2(viewport_size.x / 2, viewport_size.y / 2 + 50)
			repair_prompt.position.x -= repair_prompt.size.x / 2
			return

	repair_prompt.visible = false

# ============================================
# PHASE INDICATOR
# ============================================

func set_phasing(phasing: bool):
	is_phasing = phasing
	_update_phase_indicator()

func _update_phase_indicator():
	if not phase_indicator:
		return

	phase_indicator.visible = is_phasing

	if is_phasing:
		# Pulse effect
		var time = Time.get_ticks_msec() / 500.0
		var alpha = 0.7 + sin(time) * 0.3
		phase_indicator.modulate.a = alpha

# ============================================
# PUBLIC API
# ============================================

func show_repair_progress(barricade: Barricade, progress: float):
	"""Show repair progress for a specific barricade"""
	if not health_bars.has(barricade):
		return

	var bar_ui = health_bars[barricade] as HealthBarUI
	if bar_ui:
		bar_ui.name_label.text = "%s [REPAIRING %d%%]" % [barricade.get_type_name(), int(progress * 100)]

func get_barricade_at_crosshair() -> Barricade:
	"""Get the barricade the player is looking at"""
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return null

	var from = camera.global_position
	var direction = -camera.global_transform.basis.z
	var to = from + direction * 3.0

	var space_state = get_tree().current_scene.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 8  # Props layer

	var result = space_state.intersect_ray(query)

	if result and result.collider is Barricade:
		return result.collider as Barricade

	return null
