extends Area3D
class_name Pickup

# Base pickup class for ammo, health, grenades, etc.

signal picked_up(player: Node, pickup_type: String, amount: int)

enum PickupType {
	AMMO_RIFLE,
	AMMO_SHOTGUN,
	AMMO_PISTOL,
	AMMO_RPG,
	GRENADE_EXPLOSIVE,
	GRENADE_FLASHBANG,
	GRENADE_SMOKE,
	HEALTH_SMALL,
	HEALTH_MEDIUM,
	HEALTH_LARGE,
	FOOD,
	DRINK,
	CLAYMORE,
	MINE
}

@export var pickup_type: PickupType = PickupType.AMMO_RIFLE
@export var amount: int = 30
@export var pickup_name: String = "Ammo"
@export var respawn_time: float = 0.0  # 0 = no respawn
@export var bob_amplitude: float = 0.1
@export var bob_speed: float = 2.0
@export var rotate_speed: float = 1.0

var initial_y: float = 0.0
var time_offset: float = 0.0
var model_node: Node3D = null
var is_active: bool = true

func _ready():
	initial_y = global_position.y
	time_offset = randf() * TAU

	# Find model node for animation
	for child in get_children():
		if child is Node3D and child.name == "Model":
			model_node = child
			break

	# Connect to body entered signal
	body_entered.connect(_on_body_entered)

func _process(delta):
	if not is_active:
		return

	# Bob up and down
	var bob = sin(Time.get_ticks_msec() / 1000.0 * bob_speed + time_offset) * bob_amplitude
	global_position.y = initial_y + bob

	# Rotate
	if model_node:
		model_node.rotate_y(rotate_speed * delta)

func _on_body_entered(body: Node3D):
	if not is_active:
		return

	if body.is_in_group("player"):
		if _try_pickup(body):
			_on_picked_up(body)

func _try_pickup(player: Node) -> bool:
	"""Override in subclasses or connect to signal for specific handling"""
	match pickup_type:
		PickupType.AMMO_RIFLE, PickupType.AMMO_SHOTGUN, PickupType.AMMO_PISTOL, PickupType.AMMO_RPG:
			return _give_ammo(player)
		PickupType.GRENADE_EXPLOSIVE, PickupType.GRENADE_FLASHBANG, PickupType.GRENADE_SMOKE:
			return _give_grenade(player)
		PickupType.HEALTH_SMALL, PickupType.HEALTH_MEDIUM, PickupType.HEALTH_LARGE:
			return _give_health(player)
		PickupType.FOOD, PickupType.DRINK:
			return _give_consumable(player)
		PickupType.CLAYMORE, PickupType.MINE:
			return _give_trap(player)
	return true

func _give_ammo(player: Node) -> bool:
	if player.has_method("add_ammo"):
		var ammo_type = _get_ammo_type()
		player.add_ammo(ammo_type, amount)
		return true
	return true  # Pickup anyway if no method exists

func _give_grenade(player: Node) -> bool:
	if player.has_method("add_grenade"):
		var grenade_type = _get_grenade_type()
		player.add_grenade(grenade_type, amount)
		return true
	return true

func _give_health(player: Node) -> bool:
	if player.has_method("heal"):
		var health = player.health if "health" in player else 0
		var max_health = player.max_health if "max_health" in player else 100
		if health < max_health:
			player.heal(amount)
			return true
		return false  # Don't pickup if full health
	return true

func _give_consumable(player: Node) -> bool:
	if player.has_method("add_to_inventory"):
		player.add_to_inventory(pickup_name, 1)
		return true
	elif player.has_method("heal"):
		player.heal(amount)
		return true
	return true

func _give_trap(player: Node) -> bool:
	if player.has_method("add_trap"):
		var trap_type = "claymore" if pickup_type == PickupType.CLAYMORE else "mine"
		player.add_trap(trap_type, amount)
		return true
	return true

func _get_ammo_type() -> String:
	match pickup_type:
		PickupType.AMMO_RIFLE: return "rifle"
		PickupType.AMMO_SHOTGUN: return "shotgun"
		PickupType.AMMO_PISTOL: return "pistol"
		PickupType.AMMO_RPG: return "rpg"
	return "rifle"

func _get_grenade_type() -> String:
	match pickup_type:
		PickupType.GRENADE_EXPLOSIVE: return "explosive"
		PickupType.GRENADE_FLASHBANG: return "flashbang"
		PickupType.GRENADE_SMOKE: return "smoke"
	return "explosive"

func _on_picked_up(player: Node):
	picked_up.emit(player, pickup_name, amount)

	# Play pickup sound
	_play_pickup_sound()

	# Show pickup effect
	_show_pickup_effect()

	if respawn_time > 0:
		_start_respawn()
	else:
		queue_free()

func _start_respawn():
	is_active = false
	visible = false

	var timer = get_tree().create_timer(respawn_time)
	await timer.timeout

	is_active = true
	visible = true

func _play_pickup_sound():
	# Play pickup sound via AudioManager
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_sfx"):
		var sound_name = "pickup_item"
		match pickup_type:
			PickupType.AMMO_RIFLE, PickupType.AMMO_SHOTGUN, PickupType.AMMO_PISTOL, PickupType.AMMO_RPG:
				sound_name = "pickup_ammo"
			PickupType.HEALTH_SMALL, PickupType.HEALTH_MEDIUM, PickupType.HEALTH_LARGE:
				sound_name = "pickup_health"
			PickupType.GRENADE_EXPLOSIVE, PickupType.GRENADE_FLASHBANG, PickupType.GRENADE_SMOKE:
				sound_name = "pickup_grenade"
			PickupType.FOOD, PickupType.DRINK:
				sound_name = "pickup_consumable"
		audio_manager.play_sfx(sound_name, global_position)
	else:
		# Fallback: check for child AudioStreamPlayer3D
		var audio_player = get_node_or_null("AudioStreamPlayer3D")
		if audio_player:
			audio_player.play()

func _show_pickup_effect():
	# Spawn pickup effect via VFXManager
	var vfx_manager = get_node_or_null("/root/VFXManager")
	if vfx_manager and vfx_manager.has_method("spawn_effect"):
		var effect_name = "pickup_sparkle"
		var effect_color = Color.WHITE
		match pickup_type:
			PickupType.HEALTH_SMALL, PickupType.HEALTH_MEDIUM, PickupType.HEALTH_LARGE:
				effect_color = Color(0.3, 1.0, 0.3)  # Green
			PickupType.AMMO_RIFLE, PickupType.AMMO_SHOTGUN, PickupType.AMMO_PISTOL, PickupType.AMMO_RPG:
				effect_color = Color(1.0, 0.8, 0.2)  # Yellow
			PickupType.GRENADE_EXPLOSIVE, PickupType.GRENADE_FLASHBANG, PickupType.GRENADE_SMOKE:
				effect_color = Color(1.0, 0.4, 0.2)  # Orange
		vfx_manager.spawn_effect(effect_name, global_position, effect_color)
