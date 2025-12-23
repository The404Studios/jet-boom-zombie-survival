extends Node
class_name StatusEffectSystem

class StatusEffect:
	var effect_type: String = ""
	var damage_per_second: float = 0.0
	var duration: float = 0.0
	var elapsed: float = 0.0
	var stacks: int = 1
	var max_stacks: int = 10

	func _init(type: String, dps: float, dur: float):
		effect_type = type
		damage_per_second = dps
		duration = dur

var active_effects: Array[StatusEffect] = []
var target: Node = null

signal status_applied(effect_type: String, stacks: int)
signal status_removed(effect_type: String)
signal status_damage(effect_type: String, damage: float)

func _ready():
	target = get_parent()

func _process(delta):
	for i in range(active_effects.size() - 1, -1, -1):
		var effect = active_effects[i]
		effect.elapsed += delta

		# Deal damage
		var damage = effect.damage_per_second * effect.stacks * delta
		if damage > 0 and target and target.has_method("take_damage"):
			target.take_damage(damage, Vector3.ZERO)
			status_damage.emit(effect.effect_type, damage)

		# Check expiration
		if effect.elapsed >= effect.duration:
			remove_effect(i)

func apply_effect(effect_type: String, damage_per_second: float, duration: float):
	# Check if effect already exists
	for effect in active_effects:
		if effect.effect_type == effect_type:
			# Stack the effect
			effect.stacks = min(effect.stacks + 1, effect.max_stacks)
			effect.duration = max(effect.duration, duration)  # Refresh duration
			effect.damage_per_second = max(effect.damage_per_second, damage_per_second)
			status_applied.emit(effect_type, effect.stacks)
			return

	# Create new effect
	var new_effect = StatusEffect.new(effect_type, damage_per_second, duration)
	active_effects.append(new_effect)
	status_applied.emit(effect_type, 1)

func remove_effect(index: int):
	if index >= 0 and index < active_effects.size():
		var effect = active_effects[index]
		status_removed.emit(effect.effect_type)
		active_effects.remove_at(index)

func clear_all_effects():
	for effect in active_effects:
		status_removed.emit(effect.effect_type)
	active_effects.clear()

func has_effect(effect_type: String) -> bool:
	for effect in active_effects:
		if effect.effect_type == effect_type:
			return true
	return false

func get_effect_stacks(effect_type: String) -> int:
	for effect in active_effects:
		if effect.effect_type == effect_type:
			return effect.stacks
	return 0

func get_active_effects_summary() -> Array[Dictionary]:
	var summary: Array[Dictionary] = []
	for effect in active_effects:
		summary.append({
			"type": effect.effect_type,
			"dps": effect.damage_per_second * effect.stacks,
			"duration": effect.duration - effect.elapsed,
			"stacks": effect.stacks
		})
	return summary
