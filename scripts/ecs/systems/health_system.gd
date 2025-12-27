## HealthSystem - Processes health-related logic for entities
## Handles DOT effects, regeneration, death, and health events
class_name HealthSystem
extends System

## Signal when any entity dies
signal entity_died(entity: Entity, killer: Entity)

## Signal when any entity takes damage
signal entity_damaged(entity: Entity, damage: float, source: Entity)


func get_system_name() -> String:
	return "HealthSystem"


func get_required_components() -> Array[String]:
	return ["Health"]


func get_optional_components() -> Array[String]:
	return ["Controller", "StatusEffect"]


func _on_entity_added(entity: Entity) -> void:
	# Connect to health signals
	var health_comp := entity.get_component("Health") as HealthComponent
	if health_comp:
		health_comp.died.connect(_on_entity_health_died.bind(entity))
		health_comp.damaged.connect(_on_entity_health_damaged.bind(entity))


func _on_entity_removed(entity: Entity) -> void:
	# Disconnect signals
	var health_comp := entity.get_component("Health") as HealthComponent
	if health_comp:
		if health_comp.died.is_connected(_on_entity_health_died):
			health_comp.died.disconnect(_on_entity_health_died)
		if health_comp.damaged.is_connected(_on_entity_health_damaged):
			health_comp.damaged.disconnect(_on_entity_health_damaged)


func process_entity(entity: Entity, delta: float) -> void:
	var health_comp := entity.get_component("Health") as HealthComponent
	if not health_comp or health_comp.is_dead:
		return

	# Update health component (DOT effects, invulnerability, regen)
	health_comp.update(delta)

	# Apply status effect damage modifiers
	var status_comp := entity.get_component("StatusEffect") as StatusEffectComponent
	if status_comp:
		# Process status effect DOT damage
		var damage_ticks := status_comp.update_effects(delta)
		for tick: Dictionary in damage_ticks:
			var tick_damage: float = tick["damage"]
			health_comp.take_damage(tick_damage * status_comp.damage_taken_modifier)

	# Check for rage mode on zombie controllers
	var controller_comp := entity.get_component("Controller") as ControllerComponent
	if controller_comp is ZombieControllerComponent:
		var zombie_ctrl := controller_comp as ZombieControllerComponent
		zombie_ctrl.check_rage(health_comp.get_health_percent())


## Handle entity death
func _on_entity_health_died(killer: Entity, entity: Entity) -> void:
	entity_died.emit(entity, killer)

	# Notify controller
	var controller_comp := entity.get_component("Controller") as ControllerComponent
	if controller_comp is ZombieControllerComponent:
		(controller_comp as ZombieControllerComponent).start_death()


## Handle entity damaged
func _on_entity_health_damaged(damage: float, source: Entity, entity: Entity) -> void:
	entity_damaged.emit(entity, damage, source)


## Deal damage to an entity
func deal_damage(target: Entity, damage: float, source: Entity = null,
		damage_type: String = "physical") -> float:

	var health_comp := target.get_component("Health") as HealthComponent
	if not health_comp:
		return 0.0

	# Apply status effect modifiers to damage
	var status_comp := target.get_component("StatusEffect") as StatusEffectComponent
	var final_damage := damage
	if status_comp:
		final_damage *= status_comp.damage_taken_modifier

	return health_comp.take_damage(final_damage, source)


## Heal an entity
func heal_entity(target: Entity, amount: float) -> float:
	var health_comp := target.get_component("Health") as HealthComponent
	if not health_comp:
		return 0.0

	return health_comp.heal(amount)


## Kill an entity instantly
func kill_entity(target: Entity, killer: Entity = null) -> void:
	var health_comp := target.get_component("Health") as HealthComponent
	if health_comp:
		health_comp.kill(killer)


## Revive an entity
func revive_entity(target: Entity, health_amount: float = -1) -> void:
	var health_comp := target.get_component("Health") as HealthComponent
	if health_comp:
		health_comp.revive_with_health(health_amount)


## Get entity health percentage
func get_health_percent(entity: Entity) -> float:
	var health_comp := entity.get_component("Health") as HealthComponent
	if health_comp:
		return health_comp.get_health_percent()
	return 0.0


## Check if entity is dead
func is_dead(entity: Entity) -> bool:
	var health_comp := entity.get_component("Health") as HealthComponent
	if health_comp:
		return health_comp.is_dead
	return false
