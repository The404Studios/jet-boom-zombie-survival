extends Node
class_name PlayerConditions

# Player Condition/Status Effect System
# Handles buffs, debuffs, and status effects on the player

signal condition_applied(condition_id: String, duration: float)
signal condition_removed(condition_id: String)
signal condition_stacked(condition_id: String, stacks: int)
signal condition_tick(condition_id: String, damage: float)

# Condition Types
enum ConditionType {
	BUFF,       # Positive effect
	DEBUFF,     # Negative effect
	DOT,        # Damage over time
	HOT,        # Heal over time
	CONTROL     # Movement/action impairment
}

# Active conditions: condition_id -> ConditionData
var active_conditions: Dictionary = {}

# Immunity timers (prevent spam of same effect)
var immunity_timers: Dictionary = {}

# Reference to player
var player: Node = null

# Condition definitions
var condition_data: Dictionary = {}

func _ready():
	player = get_parent()
	_initialize_conditions()

func _process(delta):
	_update_conditions(delta)
	_update_immunity_timers(delta)

func _initialize_conditions():
	"""Define all possible conditions"""
	condition_data = {
		# ===== DEBUFFS (Negative) =====
		"poison": {
			"name": "Poison",
			"type": ConditionType.DOT,
			"description": "Taking poison damage over time",
			"damage_per_second": 5.0,
			"max_stacks": 5,
			"default_duration": 10.0,
			"icon": "poison",
			"color": Color(0.2, 0.8, 0.2),
			"immunity_after": 2.0
		},
		"bleed": {
			"name": "Bleeding",
			"type": ConditionType.DOT,
			"description": "Losing blood, taking damage over time",
			"damage_per_second": 8.0,
			"max_stacks": 3,
			"default_duration": 8.0,
			"icon": "bleed",
			"color": Color(0.8, 0.1, 0.1),
			"immunity_after": 1.0
		},
		"burn": {
			"name": "Burning",
			"type": ConditionType.DOT,
			"description": "On fire! Taking burn damage",
			"damage_per_second": 10.0,
			"max_stacks": 1,
			"default_duration": 5.0,
			"icon": "burn",
			"color": Color(1.0, 0.5, 0.0),
			"immunity_after": 3.0
		},
		"freeze": {
			"name": "Frozen",
			"type": ConditionType.CONTROL,
			"description": "Movement slowed by cold",
			"movement_slow": 0.5,  # 50% slow
			"max_stacks": 1,
			"default_duration": 4.0,
			"icon": "freeze",
			"color": Color(0.3, 0.6, 1.0),
			"immunity_after": 5.0
		},
		"slow": {
			"name": "Slowed",
			"type": ConditionType.DEBUFF,
			"description": "Movement speed reduced",
			"movement_slow": 0.3,
			"max_stacks": 1,
			"default_duration": 5.0,
			"icon": "slow",
			"color": Color(0.5, 0.5, 0.5),
			"immunity_after": 0.0
		},
		"weakness": {
			"name": "Weakened",
			"type": ConditionType.DEBUFF,
			"description": "Damage dealt reduced",
			"damage_reduction": 0.25,  # Deal 25% less damage
			"max_stacks": 3,
			"default_duration": 10.0,
			"icon": "weakness",
			"color": Color(0.6, 0.4, 0.6),
			"immunity_after": 0.0
		},
		"vulnerable": {
			"name": "Vulnerable",
			"type": ConditionType.DEBUFF,
			"description": "Taking increased damage",
			"damage_taken_increase": 0.2,  # Take 20% more damage per stack
			"max_stacks": 5,
			"default_duration": 8.0,
			"icon": "vulnerable",
			"color": Color(0.9, 0.3, 0.3),
			"immunity_after": 0.0
		},
		"infected": {
			"name": "Infected",
			"type": ConditionType.DOT,
			"description": "Zombie infection spreading",
			"damage_per_second": 2.0,
			"max_stacks": 10,
			"default_duration": 30.0,
			"icon": "infected",
			"color": Color(0.4, 0.6, 0.2),
			"immunity_after": 0.0
		},

		# ===== BUFFS (Positive) =====
		"regeneration": {
			"name": "Regeneration",
			"type": ConditionType.HOT,
			"description": "Healing over time",
			"heal_per_second": 5.0,
			"max_stacks": 3,
			"default_duration": 10.0,
			"icon": "regen",
			"color": Color(0.2, 1.0, 0.4),
			"immunity_after": 0.0
		},
		"speed_boost": {
			"name": "Speed Boost",
			"type": ConditionType.BUFF,
			"description": "Movement speed increased",
			"movement_boost": 0.3,  # 30% faster
			"max_stacks": 1,
			"default_duration": 10.0,
			"icon": "speed",
			"color": Color(0.3, 0.8, 1.0),
			"immunity_after": 0.0
		},
		"damage_boost": {
			"name": "Damage Boost",
			"type": ConditionType.BUFF,
			"description": "Dealing increased damage",
			"damage_bonus": 0.25,  # +25% damage per stack
			"max_stacks": 3,
			"default_duration": 15.0,
			"icon": "damage",
			"color": Color(1.0, 0.3, 0.1),
			"immunity_after": 0.0
		},
		"defense_boost": {
			"name": "Fortified",
			"type": ConditionType.BUFF,
			"description": "Taking reduced damage",
			"damage_reduction": 0.2,  # -20% damage taken per stack
			"max_stacks": 3,
			"default_duration": 15.0,
			"icon": "defense",
			"color": Color(0.4, 0.4, 0.8),
			"immunity_after": 0.0
		},
		"berserk": {
			"name": "Berserk",
			"type": ConditionType.BUFF,
			"description": "Attack speed and damage increased, but taking more damage",
			"damage_bonus": 0.5,
			"attack_speed_bonus": 0.3,
			"damage_taken_increase": 0.25,
			"max_stacks": 1,
			"default_duration": 10.0,
			"icon": "berserk",
			"color": Color(1.0, 0.2, 0.2),
			"immunity_after": 0.0
		},
		"invulnerable": {
			"name": "Invulnerable",
			"type": ConditionType.BUFF,
			"description": "Cannot take damage",
			"immune_to_damage": true,
			"max_stacks": 1,
			"default_duration": 3.0,
			"icon": "invuln",
			"color": Color(1.0, 0.9, 0.3),
			"immunity_after": 30.0
		},
		"adrenaline": {
			"name": "Adrenaline",
			"type": ConditionType.BUFF,
			"description": "All stats temporarily boosted",
			"damage_bonus": 0.15,
			"attack_speed_bonus": 0.15,
			"movement_boost": 0.15,
			"damage_reduction": 0.1,
			"max_stacks": 1,
			"default_duration": 8.0,
			"icon": "adrenaline",
			"color": Color(1.0, 0.5, 0.8),
			"immunity_after": 0.0
		}
	}

