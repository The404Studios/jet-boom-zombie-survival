## StatusEffectComponent - Manages status effects on entities
## Handles buffs, debuffs, DOTs, and other temporary effects
class_name StatusEffectComponent
extends Component

## Status effect data structure
class StatusEffect:
	var name: String = ""
	var type: String = ""  # buff, debuff, dot, cc
	var duration: float = 0.0
	var elapsed: float = 0.0
	var stacks: int = 1
	var max_stacks: int = 1
	var value: float = 0.0  # Effect strength/damage
	var tick_interval: float = 1.0  # For DOTs
	var tick_timer: float = 0.0
	var source_entity_id: int = -1

	func is_expired() -> bool:
		return elapsed >= duration

	func get_remaining_time() -> float:
		return maxf(duration - elapsed, 0.0)


## Active status effects
var effects: Array[StatusEffect] = []

## Immunity list (effect names that can't be applied)
var immunities: Array[String] = []

## Maximum effects at once
var max_effects: int = 10

## Stat modifiers from effects (stat_name -> total modifier)
var stat_modifiers: Dictionary = {}

## Movement speed modifier
var speed_modifier: float = 1.0

## Damage modifier (for dealt damage)
var damage_dealt_modifier: float = 1.0

## Damage taken modifier
var damage_taken_modifier: float = 1.0

## Attack speed modifier
var attack_speed_modifier: float = 1.0

## Whether entity is stunned
var is_stunned: bool = false

## Whether entity is rooted (can't move)
var is_rooted: bool = false

## Whether entity is silenced (can't use abilities)
var is_silenced: bool = false

## Whether entity is invulnerable from effects
var is_effect_invulnerable: bool = false

## Signal when effect applied
signal effect_applied(effect: StatusEffect)

## Signal when effect removed
signal effect_removed(effect_name: String)

## Signal when effect tick (for DOTs)
signal effect_ticked(effect: StatusEffect, damage: float)

## Signal when modifiers changed
signal modifiers_changed()


func get_component_name() -> String:
	return "StatusEffect"


## Apply a new status effect
func apply_effect(effect_name: String, effect_type: String, duration: float,
		value: float = 0.0, source_id: int = -1, max_stacks: int = 1,
		tick_interval: float = 1.0) -> bool:

	if is_effect_invulnerable:
		return false

	if immunities.has(effect_name):
		return false

	# Check for existing effect
	var existing := get_effect(effect_name)
	if existing:
		# Stack or refresh
		if existing.stacks < max_stacks:
			existing.stacks += 1
			existing.elapsed = 0.0  # Refresh duration
		else:
			existing.elapsed = 0.0  # Just refresh duration
		_recalculate_modifiers()
		return true

	# Check max effects
	if effects.size() >= max_effects:
		# Remove shortest duration effect
		_remove_shortest_effect()

	# Create new effect
	var effect := StatusEffect.new()
	effect.name = effect_name
	effect.type = effect_type
	effect.duration = duration
	effect.value = value
	effect.source_entity_id = source_id
	effect.max_stacks = max_stacks
	effect.tick_interval = tick_interval

	effects.append(effect)
	_apply_effect_cc(effect)
	_recalculate_modifiers()

	effect_applied.emit(effect)
	return true


## Remove a status effect by name
func remove_effect(effect_name: String) -> bool:
	for i in range(effects.size() - 1, -1, -1):
		if effects[i].name == effect_name:
			var effect := effects[i]
			_remove_effect_cc(effect)
			effects.remove_at(i)
			_recalculate_modifiers()
			effect_removed.emit(effect_name)
			return true
	return false


## Remove all effects of a type
func remove_effects_of_type(effect_type: String) -> int:
	var removed := 0
	for i in range(effects.size() - 1, -1, -1):
		if effects[i].type == effect_type:
			var effect := effects[i]
			_remove_effect_cc(effect)
			effects.remove_at(i)
			effect_removed.emit(effect.name)
			removed += 1

	if removed > 0:
		_recalculate_modifiers()
	return removed


## Clear all effects
func clear_all_effects() -> void:
	for effect in effects:
		_remove_effect_cc(effect)
		effect_removed.emit(effect.name)
	effects.clear()
	_recalculate_modifiers()


## Get an effect by name
func get_effect(effect_name: String) -> StatusEffect:
	for effect in effects:
		if effect.name == effect_name:
			return effect
	return null


## Check if has effect
func has_effect(effect_name: String) -> bool:
	return get_effect(effect_name) != null


## Get all effects
func get_all_effects() -> Array[StatusEffect]:
	return effects


## Get effects of type
func get_effects_of_type(effect_type: String) -> Array[StatusEffect]:
	var result: Array[StatusEffect] = []
	for effect in effects:
		if effect.type == effect_type:
			result.append(effect)
	return result


