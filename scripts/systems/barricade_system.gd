extends Node3D

# Barricade that can be built and repaired
# JetBoom-style nailing mechanic

@export var max_health: float = 100.0
@export var nail_health: float = 20.0
@export var nails_required: int = 6
@export var cost_to_build: int = 50

var current_health: float = 0.0
var nails_placed: int = 0
var is_built: bool = false
var is_being_nailed: bool = false

signal barricade_built
signal barricade_destroyed

func _ready():
	add_to_group("barricades")
	add_to_group("zombie_targets")

func interact(player: Node):
	if not is_built:
		_start_build(player)
	elif current_health < max_health:
		_start_repair(player)

func _start_build(player: Node):
	if is_being_nailed:
		return

	is_being_nailed = true
	nails_placed = 0

	for i in range(nails_required):
		await get_tree().create_timer(0.5).timeout

		if not is_being_nailed:
			break

		nails_placed += 1
		current_health += nail_health

		# Audio feedback
		if has_node("/root/AudioManager"):
			get_node("/root/AudioManager").play_sound_3d("hammer", global_position)

		# VFX feedback
		if has_node("/root/VFXManager"):
			var hit_pos = global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.5, 1.5), randf_range(-0.3, 0.3))
			get_node("/root/VFXManager").spawn_impact(hit_pos, Vector3.UP, "wood")

	is_built = true
	is_being_nailed = false
	barricade_built.emit()

func _start_repair(player: Node):
	if is_being_nailed or current_health >= max_health:
		return

	is_being_nailed = true

	# Calculate how many nails needed to fully repair
	var health_missing = max_health - current_health
	var nails_needed = ceili(health_missing / nail_health)

	for i in range(nails_needed):
		await get_tree().create_timer(0.5).timeout

		if not is_being_nailed:
			break

		nails_placed += 1
		current_health = min(current_health + nail_health, max_health)

		# Audio feedback
		if has_node("/root/AudioManager"):
			get_node("/root/AudioManager").play_sound_3d("hammer", global_position)

		# VFX feedback
		if has_node("/root/VFXManager"):
			var hit_pos = global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.5, 1.5), randf_range(-0.3, 0.3))
			get_node("/root/VFXManager").spawn_impact(hit_pos, Vector3.UP, "wood")

		if current_health >= max_health:
			break

	is_being_nailed = false

func cancel_nailing():
	is_being_nailed = false

func repair(player: Node = null):
	"""Public repair method - called from BarricadeSpot"""
	if current_health < max_health:
		_start_repair(player)

func add_nail():
	# Called by BarricadeNailing system
	nails_placed += 1
	current_health = min(current_health + nail_health, max_health)

func complete_repair():
	# Called when nailing is complete
	current_health = max_health
	is_being_nailed = false

func get_health_percent() -> float:
	if max_health <= 0:
		return 0.0
	return current_health / max_health

func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO):
	current_health -= amount

	# Cancel any ongoing nailing
	if is_being_nailed:
		is_being_nailed = false

	# Visual/audio feedback
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("wood_break", global_position)

	if has_node("/root/VFXManager"):
		get_node("/root/VFXManager").spawn_impact(global_position, Vector3.UP, "wood")

	if current_health <= 0:
		_destroy()

func _destroy():
	# Spawn destruction particles
	if has_node("/root/VFXManager"):
		get_node("/root/VFXManager").spawn_explosion(global_position, "wood")

	barricade_destroyed.emit()
	queue_free()
