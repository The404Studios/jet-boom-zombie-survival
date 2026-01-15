extends Node
class_name SkillSystem

## Network-replicated skill and skill tree system
## Based on Offense/Defense/Handling/Conditioning categories
## Features budget system, prestige, subclasses, and skill sets

signal skill_unlocked(skill_id: String, level: int)
signal skill_upgraded(skill_id: String, old_level: int, new_level: int)
signal attribute_changed(attribute: String, old_value: float, new_value: float)
signal subclass_unlocked(subclass_id: String)
signal prestige_level_changed(new_level: int)
signal skill_points_changed(available: int)
signal budget_changed(category: String, new_budget: float)

# Skill categories
enum SkillCategory {
	OFFENSE,
	DEFENSE,
	HANDLING,
	CONDITIONING
}

# Skill tiers
enum SkillTier {
	BASIC,      # Tier A - Easy to unlock
	ADVANCED,   # Tier B - Requires more budget
	EXPERT,     # Tier C - High budget requirement
	MASTER      # Tier D - Maximum budget
}

# Player skill data (synced over network)
var player_skills: Dictionary = {}  # skill_id -> SkillData
var attributes: Dictionary = {}
var unlocked_subclasses: Array = []
var active_subclass: String = ""
var prestige_level: int = 0
var skill_points: int = 0
var category_budgets: Dictionary = {
	"offense": 0.0,
	"defense": 0.0,
	"handling": 0.0,
	"conditioning": 0.0
}

# Skill definitions (loaded from data)
var skill_definitions: Dictionary = {}
var attribute_definitions: Dictionary = {}
var subclass_definitions: Dictionary = {}
var skill_set_definitions: Dictionary = {}

# Network
var network_manager: Node = null
var local_peer_id: int = 0

class SkillData:
	var skill_id: String = ""
	var level: int = 0
	var max_level: int = 5
	var category: SkillCategory = SkillCategory.OFFENSE
	var tier: SkillTier = SkillTier.BASIC
	var budget_cost: float = 10.0
	var is_unlocked: bool = false
	var experience: float = 0.0
	var experience_required: float = 100.0

	func to_dict() -> Dictionary:
		return {
			"skill_id": skill_id,
			"level": level,
			"is_unlocked": is_unlocked,
			"experience": experience
		}

	static func from_dict(data: Dictionary) -> SkillData:
		var skill = SkillData.new()
		skill.skill_id = data.get("skill_id", "")
		skill.level = data.get("level", 0)
		skill.is_unlocked = data.get("is_unlocked", false)
		skill.experience = data.get("experience", 0.0)
		return skill

func _ready():
	network_manager = get_node_or_null("/root/NetworkManager")
	if multiplayer.has_multiplayer_peer():
		local_peer_id = multiplayer.get_unique_id()

	# Load skill definitions
	_load_skill_definitions()
	_initialize_attributes()

