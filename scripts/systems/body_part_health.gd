extends Node
class_name BodyPartHealth

# Body Part Health System
# Tracks individual limb HP with level scaling
# Handles bleeding debuffs for blacked out limbs and healing mechanics

signal body_part_damaged(part_name: String, new_health: float, max_health: float)
signal body_part_healed(part_name: String, new_health: float, max_health: float)
signal body_part_blacked_out(part_name: String)
signal body_part_restored(part_name: String)
signal bleeding_started(part_name: String)
signal bleeding_stopped(part_name: String)
signal healing_started(part_name: String)
signal healing_progress(part_name: String, progress: float)
signal healing_completed(part_name: String)
signal healing_cancelled(part_name: String)
signal status_effect_applied(effect_name: String, duration: float)
signal status_effect_removed(effect_name: String)

# Body part definitions with base HP values
enum BodyPart {
	HEAD,
	CHEST,
	THORAX,
	LEFT_ARM,
	RIGHT_ARM,
	LEFT_HAND,
	RIGHT_HAND,
	LEFT_LEG,
	RIGHT_LEG,
	LEFT_FOOT,
	RIGHT_FOOT
}

# Base HP values per body part type
const BASE_HP = {
	BodyPart.HEAD: 15.0,
	BodyPart.CHEST: 40.0,
	BodyPart.THORAX: 40.0,
	BodyPart.LEFT_ARM: 25.0,
	BodyPart.RIGHT_ARM: 25.0,
	BodyPart.LEFT_HAND: 25.0,
	BodyPart.RIGHT_HAND: 25.0,
	BodyPart.LEFT_LEG: 25.0,
	BodyPart.RIGHT_LEG: 25.0,
	BodyPart.LEFT_FOOT: 25.0,
	BodyPart.RIGHT_FOOT: 25.0
}

# HP bonus per level (limbs get +2, vital parts get more)
const LEVEL_HP_BONUS = {
	BodyPart.HEAD: 1.0,
	BodyPart.CHEST: 3.0,
	BodyPart.THORAX: 3.0,
	BodyPart.LEFT_ARM: 2.0,
	BodyPart.RIGHT_ARM: 2.0,
	BodyPart.LEFT_HAND: 2.0,
	BodyPart.RIGHT_HAND: 2.0,
	BodyPart.LEFT_LEG: 2.0,
	BodyPart.RIGHT_LEG: 2.0,
	BodyPart.LEFT_FOOT: 2.0,
	BodyPart.RIGHT_FOOT: 2.0
}

# Body part name mapping for display
const PART_NAMES = {
	BodyPart.HEAD: "Head",
	BodyPart.CHEST: "Chest",
	BodyPart.THORAX: "Thorax",
	BodyPart.LEFT_ARM: "Left Arm",
	BodyPart.RIGHT_ARM: "Right Arm",
	BodyPart.LEFT_HAND: "Left Hand",
	BodyPart.RIGHT_HAND: "Right Hand",
	BodyPart.LEFT_LEG: "Left Leg",
	BodyPart.RIGHT_LEG: "Right Leg",
	BodyPart.LEFT_FOOT: "Left Foot",
	BodyPart.RIGHT_FOOT: "Right Foot"
}

# Current health for each body part
var current_health: Dictionary = {}
var max_health: Dictionary = {}
var is_blacked_out: Dictionary = {}
var is_bleeding: Dictionary = {}

# Player level for scaling
var player_level: int = 1

# Healing state
var is_healing: bool = false
var healing_part: int = -1
var healing_timer: float = 0.0
var healing_duration: float = 3.0  # Seconds to heal a limb

# Bleeding damage
var bleeding_damage_per_second: float = 2.0
var bleeding_tick_timer: float = 0.0

# Active status effects (for UI display)
var active_effects: Dictionary = {}  # effect_name -> { duration: float, max_duration: float, type: String }

# Reference to parent player
var player: Node = null

# Grace period to prevent damage at spawn
var spawn_grace_period: float = 2.0
var spawn_timer: float = 0.0

