extends Node
class_name CharacterStats

signal stat_changed(stat_name: String, old_value: float, new_value: float)
signal level_up(new_level: int)

# Primary Stats
@export var strength: float = 10.0  # Melee damage, carry weight
@export var dexterity: float = 10.0  # Accuracy, crit chance, reload speed
@export var intelligence: float = 10.0  # Skill cooldown, item find
@export var agility: float = 10.0  # Movement speed, dodge chance
@export var vitality: float = 10.0  # Health, stamina, regen

# Level and Experience
var level: int = 1
var experience: int = 0
var experience_to_next_level: int = 100
var stat_points: int = 0

# Derived Stats
var max_health: float = 100.0
var max_stamina: float = 100.0
var health_regen: float = 1.0
var stamina_regen: float = 5.0
var move_speed_multiplier: float = 1.0
var damage_multiplier: float = 1.0
var crit_chance: float = 0.05
var crit_damage: float = 1.5
var dodge_chance: float = 0.0
var carry_weight: float = 100.0
var item_find_bonus: float = 0.0

# Damage Type Bonuses
var headshot_damage_bonus: float = 1.5
var true_damage_percent: float = 0.0  # Ignores armor
var bleed_damage_per_second: float = 0.0
var poison_damage_per_second: float = 0.0
var additional_damage: float = 0.0
var elemental_damage: float = 0.0

# Resistances
var armor: float = 0.0
var bleed_resistance: float = 0.0
var poison_resistance: float = 0.0

func _ready():
	calculate_derived_stats()

func calculate_derived_stats():
	# Health and Stamina from Vitality
	max_health = 100.0 + (vitality * 10.0)
	max_stamina = 100.0 + (vitality * 5.0)
	health_regen = 1.0 + (vitality * 0.2)
	stamina_regen = 5.0 + (vitality * 0.5)

	# Movement from Agility
	move_speed_multiplier = 1.0 + (agility * 0.02)
	dodge_chance = agility * 0.005

	# Damage from Strength
	damage_multiplier = 1.0 + (strength * 0.05)

	# Crit from Dexterity
	crit_chance = 0.05 + (dexterity * 0.005)
	crit_damage = 1.5 + (dexterity * 0.02)

	# Carry weight from Strength
	carry_weight = 100.0 + (strength * 5.0)

	# Item find from Intelligence
	item_find_bonus = intelligence * 0.01

func add_stat(stat_name: String, amount: float):
	var old_value = get(stat_name)
	set(stat_name, old_value + amount)
	calculate_derived_stats()
	stat_changed.emit(stat_name, old_value, get(stat_name))

func increase_stat(stat_name: String):
	if stat_points > 0:
		add_stat(stat_name, 1.0)
		stat_points -= 1
		return true
	return false

func add_experience(amount: int):
	experience += amount
	check_level_up()

func check_level_up():
	while experience >= experience_to_next_level:
		experience -= experience_to_next_level
		level += 1
		stat_points += 5  # 5 stat points per level
		experience_to_next_level = int(experience_to_next_level * 1.2)
		level_up.emit(level)

func get_total_damage_multiplier() -> float:
	return damage_multiplier

func apply_gear_stats(gear_stats: Dictionary):
	# Apply stats from equipped gear
	for stat in gear_stats:
		match stat:
			"strength": strength += gear_stats[stat]
			"dexterity": dexterity += gear_stats[stat]
			"intelligence": intelligence += gear_stats[stat]
			"agility": agility += gear_stats[stat]
			"vitality": vitality += gear_stats[stat]
			"armor": armor += gear_stats[stat]
			"crit_chance": crit_chance += gear_stats[stat]
			"crit_damage": crit_damage += gear_stats[stat]
			"headshot_bonus": headshot_damage_bonus += gear_stats[stat]
			"true_damage": true_damage_percent += gear_stats[stat]
			"bleed_damage": bleed_damage_per_second += gear_stats[stat]
			"poison_damage": poison_damage_per_second += gear_stats[stat]
			"additional_damage": additional_damage += gear_stats[stat]

	calculate_derived_stats()

func remove_gear_stats(gear_stats: Dictionary):
	# Remove stats from unequipped gear
	for stat in gear_stats:
		match stat:
			"strength": strength -= gear_stats[stat]
			"dexterity": dexterity -= gear_stats[stat]
			"intelligence": intelligence -= gear_stats[stat]
			"agility": agility -= gear_stats[stat]
			"vitality": vitality -= gear_stats[stat]
			"armor": armor -= gear_stats[stat]
			"crit_chance": crit_chance -= gear_stats[stat]
			"crit_damage": crit_damage -= gear_stats[stat]
			"headshot_bonus": headshot_damage_bonus -= gear_stats[stat]
			"true_damage": true_damage_percent -= gear_stats[stat]
			"bleed_damage": bleed_damage_per_second -= gear_stats[stat]
			"poison_damage": poison_damage_per_second -= gear_stats[stat]
			"additional_damage": additional_damage -= gear_stats[stat]

	calculate_derived_stats()

func get_stat_summary() -> Dictionary:
	return {
		"strength": strength,
		"dexterity": dexterity,
		"intelligence": intelligence,
		"agility": agility,
		"vitality": vitality,
		"level": level,
		"experience": experience,
		"exp_to_next": experience_to_next_level,
		"stat_points": stat_points,
		"max_health": max_health,
		"max_stamina": max_stamina,
		"armor": armor,
		"crit_chance": crit_chance,
		"crit_damage": crit_damage,
		"move_speed": move_speed_multiplier,
		"carry_weight": carry_weight
	}