# ============================================
# CONDITION APPLICATION
# ============================================

func apply_condition(condition_id: String, duration: float = -1.0, stacks: int = 1) -> bool:
	"""Apply a condition to the player"""
	if not condition_data.has(condition_id):
		push_warning("Unknown condition: %s" % condition_id)
		return false

	var data = condition_data[condition_id]

	# Check immunity
	if immunity_timers.has(condition_id) and immunity_timers[condition_id] > 0:
		return false

	# Check resistance
	var resistance = _get_resistance_for_condition(condition_id)
	if resistance >= 1.0:
		return false  # Full immunity from resistance

	# Reduce duration by resistance
	var final_duration = (duration if duration > 0 else data.default_duration) * (1.0 - resistance)

	if active_conditions.has(condition_id):
		# Stack or refresh existing condition
		var existing = active_conditions[condition_id]
		var new_stacks = min(existing.stacks + stacks, data.max_stacks)

		if new_stacks > existing.stacks:
			existing.stacks = new_stacks
			condition_stacked.emit(condition_id, new_stacks)

		# Refresh duration
		existing.remaining_time = max(existing.remaining_time, final_duration)
	else:
		# Apply new condition
		active_conditions[condition_id] = {
			"data": data,
			"stacks": min(stacks, data.max_stacks),
			"remaining_time": final_duration,
			"tick_timer": 0.0
		}
		condition_applied.emit(condition_id, final_duration)

	# Apply immediate effects
	_apply_condition_effects(condition_id)

	return true

