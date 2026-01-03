extends Node
# Note: Do not use class_name here - this script is an autoload singleton

# Manages floating damage numbers for visual combat feedback
# Supports different damage types, critical hits, and pooling

signal damage_number_spawned(number: Node)

# Number settings
@export var default_duration: float = 1.0
@export var float_height: float = 1.5
@export var spread_range: float = 0.5
@export var font_size: int = 24
@export var crit_font_size: int = 36

# Colors
@export var damage_color: Color = Color(1, 0.3, 0.3)
@export var heal_color: Color = Color(0.3, 1, 0.3)
@export var crit_color: Color = Color(1, 0.8, 0)
@export var armor_color: Color = Color(0.5, 0.5, 1)
@export var poison_color: Color = Color(0.5, 1, 0.5)
@export var fire_color: Color = Color(1, 0.5, 0)

# Pooling
var number_pool: Array[Label3D] = []
var pool_size: int = 50
var active_numbers: Array[Dictionary] = []  # {node, timer, velocity}

# Camera reference for billboard
var camera: Camera3D = null

func _ready():
	# Pre-populate pool
	for _i in range(pool_size):
		var number = _create_number_label()
		number.visible = false
		number_pool.append(number)
		add_child(number)

func _process(delta):
	# Update camera reference
	if not camera or not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()

	# Update active numbers
	for i in range(active_numbers.size() - 1, -1, -1):
		var data = active_numbers[i]
		var node = data.node as Label3D

		if not is_instance_valid(node):
			active_numbers.remove_at(i)
			continue

		# Update timer
		data.timer -= delta

		if data.timer <= 0:
			# Return to pool
			_return_to_pool(node)
			active_numbers.remove_at(i)
			continue

		# Animate
		var progress = 1.0 - (data.timer / data.duration)

		# Float up
		node.global_position += data.velocity * delta

		# Fade out
		var alpha = 1.0 - ease(progress, 2.0)
		node.modulate.a = alpha

		# Scale effect for crits
		if data.is_crit:
			var scale_factor = 1.0 + sin(progress * PI) * 0.3
			node.pixel_size = 0.005 * scale_factor

func _create_number_label() -> Label3D:
	var label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.pixel_size = 0.005
	label.font_size = font_size
	label.outline_size = 4
	label.modulate = Color.WHITE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _get_from_pool() -> Label3D:
	if number_pool.is_empty():
		var new_label = _create_number_label()
		add_child(new_label)
		return new_label

	return number_pool.pop_back()

func _return_to_pool(label: Label3D):
	label.visible = false
	number_pool.append(label)

# ============================================
# SPAWNING METHODS
# ============================================

func spawn_damage(position: Vector3, damage: float, is_crit: bool = false):
	"""Spawn a damage number"""
	var label = _get_from_pool()
	label.visible = true

	# Position with random spread
	var spread = Vector3(
		randf_range(-spread_range, spread_range),
		randf_range(0, spread_range * 0.5),
		randf_range(-spread_range, spread_range)
	)
	label.global_position = position + spread

	# Format text
	var damage_int = int(damage)
	label.text = str(damage_int)

	if is_crit:
		label.text = str(damage_int) + "!"
		label.modulate = crit_color
		label.font_size = crit_font_size
	else:
		label.modulate = damage_color
		label.font_size = font_size

	# Animation data
	var velocity = Vector3(
		randf_range(-0.5, 0.5),
		float_height / default_duration,
		randf_range(-0.5, 0.5)
	)

	active_numbers.append({
		"node": label,
		"timer": default_duration,
		"duration": default_duration,
		"velocity": velocity,
		"is_crit": is_crit
	})

	damage_number_spawned.emit(label)

func spawn_heal(position: Vector3, amount: float):
	"""Spawn a healing number"""
	var label = _get_from_pool()
	label.visible = true

	var spread = Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
	label.global_position = position + spread

	label.text = "+" + str(int(amount))
	label.modulate = heal_color
	label.font_size = font_size

	var velocity = Vector3(0, float_height / default_duration, 0)

	active_numbers.append({
		"node": label,
		"timer": default_duration,
		"duration": default_duration,
		"velocity": velocity,
		"is_crit": false
	})

