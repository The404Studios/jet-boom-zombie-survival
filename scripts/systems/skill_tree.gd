extends Node
class_name SkillTree

# Skill Tree System
# Defines skill categories, individual skills, and progression

signal skill_unlocked(skill_id: String, skill_data: Dictionary)
signal skill_upgraded(skill_id: String, new_level: int)
signal skill_points_changed(available: int)

# Skill Categories
enum SkillCategory {
	COMBAT,
	SURVIVAL,
	UTILITY,
	SPECIAL
}

# Skill point tracking
var skill_points: int = 0
var total_skill_points_earned: int = 0

# Unlocked skills: skill_id -> current_level
var unlocked_skills: Dictionary = {}

# Skill definitions
var skill_data: Dictionary = {}

func _ready():
	_initialize_skill_data()

func _initialize_skill_data():
	"""Define all skills in the tree"""
	skill_data = {
		# ===== COMBAT SKILLS =====
		"rapid_fire": {
			"name": "Rapid Fire",
			"description": "Increases fire rate by 10% per level",
			"category": SkillCategory.COMBAT,
			"max_level": 5,
			"cost_per_level": 1,
			"requires": [],
			"effect": {
				"attack_speed_bonus": 10.0  # Per level
			},
			"icon": "rapid_fire"
		},
		"power_shot": {
			"name": "Power Shot",
			"description": "Increases weapon damage by 8% per level",
			"category": SkillCategory.COMBAT,
			"max_level": 5,
			"cost_per_level": 1,
			"requires": [],
			"effect": {
				"damage_bonus": 8.0
			},
			"icon": "power_shot"
		},
		"critical_mastery": {
			"name": "Critical Mastery",
			"description": "Increases critical chance by 5% per level",
			"category": SkillCategory.COMBAT,
			"max_level": 5,
			"cost_per_level": 2,
			"requires": ["power_shot:2"],
			"effect": {
				"crit_chance": 5.0
			},
			"icon": "crit_mastery"
		},
		"headhunter": {
			"name": "Headhunter",
			"description": "Headshot damage increased by 25% per level",
			"category": SkillCategory.COMBAT,
			"max_level": 3,
			"cost_per_level": 2,
			"requires": ["critical_mastery:3"],
			"effect": {
				"headshot_bonus": 25.0
			},
			"icon": "headhunter"
		},
		"executioner": {
			"name": "Executioner",
			"description": "Deal 50% more damage to enemies below 30% health",
			"category": SkillCategory.COMBAT,
			"max_level": 1,
			"cost_per_level": 3,
			"requires": ["headhunter:2"],
			"effect": {
				"execute_threshold": 30.0,
				"execute_damage": 50.0
			},
			"icon": "executioner"
		},
		"reload_mastery": {
			"name": "Reload Mastery",
			"description": "Decreases reload time by 15% per level",
			"category": SkillCategory.COMBAT,
			"max_level": 3,
			"cost_per_level": 1,
			"requires": ["rapid_fire:2"],
			"effect": {
				"reload_speed": 15.0
			},
			"icon": "reload"
		},
		"steady_aim": {
			"name": "Steady Aim",
			"description": "Reduces weapon spread by 20% per level",
			"category": SkillCategory.COMBAT,
			"max_level": 3,
			"cost_per_level": 1,
			"requires": [],
			"effect": {
				"spread_reduction": 20.0
			},
			"icon": "steady_aim"
		},

		# ===== SURVIVAL SKILLS =====
		"thick_skin": {
			"name": "Thick Skin",
			"description": "Increases max health by 20 per level",
			"category": SkillCategory.SURVIVAL,
			"max_level": 5,
			"cost_per_level": 1,
			"requires": [],
			"effect": {
				"max_health": 20.0
			},
			"icon": "thick_skin"
		},
		"regeneration": {
			"name": "Regeneration",
			"description": "Regenerate 1 HP per second per level",
			"category": SkillCategory.SURVIVAL,
			"max_level": 5,
			"cost_per_level": 2,
			"requires": ["thick_skin:2"],
			"effect": {
				"health_regen": 1.0
			},
			"icon": "regeneration"
		},
		"iron_will": {
			"name": "Iron Will",
			"description": "Reduces all damage taken by 5% per level",
			"category": SkillCategory.SURVIVAL,
			"max_level": 5,
			"cost_per_level": 2,
			"requires": ["thick_skin:3"],
			"effect": {
				"damage_reduction": 5.0
			},
			"icon": "iron_will"
		},
		"last_stand": {
			"name": "Last Stand",
			"description": "When below 25% health, gain 30% damage reduction",
			"category": SkillCategory.SURVIVAL,
			"max_level": 1,
			"cost_per_level": 3,
			"requires": ["iron_will:3"],
			"effect": {
				"last_stand_threshold": 25.0,
				"last_stand_reduction": 30.0
			},
			"icon": "last_stand"
		},
		"poison_resist": {
			"name": "Poison Resistance",
			"description": "Reduces poison damage by 20% per level",
			"category": SkillCategory.SURVIVAL,
			"max_level": 5,
			"cost_per_level": 1,
			"requires": [],
			"effect": {
				"poison_resist": 20.0
			},
			"icon": "poison_resist"
		},
		"second_wind": {
			"name": "Second Wind",
			"description": "Increases stamina regeneration by 25% per level",
			"category": SkillCategory.SURVIVAL,
			"max_level": 4,
			"cost_per_level": 1,
			"requires": [],
			"effect": {
				"stamina_regen": 25.0
			},
			"icon": "second_wind"
		},

		# ===== UTILITY SKILLS =====
		"quick_hands": {
			"name": "Quick Hands",
			"description": "Increases interaction speed by 20% per level",
			"category": SkillCategory.UTILITY,
			"max_level": 3,
			"cost_per_level": 1,
			"requires": [],
			"effect": {
				"interact_speed": 20.0
			},
			"icon": "quick_hands"
		},
		"scavenger": {
			"name": "Scavenger",
			"description": "Increases loot drop rate by 15% per level",
			"category": SkillCategory.UTILITY,
			"max_level": 5,
			"cost_per_level": 1,
			"requires": [],
			"effect": {
				"loot_bonus": 15.0
			},
			"icon": "scavenger"
		},
		"treasure_hunter": {
			"name": "Treasure Hunter",
			"description": "Chance to find rare items increased by 10% per level",
			"category": SkillCategory.UTILITY,
			"max_level": 3,
			"cost_per_level": 2,
			"requires": ["scavenger:3"],
			"effect": {
				"rare_loot_chance": 10.0
			},
			"icon": "treasure_hunter"
		},
		"marathon": {
			"name": "Marathon",
			"description": "Increases max stamina by 20 per level",
			"category": SkillCategory.UTILITY,
			"max_level": 5,
			"cost_per_level": 1,
			"requires": [],
			"effect": {
				"max_stamina": 20.0
			},
			"icon": "marathon"
		},
		"sprinter": {
			"name": "Sprinter",
			"description": "Increases movement speed by 5% per level",
			"category": SkillCategory.UTILITY,
			"max_level": 5,
			"cost_per_level": 1,
			"requires": ["marathon:2"],
			"effect": {
				"movement_speed": 5.0
			},
			"icon": "sprinter"
		},
		"pack_mule": {
			"name": "Pack Mule",
			"description": "Increases inventory capacity by 5 slots per level",
			"category": SkillCategory.UTILITY,
			"max_level": 4,
			"cost_per_level": 2,
			"requires": [],
			"effect": {
				"inventory_slots": 5
			},
			"icon": "pack_mule"
		},

		# ===== SPECIAL SKILLS =====
		"adrenaline_rush": {
			"name": "Adrenaline Rush",
			"description": "On kill, gain 20% attack speed for 3 seconds",
			"category": SkillCategory.SPECIAL,
			"max_level": 1,
			"cost_per_level": 3,
			"requires": ["rapid_fire:3", "power_shot:3"],
			"effect": {
				"on_kill_attack_speed": 20.0,
				"on_kill_duration": 3.0
			},
			"icon": "adrenaline"
		},
		"life_steal": {
			"name": "Life Steal",
			"description": "Heal for 5% of damage dealt per level",
			"category": SkillCategory.SPECIAL,
			"max_level": 3,
			"cost_per_level": 3,
			"requires": ["regeneration:3"],
			"effect": {
				"life_steal": 5.0
			},
			"icon": "life_steal"
		},
		"explosive_finish": {
			"name": "Explosive Finish",
			"description": "Enemies killed explode, dealing 50 damage to nearby enemies",
			"category": SkillCategory.SPECIAL,
			"max_level": 1,
			"cost_per_level": 4,
			"requires": ["headhunter:3"],
			"effect": {
				"kill_explosion_damage": 50.0,
				"kill_explosion_radius": 5.0
			},
			"icon": "explosive"
		},
		"berserker": {
			"name": "Berserker",
			"description": "Deal 2% more damage for each 1% health missing",
			"category": SkillCategory.SPECIAL,
			"max_level": 1,
			"cost_per_level": 4,
			"requires": ["last_stand:1"],
			"effect": {
				"berserker_damage_per_missing_health": 2.0
			},
			"icon": "berserker"
		},
		"lucky_shot": {
			"name": "Lucky Shot",
			"description": "10% chance to not consume ammo",
			"category": SkillCategory.SPECIAL,
			"max_level": 1,
			"cost_per_level": 3,
			"requires": ["reload_mastery:2"],
			"effect": {
				"ammo_conservation_chance": 10.0
			},
			"icon": "lucky_shot"
		}
	}