func remove_condition(condition_id: String):
	"""Remove a condition from the player"""
	if not active_conditions.has(condition_id):
		return

	var data = condition_data[condition_id]

	# Set immunity timer
	if data.immunity_after > 0:
		immunity_timers[condition_id] = data.immunity_after

	# Remove effects
	_remove_condition_effects(condition_id)

	active_conditions.erase(condition_id)
	condition_removed.emit(condition_id)

func has_condition(condition_id: String) -> bool:
	"""Check if player has a condition"""
	return active_conditions.has(condition_id)

func get_condition_stacks(condition_id: String) -> int:
	"""Get number of stacks of a condition"""
	if active_conditions.has(condition_id):
		return active_conditions[condition_id].stacks
	return 0

func get_condition_time_remaining(condition_id: String) -> float:
	"""Get remaining time of a condition"""
	if active_conditions.has(condition_id):
		return active_conditions[condition_id].remaining_time
	return 0.0

func clear_all_conditions():
	"""Remove all conditions"""
	for condition_id in active_conditions.keys():
		remove_condition(condition_id)

func clear_debuffs():
	"""Remove all negative conditions"""
	for condition_id in active_conditions.keys():
		var data = condition_data[condition_id]
		if data.type in [ConditionType.DEBUFF, ConditionType.DOT, ConditionType.CONTROL]:
			remove_condition(condition_id)

# ============================================
# CONDITION UPDATES
# ============================================

func _update_conditions(delta: float):
	"""Update all active conditions"""
	var to_remove = []

	for condition_id in active_conditions:
		var condition = active_conditions[condition_id]
		var data = condition.data

		# Update duration
		condition.remaining_time -= delta

		if condition.remaining_time <= 0:
			to_remove.append(condition_id)
			continue

		# Process DOT/HOT
		if data.type == ConditionType.DOT:
			condition.tick_timer += delta
			if condition.tick_timer >= 1.0:
				condition.tick_timer -= 1.0
				var damage = data.damage_per_second * condition.stacks
				_deal_condition_damage(condition_id, damage)

		elif data.type == ConditionType.HOT:
			condition.tick_timer += delta
			if condition.tick_timer >= 1.0:
				condition.tick_timer -= 1.0
				var heal = data.heal_per_second * condition.stacks
				_apply_condition_heal(heal)

	# Remove expired conditions
	for condition_id in to_remove:
		remove_condition(condition_id)

func _update_immunity_timers(delta: float):
	"""Update immunity timers"""
	var to_remove = []

	for condition_id in immunity_timers:
		immunity_timers[condition_id] -= delta
		if immunity_timers[condition_id] <= 0:
			to_remove.append(condition_id)

	for condition_id in to_remove:
		immunity_timers.erase(condition_id)

func _deal_condition_damage(condition_id: String, damage: float):
	"""Deal DOT damage to player"""
	if not player:
		return

	# Check invulnerability
	if has_condition("invulnerable"):
		return

	if player.has_method("take_damage"):
		player.take_damage(damage)

	condition_tick.emit(condition_id, damage)

func _apply_condition_heal(amount: float):
	"""Apply HOT healing to player"""
	if not player:
		return

	if player.has_method("heal"):
		player.heal(amount)

# ============================================
# EFFECT APPLICATION
# ============================================

func _apply_condition_effects(_condition_id: String):
	"""Apply immediate effects of a condition"""
	# Effects are generally queried through get_* methods
	# This could trigger visual effects, sounds, etc.
	pass

func _remove_condition_effects(_condition_id: String):
	"""Remove effects when condition ends"""
	pass

