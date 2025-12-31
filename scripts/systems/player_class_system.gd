extends Node
class_name PlayerClassSystem

# Player class/role system
# Defines different playstyles with unique abilities and stat modifiers

signal class_selected(class_type: String)
signal ability_unlocked(class_type: String, ability_name: String)
signal class_leveled_up(class_type: String, new_level: int)

# Class data
var classes: Dictionary = {}  # class_id -> ClassData
var player_class_progress: Dictionary = {}  # class_id -> progress data

# Current selection
var selected_class: String = "survivor"

class ClassData:
	var id: String
	var display_name: String
	var description: String
	var icon_path: String

	# Base stat modifiers (multipliers)
	var health_modifier: float = 1.0
	var speed_modifier: float = 1.0
	var damage_modifier: float = 1.0
	var reload_speed_modifier: float = 1.0
	var stamina_modifier: float = 1.0
	var armor_modifier: float = 1.0

	# Starting equipment
	var starting_weapons: Array = []
	var starting_items: Array = []
	var starting_points: int = 500
	var starting_sigils: int = 500

	# Abilities
	var passive_ability: String = ""
	var active_ability: String = ""
	var ultimate_ability: String = ""

	# Unlock requirements
	var unlock_level: int = 0
	var unlock_achievement: String = ""

	# Class-specific bonuses
	var special_bonuses: Dictionary = {}

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"display_name": display_name,
			"description": description,
			"health_modifier": health_modifier,
			"speed_modifier": speed_modifier,
			"damage_modifier": damage_modifier,
			"reload_speed_modifier": reload_speed_modifier,
			"stamina_modifier": stamina_modifier,
			"armor_modifier": armor_modifier
		}

func _ready():
	_register_default_classes()