func spawn_armor_damage(position: Vector3, damage: float):
	"""Spawn armor damage number"""
	var label = _get_from_pool()
	label.visible = true

	var spread = Vector3(randf_range(-0.3, 0.3), 0.2, randf_range(-0.3, 0.3))
	label.global_position = position + spread

	label.text = str(int(damage))
	label.modulate = armor_color
	label.font_size = int(font_size * 0.8)

	var velocity = Vector3(randf_range(-0.3, 0.3), float_height * 0.8 / default_duration, randf_range(-0.3, 0.3))

	active_numbers.append({
		"node": label,
		"timer": default_duration * 0.8,
		"duration": default_duration * 0.8,
		"velocity": velocity,
		"is_crit": false
	})

func spawn_status_damage(position: Vector3, damage: float, damage_type: String = "poison"):
	"""Spawn status effect damage number"""
	var label = _get_from_pool()
	label.visible = true

	label.global_position = position + Vector3(randf_range(-0.2, 0.2), 0.5, randf_range(-0.2, 0.2))

	label.text = str(int(damage))

	match damage_type:
		"poison":
			label.modulate = poison_color
		"fire":
			label.modulate = fire_color
		_:
			label.modulate = damage_color

	label.font_size = int(font_size * 0.7)

	var velocity = Vector3(0, float_height * 0.5 / default_duration, 0)

	active_numbers.append({
		"node": label,
		"timer": default_duration * 0.7,
		"duration": default_duration * 0.7,
		"velocity": velocity,
		"is_crit": false
	})

func spawn_text(position: Vector3, text: String, color: Color = Color.WHITE, duration: float = -1):
	"""Spawn custom text"""
	if duration < 0:
		duration = default_duration

	var label = _get_from_pool()
	label.visible = true

	label.global_position = position
	label.text = text
	label.modulate = color
	label.font_size = font_size

	var velocity = Vector3(0, float_height / duration, 0)

	active_numbers.append({
		"node": label,
		"timer": duration,
		"duration": duration,
		"velocity": velocity,
		"is_crit": false
	})

func spawn_xp(position: Vector3, amount: int):
	"""Spawn XP gain number"""
	spawn_text(position + Vector3.UP * 0.3, "+%d XP" % amount, Color(0.8, 0.6, 1))

func spawn_points(position: Vector3, amount: int):
	"""Spawn points gain number"""
	spawn_text(position + Vector3.UP * 0.5, "+%d" % amount, Color(1, 0.9, 0.3))

# ============================================
# COMBO SYSTEM
# ============================================

var combo_count: int = 0
var combo_timer: float = 0.0
var combo_timeout: float = 2.0

func add_to_combo(position: Vector3, damage: float):
	"""Add a hit to the combo counter"""
	combo_count += 1
	combo_timer = combo_timeout

	if combo_count >= 3:
		spawn_combo(position)

func _update_combo(delta: float):
	if combo_timer > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			combo_count = 0

func spawn_combo(position: Vector3):
	"""Spawn combo notification"""
	var combo_text = ""
	var color = Color.WHITE

	if combo_count >= 10:
		combo_text = "UNSTOPPABLE! x%d" % combo_count
		color = Color(1, 0.2, 0.8)
	elif combo_count >= 7:
		combo_text = "RAMPAGE! x%d" % combo_count
		color = Color(1, 0.5, 0)
	elif combo_count >= 5:
		combo_text = "KILLING SPREE! x%d" % combo_count
		color = Color(1, 0.8, 0)
	elif combo_count >= 3:
		combo_text = "MULTI-KILL! x%d" % combo_count
		color = Color(0.8, 0.8, 1)

	if not combo_text.is_empty():
		spawn_text(position + Vector3.UP, combo_text, color, 1.5)