func _ready():
	# Initialize all body parts to full health
	for part in BodyPart.values():
		_initialize_body_part(part)

	# Find player parent
	player = get_parent()

	# Connect to character attributes for level changes
	if player and player.has_node("CharacterAttributes"):
		var attrs = player.get_node("CharacterAttributes")
		if attrs.has_signal("level_up"):
			attrs.level_up.connect(_on_level_up)

	# Start spawn grace period
	spawn_timer = spawn_grace_period

func _initialize_body_part(part: int):
	"""Initialize a body part with base HP"""
	max_health[part] = _calculate_max_health(part)
	current_health[part] = max_health[part]
	is_blacked_out[part] = false
	is_bleeding[part] = false

func _calculate_max_health(part: int) -> float:
	"""Calculate max HP for a body part based on level"""
	var base = BASE_HP.get(part, 25.0)
	var bonus = LEVEL_HP_BONUS.get(part, 2.0)
	return base + (bonus * (player_level - 1))

func _process(delta):
	# Update spawn grace period
	if spawn_timer > 0:
		spawn_timer -= delta

	# Process healing
	if is_healing and healing_part >= 0:
		healing_timer += delta
		var progress = healing_timer / healing_duration
		healing_progress.emit(PART_NAMES[healing_part], progress)

		if healing_timer >= healing_duration:
			_complete_healing()

	# Process bleeding damage (skip during grace period)
	if spawn_timer <= 0:
		bleeding_tick_timer += delta
		if bleeding_tick_timer >= 1.0:
			bleeding_tick_timer = 0.0
			_apply_bleeding_damage()

	# Update effect durations
	_update_effects(delta)

func _apply_bleeding_damage():
	"""Apply bleeding damage from blacked out limbs"""
	var total_bleed_count = 0

	for part in BodyPart.values():
		if is_bleeding.get(part, false):
			total_bleed_count += 1

	# Only apply damage if actually bleeding
	if total_bleed_count > 0 and player and player.has_method("take_damage"):
		# Bleeding damages the player's overall health (scale with number of bleeding parts)
		var damage = bleeding_damage_per_second * min(total_bleed_count, 3)  # Cap at 3x damage
		player.take_damage(damage, Vector3.ZERO)

func reset_to_full_health():
	"""Reset all body parts to full health - call on spawn/respawn"""
	spawn_timer = spawn_grace_period

	for part in BodyPart.values():
		max_health[part] = _calculate_max_health(part)
		current_health[part] = max_health[part]
		is_blacked_out[part] = false
		is_bleeding[part] = false

	# Clear active bleeding effects
	for effect_name in active_effects.keys():
		if effect_name.begins_with("Bleeding"):
			remove_effect(effect_name)

	# Remove all blackout penalties
	if player and player.has_node("PlayerConditions"):
		var conditions = player.get_node("PlayerConditions")
		conditions.remove_condition("blurred_vision")
		conditions.remove_condition("exhaustion")
		conditions.remove_condition("limping")
		conditions.remove_condition("weakened")

func _update_effects(delta: float):
	"""Update status effect durations"""
	var effects_to_remove: Array = []

	for effect_name in active_effects.keys():
		var effect = active_effects[effect_name]
		effect.duration -= delta

		if effect.duration <= 0:
			effects_to_remove.append(effect_name)

	for effect_name in effects_to_remove:
		remove_effect(effect_name)

func _on_level_up(new_level: int, _points: int):
	"""Handle player level up - increase max HP for all parts"""
	player_level = new_level

	for part in BodyPart.values():
		var old_max = max_health[part]
		max_health[part] = _calculate_max_health(part)

		# Heal the difference on level up
		var hp_increase = max_health[part] - old_max
		if hp_increase > 0:
			current_health[part] = min(current_health[part] + hp_increase, max_health[part])
			body_part_healed.emit(PART_NAMES[part], current_health[part], max_health[part])

# ============================================
# DAMAGE SYSTEM
# ============================================