# ============================================
# SKILL MANAGEMENT
# ============================================

func add_skill_points(amount: int):
	"""Add skill points to spend"""
	skill_points += amount
	total_skill_points_earned += amount
	skill_points_changed.emit(skill_points)

func can_unlock_skill(skill_id: String) -> bool:
	"""Check if a skill can be unlocked or upgraded"""
	if not skill_data.has(skill_id):
		return false

	var skill = skill_data[skill_id]
	var current_level = unlocked_skills.get(skill_id, 0)

	# Check max level
	if current_level >= skill.max_level:
		return false

	# Check skill point cost
	if skill_points < skill.cost_per_level:
		return false

	# Check prerequisites
	for req in skill.requires:
		var parts = req.split(":")
		if parts.is_empty():
			continue
		var req_skill = parts[0]
		var req_level = int(parts[1]) if parts.size() > 1 else 1

		if unlocked_skills.get(req_skill, 0) < req_level:
			return false

	return true

func unlock_skill(skill_id: String) -> bool:
	"""Unlock or upgrade a skill"""
	if not can_unlock_skill(skill_id):
		return false

	var skill = skill_data[skill_id]
	var current_level = unlocked_skills.get(skill_id, 0)

	# Spend points
	skill_points -= skill.cost_per_level
	skill_points_changed.emit(skill_points)

	# Upgrade skill
	unlocked_skills[skill_id] = current_level + 1

	if current_level == 0:
		skill_unlocked.emit(skill_id, skill)
	else:
		skill_upgraded.emit(skill_id, current_level + 1)

	return true

