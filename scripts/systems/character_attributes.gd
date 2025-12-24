extends Node
class_name CharacterAttributes

# RPG Attributes System
# Defines core player stats that affect combat, exploration, and survival

signal attribute_changed(attribute_name: String, old_value: int, new_value: int)
signal level_up(new_level: int, available_points: int)
signal experience_gained(amount: int, total: int)

# Core Attributes
@export var strength: int = 10:
	set(value):
		var old = strength
		strength = clamp(value, 1, max_attribute)
		attribute_changed.emit("strength", old, strength)
		_recalculate_derived_stats()

@export var agility: int = 10:
	set(value):
		var old = agility
		agility = clamp(value, 1, max_attribute)
		attribute_changed.emit("agility", old, agility)
		_recalculate_derived_stats()

@export var vitality: int = 10:
	set(value):
		var old = vitality
		vitality = clamp(value, 1, max_attribute)
		attribute_changed.emit("vitality", old, vitality)
		_recalculate_derived_stats()

@export var intelligence: int = 10:
	set(value):
		var old = intelligence
		intelligence = clamp(value, 1, max_attribute)
		attribute_changed.emit("intelligence", old, intelligence)
		_recalculate_derived_stats()

@export var luck: int = 10:
	set(value):
		var old = luck
		luck = clamp(value, 1, max_attribute)
		attribute_changed.emit("luck", old, luck)
		_recalculate_derived_stats()

@export var endurance: int = 10:
	set(value):
		var old = endurance
		endurance = clamp(value, 1, max_attribute)
		attribute_changed.emit("endurance", old, endurance)
		_recalculate_derived_stats()

# Level & Experience
var level: int = 1
var experience: int = 0
var experience_to_next_level: int = 100
var available_attribute_points: int = 0
var max_attribute: int = 100

# Derived Stats (calculated from attributes)
var max_health: float = 100.0
var max_stamina: float = 100.0
var max_mana: float = 50.0
var melee_damage_bonus: float = 0.0
var ranged_damage_bonus: float = 0.0
var armor_value: float = 0.0
var dodge_chance: float = 0.0
var critical_chance: float = 0.05
var critical_damage: float = 1.5
var movement_speed_bonus: float = 0.0
var attack_speed_bonus: float = 0.0
var cooldown_reduction: float = 0.0
var health_regen: float = 0.0
var stamina_regen: float = 0.0
var loot_bonus: float = 0.0
var experience_bonus: float = 0.0

# Equipment bonuses (added by EquipmentSystem)
var equipment_bonuses: Dictionary = {}

func _ready():
	_recalculate_derived_stats()

func _recalculate_derived_stats():
	"""Recalculate all derived stats from base attributes and equipment"""
	# Base stats from Vitality
	max_health = 50.0 + (vitality * 10.0)
	health_regen = vitality * 0.1  # 0.1 HP/sec per VIT

	# Stamina from Endurance
	max_stamina = 50.0 + (endurance * 5.0)
	stamina_regen = endurance * 0.5  # 0.5 stamina/sec per END

	# Mana from Intelligence
	max_mana = 20.0 + (intelligence * 3.0)
	cooldown_reduction = min(intelligence * 0.5, 50.0)  # Max 50% CDR

	# Damage from Strength
	melee_damage_bonus = strength * 2.0  # +2 damage per STR

	# Speed & Dodge from Agility
	movement_speed_bonus = agility * 0.5  # +0.5% speed per AGI
	dodge_chance = min(agility * 0.5, 30.0)  # Max 30% dodge
	attack_speed_bonus = agility * 0.3  # +0.3% attack speed per AGI
	ranged_damage_bonus = agility * 1.0  # +1 ranged damage per AGI

	# Crit & Loot from Luck
	critical_chance = 0.05 + (luck * 0.005)  # 5% base + 0.5% per LCK
	critical_damage = 1.5 + (luck * 0.02)  # 150% base + 2% per LCK
	loot_bonus = luck * 1.0  # +1% loot per LCK
	experience_bonus = luck * 0.5  # +0.5% XP per LCK

	# Apply equipment bonuses
	_apply_equipment_bonuses()

func _apply_equipment_bonuses():
	"""Apply stat bonuses from equipment"""
	max_health += equipment_bonuses.get("health", 0.0)
	max_stamina += equipment_bonuses.get("stamina", 0.0)
	max_mana += equipment_bonuses.get("mana", 0.0)
	armor_value += equipment_bonuses.get("armor", 0.0)
	melee_damage_bonus += equipment_bonuses.get("melee_damage", 0.0)
	ranged_damage_bonus += equipment_bonuses.get("ranged_damage", 0.0)
	critical_chance += equipment_bonuses.get("crit_chance", 0.0)
	critical_damage += equipment_bonuses.get("crit_damage", 0.0)
	movement_speed_bonus += equipment_bonuses.get("movement_speed", 0.0)

