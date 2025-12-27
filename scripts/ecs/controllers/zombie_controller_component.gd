## ZombieControllerComponent - AI controller for zombie entities
## Handles zombie behavior: target acquisition, pathfinding, attacking
class_name ZombieControllerComponent
extends ControllerComponent

## Zombie AI states
enum ZombieState {
	IDLE,
	WANDER,
	CHASE,
	ATTACK,
	STUNNED,
	DYING,
	DEAD
}

## Current AI state
var ai_state: ZombieState = ZombieState.IDLE

## Zombie class data (from resource)
var zombie_class_data: Resource = null

## Movement speed
var move_speed: float = 3.0

## Attack damage
var attack_damage: float = 10.0

## Attack range
var attack_range: float = 2.0

## Attack cooldown
var attack_cooldown: float = 1.0

## Time since last attack
var attack_timer: float = 0.0

## Detection range for targets
var detection_range: float = 20.0

## Lose target range (stop chasing)
var lose_target_range: float = 30.0

## Wander settings
var wander_radius: float = 10.0
var wander_wait_time: float = 3.0
var wander_timer: float = 0.0

## Spawn position (for wander)
var spawn_position: Vector3 = Vector3.ZERO

## Target priorities (entity tags to prioritize)
var target_priorities: Array[String] = ["player", "sigil"]

## Current target found via detection
var detected_target: Entity = null

## Whether zombie can break barricades
var can_break_barricades: bool = false

## Stun duration
var stun_duration: float = 0.0

## Special ability cooldown
var ability_cooldown: float = 0.0
var ability_timer: float = 0.0

## Whether this zombie is a boss
var is_boss: bool = false

## Rage mode threshold (activate at this health %)
var rage_threshold: float = 0.3

## Whether rage mode is active
var is_enraged: bool = false

## Rage mode multipliers
var rage_speed_mult: float = 1.5
var rage_damage_mult: float = 1.5

## Animation triggers
var anim_idle: String = "idle"
var anim_walk: String = "walk"
var anim_run: String = "run"
var anim_attack: String = "attack"
var anim_hurt: String = "hurt"
var anim_death: String = "death"

## Signal when attacking
signal attacking(target: Entity)

## Signal when target acquired
signal target_acquired(target: Entity)

## Signal when target lost
signal target_lost()

## Signal when entering rage mode
signal rage_activated()

## Signal when died
signal died()


func get_component_name() -> String:
	return "ZombieController"


func _init() -> void:
	controller_type = ControllerType.AI_ZOMBIE


## Setup from ZombieClassData resource
func setup_from_class_data(data: Resource) -> void:
	if not data:
		return

	zombie_class_data = data

	# Copy properties if they exist
	if "base_move_speed" in data:
		move_speed = data.base_move_speed
	if "base_damage" in data:
		attack_damage = data.base_damage
	if "attack_range" in data:
		attack_range = data.attack_range
	if "attack_cooldown" in data:
		attack_cooldown = data.attack_cooldown
	if "detection_range" in data:
		detection_range = data.detection_range
	if "can_break_barricades" in data:
		can_break_barricades = data.can_break_barricades
	if "rage_threshold" in data:
		rage_threshold = data.rage_threshold
	if "is_boss" in data:
		is_boss = data.is_boss


## Update AI controller
func _update_controller(delta: float) -> void:
	if not controller_active:
		return

	# Update timers
	attack_timer -= delta
	ability_timer -= delta
	stun_duration -= delta

	# Handle stun
	if stun_duration > 0:
		ai_state = ZombieState.STUNNED
		clear_input()
		return

	# State machine
	match ai_state:
		ZombieState.IDLE:
			_state_idle(delta)
		ZombieState.WANDER:
			_state_wander(delta)
		ZombieState.CHASE:
			_state_chase(delta)
		ZombieState.ATTACK:
			_state_attack(delta)
		ZombieState.STUNNED:
			_state_stunned(delta)
		ZombieState.DYING:
			_state_dying(delta)
		ZombieState.DEAD:
			clear_input()


## Idle state - look for targets
func _state_idle(delta: float) -> void:
	clear_input()
	change_state("idle")

	# Look for targets
	if _try_acquire_target():
		_transition_to_chase()
		return

	# Transition to wander after a bit
	wander_timer += delta
	if wander_timer >= wander_wait_time:
		wander_timer = 0.0
		ai_state = ZombieState.WANDER
		_pick_wander_target()


## Wander state - move randomly
func _state_wander(delta: float) -> void:
	change_state("walk")

	# Check for targets while wandering
	if _try_acquire_target():
		_transition_to_chase()
		return

	# Move toward wander target
	if target_position.distance_to(spawn_position) > wander_radius:
		_pick_wander_target()

	# Check if reached wander target
	var transform_comp := entity.get_component("Transform") as TransformComponent
	if transform_comp:
		var distance := transform_comp.position.distance_to(target_position)
		if distance < 1.0:
			ai_state = ZombieState.IDLE
			wander_timer = 0.0


## Chase state - pursue target
func _state_chase(_delta: float) -> void:
	change_state("chase")

	# Verify target still valid
	if not _is_target_valid():
		_lose_target()
		return

	# Update target position
	_update_target_position()

	# Get distance to target
	var transform_comp := entity.get_component("Transform") as TransformComponent
	if not transform_comp:
		return

	var distance := transform_comp.position.distance_to(target_position)

	# Check if in attack range
	if distance <= attack_range:
		ai_state = ZombieState.ATTACK
		return

	# Check if target too far
	if distance > lose_target_range:
		_lose_target()
		return

	# Set movement toward target
	var direction := transform_comp.position.direction_to(target_position)
	direction.y = 0
	input_direction = direction.normalized()

	# Face target
	look_direction = direction.normalized()


