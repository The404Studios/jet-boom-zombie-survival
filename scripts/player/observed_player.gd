extends CharacterBody3D
class_name ObservedPlayer

# Networked representation of a remote player
# Receives state updates from the authoritative player and interpolates visuals
# Used in multiplayer to show other players' positions, animations, and actions

signal player_died(player_id: int)
signal player_respawned(player_id: int)
signal player_shot(position: Vector3, direction: Vector3)
signal player_hit(damage: float)

# Network identification
@export var peer_id: int = 0
@export var player_name: String = "Player"
@export var team_id: int = 0

# Interpolation settings
@export var interpolation_speed: float = 15.0
@export var rotation_speed: float = 20.0
@export var position_threshold: float = 5.0  # Snap if too far

# Visual components
@onready var model: Node3D = $Model if has_node("Model") else null
@onready var nameplate: Label3D = $Nameplate if has_node("Nameplate") else null
@onready var health_bar_3d: Node3D = $HealthBar3D if has_node("HealthBar3D") else null
@onready var animation_player: AnimationPlayer = $AnimationPlayer if has_node("AnimationPlayer") else null
@onready var weapon_holder: Node3D = $Model/WeaponHolder if has_node("Model/WeaponHolder") else null

# Audio
@onready var footstep_player: AudioStreamPlayer3D = $FootstepPlayer if has_node("FootstepPlayer") else null
@onready var voice_player: AudioStreamPlayer3D = $VoicePlayer if has_node("VoicePlayer") else null

# State
var target_position: Vector3 = Vector3.ZERO
var target_rotation: float = 0.0
var target_head_rotation: float = 0.0
var current_health: float = 100.0
var max_health: float = 100.0
var is_dead: bool = false
var is_sprinting: bool = false
var is_crouching: bool = false
var is_aiming: bool = false
var current_weapon: String = ""
var is_reloading: bool = false

# Movement state for animation
var move_velocity: Vector3 = Vector3.ZERO
var last_position: Vector3 = Vector3.ZERO
var footstep_timer: float = 0.0

# State history for interpolation
var state_buffer: Array = []
var buffer_time: float = 0.1  # 100ms interpolation delay
const MAX_BUFFER_SIZE: int = 20

# Carried prop visualization
var carried_prop_visual: Node3D = null

func _ready():
	# Initialize target position
	target_position = global_position
	last_position = global_position

	# Set up nameplate
	if nameplate:
		nameplate.text = player_name
		nameplate.visible = true

	# Set up health bar
	_update_health_bar()

	# Add to observed players group
	add_to_group("observed_players")
	add_to_group("players")

func _process(delta):
	if is_dead:
		return

	# Interpolate position
	_interpolate_position(delta)

	# Interpolate rotation
	_interpolate_rotation(delta)

	# Update animations based on movement
	_update_animations(delta)

	# Update footsteps
	_update_footsteps(delta)

	# Keep nameplate facing camera
	_update_nameplate()

func _interpolate_position(delta: float):
	var distance = global_position.distance_to(target_position)

	# Snap if too far (teleport/spawn)
	if distance > position_threshold:
		global_position = target_position
	else:
		# Smooth interpolation
		global_position = global_position.lerp(target_position, interpolation_speed * delta)

	# Calculate velocity for animations
	move_velocity = (global_position - last_position) / max(delta, 0.001)
	last_position = global_position

func _interpolate_rotation(delta: float):
	# Body rotation (Y axis)
	rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)

	# Head rotation (looking up/down) - applied to model or head bone
	if model:
		# Apply head pitch to model or skeleton
		var head_node = model.get_node_or_null("Head")
		if head_node:
			head_node.rotation.x = lerp_angle(head_node.rotation.x, target_head_rotation, rotation_speed * delta)

func _update_animations(delta: float):
	if not animation_player:
		return

	var horizontal_speed = Vector2(move_velocity.x, move_velocity.z).length()

	if is_dead:
		if animation_player.has_animation("death"):
			animation_player.play("death")
	elif is_reloading:
		if animation_player.has_animation("reload"):
			animation_player.play("reload")
	elif horizontal_speed > 0.5:
		if is_sprinting and horizontal_speed > 4.0:
			if animation_player.has_animation("sprint"):
				animation_player.play("sprint")
			elif animation_player.has_animation("run"):
				animation_player.play("run")
		else:
			if animation_player.has_animation("walk"):
				animation_player.play("walk")
	else:
		if is_crouching:
			if animation_player.has_animation("crouch_idle"):
				animation_player.play("crouch_idle")
		elif is_aiming:
			if animation_player.has_animation("aim_idle"):
				animation_player.play("aim_idle")
		else:
			if animation_player.has_animation("idle"):
				animation_player.play("idle")

func _update_footsteps(delta: float):
	if not footstep_player:
		return

	var horizontal_speed = Vector2(move_velocity.x, move_velocity.z).length()

	if horizontal_speed > 0.5 and not is_dead:
		footstep_timer -= delta
		if footstep_timer <= 0:
			# Set footstep interval based on speed
			var interval = 0.3 if is_sprinting else 0.5
			footstep_timer = interval

			# Play footstep sound
			if footstep_player.stream:
				footstep_player.pitch_scale = randf_range(0.9, 1.1)
				footstep_player.play()

func _update_nameplate():
	if not nameplate:
		return

	# Face the local camera
	var camera = get_viewport().get_camera_3d()
	if camera:
		nameplate.look_at(camera.global_position, Vector3.UP)
		nameplate.rotation.x = 0  # Keep upright

func _update_health_bar():
	if not health_bar_3d:
		return

	var health_percent = current_health / max_health if max_health > 0 else 0.0

	# Update health bar visual (assuming it has a fill node)
	var fill = health_bar_3d.get_node_or_null("Fill")
	if fill and fill is MeshInstance3D:
		fill.scale.x = health_percent

	# Hide if full health
	health_bar_3d.visible = health_percent < 1.0

