extends StaticBody3D

# JetBoom-style props - zombies attack as secondary target
# Players can phase through by holding Z
# Players can pick up and carry props

@export var max_health: float = 500.0
@export var health_per_wave: float = 100.0
@export var prop_name: String = "Prop"

# Weight system - affects player speed/jump when carrying
# Weight ranges from 0.0 (light) to 1.0 (very heavy)
@export_range(0.0, 1.0) var prop_weight: float = 0.5
@export var prop_size: Vector3 = Vector3(1.0, 1.0, 1.0)  # Used for visual scaling
@export var can_be_picked_up: bool = true

var current_health: float = 500.0
var current_wave: int = 1
var is_destroyed: bool = false
var is_being_carried: bool = false
var carrier: Node = null  # Reference to player carrying this prop

# Phasing mechanic
const PHASE_LAYER = 32  # Layer 6 - dedicated phase layer
const NORMAL_LAYER = 1  # Layer 1 - world geometry

signal prop_damaged(health_remaining: float, health_percent: float)
signal prop_destroyed
signal prop_picked_up(by_player: Node)
signal prop_dropped(at_position: Vector3)

@onready var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
@onready var health_label: Label3D = get_node_or_null("HealthLabel3D") as Label3D

var health_bar: WorldHealthBar = null
var is_barricaded: bool = false
var barricade_nails: int = 0
var max_barricade_nails: int = 6

signal barricade_started
signal barricade_completed
signal barricade_damaged(nails_remaining: int)

func _ready():
	add_to_group("props")
	add_to_group("zombie_targets")

	# Calculate health based on weight
	_recalculate_health_from_weight()

	_setup_health_bar()
	_update_visual()

func setup_for_wave(wave: int):
	"""Scale health based on wave"""
	current_wave = wave
	max_health = 500.0 + (health_per_wave * (wave - 1))
	current_health = max_health
	_update_visual()

func take_damage(amount: float, attacker: Node = null):
	"""Take damage from zombie or other sources"""
	if is_destroyed:
		return

	current_health -= amount
	current_health = max(current_health, 0)

	var health_percent = current_health / max_health if max_health > 0 else 0.0

	# Emit signal
	prop_damaged.emit(current_health, health_percent)

	# Track barricade damage - nails can be knocked off
	if is_barricaded and barricade_nails > 0:
		# Every 50 damage knocks off a nail
		var damage_threshold = 50.0
		if current_health <= (max_barricade_nails - barricade_nails + 1) * damage_threshold:
			barricade_nails = max(barricade_nails - 1, 0)
			barricade_damaged.emit(barricade_nails)

			if barricade_nails == 0:
				is_barricaded = false
				remove_from_group("barricades")

	# Update visual
	_update_visual()

	# Play damage sound
	if has_node("/root/AudioManager"):
		var sound = "wood_hit" if not is_barricaded else "wood_break"
		get_node("/root/AudioManager").play_sound_3d(sound, global_position, 0.5)

	# Show health bar when damaged (always show for barricaded props)
	if health_bar:
		health_bar.show_bar()
		if is_barricaded:
			health_bar.set_always_visible(true)

	# Check destroyed
	if current_health <= 0:
		_destroy()

func _update_visual():
	var health_percent = current_health / max_health if max_health > 0 else 0.0

	# Update health bar
	_update_health_bar()

	# Change material based on damage
	if mesh:
		var mat = mesh.get_active_material(0)
		if mat is StandardMaterial3D:
			# Darken as it takes damage
			var damage_factor = health_percent
			mat.albedo_color = Color(damage_factor, damage_factor, damage_factor, 1.0)

func _setup_health_bar():
	"""Create 3D world health bar"""
	health_bar = WorldHealthBar.new()
	add_child(health_bar)
	health_bar.bar_width = 2.0
	health_bar.offset_y = 2.5
	health_bar.show_text = true
	health_bar.always_visible = false
	health_bar.auto_hide_delay = 5.0
	health_bar.setup(self, current_health, max_health, prop_name)

func _update_health_bar():
	"""Update world health bar display"""
	if health_bar:
		var display_name = prop_name
		if is_barricaded:
			display_name = "%s [%d/%d Nails]" % [prop_name, barricade_nails, max_barricade_nails]
		health_bar.entity_name = display_name
		health_bar.update_health(current_health, max_health)