func _load_skill_definitions():
	"""Load skill, attribute, and subclass definitions"""
	# Define skills for each category

	# OFFENSE SKILLS
	_define_skill("damage_boost", "Damage Boost", SkillCategory.OFFENSE, SkillTier.BASIC, {
		"description": "Increase weapon damage",
		"per_level": {"damage_mult": 0.05},
		"max_level": 10,
		"budget_cost": 10.0
	})
	_define_skill("critical_hit", "Critical Hit", SkillCategory.OFFENSE, SkillTier.BASIC, {
		"description": "Increase critical hit chance",
		"per_level": {"crit_chance": 0.02},
		"max_level": 10,
		"budget_cost": 15.0
	})
	_define_skill("headshot_damage", "Headshot Expert", SkillCategory.OFFENSE, SkillTier.ADVANCED, {
		"description": "Increase headshot damage multiplier",
		"per_level": {"headshot_mult": 0.1},
		"max_level": 5,
		"budget_cost": 25.0
	})
	_define_skill("penetration", "Armor Penetration", SkillCategory.OFFENSE, SkillTier.ADVANCED, {
		"description": "Ignore a percentage of enemy armor",
		"per_level": {"armor_pen": 0.05},
		"max_level": 5,
		"budget_cost": 30.0
	})
	_define_skill("explosive_expert", "Explosive Expert", SkillCategory.OFFENSE, SkillTier.EXPERT, {
		"description": "Increase explosive damage and radius",
		"per_level": {"explosive_damage": 0.1, "explosive_radius": 0.05},
		"max_level": 5,
		"budget_cost": 50.0
	})

	# DEFENSE SKILLS
	_define_skill("health_boost", "Health Boost", SkillCategory.DEFENSE, SkillTier.BASIC, {
		"description": "Increase maximum health",
		"per_level": {"max_health": 10.0},
		"max_level": 10,
		"budget_cost": 10.0
	})
	_define_skill("damage_reduction", "Damage Reduction", SkillCategory.DEFENSE, SkillTier.BASIC, {
		"description": "Reduce incoming damage",
		"per_level": {"damage_reduction": 0.02},
		"max_level": 10,
		"budget_cost": 15.0
	})
	_define_skill("armor_efficiency", "Armor Efficiency", SkillCategory.DEFENSE, SkillTier.ADVANCED, {
		"description": "Armor provides more protection",
		"per_level": {"armor_efficiency": 0.05},
		"max_level": 5,
		"budget_cost": 25.0
	})
	_define_skill("regeneration", "Regeneration", SkillCategory.DEFENSE, SkillTier.ADVANCED, {
		"description": "Slowly regenerate health over time",
		"per_level": {"health_regen": 0.5},
		"max_level": 5,
		"budget_cost": 35.0
	})
	_define_skill("last_stand", "Last Stand", SkillCategory.DEFENSE, SkillTier.EXPERT, {
		"description": "Survive lethal damage once per wave",
		"per_level": {"last_stand_health": 0.1},
		"max_level": 3,
		"budget_cost": 60.0
	})

	# HANDLING SKILLS
	_define_skill("reload_speed", "Quick Reload", SkillCategory.HANDLING, SkillTier.BASIC, {
		"description": "Increase reload speed",
		"per_level": {"reload_speed": 0.05},
		"max_level": 10,
		"budget_cost": 10.0
	})
	_define_skill("aim_stability", "Aim Stability", SkillCategory.HANDLING, SkillTier.BASIC, {
		"description": "Reduce weapon sway and recoil",
		"per_level": {"recoil_reduction": 0.05},
		"max_level": 10,
		"budget_cost": 12.0
	})
	_define_skill("swap_speed", "Quick Swap", SkillCategory.HANDLING, SkillTier.ADVANCED, {
		"description": "Switch weapons faster",
		"per_level": {"swap_speed": 0.1},
		"max_level": 5,
		"budget_cost": 20.0
	})
	_define_skill("ammo_efficiency", "Ammo Efficiency", SkillCategory.HANDLING, SkillTier.ADVANCED, {
		"description": "Chance to not consume ammo",
		"per_level": {"ammo_save_chance": 0.03},
		"max_level": 5,
		"budget_cost": 30.0
	})
	_define_skill("steady_aim", "Steady Aim", SkillCategory.HANDLING, SkillTier.EXPERT, {
		"description": "Increased accuracy when standing still",
		"per_level": {"accuracy_bonus": 0.1},
		"max_level": 5,
		"budget_cost": 45.0
	})

	# CONDITIONING SKILLS
	_define_skill("stamina_boost", "Stamina Boost", SkillCategory.CONDITIONING, SkillTier.BASIC, {
		"description": "Increase maximum stamina",
		"per_level": {"max_stamina": 10.0},
		"max_level": 10,
		"budget_cost": 10.0
	})
	_define_skill("sprint_speed", "Sprint Speed", SkillCategory.CONDITIONING, SkillTier.BASIC, {
		"description": "Increase sprint speed",
		"per_level": {"sprint_speed": 0.03},
		"max_level": 10,
		"budget_cost": 12.0
	})
	_define_skill("stamina_regen", "Endurance", SkillCategory.CONDITIONING, SkillTier.ADVANCED, {
		"description": "Regenerate stamina faster",
		"per_level": {"stamina_regen": 0.1},
		"max_level": 5,
		"budget_cost": 25.0
	})
	_define_skill("carry_weight", "Pack Mule", SkillCategory.CONDITIONING, SkillTier.ADVANCED, {
		"description": "Increase carry capacity",
		"per_level": {"carry_weight": 5.0},
		"max_level": 5,
		"budget_cost": 20.0
	})
	_define_skill("second_wind", "Second Wind", SkillCategory.CONDITIONING, SkillTier.EXPERT, {
		"description": "Restore stamina after kills",
		"per_level": {"stamina_on_kill": 5.0},
		"max_level": 5,
		"budget_cost": 40.0
	})

	# Define subclasses
	_define_subclass("assault", "Assault", {
		"description": "Focused on dealing damage",
		"required_offense_budget": 100.0,
		"bonuses": {"damage_mult": 0.1, "fire_rate": 0.05}
	})
	_define_subclass("tank", "Tank", {
		"description": "Focused on absorbing damage",
		"required_defense_budget": 100.0,
		"bonuses": {"max_health": 50.0, "damage_reduction": 0.1}
	})
	_define_subclass("support", "Support", {
		"description": "Focused on helping teammates",
		"required_handling_budget": 75.0,
		"required_conditioning_budget": 75.0,
		"bonuses": {"heal_bonus": 0.2, "revive_speed": 0.3}
	})
	_define_subclass("scout", "Scout", {
		"description": "Fast and agile",
		"required_conditioning_budget": 100.0,
		"bonuses": {"move_speed": 0.15, "stamina_regen": 0.2}
	})

	# Define skill sets (combinations that unlock special abilities)
	_define_skill_set("berserker", "Berserker", {
		"required_skills": ["damage_boost:5", "critical_hit:5", "sprint_speed:3"],
		"bonus": "Deal 50% more damage when below 30% health"
	})
	_define_skill_set("fortress", "Fortress", {
		"required_skills": ["health_boost:5", "damage_reduction:5", "armor_efficiency:3"],
		"bonus": "Take 25% less damage when standing still"
	})
	_define_skill_set("gunslinger", "Gunslinger", {
		"required_skills": ["reload_speed:5", "swap_speed:3", "aim_stability:5"],
		"bonus": "First shot after swapping weapons deals double damage"
	})