func _register_default_classes():
	# ============================================
	# SURVIVOR - Balanced default class
	# ============================================
	var survivor = ClassData.new()
	survivor.id = "survivor"
	survivor.display_name = "Survivor"
	survivor.description = "Balanced class with no specialization. Good for learning the game."
	survivor.health_modifier = 1.0
	survivor.speed_modifier = 1.0
	survivor.damage_modifier = 1.0
	survivor.starting_weapons = ["pistol"]
	survivor.starting_points = 500
	survivor.passive_ability = "quick_learner"  # +10% XP gain
	survivor.active_ability = "adrenaline_rush"  # Temporary speed boost
	classes["survivor"] = survivor

	# ============================================
	# ASSAULT - High damage, lower survivability
	# ============================================
	var assault = ClassData.new()
	assault.id = "assault"
	assault.display_name = "Assault"
	assault.description = "Combat specialist with increased damage output. Glass cannon."
	assault.health_modifier = 0.85
	assault.speed_modifier = 1.1
	assault.damage_modifier = 1.25
	assault.reload_speed_modifier = 1.1
	assault.stamina_modifier = 1.15
	assault.starting_weapons = ["assault_rifle", "pistol"]
	assault.starting_points = 400
	assault.passive_ability = "trigger_happy"  # +15% fire rate
	assault.active_ability = "rage_mode"  # Double damage for 5 seconds
	assault.ultimate_ability = "bullet_storm"  # Unlimited ammo for 10 seconds
	assault.special_bonuses = {"headshot_damage": 1.5, "recoil_reduction": 0.2}
	assault.unlock_level = 5
	classes["assault"] = assault

	# ============================================
	# MEDIC - Team support and healing
	# ============================================
	var medic = ClassData.new()
	medic.id = "medic"
	medic.display_name = "Medic"
	medic.description = "Support class that can heal teammates and has increased survivability."
	medic.health_modifier = 1.1
	medic.speed_modifier = 0.95
	medic.damage_modifier = 0.9
	medic.stamina_modifier = 1.2
	medic.starting_weapons = ["smg", "pistol"]
	medic.starting_items = ["medkit", "medkit"]
	medic.starting_points = 450
	medic.passive_ability = "healing_aura"  # Slowly heal nearby allies
	medic.active_ability = "emergency_heal"  # Instant team heal
	medic.ultimate_ability = "revive_all"  # Revive all dead teammates
	medic.special_bonuses = {"heal_efficiency": 1.5, "revive_speed": 2.0}
	medic.unlock_level = 8
	classes["medic"] = medic

	# ============================================
	# TANK - High survivability, slow
	# ============================================
	var tank = ClassData.new()
	tank.id = "tank"
	tank.display_name = "Tank"
	tank.description = "Heavy class with massive health and armor. Slow but nearly unstoppable."
	tank.health_modifier = 1.5
	tank.speed_modifier = 0.8
	tank.damage_modifier = 0.95
	tank.armor_modifier = 1.5
	tank.stamina_modifier = 0.8
	tank.starting_weapons = ["shotgun", "pistol"]
	tank.starting_points = 550
	tank.passive_ability = "thick_skin"  # 20% damage reduction
	tank.active_ability = "taunt"  # Draw zombie aggro
	tank.ultimate_ability = "fortress"  # Immovable for 10s, 80% damage reduction
	tank.special_bonuses = {"knockback_resistance": 0.8, "melee_damage": 1.3}
	tank.unlock_level = 10
	classes["tank"] = tank

	# ============================================
	# ENGINEER - Building and traps
	# ============================================
	var engineer = ClassData.new()
	engineer.id = "engineer"
	engineer.display_name = "Engineer"
	engineer.description = "Technical class that excels at building barricades and setting traps."
	engineer.health_modifier = 0.95
	engineer.speed_modifier = 1.0
	engineer.damage_modifier = 0.9
	engineer.reload_speed_modifier = 0.9
	engineer.starting_weapons = ["smg", "pistol"]
	engineer.starting_items = ["nails", "nails", "nails"]
	engineer.starting_points = 600
	engineer.passive_ability = "efficient_builder"  # 50% faster nailing, cheaper repairs
	engineer.active_ability = "deploy_turret"  # Place auto-turret
	engineer.ultimate_ability = "fortify_all"  # Instantly repair all barricades
	engineer.special_bonuses = {"nail_speed": 2.0, "repair_cost": 0.5, "turret_damage": 1.3}
	engineer.unlock_level = 12
	classes["engineer"] = engineer

	# ============================================
	# SCOUT - Fast and stealthy
	# ============================================
	var scout = ClassData.new()
	scout.id = "scout"
	scout.display_name = "Scout"
	scout.description = "Agile class that moves fast and can spot threats. Hit and run tactics."
	scout.health_modifier = 0.8
	scout.speed_modifier = 1.3
	scout.damage_modifier = 1.0
	scout.reload_speed_modifier = 1.2
	scout.stamina_modifier = 1.5
	scout.starting_weapons = ["pistol", "knife"]
	scout.starting_points = 400
	scout.passive_ability = "eagle_eye"  # See zombies through walls, extended minimap
	scout.active_ability = "sprint_burst"  # 50% speed for 5 seconds
	scout.ultimate_ability = "invisibility"  # Zombies ignore you for 8 seconds
	scout.special_bonuses = {"minimap_range": 2.0, "critical_chance": 0.15}
	scout.unlock_level = 7
	classes["scout"] = scout

	# ============================================
	# DEMOLITIONIST - Explosives expert
	# ============================================
	var demo = ClassData.new()
	demo.id = "demolitionist"
	demo.display_name = "Demolitionist"
	demo.description = "Explosives expert. High AoE damage but dangerous to self and allies."
	demo.health_modifier = 1.0
	demo.speed_modifier = 0.9
	demo.damage_modifier = 1.0
	demo.starting_weapons = ["shotgun", "pistol"]
	demo.starting_items = ["grenade", "grenade", "grenade"]
	demo.starting_points = 450
	demo.passive_ability = "blast_resistance"  # 50% reduced explosive self-damage
	demo.active_ability = "c4_charge"  # Plant remote explosive
	demo.ultimate_ability = "airstrike"  # Call in explosive barrage
	demo.special_bonuses = {"explosive_damage": 1.5, "explosive_radius": 1.3}
	demo.unlock_level = 15
	classes["demolitionist"] = demo

# ============================================
# CLASS SELECTION
# ============================================

func select_class(class_id: String) -> bool:
	"""Select a class for the player"""
	if not classes.has(class_id):
		push_error("Unknown class: %s" % class_id)
		return false

	var class_data = classes[class_id]

	# Check if unlocked
	if not is_class_unlocked(class_id):
		push_warning("Class not unlocked: %s" % class_id)
		return false

	selected_class = class_id
	class_selected.emit(class_id)

	return true

func is_class_unlocked(class_id: String) -> bool:
	"""Check if a class is unlocked"""
	if not classes.has(class_id):
		return false

	var class_data = classes[class_id]

	# Check level requirement
	var player_level = _get_player_level()
	if class_data.unlock_level > player_level:
		return false

	# Check achievement requirement
	if not class_data.unlock_achievement.is_empty():
		if not _has_achievement(class_data.unlock_achievement):
			return false

	return true