# ============================================
# STATE SYNCHRONIZATION
# ============================================

func receive_state(state: Dictionary):
	"""Receive state update from network"""
	# Add to buffer with timestamp
	state.timestamp = Time.get_ticks_msec() / 1000.0
	state_buffer.append(state)

	# Trim buffer
	while state_buffer.size() > MAX_BUFFER_SIZE:
		state_buffer.pop_front()

	# Apply latest state immediately for responsiveness
	_apply_state(state)

func _apply_state(state: Dictionary):
	"""Apply a state snapshot"""
	if state.has("position"):
		target_position = state.position

	if state.has("rotation"):
		target_rotation = state.rotation

	if state.has("head_rotation"):
		target_head_rotation = state.head_rotation

	if state.has("health"):
		set_health(state.health, state.get("max_health", max_health))

	if state.has("is_sprinting"):
		is_sprinting = state.is_sprinting

	if state.has("is_crouching"):
		is_crouching = state.is_crouching

	if state.has("is_aiming"):
		is_aiming = state.is_aiming

	if state.has("weapon"):
		if state.weapon != current_weapon:
			current_weapon = state.weapon
			_update_weapon_visual(current_weapon)

	if state.has("is_reloading"):
		is_reloading = state.is_reloading

func set_health(health: float, new_max_health: float = -1.0):
	"""Update health state"""
	var old_health = current_health
	current_health = health

	if new_max_health > 0:
		max_health = new_max_health

	_update_health_bar()

	# Check for death
	if current_health <= 0 and not is_dead:
		die()
	elif current_health > 0 and is_dead:
		respawn()

	# Damage flash effect
	if current_health < old_health:
		_show_damage_effect()

func die():
	"""Handle player death"""
	is_dead = true

	# Play death animation
	if animation_player and animation_player.has_animation("death"):
		animation_player.play("death")

	# Hide weapon
	if weapon_holder:
		weapon_holder.visible = false

	# Disable collision
	set_collision_layer_value(1, false)

	player_died.emit(peer_id)

func respawn():
	"""Handle player respawn"""
	is_dead = false
	current_health = max_health

	# Show weapon
	if weapon_holder:
		weapon_holder.visible = true

	# Enable collision
	set_collision_layer_value(1, true)

	# Reset animation
	if animation_player and animation_player.has_animation("idle"):
		animation_player.play("idle")

	_update_health_bar()
	player_respawned.emit(peer_id)

# ============================================
# VISUAL EFFECTS
# ============================================

func _update_weapon_visual(weapon_name: String):
	"""Update the visible weapon model"""
	if not weapon_holder:
		return

	# Clear existing weapon
	for child in weapon_holder.get_children():
		child.queue_free()

	# Load and add new weapon visual
	var weapon_path = "res://scenes/weapons/weapon_%s.tscn" % weapon_name.to_lower()
	if ResourceLoader.exists(weapon_path):
		var weapon_scene = load(weapon_path)
		if weapon_scene:
			var weapon = weapon_scene.instantiate()
			weapon_holder.add_child(weapon)

func _show_damage_effect():
	"""Visual feedback when taking damage"""
	# Flash red
	if model:
		var tween = create_tween()
		# Store original material or modulate
		tween.tween_property(self, "modulate", Color(1.5, 0.5, 0.5, 1), 0.05)
		tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.15)

func play_shoot_effect(muzzle_position: Vector3, direction: Vector3):
	"""Show shooting visual effects"""
	player_shot.emit(muzzle_position, direction)

	# Muzzle flash would be spawned by VFX manager
	var vfx_manager = get_node_or_null("/root/VFXManager")
	if vfx_manager and vfx_manager.has_method("spawn_muzzle_flash"):
		vfx_manager.spawn_muzzle_flash(muzzle_position, direction, current_weapon)

func play_reload_effect():
	"""Show reloading animation"""
	is_reloading = true

	if animation_player and animation_player.has_animation("reload"):
		animation_player.play("reload")

	# Reset after animation
	await get_tree().create_timer(2.0).timeout
	is_reloading = false

func set_carried_prop(prop_name: String, prop_scale: Vector3 = Vector3.ONE):
	"""Show a carried prop visual"""
	# Clear existing
	if carried_prop_visual:
		carried_prop_visual.queue_free()
		carried_prop_visual = null

	if prop_name.is_empty():
		return

	# Create simple visual representation
	var mesh = MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.scale = prop_scale * 0.5

	# Position in front of player
	if model:
		model.add_child(mesh)
		mesh.position = Vector3(0.5, 0.8, -0.5)

	carried_prop_visual = mesh

# ============================================
# UTILITY
# ============================================

func set_player_info(info: Dictionary):
	"""Set player information"""
	if info.has("peer_id"):
		peer_id = info.peer_id

	if info.has("name"):
		player_name = info.name
		if nameplate:
			nameplate.text = player_name

	if info.has("team"):
		team_id = info.team
		_update_team_color()

func _update_team_color():
	"""Update visual color based on team"""
	var team_colors = {
		0: Color.WHITE,
		1: Color.BLUE,
		2: Color.RED,
		3: Color.GREEN,
		4: Color.YELLOW
	}

	var color = team_colors.get(team_id, Color.WHITE)

	if nameplate:
		nameplate.modulate = color

func get_aim_direction() -> Vector3:
	"""Get the direction the player is aiming"""
	return -global_transform.basis.z.rotated(Vector3.RIGHT, target_head_rotation)

func is_visible_to_local_player() -> bool:
	"""Check if this player is visible to the local camera"""
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return false

	return camera.is_position_in_frustum(global_position)