func take_damage_to_part(part: int, amount: float) -> float:
	"""
	Apply damage to a specific body part.
	Returns actual damage dealt.
	"""
	# Ignore damage during spawn grace period
	if spawn_timer > 0:
		return 0.0

	if part < 0 or part >= BodyPart.size():
		return 0.0

	# Ensure dictionaries are initialized for this part
	if not current_health.has(part):
		_initialize_body_part(part)

	if is_blacked_out.get(part, false):
		# Blacked out parts spread damage to adjacent parts
		return _spread_damage(part, amount)

	var old_health = current_health.get(part, 0.0)
	current_health[part] = max(0.0, old_health - amount)
	var damage_dealt = old_health - current_health[part]

	body_part_damaged.emit(PART_NAMES[part], current_health[part], max_health.get(part, 1.0))

	# Check for blackout
	if current_health[part] <= 0 and not is_blacked_out.get(part, false):
		_blackout_part(part)

	return damage_dealt

func take_damage_random(amount: float) -> float:
	"""Apply damage to a random body part (weighted by size)"""
	var part = _get_random_hit_part()
	return take_damage_to_part(part, amount)

func take_damage_at_position(amount: float, hit_position: Vector3, player_position: Vector3) -> float:
	"""Determine hit body part based on hit position relative to player"""
	var local_hit = hit_position - player_position
	var part = _get_part_from_position(local_hit)
	return take_damage_to_part(part, amount)

func _get_part_from_position(local_hit: Vector3) -> int:
	"""Determine which body part was hit based on local position"""
	var height = local_hit.y
	var side = local_hit.x  # Positive = right side, negative = left side

	# Head (above 1.5m)
	if height > 1.5:
		return BodyPart.HEAD

	# Upper body (0.9m - 1.5m)
	if height > 0.9:
		if abs(side) > 0.3:
			# Arms
			if side > 0:
				return BodyPart.RIGHT_ARM
			else:
				return BodyPart.LEFT_ARM
		else:
			# Chest
			return BodyPart.CHEST

	# Middle body (0.5m - 0.9m)
	if height > 0.5:
		if abs(side) > 0.3:
			# Hands
			if side > 0:
				return BodyPart.RIGHT_HAND
			else:
				return BodyPart.LEFT_HAND
		else:
			# Thorax
			return BodyPart.THORAX

	# Lower body (0.2m - 0.5m)
	if height > 0.2:
		if side > 0:
			return BodyPart.RIGHT_LEG
		else:
			return BodyPart.LEFT_LEG

	# Feet (below 0.2m)
	if side > 0:
		return BodyPart.RIGHT_FOOT
	else:
		return BodyPart.LEFT_FOOT

func _get_random_hit_part() -> int:
	"""Get a random body part weighted by hitbox size"""
	var weights = {
		BodyPart.HEAD: 5,
		BodyPart.CHEST: 25,
		BodyPart.THORAX: 20,
		BodyPart.LEFT_ARM: 10,
		BodyPart.RIGHT_ARM: 10,
		BodyPart.LEFT_HAND: 3,
		BodyPart.RIGHT_HAND: 3,
		BodyPart.LEFT_LEG: 10,
		BodyPart.RIGHT_LEG: 10,
		BodyPart.LEFT_FOOT: 2,
		BodyPart.RIGHT_FOOT: 2
	}

	var total_weight = 0
	for part in weights:
		total_weight += weights[part]

	var roll = randi() % total_weight
	var cumulative = 0

	for part in weights:
		cumulative += weights[part]
		if roll < cumulative:
			return part

	return BodyPart.CHEST  # Fallback

func _spread_damage(original_part: int, amount: float) -> float:
	"""Spread damage from a blacked out part to adjacent parts"""
	var adjacent_parts = _get_adjacent_parts(original_part)
	var damage_per_part = amount / max(adjacent_parts.size(), 1)
	var total_damage = 0.0

	for part in adjacent_parts:
		if not is_blacked_out[part]:
			total_damage += take_damage_to_part(part, damage_per_part)

	return total_damage

