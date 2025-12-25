extends Node3D
class_name WorldHealthBar

# 3D World-space health bar for props, barricades, and other entities
# Billboard-style that always faces the camera

@export var bar_width: float = 1.5
@export var bar_height: float = 0.15
@export var offset_y: float = 2.0
@export var show_text: bool = true
@export var auto_hide_delay: float = 3.0  # Hide bar after no damage for X seconds
@export var always_visible: bool = false

var max_health: float = 100.0
var current_health: float = 100.0
var target_node: Node3D = null
var entity_name: String = ""

var _hide_timer: float = 0.0
var _is_visible: bool = false

# Node references
var background_mesh: MeshInstance3D
var foreground_mesh: MeshInstance3D
var label_3d: Label3D

# Colors
const COLOR_HEALTHY = Color(0.2, 0.9, 0.2, 1.0)  # Green
const COLOR_DAMAGED = Color(0.9, 0.9, 0.2, 1.0)  # Yellow
const COLOR_CRITICAL = Color(0.9, 0.2, 0.2, 1.0)  # Red
const COLOR_BACKGROUND = Color(0.1, 0.1, 0.1, 0.8)

func _ready():
	_create_health_bar()
	visible = always_visible

func _process(delta):
	# Billboard effect - face camera
	var camera = get_viewport().get_camera_3d()
	if camera:
		look_at(camera.global_position, Vector3.UP)
		# Flip to face correctly
		rotation.y += PI

	# Follow target
	if target_node and is_instance_valid(target_node):
		global_position = target_node.global_position + Vector3(0, offset_y, 0)

	# Auto-hide logic
	if not always_visible and _is_visible:
		_hide_timer -= delta
		if _hide_timer <= 0:
			_is_visible = false
			visible = false

func _create_health_bar():
	# Background (dark bar)
	background_mesh = MeshInstance3D.new()
	add_child(background_mesh)

	var bg_quad = QuadMesh.new()
	bg_quad.size = Vector2(bar_width, bar_height)
	background_mesh.mesh = bg_quad

	var bg_mat = StandardMaterial3D.new()
	bg_mat.albedo_color = COLOR_BACKGROUND
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 100
	background_mesh.material_override = bg_mat

	# Foreground (colored health bar)
	foreground_mesh = MeshInstance3D.new()
	add_child(foreground_mesh)

	var fg_quad = QuadMesh.new()
	fg_quad.size = Vector2(bar_width, bar_height * 0.8)
	foreground_mesh.mesh = fg_quad
	foreground_mesh.position.z = -0.01  # Slightly in front

	var fg_mat = StandardMaterial3D.new()
	fg_mat.albedo_color = COLOR_HEALTHY
	fg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fg_mat.no_depth_test = true
	fg_mat.render_priority = 101
	foreground_mesh.material_override = fg_mat

	# Label for text
	if show_text:
		label_3d = Label3D.new()
		add_child(label_3d)
		label_3d.position = Vector3(0, bar_height * 1.5, -0.02)
		label_3d.pixel_size = 0.005
		label_3d.font_size = 32
		label_3d.outline_size = 6
		label_3d.modulate = Color.WHITE
		label_3d.no_depth_test = true
		label_3d.render_priority = 102

func setup(target: Node3D, health: float, max_hp: float, name_text: String = ""):
	"""Initialize the health bar for an entity"""
	target_node = target
	max_health = max_hp
	current_health = health
	entity_name = name_text

	update_display()

	if always_visible:
		visible = true
		_is_visible = true

func update_health(new_health: float, new_max_health: float = -1):
	"""Update health value and refresh display"""
	var took_damage = new_health < current_health

	current_health = new_health
	if new_max_health > 0:
		max_health = new_max_health

	update_display()

	# Show bar when damaged
	if took_damage:
		show_bar()

func show_bar():
	"""Show the health bar temporarily"""
	visible = true
	_is_visible = true
	_hide_timer = auto_hide_delay

func update_display():
	"""Update visual display of health bar"""
	var health_percent = current_health / max_health if max_health > 0 else 0.0
	health_percent = clamp(health_percent, 0.0, 1.0)

	# Update foreground bar width and position
	if foreground_mesh:
		var fg_mesh = foreground_mesh.mesh as QuadMesh
		if fg_mesh:
			var new_width = bar_width * health_percent
			fg_mesh.size.x = max(new_width, 0.01)  # Minimum width to avoid disappearing

			# Align to left side
			var offset = (bar_width - new_width) * 0.5
			foreground_mesh.position.x = -offset

		# Update color based on health
		var mat = foreground_mesh.material_override as StandardMaterial3D
		if mat:
			if health_percent > 0.6:
				mat.albedo_color = COLOR_HEALTHY
			elif health_percent > 0.3:
				mat.albedo_color = COLOR_DAMAGED
			else:
				mat.albedo_color = COLOR_CRITICAL

	# Update label
	if label_3d and show_text:
		if entity_name.length() > 0:
			label_3d.text = "%s\n%.0f / %.0f" % [entity_name, current_health, max_health]
		else:
			label_3d.text = "%.0f / %.0f" % [current_health, max_health]

		# Color label based on health
		if health_percent > 0.6:
			label_3d.modulate = COLOR_HEALTHY
		elif health_percent > 0.3:
			label_3d.modulate = COLOR_DAMAGED
		else:
			label_3d.modulate = COLOR_CRITICAL

func set_always_visible(value: bool):
	always_visible = value
	if value:
		visible = true
		_is_visible = true