# ============================================
# BARRICADING SYSTEM
# ============================================

func can_be_barricaded() -> bool:
	"""Check if prop can be barricaded"""
	return not is_barricaded or barricade_nails < max_barricade_nails

func start_barricade():
	"""Begin barricading this prop"""
	if is_barricaded:
		return
	is_barricaded = true
	barricade_nails = 0
	add_to_group("barricades")
	barricade_started.emit()

	# Show health bar when barricading starts
	if health_bar:
		health_bar.set_always_visible(true)
		_update_health_bar()

func add_barricade_nail() -> bool:
	"""Add a nail to the barricade, returns true if nail was added"""
	if barricade_nails >= max_barricade_nails:
		return false

	if not is_barricaded:
		start_barricade()

	barricade_nails += 1

	# Each nail adds health based on prop weight
	var nail_health = get_weight_based_nail_health()
	max_health += nail_health
	current_health += nail_health

	# Audio feedback
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("hammer", global_position)

	# VFX feedback
	if has_node("/root/VFXManager"):
		var hit_pos = global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.5, 1.5), randf_range(-0.3, 0.3))
		get_node("/root/VFXManager").spawn_impact_effect(hit_pos, Vector3.UP, "wood")

	_update_health_bar()
	_update_visual()

	if barricade_nails >= max_barricade_nails:
		barricade_completed.emit()
		if has_node("/root/ChatSystem"):
			get_node("/root/ChatSystem").emit_system_message("%s fully barricaded!" % prop_name)

	return true

func get_barricade_progress() -> float:
	"""Get barricade progress from 0.0 to 1.0"""
	return float(barricade_nails) / float(max_barricade_nails)

func is_fully_barricaded() -> bool:
	return is_barricaded and barricade_nails >= max_barricade_nails

# ============================================
# CARRYING SYSTEM
# ============================================

func can_pickup() -> bool:
	"""Check if this prop can be picked up"""
	return can_be_picked_up and not is_being_carried and not is_barricaded and not is_destroyed

func pickup(player: Node) -> bool:
	"""Pick up this prop - called by player"""
	if not can_pickup():
		return false

	is_being_carried = true
	carrier = player

	# Disable collision while being carried
	collision_layer = 0
	collision_mask = 0

	# Remove from groups temporarily
	remove_from_group("props")
	remove_from_group("zombie_targets")

	# Hide health bar while carrying
	if health_bar:
		health_bar.visible = false

	prop_picked_up.emit(player)

	# Play pickup sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("prop_pickup", global_position, 0.6)

	return true

func drop(drop_position: Vector3, drop_rotation: Vector3 = Vector3.ZERO):
	"""Drop this prop at the specified position"""
	if not is_being_carried:
		return

	is_being_carried = false
	carrier = null

	# Set position and rotation
	global_position = drop_position
	rotation = drop_rotation

	# Re-enable collision
	collision_layer = NORMAL_LAYER
	collision_mask = 1

	# Re-add to groups
	add_to_group("props")
	add_to_group("zombie_targets")

	# Show health bar again
	if health_bar:
		health_bar.visible = true
		_update_health_bar()

	prop_dropped.emit(drop_position)

	# Play drop sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("prop_drop", global_position, 0.7)

func get_weight_penalty() -> float:
	"""Get movement/jump penalty based on weight (0.4 to 0.7)"""
	# Weight 0.0 = 40% penalty, Weight 1.0 = 70% penalty
	return 0.4 + (prop_weight * 0.3)

func get_weight_based_health() -> float:
	"""Get base health scaled by weight - heavier props have more HP"""
	# Light props: 300 HP base, Heavy props: 800 HP base
	return 300.0 + (prop_weight * 500.0)

func get_weight_based_nail_health() -> float:
	"""Get nail health scaled by weight - heavier props get more HP per nail"""
	# Light props: 30 HP per nail, Heavy props: 100 HP per nail
	return 30.0 + (prop_weight * 70.0)

func _recalculate_health_from_weight():
	"""Recalculate health values based on prop weight"""
	var base_health = get_weight_based_health()
	max_health = base_health + (health_per_wave * (current_wave - 1))
	current_health = max_health

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
