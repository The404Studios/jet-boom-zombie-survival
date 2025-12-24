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
@onready var health_label: Label3D = $HealthLabel3D if has_node("HealthLabel3D") else null

func _ready():
	add_to_group("props")
	add_to_group("zombie_targets")
	_setup_health_label()
	_update_visual()

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

	var health_percent = current_health / max_health if max_health > 0 else 0.0

	# Emit signal
	prop_damaged.emit(current_health, health_percent)

	# Update visual
	_update_visual()

	# Play damage sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("wood_hit", global_position, 0.5)

	# Show health label when damaged
	if health_label:
		health_label.visible = true

	# Check destroyed
	if current_health <= 0:
		_destroy()

func _update_visual():
	var health_percent = current_health / max_health if max_health > 0 else 0.0

	# Update health label
	_update_health_label(health_percent)

	# Change material based on damage
	if mesh:
		var mat = mesh.get_active_material(0)
		if mat is StandardMaterial3D:
			# Darken as it takes damage
			var damage_factor = health_percent
			mat.albedo_color = Color(damage_factor, damage_factor, damage_factor, 1.0)

func _setup_health_label():
	"""Create 3D health label"""
	if not health_label:
		health_label = Label3D.new()
		add_child(health_label)
		health_label.name = "HealthLabel3D"
		health_label.pixel_size = 0.01
		health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		health_label.position = Vector3(0, 2, 0)  # Above prop
		health_label.font_size = 24
		health_label.outline_size = 4
		health_label.visible = false

func _update_health_label(health_percent: float):
	"""Update health label display"""
	if not health_label:
		return

	# Update text
	health_label.text = "%s\n%.0f/%.0f HP" % [prop_name, current_health, max_health]

	# Color based on health
	if health_percent > 0.6:
		health_label.modulate = Color(0, 1, 0, 1)  # Green
	elif health_percent > 0.3:
		health_label.modulate = Color(1, 1, 0, 1)  # Yellow
	else:
		health_label.modulate = Color(1, 0, 0, 1)  # Red

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