func get_skill_level(skill_id: String) -> int:
	"""Get current level of a skill"""
	return unlocked_skills.get(skill_id, 0)

func is_skill_maxed(skill_id: String) -> bool:
	"""Check if skill is at max level"""
	if not skill_data.has(skill_id):
		return false
	return get_skill_level(skill_id) >= skill_data[skill_id].max_level

# ============================================
# EFFECT CALCULATION
# ============================================

func get_total_effects() -> Dictionary:
	"""Calculate total effects from all unlocked skills"""
	var effects = {}

	for skill_id in unlocked_skills:
		var level = unlocked_skills[skill_id]
		if level <= 0:
			continue

		var skill = skill_data[skill_id]
		for effect_name in skill.effect:
			var effect_value = skill.effect[effect_name] * level

			if not effects.has(effect_name):
				effects[effect_name] = 0.0
			effects[effect_name] += effect_value

	return effects

func get_effect_value(effect_name: String) -> float:
	"""Get a specific effect value"""
	var effects = get_total_effects()
	return effects.get(effect_name, 0.0)

func has_skill(skill_id: String) -> bool:
	"""Check if player has a skill unlocked"""
	return unlocked_skills.get(skill_id, 0) > 0

# ============================================
# SKILL QUERIES
# ============================================

func get_skills_by_category(category: SkillCategory) -> Array:
	"""Get all skills in a category"""
	var skills = []
	for skill_id in skill_data:
		if skill_data[skill_id].category == category:
			skills.append(skill_id)
	return skills

func get_available_skills() -> Array:
	"""Get skills that can be unlocked"""
	var available = []
	for skill_id in skill_data:
		if can_unlock_skill(skill_id):
			available.append(skill_id)
	return available

func get_skill_info(skill_id: String) -> Dictionary:
	"""Get full skill information including current state"""
	if not skill_data.has(skill_id):
		return {}

	var skill = skill_data[skill_id].duplicate()
	skill["current_level"] = get_skill_level(skill_id)
	skill["can_unlock"] = can_unlock_skill(skill_id)
	skill["is_maxed"] = is_skill_maxed(skill_id)

	return skill

# ============================================
# RESET
# ============================================

func reset_skills():
	"""Reset all skills and refund points"""
	skill_points = total_skill_points_earned
	unlocked_skills.clear()
	skill_points_changed.emit(skill_points)

# ============================================
# SAVE/LOAD
# ============================================

func get_save_data() -> Dictionary:
	return {
		"skill_points": skill_points,
		"total_earned": total_skill_points_earned,
		"unlocked_skills": unlocked_skills.duplicate()
	}

func load_save_data(data: Dictionary):
	skill_points = data.get("skill_points", 0)
	total_skill_points_earned = data.get("total_earned", 0)
	unlocked_skills = data.get("unlocked_skills", {}).duplicate()
