extends StaticBody3D

# Sigil - the main objective zombies attack
# Primary target for zombies (higher priority than props)

@export var max_health: float = 10000.0
@export var health_per_wave: float = 2000.0

var current_health: float = 10000.0
var current_wave: int = 1

signal sigil_damaged(health_remaining: float, health_percent: float)
signal sigil_destroyed

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var health_label: Label3D = $HealthLabel3D

func _ready():
	add_to_group("sigil")
	_update_visual()

func setup_for_wave(wave: int):
	"""Scale health based on wave"""
	current_wave = wave
	max_health = 10000.0 + (health_per_wave * (wave - 1))
	current_health = max_health
	_update_visual()

func take_damage(amount: float, _attacker: Node = null):
	"""Take damage from zombie"""
	current_health -= amount
	current_health = max(current_health, 0)

	var health_percent = current_health / max_health

	# Emit signal
	sigil_damaged.emit(current_health, health_percent)

	# Update visual
	_update_visual()

	# Play damage sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("sigil_hit", global_position, 0.6)

	# Notify players
	if health_percent < 0.25 and fmod(Time.get_ticks_msec(), 5000) < 100:
		if has_node("/root/ChatSystem"):
			get_node("/root/ChatSystem").emit_system_message("SIGIL CRITICAL! %.0f%% remaining!" % (health_percent * 100))

	# Check destroyed
	if current_health <= 0:
		_destroy()

func _update_visual():
	var health_percent = current_health / max_health

	# Update mesh color based on health
	if mesh:
		var mat = StandardMaterial3D.new()

		if health_percent > 0.7:
			mat.albedo_color = Color(0.2, 0.5, 1.0, 1.0)  # Blue - healthy
			mat.emission = Color(0.2, 0.5, 1.0)
			mat.emission_energy_multiplier = 2.0
		elif health_percent > 0.4:
			mat.albedo_color = Color(0.8, 0.8, 0.0, 1.0)  # Yellow - damaged
			mat.emission = Color(0.8, 0.8, 0.0)
			mat.emission_energy_multiplier = 1.5
		else:
			mat.albedo_color = Color(1.0, 0.2, 0.0, 1.0)  # Red - critical
			mat.emission = Color(1.0, 0.2, 0.0)
			mat.emission_energy_multiplier = 3.0

		mat.emission_enabled = true
		mesh.material_override = mat

	# Update health label
	if health_label:
		health_label.text = "SIGIL\n%.0f / %.0f" % [current_health, max_health]
		health_label.modulate = Color(1, 1 - health_percent, 0, 1)

func _destroy():
	sigil_destroyed.emit()

	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message("SIGIL DESTROYED! Game Over!")

	# Play destruction sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("sigil_destroyed", global_position, 1.0)

	# Explosion effect
	if has_node("/root/VFXManager"):
		get_node("/root/VFXManager").spawn_explosion(global_position, 10.0)

	# Game over logic would go here
	# For now, just disable
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