## Attack state - attack target
func _state_attack(_delta: float) -> void:
	change_state("attack")
	clear_input()

	# Verify target still in range
	var transform_comp := entity.get_component("Transform") as TransformComponent
	if transform_comp and target_entity:
		var target_transform := target_entity.get_component("Transform") as TransformComponent
		if target_transform:
			var distance := transform_comp.position.distance_to(target_transform.position)
			if distance > attack_range * 1.5:
				ai_state = ZombieState.CHASE
				return

	# Attack if cooldown ready
	if attack_timer <= 0:
		_perform_attack()
		attack_timer = attack_cooldown

		# Return to chase after attack
		ai_state = ZombieState.CHASE


## Stunned state
func _state_stunned(_delta: float) -> void:
	change_state("stunned")
	clear_input()

	if stun_duration <= 0:
		ai_state = ZombieState.CHASE if target_entity else ZombieState.IDLE


## Dying state
func _state_dying(_delta: float) -> void:
	change_state("death")
	clear_input()

	# Wait for death animation then transition to dead
	if state_time_exceeds(2.0):
		ai_state = ZombieState.DEAD
		died.emit()


## Try to acquire a target
func _try_acquire_target() -> bool:
	if not entity or not entity.world:
		return false

	var transform_comp := entity.get_component("Transform") as TransformComponent
	if not transform_comp:
		return false

	var best_target: Entity = null
	var best_distance := detection_range
	var best_priority := 999

	# Check each priority tag
	for i in range(target_priorities.size()):
		var tag := target_priorities[i]
		var targets := entity.world.get_entities_with_tag(tag)

		for target in targets:
			if target == entity:
				continue

			var target_transform := target.get_component("Transform") as TransformComponent
			if not target_transform:
				continue

			var distance := transform_comp.position.distance_to(target_transform.position)
			if distance < best_distance and i <= best_priority:
				best_target = target
				best_distance = distance
				best_priority = i

	if best_target:
		target_entity = best_target
		detected_target = best_target
		target_acquired.emit(best_target)
		return true

	return false


## Check if current target is still valid
func _is_target_valid() -> bool:
	if not target_entity:
		return false

	# Check if entity still exists and is active
	if not is_instance_valid(target_entity) or not target_entity.active:
		return false

	# Check if target has health and is alive
	var health_comp := target_entity.get_component("Health") as HealthComponent
	if health_comp and health_comp.is_dead:
		return false

	return true


## Update target position from entity
func _update_target_position() -> void:
	if not target_entity:
		return

	var transform_comp := target_entity.get_component("Transform") as TransformComponent
	if transform_comp:
		target_position = transform_comp.position


## Lose target and return to idle/wander
func _lose_target() -> void:
	target_entity = null
	detected_target = null
	ai_state = ZombieState.IDLE
	target_lost.emit()


## Transition to chase state
func _transition_to_chase() -> void:
	ai_state = ZombieState.CHASE
	_update_target_position()


## Pick a random wander target
func _pick_wander_target() -> void:
	var random_offset := Vector3(
		randf_range(-wander_radius, wander_radius),
		0,
		randf_range(-wander_radius, wander_radius)
	)
	target_position = spawn_position + random_offset


## Perform attack on target
func _perform_attack() -> void:
	if not target_entity:
		return

	action_primary = true
	attacking.emit(target_entity)

	# Deal damage to target
	var health_comp := target_entity.get_component("Health") as HealthComponent
	if health_comp:
		var damage := attack_damage
		if is_enraged:
			damage *= rage_damage_mult
		health_comp.take_damage(damage, entity)


## Apply stun
func apply_stun(duration: float) -> void:
	stun_duration = maxf(stun_duration, duration)
	ai_state = ZombieState.STUNNED


## Check and activate rage mode
func check_rage(current_health_percent: float) -> void:
	if is_enraged:
		return

	if current_health_percent <= rage_threshold:
		is_enraged = true
		move_speed *= rage_speed_mult
		rage_activated.emit()


## Start dying
func start_death() -> void:
	ai_state = ZombieState.DYING
	controller_active = false
	clear_input()


## Get current speed (with rage modifier)
func get_current_speed() -> float:
	var speed := move_speed
	if is_enraged:
		speed *= rage_speed_mult

	# Apply status effect modifiers
	var status_comp := entity.get_component("StatusEffect") as StatusEffectComponent
	if status_comp:
		speed *= status_comp.speed_modifier

	return speed


func serialize() -> Dictionary:
	var data := super.serialize()
	data["ai_state"] = ai_state
	data["move_speed"] = move_speed
	data["attack_damage"] = attack_damage
	data["attack_range"] = attack_range
	data["detection_range"] = detection_range
	data["spawn_position"] = {
		"x": spawn_position.x,
		"y": spawn_position.y,
		"z": spawn_position.z
	}
	data["is_enraged"] = is_enraged
	data["is_boss"] = is_boss
	return data


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	ai_state = data.get("ai_state", ZombieState.IDLE)
	move_speed = data.get("move_speed", 3.0)
	attack_damage = data.get("attack_damage", 10.0)
	attack_range = data.get("attack_range", 2.0)
	detection_range = data.get("detection_range", 20.0)
	if data.has("spawn_position"):
		var s: Dictionary = data["spawn_position"]
		spawn_position = Vector3(s.get("x", 0), s.get("y", 0), s.get("z", 0))
	is_enraged = data.get("is_enraged", false)
	is_boss = data.get("is_boss", false)
