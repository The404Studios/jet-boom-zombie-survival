extends Area3D

# Pickup item - ammo, health, weapons, etc.
# Network replicated pickups

@export var pickup_type: String = "ammo"  # ammo, health, weapon, points
@export var ammo_amount: int = 30
@export var health_amount: float = 25.0
@export var points_amount: int = 100
@export var weapon_name: String = "AK-47"

var is_picked_up: bool = false
var respawn_time: float = 30.0
var rotation_speed: float = 1.0
var base_y_position: float = 0.0
var bob_tween: Tween = null

func _ready():
	body_entered.connect(_on_body_entered)
	base_y_position = position.y

	# Start animations
	_start_rotation_animation()
	_start_bob_animation()

func _process(delta):
	# Rotate pickup
	rotate_y(rotation_speed * delta)

func _start_rotation_animation():
	"""Simple rotation - handled in _process"""
	rotation_speed = randf_range(0.8, 1.2)  # Randomize rotation speed slightly

func _start_bob_animation():
	"""Start smooth bobbing animation using Tween"""
	if bob_tween and bob_tween.is_valid():
		bob_tween.kill()

	bob_tween = create_tween()
	bob_tween.set_loops()  # Infinite loop
	bob_tween.set_trans(Tween.TRANS_SINE)
	bob_tween.set_ease(Tween.EASE_IN_OUT)
	bob_tween.tween_property(self, "position:y", base_y_position + 0.15, 0.8)
	bob_tween.tween_property(self, "position:y", base_y_position - 0.05, 0.8)

func _exit_tree():
	if bob_tween and bob_tween.is_valid():
		bob_tween.kill()

func _on_body_entered(body: Node3D):
	if is_picked_up:
		return

	# Check if player
	if not body.is_in_group("player"):
		return

	# Pick up
	_pickup(body)

func _pickup(_player: Node):
	# Network replicate pickup (or call directly in single-player)
	if not multiplayer.has_multiplayer_peer():
		_pickup_networked(get_path())
		return

	if multiplayer.is_server():
		_pickup_networked.rpc(get_path())
	else:
		_pickup_networked.rpc_id(1, get_path())

@rpc("any_peer", "call_local")
func _pickup_networked(_item_path: NodePath):
	if is_picked_up:
		return

	is_picked_up = true

	# Find player
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	# Apply pickup effect
	match pickup_type:
		"ammo":
			if "reserve_ammo" in player:
				player.reserve_ammo += ammo_amount

				if has_node("/root/ChatSystem"):
					get_node("/root/ChatSystem").emit_system_message("+%d Ammo" % ammo_amount)

		"health":
			if "current_health" in player and "max_health" in player:
				player.current_health = min(player.current_health + health_amount, player.max_health)

				if has_node("/root/ChatSystem"):
					get_node("/root/ChatSystem").emit_system_message("+%d Health" % int(health_amount))

		"weapon":
			if player.has_method("equip_weapon"):
				# Add weapon to inventory
				if has_node("/root/ChatSystem"):
					get_node("/root/ChatSystem").emit_system_message("Picked up %s" % weapon_name)

		"points":
			# Award points (handled by arena manager)
			if has_node("/root/ChatSystem"):
				get_node("/root/ChatSystem").emit_system_message("+%d Points" % points_amount)

	# Play pickup sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("pickup", global_position, 0.8)

	# Visual effect
	_spawn_pickup_effect()

	# Hide and schedule respawn
	visible = false
	monitoring = false

	# Respawn after delay
	await get_tree().create_timer(respawn_time).timeout
	_respawn()

func _spawn_pickup_effect():
	"""Spawn visual effect when picked up"""
	if has_node("/root/VFXManager"):
		var vfx = get_node("/root/VFXManager")
		# Spawn sparkle effect based on pickup type
		var effect_type = "sparkle"
		match pickup_type:
			"health":
				effect_type = "health_pickup"
			"ammo":
				effect_type = "ammo_pickup"
			"weapon":
				effect_type = "weapon_pickup"

		if vfx.has_method("spawn_impact_effect"):
			vfx.spawn_impact_effect(global_position, Vector3.UP, effect_type)

func _respawn():
	if not is_instance_valid(self):
		return

	is_picked_up = false
	visible = true
	monitoring = true