func _define_skill(id: String, display_name: String, category: SkillCategory, tier: SkillTier, data: Dictionary):
	skill_definitions[id] = {
		"id": id,
		"name": display_name,
		"category": category,
		"tier": tier,
		"description": data.get("description", ""),
		"per_level": data.get("per_level", {}),
		"max_level": data.get("max_level", 5),
		"budget_cost": data.get("budget_cost", 10.0)
	}

func _define_subclass(id: String, display_name: String, data: Dictionary):
	subclass_definitions[id] = {
		"id": id,
		"name": display_name,
		"description": data.get("description", ""),
		"required_offense_budget": data.get("required_offense_budget", 0.0),
		"required_defense_budget": data.get("required_defense_budget", 0.0),
		"required_handling_budget": data.get("required_handling_budget", 0.0),
		"required_conditioning_budget": data.get("required_conditioning_budget", 0.0),
		"bonuses": data.get("bonuses", {})
	}

func _define_skill_set(id: String, display_name: String, data: Dictionary):
	skill_set_definitions[id] = {
		"id": id,
		"name": display_name,
		"required_skills": data.get("required_skills", []),
		"bonus": data.get("bonus", "")
	}

func _initialize_attributes():
	"""Initialize base attributes"""
	attributes = {
		# Combat
		"damage_mult": 1.0,
		"crit_chance": 0.05,
		"crit_damage": 1.5,
		"headshot_mult": 2.0,
		"armor_pen": 0.0,
		"fire_rate": 1.0,
		"explosive_damage": 1.0,
		"explosive_radius": 1.0,

		# Defense
		"max_health": 100.0,
		"damage_reduction": 0.0,
		"armor_efficiency": 1.0,
		"health_regen": 0.0,
		"last_stand_health": 0.0,

		# Handling
		"reload_speed": 1.0,
		"recoil_reduction": 0.0,
		"swap_speed": 1.0,
		"ammo_save_chance": 0.0,
		"accuracy_bonus": 0.0,

		# Conditioning
		"max_stamina": 100.0,
		"sprint_speed": 1.0,
		"stamina_regen": 1.0,
		"carry_weight": 50.0,
		"stamina_on_kill": 0.0,
		"move_speed": 1.0,

		# Support
		"heal_bonus": 1.0,
		"revive_speed": 1.0
	}

# ============================================
# SKILL MANAGEMENT
# ============================================