func set_equipment_bonuses(bonuses: Dictionary):
	"""Set equipment stat bonuses and recalculate"""
	equipment_bonuses = bonuses
	_recalculate_derived_stats()

# ============================================
# EXPERIENCE & LEVELING
# ============================================

func add_experience(amount: int):
	"""Add experience points"""
	var bonus_amount = int(amount * (1.0 + experience_bonus / 100.0))
	experience += bonus_amount
	experience_gained.emit(bonus_amount, experience)

	# Check for level up
	while experience >= experience_to_next_level:
		_level_up()

func _level_up():
	"""Handle level up"""
	experience -= experience_to_next_level
	level += 1

	# Calculate next level XP requirement (exponential curve)
	experience_to_next_level = int(100 * pow(level, 1.5))

	# Award attribute points
	available_attribute_points += 3

	level_up.emit(level, available_attribute_points)

	# Notify via chat if available
	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message(
			"Level Up! You are now level %d. You have %d attribute points to spend." %
			[level, available_attribute_points]
		)

func spend_attribute_point(attribute_name: String) -> bool:
	"""Spend an attribute point on a specific attribute"""
	if available_attribute_points <= 0:
		return false

	match attribute_name.to_lower():
		"strength", "str":
			strength += 1
		"agility", "agi":
			agility += 1
		"vitality", "vit":
			vitality += 1
		"intelligence", "int":
			intelligence += 1
		"endurance", "end":
			endurance += 1
		"luck", "lck":
			luck += 1
		_:
			return false

	available_attribute_points -= 1
	return true

# ============================================
# ATTRIBUTE QUERIES
# ============================================

func get_attribute(attr_name: String) -> int:
	"""Get attribute value by name"""
	match attr_name.to_lower():
		"strength", "str":
			return strength
		"agility", "agi":
			return agility
		"vitality", "vit":
			return vitality
		"intelligence", "int":
			return intelligence
		"endurance", "end":
			return endurance
		"luck", "lck":
			return luck
	return 0

func get_all_attributes() -> Dictionary:
	"""Get all attributes as dictionary"""
	return {
		"strength": strength,
		"agility": agility,
		"vitality": vitality,
		"intelligence": intelligence,
		"endurance": endurance,
		"luck": luck
	}

func get_derived_stats() -> Dictionary:
	"""Get all derived stats"""
	return {
		"max_health": max_health,
		"max_stamina": max_stamina,
		"max_mana": max_mana,
		"armor": armor_value,
		"melee_damage": melee_damage_bonus,
		"ranged_damage": ranged_damage_bonus,
		"dodge_chance": dodge_chance,
		"crit_chance": critical_chance,
		"crit_damage": critical_damage,
		"movement_speed": movement_speed_bonus,
		"attack_speed": attack_speed_bonus,
		"cooldown_reduction": cooldown_reduction,
		"health_regen": health_regen,
		"stamina_regen": stamina_regen,
		"loot_bonus": loot_bonus,
		"experience_bonus": experience_bonus
	}

# ============================================
# DAMAGE CALCULATION HELPERS
# ============================================

func calculate_melee_damage(base_damage: float) -> float:
	"""Calculate final melee damage with bonuses"""
	var damage = base_damage + melee_damage_bonus

	# Check for critical hit
	if randf() < critical_chance:
		damage *= critical_damage

	return damage

func calculate_ranged_damage(base_damage: float) -> float:
	"""Calculate final ranged damage with bonuses"""
	var damage = base_damage + ranged_damage_bonus

	# Check for critical hit
	if randf() < critical_chance:
		damage *= critical_damage

	return damage

func calculate_incoming_damage(base_damage: float) -> float:
	"""Calculate damage after armor reduction"""
	# Check dodge
	if randf() < dodge_chance / 100.0:
		return 0.0  # Dodged!

	# Armor formula: damage_reduction = armor / (armor + 100)
	# Guard against division by zero (when armor is exactly -100)
	var armor_divisor = armor_value + 100.0
	if armor_divisor <= 0.0:
		return base_damage  # No reduction possible
	var damage_reduction = armor_value / armor_divisor
	return base_damage * (1.0 - damage_reduction)

# ============================================
# SAVE/LOAD
# ============================================

func get_save_data() -> Dictionary:
	return {
		"strength": strength,
		"agility": agility,
		"vitality": vitality,
		"intelligence": intelligence,
		"endurance": endurance,
		"luck": luck,
		"level": level,
		"experience": experience,
		"available_points": available_attribute_points
	}

func load_save_data(data: Dictionary):
	strength = data.get("strength", 10)
	agility = data.get("agility", 10)
	vitality = data.get("vitality", 10)
	intelligence = data.get("intelligence", 10)
	endurance = data.get("endurance", 10)
	luck = data.get("luck", 10)
	level = data.get("level", 1)
	experience = data.get("experience", 0)
	available_attribute_points = data.get("available_points", 0)
	experience_to_next_level = int(100 * pow(level, 1.5))
	_recalculate_derived_stats()