## Update effects (called by StatusEffectSystem)
func update_effects(delta: float) -> Array[Dictionary]:
	var damage_ticks: Array[Dictionary] = []

	for i in range(effects.size() - 1, -1, -1):
		var effect := effects[i]
		effect.elapsed += delta

		# Handle DOT ticks
		if effect.type == "dot":
			effect.tick_timer += delta
			if effect.tick_timer >= effect.tick_interval:
				effect.tick_timer -= effect.tick_interval
				var tick_damage := effect.value * effect.stacks
				damage_ticks.append({
					"effect": effect,
					"damage": tick_damage
				})
				effect_ticked.emit(effect, tick_damage)

		# Remove expired effects
		if effect.is_expired():
			_remove_effect_cc(effect)
			effects.remove_at(i)
			effect_removed.emit(effect.name)

	if damage_ticks.size() > 0:
		_recalculate_modifiers()

	return damage_ticks


## Add immunity
func add_immunity(effect_name: String) -> void:
	if not immunities.has(effect_name):
		immunities.append(effect_name)
		# Remove effect if currently applied
		remove_effect(effect_name)


## Remove immunity
func remove_immunity(effect_name: String) -> void:
	immunities.erase(effect_name)


## Apply CC flags from effect
func _apply_effect_cc(effect: StatusEffect) -> void:
	match effect.name:
		"stun":
			is_stunned = true
		"root":
			is_rooted = true
		"silence":
			is_silenced = true


## Remove CC flags from effect
func _remove_effect_cc(effect: StatusEffect) -> void:
	match effect.name:
		"stun":
			is_stunned = not has_effect("stun")
		"root":
			is_rooted = not has_effect("root")
		"silence":
			is_silenced = not has_effect("silence")


## Recalculate stat modifiers from all effects
func _recalculate_modifiers() -> void:
	stat_modifiers.clear()
	speed_modifier = 1.0
	damage_dealt_modifier = 1.0
	damage_taken_modifier = 1.0
	attack_speed_modifier = 1.0

	for effect in effects:
		var modifier := effect.value * effect.stacks

		match effect.name:
			"slow":
				speed_modifier -= modifier
			"haste":
				speed_modifier += modifier
			"weakness":
				damage_dealt_modifier -= modifier
			"strength":
				damage_dealt_modifier += modifier
			"vulnerability":
				damage_taken_modifier += modifier
			"fortify":
				damage_taken_modifier -= modifier
			"attack_slow":
				attack_speed_modifier -= modifier
			"attack_speed":
				attack_speed_modifier += modifier
			_:
				# Generic stat modifier
				if effect.type == "buff":
					stat_modifiers[effect.name] = stat_modifiers.get(effect.name, 0.0) + modifier
				elif effect.type == "debuff":
					stat_modifiers[effect.name] = stat_modifiers.get(effect.name, 0.0) - modifier

	# Clamp modifiers
	speed_modifier = maxf(speed_modifier, 0.1)
	damage_dealt_modifier = maxf(damage_dealt_modifier, 0.1)
	damage_taken_modifier = maxf(damage_taken_modifier, 0.0)
	attack_speed_modifier = maxf(attack_speed_modifier, 0.1)

	modifiers_changed.emit()


## Remove the effect with shortest remaining duration
func _remove_shortest_effect() -> void:
	if effects.is_empty():
		return

	var shortest_idx := 0
	var shortest_time := effects[0].get_remaining_time()

	for i in range(1, effects.size()):
		var remaining := effects[i].get_remaining_time()
		if remaining < shortest_time:
			shortest_time = remaining
			shortest_idx = i

	var effect := effects[shortest_idx]
	_remove_effect_cc(effect)
	effects.remove_at(shortest_idx)
	effect_removed.emit(effect.name)


func serialize() -> Dictionary:
	var data := super.serialize()
	var effects_data: Array[Dictionary] = []

	for effect in effects:
		effects_data.append({
			"name": effect.name,
			"type": effect.type,
			"duration": effect.duration,
			"elapsed": effect.elapsed,
			"stacks": effect.stacks,
			"value": effect.value
		})

	data["effects"] = effects_data
	data["immunities"] = immunities
	return data


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)

	effects.clear()
	if data.has("effects"):
		for effect_data: Dictionary in data["effects"]:
			var effect := StatusEffect.new()
			effect.name = effect_data.get("name", "")
			effect.type = effect_data.get("type", "")
			effect.duration = effect_data.get("duration", 0.0)
			effect.elapsed = effect_data.get("elapsed", 0.0)
			effect.stacks = effect_data.get("stacks", 1)
			effect.value = effect_data.get("value", 0.0)
			effects.append(effect)

	if data.has("immunities"):
		immunities = data["immunities"]

	_recalculate_modifiers()