func _get_adjacent_parts(part: int) -> Array:
	"""Get adjacent body parts for damage spreading"""
	match part:
		BodyPart.HEAD:
			return [BodyPart.CHEST]
		BodyPart.CHEST:
			return [BodyPart.HEAD, BodyPart.THORAX, BodyPart.LEFT_ARM, BodyPart.RIGHT_ARM]
		BodyPart.THORAX:
			return [BodyPart.CHEST, BodyPart.LEFT_LEG, BodyPart.RIGHT_LEG]
		BodyPart.LEFT_ARM:
			return [BodyPart.CHEST, BodyPart.LEFT_HAND]
		BodyPart.RIGHT_ARM:
			return [BodyPart.CHEST, BodyPart.RIGHT_HAND]
		BodyPart.LEFT_HAND:
			return [BodyPart.LEFT_ARM]
		BodyPart.RIGHT_HAND:
			return [BodyPart.RIGHT_ARM]
		BodyPart.LEFT_LEG:
			return [BodyPart.THORAX, BodyPart.LEFT_FOOT]
		BodyPart.RIGHT_LEG:
			return [BodyPart.THORAX, BodyPart.RIGHT_FOOT]
		BodyPart.LEFT_FOOT:
			return [BodyPart.LEFT_LEG]
		BodyPart.RIGHT_FOOT:
			return [BodyPart.RIGHT_LEG]
	return []

func _blackout_part(part: int):
	"""Handle a body part being blacked out (0 HP)"""
	is_blacked_out[part] = true
	is_bleeding[part] = true

	body_part_blacked_out.emit(PART_NAMES[part])
	bleeding_started.emit(PART_NAMES[part])

	# Add bleeding effect to active effects
	add_effect("Bleeding (%s)" % PART_NAMES[part], -1.0, "debuff")  # -1 = until healed

	# Apply movement/combat penalties based on blacked out part
	_apply_blackout_penalties(part)

func _apply_blackout_penalties(part: int):
	"""Apply penalties for blacked out body parts"""
	if not player:
		return

	match part:
		BodyPart.HEAD:
			# Vision/accuracy penalties
			if player.has_node("PlayerConditions"):
				player.get_node("PlayerConditions").apply_condition("blurred_vision", -1.0)
		BodyPart.CHEST, BodyPart.THORAX:
			# Stamina drain penalty
			if player.has_node("PlayerConditions"):
				player.get_node("PlayerConditions").apply_condition("exhaustion", -1.0)
		BodyPart.LEFT_LEG, BodyPart.RIGHT_LEG, BodyPart.LEFT_FOOT, BodyPart.RIGHT_FOOT:
			# Movement speed penalty
			if player.has_node("PlayerConditions"):
				player.get_node("PlayerConditions").apply_condition("limping", -1.0)
		BodyPart.LEFT_ARM, BodyPart.RIGHT_ARM, BodyPart.LEFT_HAND, BodyPart.RIGHT_HAND:
			# Weapon handling penalty
			if player.has_node("PlayerConditions"):
				player.get_node("PlayerConditions").apply_condition("weakened", -1.0)

# ============================================
# HEALING SYSTEM
# ============================================

func can_heal_part(part: int) -> bool:
	"""Check if a body part can be healed"""
	if part < 0 or part >= BodyPart.size():
		return false

	# Can heal if damaged or blacked out
	return current_health[part] < max_health[part]

func start_healing(part: int) -> bool:
	"""Start healing a specific body part. Returns true if healing started."""
	if not can_heal_part(part):
		return false

	if is_healing:
		cancel_healing()

	is_healing = true
	healing_part = part
	healing_timer = 0.0

	# Blacked out parts take longer to heal
	if is_blacked_out[part]:
		healing_duration = 5.0
	else:
		healing_duration = 3.0

	healing_started.emit(PART_NAMES[part])
	return true

