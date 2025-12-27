## HealthComponent - Stores health-related data for entities
## Handles damage, healing, and death state
class_name HealthComponent
extends Component

## Current health
var current: float = 100.0

## Maximum health
var maximum: float = 100.0

## Whether entity is dead
var is_dead: bool = false

## Armor value (damage reduction)
var armor: float = 0.0

## Armor percentage (0-1, percentage damage reduction)
var armor_percent: float = 0.0

## Whether entity can be damaged
var invulnerable: bool = false

## Invulnerability timer
var invulnerability_time: float = 0.0

## Health regeneration per second
var regen_rate: float = 0.0

## Damage over time effects (name -> {damage_per_second, duration})
var dot_effects: Dictionary = {}

## Signal emitted when damaged
signal damaged(amount: float, source: Entity)

## Signal emitted when healed
signal healed(amount: float)

## Signal emitted when health changes
signal health_changed(current_health: float, max_health: float)

## Signal emitted when entity dies
signal died(killer: Entity)

## Signal emitted when entity is revived
signal revived()


func get_component_name() -> String:
	return "Health"


func _on_added() -> void:
	current = maximum


## Take damage from a source
func take_damage(amount: float, source: Entity = null) -> float:
	if invulnerable or is_dead or amount <= 0:
		return 0.0

	# Apply armor reduction
	var actual_damage := amount
	actual_damage -= armor
	actual_damage *= (1.0 - armor_percent)
	actual_damage = maxf(actual_damage, 0.0)

	current -= actual_damage
	current = maxf(current, 0.0)

	damaged.emit(actual_damage, source)
	health_changed.emit(current, maximum)

	if current <= 0:
		_die(source)

	return actual_damage


## Heal the entity
func heal(amount: float) -> float:
	if is_dead or amount <= 0:
		return 0.0

	var actual_heal := minf(amount, maximum - current)
	current += actual_heal
	current = minf(current, maximum)

	healed.emit(actual_heal)
	health_changed.emit(current, maximum)

	return actual_heal


## Set health directly (bypasses armor)
func set_health(value: float) -> void:
	var was_dead := is_dead
	current = clampf(value, 0.0, maximum)
	is_dead = current <= 0

	if is_dead and not was_dead:
		_die(null)
	elif not is_dead and was_dead:
		_revive()

	health_changed.emit(current, maximum)


## Set maximum health
func set_max_health(value: float, heal_to_full: bool = false) -> void:
	maximum = maxf(value, 1.0)
	if heal_to_full:
		current = maximum
	else:
		current = minf(current, maximum)
	health_changed.emit(current, maximum)


## Get health percentage (0-1)
func get_health_percent() -> float:
	if maximum <= 0:
		return 0.0
	return current / maximum


## Check if at full health
func is_full_health() -> bool:
	return current >= maximum


## Check if below certain percentage
func is_below_percent(percent: float) -> bool:
	return get_health_percent() < percent


## Add damage over time effect
func add_dot_effect(name: String, damage_per_second: float, duration: float) -> void:
	dot_effects[name] = {
		"dps": damage_per_second,
		"duration": duration,
		"elapsed": 0.0
	}


## Remove damage over time effect
func remove_dot_effect(name: String) -> void:
	dot_effects.erase(name)


## Clear all dot effects
func clear_dot_effects() -> void:
	dot_effects.clear()


## Make invulnerable for a duration
func set_invulnerable_for(duration: float) -> void:
	invulnerable = true
	invulnerability_time = duration


## Update DOT effects and invulnerability (called by HealthSystem)
func update(delta: float, source: Entity = null) -> void:
	# Update invulnerability
	if invulnerability_time > 0:
		invulnerability_time -= delta
		if invulnerability_time <= 0:
			invulnerable = false

	# Update DOT effects
	var effects_to_remove: Array[String] = []
	for effect_name: String in dot_effects.keys():
		var effect: Dictionary = dot_effects[effect_name]
		effect["elapsed"] += delta

		# Apply damage
		var dps: float = effect["dps"]
		take_damage(dps * delta, source)

		# Check if expired
		if effect["elapsed"] >= effect["duration"]:
			effects_to_remove.append(effect_name)

	for effect_name in effects_to_remove:
		dot_effects.erase(effect_name)

	# Apply regeneration
	if regen_rate > 0 and not is_dead:
		heal(regen_rate * delta)


## Kill the entity instantly
func kill(killer: Entity = null) -> void:
	current = 0
	_die(killer)


## Revive the entity
func revive_with_health(health: float = -1) -> void:
	if health < 0:
		current = maximum
	else:
		current = clampf(health, 1.0, maximum)
	_revive()


## Internal die function
func _die(killer: Entity) -> void:
	if is_dead:
		return
	is_dead = true
	died.emit(killer)


## Internal revive function
func _revive() -> void:
	is_dead = false
	invulnerable = false
	invulnerability_time = 0.0
	dot_effects.clear()
	revived.emit()


func serialize() -> Dictionary:
	var data := super.serialize()
	data["current"] = current
	data["maximum"] = maximum
	data["is_dead"] = is_dead
	data["armor"] = armor
	data["armor_percent"] = armor_percent
	data["regen_rate"] = regen_rate
	return data


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	current = data.get("current", 100.0)
	maximum = data.get("maximum", 100.0)
	is_dead = data.get("is_dead", false)
	armor = data.get("armor", 0.0)
	armor_percent = data.get("armor_percent", 0.0)
	regen_rate = data.get("regen_rate", 0.0)
