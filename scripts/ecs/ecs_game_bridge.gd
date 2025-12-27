## ECSGameBridge - Bridge between ECS and existing game systems
## Connects ECS events to existing game managers and systems
extends Node

## Reference to ECS Manager
var ecs: Node = null

## Reference to existing game systems (autoloads)
var game_manager: Node = null
var points_system: Node = null
var audio_manager: Node = null
var vfx_manager: Node = null


func _ready() -> void:
	# Wait for autoloads to be ready
	await get_tree().process_frame
	_connect_systems()


## Connect to existing game systems
func _connect_systems() -> void:
	# Get ECS Manager
	ecs = get_node_or_null("/root/ECSManager")
	if not ecs:
		push_warning("[ECSBridge] ECSManager not found")
		return

	# Get existing autoloads
	game_manager = get_node_or_null("/root/GameManager")
	points_system = get_node_or_null("/root/PointsSystem")
	audio_manager = get_node_or_null("/root/AudioManager")
	vfx_manager = get_node_or_null("/root/VFXManager")

	# Connect ECS signals
	ecs.player_created.connect(_on_player_created)
	ecs.zombie_created.connect(_on_zombie_created)
	ecs.entity_destroyed.connect(_on_entity_destroyed)

	# Connect health system signals
	if ecs.health_system:
		ecs.health_system.entity_died.connect(_on_entity_died)
		ecs.health_system.entity_damaged.connect(_on_entity_damaged)

	# Connect combat system signals
	if ecs.combat_system:
		ecs.combat_system.weapon_fired.connect(_on_weapon_fired)
		ecs.combat_system.target_hit.connect(_on_target_hit)

	print("[ECSBridge] Connected to game systems")


## Player created callback
func _on_player_created(entity: Entity) -> void:
	# Connect player health to existing UI
	var health := entity.get_component("Health") as HealthComponent
	if health:
		health.health_changed.connect(_on_player_health_changed)
		health.died.connect(_on_player_died)

	# Connect player controller for stamina
	var controller := entity.get_component("PlayerController") as PlayerControllerComponent
	if controller:
		controller.stamina_changed.connect(_on_player_stamina_changed)


## Zombie created callback
func _on_zombie_created(_entity: Entity) -> void:
	# Notify game manager of spawn
	if game_manager and game_manager.has_signal("zombie_spawned"):
		game_manager.emit_signal("zombie_spawned", _entity)


## Entity destroyed callback
func _on_entity_destroyed(entity: Entity) -> void:
	# Cleanup any references
	pass


## Entity died callback
func _on_entity_died(entity: Entity, killer: Entity) -> void:
	if entity.has_tag("zombie"):
		_on_zombie_died(entity, killer)
	elif entity.has_tag("player"):
		_on_player_died(killer)


## Zombie died callback
func _on_zombie_died(zombie: Entity, killer: Entity) -> void:
	# Award points
	if points_system and killer and killer.has_tag("player"):
		var points := 100  # Base points

		# Bonus points for special zombies
		if zombie.has_tag("tank"):
			points = 300
		elif zombie.has_tag("runner"):
			points = 150
		elif zombie.has_tag("boss"):
			points = 1000

		if points_system.has_method("add_points"):
			points_system.add_points(points)

	# Play death sound
	if audio_manager and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("zombie_death")

	# Spawn death VFX
	if vfx_manager and vfx_manager.has_method("spawn_effect"):
		var transform := zombie.get_component("Transform") as TransformComponent
		if transform:
			vfx_manager.spawn_effect("blood_splatter", transform.position)

	# Notify game manager
	if game_manager and game_manager.has_method("on_zombie_killed"):
		game_manager.on_zombie_killed()


## Player died callback
func _on_player_died(_killer: Entity) -> void:
	# Trigger game over
	if game_manager and game_manager.has_signal("game_over"):
		game_manager.emit_signal("game_over", false)


## Entity damaged callback
func _on_entity_damaged(entity: Entity, damage: float, _source: Entity) -> void:
	# Play hit sound
	if audio_manager and audio_manager.has_method("play_sfx"):
		if entity.has_tag("zombie"):
			audio_manager.play_sfx("zombie_hit")
		elif entity.has_tag("player"):
			audio_manager.play_sfx("player_hit")

	# Spawn hit VFX
	if vfx_manager and vfx_manager.has_method("spawn_effect"):
		var transform := entity.get_component("Transform") as TransformComponent
		if transform:
			vfx_manager.spawn_effect("hit_spark", transform.position)


## Weapon fired callback
func _on_weapon_fired(entity: Entity, weapon: WeaponComponent) -> void:
	if not entity.has_tag("player"):
		return

	# Play weapon sound
	if audio_manager and audio_manager.has_method("play_sfx"):
		var sfx_name := "weapon_fire"
		match weapon.weapon_type:
			WeaponComponent.WeaponType.SHOTGUN:
				sfx_name = "shotgun_fire"
			WeaponComponent.WeaponType.SNIPER:
				sfx_name = "sniper_fire"
			WeaponComponent.WeaponType.EXPLOSIVE:
				sfx_name = "rpg_fire"
		audio_manager.play_sfx(sfx_name)

	# Spawn muzzle flash
	if vfx_manager and vfx_manager.has_method("spawn_effect"):
		var transform := entity.get_component("Transform") as TransformComponent
		if transform:
			var muzzle_pos := transform.position + weapon.muzzle_offset
			vfx_manager.spawn_effect("muzzle_flash", muzzle_pos)


## Target hit callback
func _on_target_hit(_attacker: Entity, target: Entity, damage: float, is_crit: bool) -> void:
	# Show damage number
	if vfx_manager and vfx_manager.has_method("spawn_damage_number"):
		var transform := target.get_component("Transform") as TransformComponent
		if transform:
			var color := Color.YELLOW if is_crit else Color.WHITE
			vfx_manager.spawn_damage_number(transform.position, damage, color)


## Player health changed callback
func _on_player_health_changed(current: float, maximum: float) -> void:
	# Update HUD - this would be connected to the actual HUD
	# The existing HUD system should listen for this
	pass


## Player stamina changed callback
func _on_player_stamina_changed(current: float, maximum: float) -> void:
	# Update HUD
	pass


## Spawn zombie using ECS (for GameManager integration)
func spawn_zombie(position: Vector3, zombie_type: String = "shambler",
		wave_number: int = 1) -> Entity:

	if not ecs:
		return null

	# Scale stats based on wave
	var config := {
		"health": _get_scaled_health(zombie_type, wave_number),
		"damage": _get_scaled_damage(zombie_type, wave_number),
	}

	return ecs.create_zombie(position, zombie_type, config)


## Get wave-scaled health
func _get_scaled_health(zombie_type: String, wave: int) -> float:
	var base_health := 100.0
	var health_per_wave := 10.0

	match zombie_type:
		"runner":
			base_health = 60.0
			health_per_wave = 5.0
		"tank":
			base_health = 300.0
			health_per_wave = 40.0
		"boss_behemoth":
			base_health = 1000.0
			health_per_wave = 100.0

	return base_health + (wave - 1) * health_per_wave


## Get wave-scaled damage
func _get_scaled_damage(zombie_type: String, wave: int) -> float:
	var base_damage := 10.0
	var damage_per_wave := 2.0

	match zombie_type:
		"runner":
			base_damage = 8.0
			damage_per_wave = 1.0
		"tank":
			base_damage = 25.0
			damage_per_wave = 5.0
		"boss_behemoth":
			base_damage = 50.0
			damage_per_wave = 10.0

	return base_damage + (wave - 1) * damage_per_wave