func get_class_data(class_id: String) -> ClassData:
	"""Get class data by ID"""
	return classes.get(class_id, null)

func get_selected_class() -> ClassData:
	"""Get currently selected class"""
	return classes.get(selected_class, null)

func get_all_classes() -> Array:
	"""Get all class data"""
	return classes.values()

func get_unlocked_classes() -> Array:
	"""Get all unlocked classes"""
	var unlocked = []
	for class_id in classes:
		if is_class_unlocked(class_id):
			unlocked.append(classes[class_id])
	return unlocked

# ============================================
# STAT APPLICATION
# ============================================

func apply_class_to_player(player: Node, class_id: String = ""):
	"""Apply class modifiers to a player"""
	if class_id.is_empty():
		class_id = selected_class

	var class_data = classes.get(class_id)
	if not class_data:
		return

	# Apply health modifier
	if "max_health" in player:
		var base_health = 100.0
		player.max_health = base_health * class_data.health_modifier
		if "current_health" in player:
			player.current_health = player.max_health

	# Apply speed modifier
	if "move_speed" in player:
		var base_speed = 5.0
		player.move_speed = base_speed * class_data.speed_modifier
	if "sprint_speed" in player:
		var base_sprint = 8.0
		player.sprint_speed = base_sprint * class_data.speed_modifier

	# Apply stamina modifier
	if "max_stamina" in player:
		var base_stamina = 100.0
		player.max_stamina = base_stamina * class_data.stamina_modifier

	# Store class info on player
	if player.has_method("set_class"):
		player.set_class(class_id, class_data)
	else:
		player.set_meta("player_class", class_id)
		player.set_meta("class_data", class_data)

	# Give starting equipment
	_give_starting_equipment(player, class_data)

func get_damage_modifier(class_id: String = "") -> float:
	"""Get damage modifier for class"""
	if class_id.is_empty():
		class_id = selected_class

	var class_data = classes.get(class_id)
	return class_data.damage_modifier if class_data else 1.0

func get_special_bonus(class_id: String, bonus_name: String) -> float:
	"""Get a special bonus value"""
	var class_data = classes.get(class_id)
	if not class_data:
		return 1.0

	return class_data.special_bonuses.get(bonus_name, 1.0)

# ============================================
# EQUIPMENT
# ============================================

func _give_starting_equipment(player: Node, class_data: ClassData):
	"""Give starting weapons and items to player"""
	# Give weapons
	for weapon_id in class_data.starting_weapons:
		if player.has_method("give_weapon"):
			player.give_weapon(weapon_id)
		elif player.has_node("Inventory"):
			var inv = player.get_node("Inventory")
			if inv.has_method("add_weapon"):
				inv.add_weapon(weapon_id)

	# Give items
	for item_id in class_data.starting_items:
		if player.has_method("give_item"):
			player.give_item(item_id)
		elif player.has_node("Inventory"):
			var inv = player.get_node("Inventory")
			if inv.has_method("add_item"):
				inv.add_item(item_id)

	# Give starting currency
	var points_system = get_node_or_null("/root/PointsSystem")
	if points_system:
		if points_system.has_method("add_points"):
			points_system.add_points(class_data.starting_points)

	var persistence = get_node_or_null("/root/PlayerPersistence")
	if persistence:
		if persistence.has_method("add_currency"):
			persistence.add_currency("sigils", class_data.starting_sigils)

# ============================================
# ABILITIES
# ============================================

func get_passive_ability(class_id: String = "") -> String:
	if class_id.is_empty():
		class_id = selected_class

	var class_data = classes.get(class_id)
	return class_data.passive_ability if class_data else ""

func get_active_ability(class_id: String = "") -> String:
	if class_id.is_empty():
		class_id = selected_class

	var class_data = classes.get(class_id)
	return class_data.active_ability if class_data else ""

func get_ultimate_ability(class_id: String = "") -> String:
	if class_id.is_empty():
		class_id = selected_class

	var class_data = classes.get(class_id)
	return class_data.ultimate_ability if class_data else ""

# ============================================
# UTILITY
# ============================================

func _get_player_level() -> int:
	var persistence = get_node_or_null("/root/PlayerPersistence")
	if persistence and "player_level" in persistence:
		return persistence.player_level

	return 1

func _has_achievement(achievement_id: String) -> bool:
	var persistence = get_node_or_null("/root/PlayerPersistence")
	if persistence and persistence.has_method("has_achievement"):
		return persistence.has_achievement(achievement_id)

	return false

func register_class(class_data: ClassData):
	"""Register a custom class"""
	classes[class_data.id] = class_data