func unlock_skill(skill_id: String) -> bool:
	"""Unlock a skill"""
	if not skill_definitions.has(skill_id):
		return false

	if player_skills.has(skill_id) and player_skills[skill_id].is_unlocked:
		return false  # Already unlocked

	var definition = skill_definitions[skill_id]
	var budget_cost = definition.budget_cost

	# Check if we have enough skill points
	if skill_points < 1:
		return false

	# Create skill data if not exists
	if not player_skills.has(skill_id):
		var skill = SkillData.new()
		skill.skill_id = skill_id
		skill.category = definition.category
		skill.tier = definition.tier
		skill.max_level = definition.max_level
		skill.budget_cost = budget_cost
		player_skills[skill_id] = skill

	player_skills[skill_id].is_unlocked = true
	player_skills[skill_id].level = 1
	skill_points -= 1

	# Add to category budget
	var category_name = _get_category_name(definition.category)
	category_budgets[category_name] += budget_cost

	# Recalculate attributes
	_recalculate_attributes()

	# Network sync
	_sync_skill_state()

	skill_unlocked.emit(skill_id, 1)
	skill_points_changed.emit(skill_points)
	budget_changed.emit(category_name, category_budgets[category_name])

	# Check for subclass unlocks
	_check_subclass_unlocks()

	return true

func upgrade_skill(skill_id: String) -> bool:
	"""Upgrade an existing skill"""
	if not player_skills.has(skill_id):
		return false

	var skill = player_skills[skill_id]
	if not skill.is_unlocked:
		return false

	if skill.level >= skill.max_level:
		return false

	if skill_points < 1:
		return false

	var old_level = skill.level
	skill.level += 1
	skill_points -= 1

	var definition = skill_definitions[skill_id]
	var category_name = _get_category_name(definition.category)
	category_budgets[category_name] += definition.budget_cost

	_recalculate_attributes()
	_sync_skill_state()

	skill_upgraded.emit(skill_id, old_level, skill.level)
	skill_points_changed.emit(skill_points)
	budget_changed.emit(category_name, category_budgets[category_name])

	_check_subclass_unlocks()
	return true

func add_skill_experience(skill_id: String, amount: float):
	"""Add experience to a skill (passive leveling)"""
	if not player_skills.has(skill_id):
		return

	var skill = player_skills[skill_id]
	if not skill.is_unlocked:
		return

	skill.experience += amount

	# Check for level up
	while skill.experience >= skill.experience_required and skill.level < skill.max_level:
		skill.experience -= skill.experience_required
		skill.level += 1
		skill.experience_required *= 1.5  # Harder to level up

		_recalculate_attributes()
		skill_upgraded.emit(skill_id, skill.level - 1, skill.level)

	_sync_skill_state()

func add_skill_points(amount: int):
	"""Add skill points"""
	skill_points += amount
	skill_points_changed.emit(skill_points)
	_sync_skill_state()

# ============================================
# ATTRIBUTE CALCULATION
# ============================================

func _recalculate_attributes():
	"""Recalculate all attributes based on skills and subclass"""
	_initialize_attributes()  # Reset to base

	# Apply skill bonuses
	for skill_id in player_skills:
		var skill = player_skills[skill_id]
		if not skill.is_unlocked or skill.level <= 0:
			continue

		var definition = skill_definitions.get(skill_id, {})
		var per_level = definition.get("per_level", {})

		for attr in per_level:
			if attributes.has(attr):
				attributes[attr] += per_level[attr] * skill.level

	# Apply subclass bonuses
	if active_subclass != "" and subclass_definitions.has(active_subclass):
		var subclass = subclass_definitions[active_subclass]
		var bonuses = subclass.get("bonuses", {})
		for attr in bonuses:
			if attributes.has(attr):
				attributes[attr] += bonuses[attr]

	# Apply prestige bonuses (5% per prestige level)
	var prestige_bonus = 1.0 + (prestige_level * 0.05)
	for attr in ["damage_mult", "max_health", "max_stamina"]:
		attributes[attr] *= prestige_bonus

func get_attribute(attr: String) -> float:
	"""Get current attribute value"""
	return attributes.get(attr, 0.0)

func get_skill_level(skill_id: String) -> int:
	"""Get current level of a skill"""
	if player_skills.has(skill_id):
		return player_skills[skill_id].level
	return 0

func is_skill_unlocked(skill_id: String) -> bool:
	"""Check if skill is unlocked"""
	return player_skills.has(skill_id) and player_skills[skill_id].is_unlocked

# ============================================
# SUBCLASS SYSTEM
# ============================================