func cancel_healing():
	"""Cancel current healing"""
	if is_healing and healing_part >= 0:
		healing_cancelled.emit(PART_NAMES[healing_part])

	is_healing = false
	healing_part = -1
	healing_timer = 0.0

func _complete_healing():
	"""Complete the healing process"""
	if healing_part < 0:
		return

	var part = healing_part
	var was_blacked_out = is_blacked_out[part]

	# Heal the part
	if was_blacked_out:
		# Restore from blackout to 1 HP
		is_blacked_out[part] = false
		is_bleeding[part] = false
		current_health[part] = 1.0

		body_part_restored.emit(PART_NAMES[part])
		bleeding_stopped.emit(PART_NAMES[part])

		# Remove bleeding effect
		remove_effect("Bleeding (%s)" % PART_NAMES[part])

		# Remove penalties
		_remove_blackout_penalties(part)
	else:
		# Full heal the part
		current_health[part] = max_health[part]

	body_part_healed.emit(PART_NAMES[part], current_health[part], max_health[part])
	healing_completed.emit(PART_NAMES[part])

	is_healing = false
	healing_part = -1
	healing_timer = 0.0

func _remove_blackout_penalties(part: int):
	"""Remove penalties when a blacked out part is healed"""
	if not player or not player.has_node("PlayerConditions"):
		return

	var conditions = player.get_node("PlayerConditions")

	match part:
		BodyPart.HEAD:
			conditions.remove_condition("blurred_vision")
		BodyPart.CHEST, BodyPart.THORAX:
			# Only remove if neither chest nor thorax is blacked out
			if not is_blacked_out[BodyPart.CHEST] and not is_blacked_out[BodyPart.THORAX]:
				conditions.remove_condition("exhaustion")
		BodyPart.LEFT_LEG, BodyPart.RIGHT_LEG, BodyPart.LEFT_FOOT, BodyPart.RIGHT_FOOT:
			# Only remove if no leg/foot is blacked out
			var any_leg_blacked = is_blacked_out[BodyPart.LEFT_LEG] or is_blacked_out[BodyPart.RIGHT_LEG] or \
								  is_blacked_out[BodyPart.LEFT_FOOT] or is_blacked_out[BodyPart.RIGHT_FOOT]
			if not any_leg_blacked:
				conditions.remove_condition("limping")
		BodyPart.LEFT_ARM, BodyPart.RIGHT_ARM, BodyPart.LEFT_HAND, BodyPart.RIGHT_HAND:
			# Only remove if no arm/hand is blacked out
			var any_arm_blacked = is_blacked_out[BodyPart.LEFT_ARM] or is_blacked_out[BodyPart.RIGHT_ARM] or \
								  is_blacked_out[BodyPart.LEFT_HAND] or is_blacked_out[BodyPart.RIGHT_HAND]
			if not any_arm_blacked:
				conditions.remove_condition("weakened")

func heal_part_instant(part: int, amount: float):
	"""Instantly heal a body part by a specific amount"""
	if part < 0 or part >= BodyPart.size():
		return

	# Can't instant heal blacked out parts - need to use start_healing()
	if is_blacked_out[part]:
		return

	var old_health = current_health[part]
	current_health[part] = min(current_health[part] + amount, max_health[part])

	if current_health[part] > old_health:
		body_part_healed.emit(PART_NAMES[part], current_health[part], max_health[part])

func heal_all_parts(amount: float):
	"""Heal all non-blacked-out parts by an amount"""
	for part in BodyPart.values():
		if not is_blacked_out[part]:
			heal_part_instant(part, amount)

func full_heal():
	"""Fully heal all body parts and remove all bleeds"""
	for part in BodyPart.values():
		is_blacked_out[part] = false
		is_bleeding[part] = false
		current_health[part] = max_health[part]
		body_part_healed.emit(PART_NAMES[part], current_health[part], max_health[part])

	# Clear all bleeding effects
	for effect_name in active_effects.keys():
		if effect_name.begins_with("Bleeding"):
			remove_effect(effect_name)

	# Remove all blackout penalties
	if player and player.has_node("PlayerConditions"):
		var conditions = player.get_node("PlayerConditions")
		conditions.remove_condition("blurred_vision")
		conditions.remove_condition("exhaustion")
		conditions.remove_condition("limping")
		conditions.remove_condition("weakened")

