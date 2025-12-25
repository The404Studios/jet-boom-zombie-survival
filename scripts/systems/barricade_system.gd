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
var health_bar: WorldHealthBar = null

signal barricade_built
signal barricade_destroyed

func _ready():
	add_to_group("barricades")
	add_to_group("zombie_targets")
	_setup_health_bar()

func _setup_health_bar():
	"""Create 3D world health bar for this barricade"""
	health_bar = WorldHealthBar.new()
	add_child(health_bar)
	health_bar.bar_width = 1.8
	health_bar.offset_y = 2.0
	health_bar.show_text = true
	health_bar.always_visible = false
	health_bar.auto_hide_delay = 5.0
	health_bar.setup(self, current_health, max_health, "Barricade")

func _update_health_bar():
	"""Update health bar display"""
	if health_bar:
		var nail_text = "[%d/%d Nails]" % [nails_placed, nails_required]
		health_bar.entity_name = "Barricade %s" % nail_text
		health_bar.update_health(current_health, max_health)

		# Show bar when barricade is built
		if is_built:
			health_bar.set_always_visible(true)

func interact(player: Node):
	if not is_built:
		_start_build(player)
	elif current_health < max_health:
		_start_repair(player)

func _start_build(_player: Node):
	if is_being_nailed:
		return

	is_being_nailed = true
	nails_placed = 0

	for i in range(nails_required):
		await get_tree().create_timer(0.5).timeout

		# Validate instance after await
		if not is_instance_valid(self) or not is_inside_tree():
			return

		if not is_being_nailed:
			break

		nails_placed += 1
		current_health += nail_health

		# Update health bar
		_update_health_bar()

		# Audio feedback
		if has_node("/root/AudioManager"):
			get_node("/root/AudioManager").play_sound_3d("hammer", global_position)

		# VFX feedback
		if has_node("/root/VFXManager"):
			var hit_pos = global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.5, 1.5), randf_range(-0.3, 0.3))
			get_node("/root/VFXManager").spawn_impact_effect(hit_pos, Vector3.UP, "wood")

	if not is_instance_valid(self):
		return
	is_built = true
	is_being_nailed = false
	_update_health_bar()
	barricade_built.emit()

func _start_repair(_player: Node):
	if is_being_nailed or current_health >= max_health:
		return

	is_being_nailed = true

	# Calculate how many nails needed to fully repair
	var health_missing = max_health - current_health
	var nails_needed = int(ceil(health_missing / nail_health))

	for i in range(nails_needed):
		await get_tree().create_timer(0.5).timeout

		# Validate instance after await
		if not is_instance_valid(self) or not is_inside_tree():
			return

		if not is_being_nailed:
			break

		nails_placed += 1
		current_health = min(current_health + nail_health, max_health)

		# Update health bar
		_update_health_bar()

		# Audio feedback
		if has_node("/root/AudioManager"):
			get_node("/root/AudioManager").play_sound_3d("hammer", global_position)

		# VFX feedback
		if has_node("/root/VFXManager"):
			var hit_pos = global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.5, 1.5), randf_range(-0.3, 0.3))
			get_node("/root/VFXManager").spawn_impact_effect(hit_pos, Vector3.UP, "wood")

		if current_health >= max_health:
			break

	if not is_instance_valid(self):
		return
	is_being_nailed = false
	_update_health_bar()

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
	current_health = max(current_health, 0)

	# Cancel any ongoing nailing
	if is_being_nailed:
		is_being_nailed = false

	# Track nails knocked off
	var nails_lost = int(amount / nail_health)
	if nails_lost > 0:
		nails_placed = max(nails_placed - nails_lost, 0)

	# Update health bar
	_update_health_bar()
	if health_bar:
		health_bar.show_bar()

	# Visual/audio feedback
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("wood_break", global_position)

	if has_node("/root/VFXManager"):
		get_node("/root/VFXManager").spawn_impact_effect(global_position, Vector3.UP, "wood")

	if current_health <= 0:
		_destroy()

func _destroy():
	# Spawn destruction particles
	if has_node("/root/VFXManager"):
		get_node("/root/VFXManager").spawn_explosion(global_position, 2.0)  # Small explosion for barricade

	barricade_destroyed.emit()
	queue_free()