func _get_resistance_for_condition(condition_id: String) -> float:
	"""Get player's resistance to a condition type"""
	if not player:
		return 0.0

	# Check for resistance stats
	var resistance = 0.0

	match condition_id:
		"poison", "infected":
			if player.has_node("CharacterAttributes"):
				var attrs = player.get_node("CharacterAttributes")
				resistance = attrs.get_derived_stats().get("poison_resist", 0.0) / 100.0
			if player.has_node("SkillTree"):
				var skills = player.get_node("SkillTree")
				resistance += skills.get_effect_value("poison_resist") / 100.0
		"bleed":
			if player.has_node("EquipmentSystem"):
				var equip = player.get_node("EquipmentSystem")
				resistance = equip.get_total_bonuses().get("bleed_resist", 0.0) / 100.0
		"burn":
			if player.has_node("EquipmentSystem"):
				var equip = player.get_node("EquipmentSystem")
				resistance = equip.get_total_bonuses().get("fire_resist", 0.0) / 100.0
		"freeze":
			if player.has_node("EquipmentSystem"):
				var equip = player.get_node("EquipmentSystem")
				resistance = equip.get_total_bonuses().get("ice_resist", 0.0) / 100.0

	return clamp(resistance, 0.0, 1.0)

# ============================================
# STAT MODIFIERS
# ============================================

func get_movement_speed_modifier() -> float:
	"""Get total movement speed modifier from conditions"""
	var modifier = 1.0

	for condition_id in active_conditions:
		var data = condition_data[condition_id]
		var stacks = active_conditions[condition_id].stacks

		if "movement_slow" in data:
			modifier -= data.movement_slow * stacks
		if "movement_boost" in data:
			modifier += data.movement_boost * stacks

	return max(modifier, 0.1)  # Minimum 10% speed

func get_damage_dealt_modifier() -> float:
	"""Get total damage dealt modifier from conditions"""
	var modifier = 1.0

	for condition_id in active_conditions:
		var data = condition_data[condition_id]
		var stacks = active_conditions[condition_id].stacks

		if "damage_reduction" in data and data.type == ConditionType.DEBUFF:
			modifier -= data.damage_reduction * stacks
		if "damage_bonus" in data:
			modifier += data.damage_bonus * stacks

	return max(modifier, 0.1)

func get_damage_taken_modifier() -> float:
	"""Get total damage taken modifier from conditions"""
	var modifier = 1.0

	# Check invulnerability first
	if has_condition("invulnerable"):
		return 0.0

	for condition_id in active_conditions:
		var data = condition_data[condition_id]
		var stacks = active_conditions[condition_id].stacks

		if "damage_taken_increase" in data:
			modifier += data.damage_taken_increase * stacks
		if "damage_reduction" in data and data.type == ConditionType.BUFF:
			modifier -= data.damage_reduction * stacks

	return max(modifier, 0.0)

func get_attack_speed_modifier() -> float:
	"""Get total attack speed modifier from conditions"""
	var modifier = 1.0

	for condition_id in active_conditions:
		var data = condition_data[condition_id]
		var stacks = active_conditions[condition_id].stacks

		if "attack_speed_bonus" in data:
			modifier += data.attack_speed_bonus * stacks

	return max(modifier, 0.1)

# ============================================
# UI HELPERS
# ============================================

func get_active_conditions_display() -> Array:
	"""Get list of active conditions for UI display"""
	var display = []

	for condition_id in active_conditions:
		var condition = active_conditions[condition_id]
		var data = condition.data

		display.append({
			"id": condition_id,
			"name": data.name,
			"description": data.description,
			"stacks": condition.stacks,
			"max_stacks": data.max_stacks,
			"time_remaining": condition.remaining_time,
			"icon": data.icon,
			"color": data.color,
			"is_buff": data.type in [ConditionType.BUFF, ConditionType.HOT]
		})

	return display

func get_buffs() -> Array:
	"""Get only positive conditions"""
	var buffs = []
	for cond in get_active_conditions_display():
		if cond.is_buff:
			buffs.append(cond)
	return buffs

func get_debuffs() -> Array:
	"""Get only negative conditions"""
	var debuffs = []
	for cond in get_active_conditions_display():
		if not cond.is_buff:
			debuffs.append(cond)
	return debuffs