# ============================================
# STATUS EFFECTS
# ============================================

func add_effect(effect_name: String, duration: float, effect_type: String = "neutral"):
	"""Add a status effect for UI display"""
	active_effects[effect_name] = {
		"duration": duration,
		"max_duration": duration,
		"type": effect_type  # "buff", "debuff", or "neutral"
	}
	status_effect_applied.emit(effect_name, duration)

func remove_effect(effect_name: String):
	"""Remove a status effect"""
	if active_effects.has(effect_name):
		active_effects.erase(effect_name)
		status_effect_removed.emit(effect_name)

func get_active_effects() -> Dictionary:
	"""Get all active effects for UI display"""
	return active_effects.duplicate()

# ============================================
# QUERIES
# ============================================

func get_part_health(part: int) -> float:
	return current_health.get(part, 0.0)

func get_part_max_health(part: int) -> float:
	return max_health.get(part, 0.0)

func get_part_health_percent(part: int) -> float:
	var max_hp = max_health.get(part, 1.0)
	if max_hp <= 0:
		return 0.0
	return current_health.get(part, 0.0) / max_hp

func is_part_blacked_out(part: int) -> bool:
	return is_blacked_out.get(part, false)

func is_part_bleeding(part: int) -> bool:
	return is_bleeding.get(part, false)

func get_total_health() -> float:
	"""Get sum of all body part health"""
	var total = 0.0
	for part in BodyPart.values():
		total += current_health[part]
	return total

func get_total_max_health() -> float:
	"""Get sum of all body part max health"""
	var total = 0.0
	for part in BodyPart.values():
		total += max_health[part]
	return total

func get_overall_condition() -> float:
	"""Get overall health as a percentage (0.0 - 1.0)"""
	var total_max = get_total_max_health()
	if total_max <= 0:
		return 0.0
	return get_total_health() / total_max

func get_blacked_out_count() -> int:
	"""Get number of blacked out body parts"""
	var count = 0
	for part in BodyPart.values():
		if is_blacked_out[part]:
			count += 1
	return count

func is_critical() -> bool:
	"""Check if player is in critical condition (multiple blacked out parts)"""
	return get_blacked_out_count() >= 3

func is_dead() -> bool:
	"""Check if player should be dead (head or both vital parts blacked out)"""
	if is_blacked_out[BodyPart.HEAD]:
		return true
	if is_blacked_out[BodyPart.CHEST] and is_blacked_out[BodyPart.THORAX]:
		return true
	return false

# ============================================
# SAVE/LOAD
# ============================================

func get_save_data() -> Dictionary:
	var data = {
		"player_level": player_level,
		"current_health": {},
		"max_health": {},
		"is_blacked_out": {},
		"is_bleeding": {}
	}

	for part in BodyPart.values():
		data.current_health[part] = current_health[part]
		data.max_health[part] = max_health[part]
		data.is_blacked_out[part] = is_blacked_out[part]
		data.is_bleeding[part] = is_bleeding[part]

	return data

func load_save_data(data: Dictionary):
	player_level = data.get("player_level", 1)

	var saved_health = data.get("current_health", {})
	var saved_max = data.get("max_health", {})
	var saved_blacked = data.get("is_blacked_out", {})
	var saved_bleeding = data.get("is_bleeding", {})

	for part in BodyPart.values():
		max_health[part] = saved_max.get(part, _calculate_max_health(part))
		current_health[part] = saved_health.get(part, max_health[part])
		is_blacked_out[part] = saved_blacked.get(part, false)
		is_bleeding[part] = saved_bleeding.get(part, false)

		# Re-apply bleeding effects
		if is_bleeding[part]:
			add_effect("Bleeding (%s)" % PART_NAMES[part], -1.0, "debuff")