func _check_subclass_unlocks():
	"""Check if any subclasses can be unlocked"""
	for subclass_id in subclass_definitions:
		if subclass_id in unlocked_subclasses:
			continue

		var subclass = subclass_definitions[subclass_id]
		var can_unlock = true

		if category_budgets["offense"] < subclass.get("required_offense_budget", 0.0):
			can_unlock = false
		if category_budgets["defense"] < subclass.get("required_defense_budget", 0.0):
			can_unlock = false
		if category_budgets["handling"] < subclass.get("required_handling_budget", 0.0):
			can_unlock = false
		if category_budgets["conditioning"] < subclass.get("required_conditioning_budget", 0.0):
			can_unlock = false

		if can_unlock:
			unlocked_subclasses.append(subclass_id)
			subclass_unlocked.emit(subclass_id)

func set_active_subclass(subclass_id: String) -> bool:
	"""Set active subclass"""
	if subclass_id not in unlocked_subclasses:
		return false

	active_subclass = subclass_id
	_recalculate_attributes()
	_sync_skill_state()
	return true

func get_unlocked_subclasses() -> Array:
	return unlocked_subclasses

# ============================================
# PRESTIGE SYSTEM
# ============================================

func can_prestige() -> bool:
	"""Check if player can prestige"""
	var total_budget = 0.0
	for cat in category_budgets:
		total_budget += category_budgets[cat]
	return total_budget >= 500.0  # Require 500 total budget

func prestige() -> bool:
	"""Reset skills and gain prestige level"""
	if not can_prestige():
		return false

	prestige_level += 1

	# Reset skills but keep a portion of budget
	var kept_budget = {}
	for cat in category_budgets:
		kept_budget[cat] = category_budgets[cat] * 0.1  # Keep 10%

	player_skills.clear()
	category_budgets = kept_budget
	unlocked_subclasses.clear()
	active_subclass = ""

	# Grant bonus skill points
	skill_points += prestige_level * 5

	_recalculate_attributes()
	_sync_skill_state()

	prestige_level_changed.emit(prestige_level)
	return true

# ============================================
# NETWORK SYNCHRONIZATION
# ============================================

func _sync_skill_state():
	"""Sync skill state to server"""
	if network_manager and multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		var state = get_full_skill_state()
		_send_skill_state_to_server.rpc_id(1, state)

func get_full_skill_state() -> Dictionary:
	"""Get complete skill state for sync"""
	var skills_data = {}
	for skill_id in player_skills:
		skills_data[skill_id] = player_skills[skill_id].to_dict()

	return {
		"skills": skills_data,
		"attributes": attributes.duplicate(),
		"category_budgets": category_budgets.duplicate(),
		"unlocked_subclasses": unlocked_subclasses.duplicate(),
		"active_subclass": active_subclass,
		"prestige_level": prestige_level,
		"skill_points": skill_points
	}

func load_skill_state(state: Dictionary):
	"""Load skill state from data"""
	var skills_data = state.get("skills", {})
	player_skills.clear()
	for skill_id in skills_data:
		player_skills[skill_id] = SkillData.from_dict(skills_data[skill_id])

	category_budgets = state.get("category_budgets", category_budgets)
	unlocked_subclasses = state.get("unlocked_subclasses", [])
	active_subclass = state.get("active_subclass", "")
	prestige_level = state.get("prestige_level", 0)
	skill_points = state.get("skill_points", 0)

	_recalculate_attributes()

@rpc("any_peer", "reliable")
func _send_skill_state_to_server(_state: Dictionary):
	# Server receives skill state from client
	pass

@rpc("authority", "reliable")
func _receive_skill_state(_state: Dictionary):
	"""Client receives skill state from server"""
	load_skill_state(_state)

# ============================================
# UTILITY
# ============================================

func _get_category_name(category: SkillCategory) -> String:
	match category:
		SkillCategory.OFFENSE: return "offense"
		SkillCategory.DEFENSE: return "defense"
		SkillCategory.HANDLING: return "handling"
		SkillCategory.CONDITIONING: return "conditioning"
	return "offense"

func get_skills_by_category(category: SkillCategory) -> Array:
	"""Get all skills in a category"""
	var result = []
	for skill_id in skill_definitions:
		if skill_definitions[skill_id].category == category:
			result.append(skill_definitions[skill_id])
	return result

func get_skill_definition(skill_id: String) -> Dictionary:
	return skill_definitions.get(skill_id, {})

func get_subclass_definition(subclass_id: String) -> Dictionary:
	return subclass_definitions.get(subclass_id, {})
