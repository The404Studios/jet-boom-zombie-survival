extends StaticBody3D

# JetBoom-style props - zombies attack as secondary target
# Players can phase through by holding Z

@export var max_health: float = 500.0
@export var health_per_wave: float = 100.0
@export var prop_name: String = "Prop"

var current_health: float = 500.0
var current_wave: int = 1
var is_destroyed: bool = false

# Phasing mechanic
const PHASE_LAYER = 32  # Layer 6 - dedicated phase layer
const NORMAL_LAYER = 1  # Layer 1 - world geometry

signal prop_damaged(health_remaining: float, health_percent: float)
signal prop_destroyed

@onready var mesh: MeshInstance3D = $MeshInstance3D if has_node("MeshInstance3D") else null
@onready var health_bar: SubViewport = $HealthBarViewport if has_node("HealthBarViewport") else null
@onready var health_bar_sprite: Sprite3D = $HealthBarSprite if has_node("HealthBarSprite") else null

func _ready():
	add_to_group("props")
	add_to_group("zombie_targets")
	_update_visual()
	_setup_health_bar()

func setup_for_wave(wave: int):
	"""Scale health based on wave"""
	current_wave = wave
	max_health = 500.0 + (health_per_wave * (wave - 1))
	current_health = max_health
	_update_visual()

func take_damage(amount: float, attacker: Node = null):
	"""Take damage from zombie"""
	if is_destroyed:
		return

	current_health -= amount
	current_health = max(current_health, 0)

	var health_percent = current_health / max_health

	# Emit signal
	prop_damaged.emit(current_health, health_percent)

	# Update visual
	_update_visual()

	# Play damage sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("wood_hit", global_position, 0.5)

	# Show health bar when damaged
	if health_bar_sprite:
		health_bar_sprite.visible = true

	# Check destroyed
	if current_health <= 0:
		_destroy()

func _update_visual():
	var health_percent = current_health / max_health

	# Update health bar
	_update_health_bar(health_percent)

	# Change material based on damage
	if mesh:
		var mat = mesh.get_active_material(0)
		if mat is StandardMaterial3D:
			# Darken as it takes damage
			var damage_factor = health_percent
			mat.albedo_color = Color(damage_factor, damage_factor, damage_factor, 1.0)

func _setup_health_bar():
	"""Create 3D health bar display"""
	if not health_bar_sprite:
		# Create health bar sprite
		health_bar_sprite = Sprite3D.new()
		add_child(health_bar_sprite)
		health_bar_sprite.name = "HealthBarSprite"
		health_bar_sprite.pixel_size = 0.01
		health_bar_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		health_bar_sprite.offset = Vector2(0, 50)  # Above prop
		health_bar_sprite.visible = false

		# Create viewport for health bar rendering
		var viewport = SubViewport.new()
		add_child(viewport)
		viewport.name = "HealthBarViewport"
		viewport.size = Vector2i(200, 20)
		viewport.transparent_bg = true

		# Create ColorRect for health bar
		var bg = ColorRect.new()
		bg.size = Vector2(200, 20)
		bg.color = Color(0.2, 0.2, 0.2, 0.8)
		viewport.add_child(bg)

		var fill = ColorRect.new()
		fill.name = "HealthFill"
		fill.size = Vector2(200, 20)
		fill.color = Color(0, 1, 0, 1)
		viewport.add_child(fill)

		var label = Label.new()
		label.name = "HealthLabel"
		label.text = prop_name
		label.position = Vector2(5, 0)
		label.add_theme_font_size_override("font_size", 14)
		viewport.add_child(label)

		health_bar = viewport
		health_bar_sprite.texture = viewport.get_texture()

func _update_health_bar(health_percent: float):
	"""Update health bar display"""
	if not health_bar:
		return

	var fill = health_bar.get_node_or_null("HealthFill")
	if fill:
		fill.size.x = 200 * health_percent

		# Color based on health
		if health_percent > 0.6:
			fill.color = Color(0, 1, 0, 1)  # Green
		elif health_percent > 0.3:
			fill.color = Color(1, 1, 0, 1)  # Yellow
		else:
			fill.color = Color(1, 0, 0, 1)  # Red

	var label = health_bar.get_node_or_null("HealthLabel")
	if label:
		label.text = "%s: %.0f/%.0f" % [prop_name, current_health, max_health]

func enable_phasing():
	"""Allow player to phase through (called when holding Z)"""
	collision_layer = PHASE_LAYER
	collision_mask = 0  # Don't collide with anything while phasing

func disable_phasing():
	"""Return to normal collision (called when releasing Z)"""
	collision_layer = NORMAL_LAYER
	collision_mask = 1

func _destroy():
	is_destroyed = true
	prop_destroyed.emit()

	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message("%s destroyed!" % prop_name)

	# Play destruction sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("wood_break", global_position, 1.0)

	# Spawn debris
	if has_node("/root/VFXManager"):
		get_node("/root/VFXManager").spawn_impact_effect(global_position, Vector3.UP, "wood")

	# Hide or remove
	visible = false
	collision_layer = 0
	collision_mask = 0

	# Could respawn after a delay or just stay destroyed
	await get_tree().create_timer(5.0).timeout
	queue_free()
