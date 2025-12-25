extends Resource
class_name ItemDataExtended

enum ItemType {
	WEAPON,
	AMMO,
	HELMET,
	CHEST_ARMOR,
	GLOVES,
	BOOTS,
	RING,
	AMULET,
	CONSUMABLE,
	MATERIAL,
	AUGMENT
}

enum ItemRarity {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY,
	MYTHIC
}

enum DamageType {
	PHYSICAL,
	TRUE,
	BLEED,
	POISON,
	FIRE,
	ICE,
	LIGHTNING
}

# Basic Info
@export var item_name: String = ""
@export var item_type: ItemType = ItemType.CONSUMABLE
@export var rarity: ItemRarity = ItemRarity.COMMON
@export var description: String = ""
@export var icon: Texture2D
@export var mesh_scene: PackedScene
@export var stack_size: int = 1
@export var weight: float = 1.0
@export var value: int = 100
@export var price: int = 100  # Shop price (can differ from value)
@export var level_requirement: int = 1
@export var grid_size: Vector2i = Vector2i(1, 1)  # Size in inventory grid (width x height)

# Weapon Properties
@export var damage: float = 10.0
@export var damage_type: DamageType = DamageType.PHYSICAL
@export var fire_rate: float = 0.1
@export var magazine_size: int = 30
@export var reload_time: float = 2.0
@export var weapon_range: float = 100.0
@export var accuracy: float = 1.0
@export var recoil: float = 1.0

# Damage Type Distribution
@export var true_damage: float = 0.0
@export var bleed_damage: float = 0.0
@export var poison_damage: float = 0.0
@export var fire_damage: float = 0.0
@export var additional_damage: float = 0.0

# Armor/Gear Properties
@export var armor_value: float = 0.0
@export var durability: float = 100.0
@export var max_durability: float = 100.0

# Stat Bonuses
@export var strength_bonus: float = 0.0
@export var dexterity_bonus: float = 0.0
@export var intelligence_bonus: float = 0.0
@export var agility_bonus: float = 0.0
@export var vitality_bonus: float = 0.0

# Special Bonuses
@export var crit_chance_bonus: float = 0.0
@export var crit_damage_bonus: float = 0.0
@export var headshot_bonus: float = 0.0
@export var health_bonus: float = 0.0
@export var stamina_bonus: float = 0.0
@export var health_regen_bonus: float = 0.0
@export var stamina_regen_bonus: float = 0.0

# Augment/Socket System
@export var socket_count: int = 0
@export var max_sockets: int = 0
var augments: Array[ItemDataExtended] = []

# Consumable Properties
@export var health_restore: float = 0.0
@export var stamina_restore: float = 0.0
@export var buff_duration: float = 0.0

# Augment Properties (for augment items)
@export var augment_stat_type: String = ""
@export var augment_stat_value: float = 0.0

# Upgrade System (Remantler)
@export var upgrade_tier: int = 0  # 0-6 tiers
@export var is_melee: bool = false
@export var projectile_count: int = 1  # For shotguns
@export var spread_angle: float = 0.0  # For shotguns
@export var armor_penetration: float = 0.0

# Resistances (for armor)
@export var fire_resistance: float = 0.0
@export var ice_resistance: float = 0.0
@export var poison_resistance: float = 0.0
@export var bleed_resistance: float = 0.0
@export var lightning_resistance: float = 0.0

# Movement bonuses
@export var movement_speed_bonus: float = 0.0
@export var attack_speed_bonus: float = 0.0
@export var dodge_chance: float = 0.0

# Equipment set for set bonuses
@export var equipment_set: String = ""

func get_upgrade_tier_name() -> String:
	match upgrade_tier:
		0: return "Standard"
		1: return "Improved"
		2: return "Enhanced"
		3: return "Superior"
		4: return "Masterwork"
		5: return "Legendary"
		6: return "Mythic"
	return "Unknown"

func get_upgrade_tier_color() -> Color:
	match upgrade_tier:
		0: return Color(0.7, 0.7, 0.7)    # Gray
		1: return Color(0.2, 0.8, 0.2)    # Green
		2: return Color(0.2, 0.5, 1.0)    # Blue
		3: return Color(0.7, 0.3, 1.0)    # Purple
		4: return Color(1.0, 0.5, 0.0)    # Orange
		5: return Color(1.0, 0.8, 0.0)    # Gold
		6: return Color(1.0, 0.2, 0.2)    # Red
	return Color.WHITE

func get_rarity_color() -> Color:
	match rarity:
		ItemRarity.COMMON: return Color(0.7, 0.7, 0.7)
		ItemRarity.UNCOMMON: return Color(0.2, 0.8, 0.2)
		ItemRarity.RARE: return Color(0.2, 0.5, 1.0)
		ItemRarity.EPIC: return Color(0.7, 0.3, 1.0)
		ItemRarity.LEGENDARY: return Color(1.0, 0.5, 0.0)
		ItemRarity.MYTHIC: return Color(1.0, 0.2, 0.2)
	return Color.WHITE

func get_rarity_name() -> String:
	match rarity:
		ItemRarity.COMMON: return "Common"
		ItemRarity.UNCOMMON: return "Uncommon"
		ItemRarity.RARE: return "Rare"
		ItemRarity.EPIC: return "Epic"
		ItemRarity.LEGENDARY: return "Legendary"
		ItemRarity.MYTHIC: return "Mythic"
	return "Unknown"

func get_all_stats() -> Dictionary:
	var stats = {}
	if strength_bonus > 0: stats["strength"] = strength_bonus
	if dexterity_bonus > 0: stats["dexterity"] = dexterity_bonus
	if intelligence_bonus > 0: stats["intelligence"] = intelligence_bonus
	if agility_bonus > 0: stats["agility"] = agility_bonus
	if vitality_bonus > 0: stats["vitality"] = vitality_bonus
	if armor_value > 0: stats["armor"] = armor_value
	if crit_chance_bonus > 0: stats["crit_chance"] = crit_chance_bonus
	if crit_damage_bonus > 0: stats["crit_damage"] = crit_damage_bonus
	if headshot_bonus > 0: stats["headshot_bonus"] = headshot_bonus
	if true_damage > 0: stats["true_damage"] = true_damage
	if bleed_damage > 0: stats["bleed_damage"] = bleed_damage
	if poison_damage > 0: stats["poison_damage"] = poison_damage
	if additional_damage > 0: stats["additional_damage"] = additional_damage

	# Add augment stats
	for augment in augments:
		if augment.augment_stat_type != "":
			if stats.has(augment.augment_stat_type):
				stats[augment.augment_stat_type] += augment.augment_stat_value
			else:
				stats[augment.augment_stat_type] = augment.augment_stat_value

	return stats

func can_socket_augment() -> bool:
	return augments.size() < max_sockets

func add_augment(augment: ItemDataExtended) -> bool:
	if can_socket_augment() and augment.item_type == ItemType.AUGMENT:
		augments.append(augment)
		socket_count = augments.size()
		return true
	return false

func remove_augment(index: int) -> ItemDataExtended:
	if index >= 0 and index < augments.size():
		var augment = augments[index]
		augments.remove_at(index)
		socket_count = augments.size()
		return augment
	return null

func get_tooltip_text() -> String:
	var text = "[b][color=%s]%s[/color][/b]\n" % [get_rarity_color().to_html(), item_name]
	text += "[color=gray]%s[/color]" % get_rarity_name()

	# Show upgrade tier for weapons
	if item_type == ItemType.WEAPON and upgrade_tier > 0:
		text += " [color=%s](%s)[/color]" % [get_upgrade_tier_color().to_html(), get_upgrade_tier_name()]

	text += "\n"

	# Item type
	text += "[color=silver]%s[/color]\n\n" % _get_item_type_name()

	# Weapon stats
	if item_type == ItemType.WEAPON:
		text += "[color=white]Weapon Stats:[/color]\n"
		text += "  Damage: [color=red]%.1f[/color]\n" % damage

		if projectile_count > 1:
			text += "  Pellets: [color=orange]x%d[/color]\n" % projectile_count
			text += "  Damage/Pellet: [color=red]%.1f[/color]\n" % (damage / projectile_count)

		if fire_rate > 0:
			text += "  Fire Rate: [color=cyan]%.1f/s[/color]\n" % (1.0 / fire_rate)

		if not is_melee:
			text += "  Magazine: [color=yellow]%d[/color]\n" % magazine_size
			text += "  Reload: [color=orange]%.1fs[/color]\n" % reload_time

		text += "  Range: [color=gray]%.0fm[/color]\n" % weapon_range

		if accuracy < 1.0:
			text += "  Accuracy: [color=lime]%.0f%%[/color]\n" % (accuracy * 100)
		if recoil > 1.0:
			text += "  Recoil: [color=orange]%.1f[/color]\n" % recoil
		if armor_penetration > 0:
			text += "  Armor Pierce: [color=purple]%.0f%%[/color]\n" % (armor_penetration * 100)

		text += "\n"

	# Armor stats
	if armor_value > 0:
		text += "[color=white]Defense:[/color]\n"
		text += "  Armor: [color=cyan]%.1f[/color]\n" % armor_value
		if durability < max_durability:
			text += "  Durability: [color=orange]%.0f/%.0f[/color]\n" % [durability, max_durability]
		text += "\n"

	# Resistances
	var has_resistance = false
	var resist_text = "[color=white]Resistances:[/color]\n"
	if fire_resistance > 0:
		resist_text += "  Fire: [color=red]+%.0f%%[/color]\n" % (fire_resistance * 100)
		has_resistance = true
	if ice_resistance > 0:
		resist_text += "  Ice: [color=aqua]+%.0f%%[/color]\n" % (ice_resistance * 100)
		has_resistance = true
	if poison_resistance > 0:
		resist_text += "  Poison: [color=green]+%.0f%%[/color]\n" % (poison_resistance * 100)
		has_resistance = true
	if bleed_resistance > 0:
		resist_text += "  Bleed: [color=maroon]+%.0f%%[/color]\n" % (bleed_resistance * 100)
		has_resistance = true
	if lightning_resistance > 0:
		resist_text += "  Lightning: [color=yellow]+%.0f%%[/color]\n" % (lightning_resistance * 100)
		has_resistance = true
	if has_resistance:
		text += resist_text + "\n"

	# Attribute bonuses
	var stats = get_all_stats()
	if stats.size() > 0:
		text += "[color=lime]Stat Bonuses:[/color]\n"
		for stat in stats:
			var stat_name = _format_stat_name(stat)
			var value = stats[stat]
			if stat in ["crit_chance", "crit_damage", "headshot_bonus"]:
				text += "  +%.1f%% %s\n" % [value * 100, stat_name]
			else:
				text += "  +%.1f %s\n" % [value, stat_name]
		text += "\n"

	# Movement/Combat bonuses
	var has_bonus = false
	var bonus_text = "[color=cyan]Bonuses:[/color]\n"
	if movement_speed_bonus > 0:
		bonus_text += "  +%.0f%% Movement Speed\n" % (movement_speed_bonus * 100)
		has_bonus = true
	if attack_speed_bonus > 0:
		bonus_text += "  +%.0f%% Attack Speed\n" % (attack_speed_bonus * 100)
		has_bonus = true
	if dodge_chance > 0:
		bonus_text += "  +%.0f%% Dodge Chance\n" % (dodge_chance * 100)
		has_bonus = true
	if health_bonus > 0:
		bonus_text += "  +%.0f Max Health\n" % health_bonus
		has_bonus = true
	if stamina_bonus > 0:
		bonus_text += "  +%.0f Max Stamina\n" % stamina_bonus
		has_bonus = true
	if health_regen_bonus > 0:
		bonus_text += "  +%.1f Health Regen/s\n" % health_regen_bonus
		has_bonus = true
	if stamina_regen_bonus > 0:
		bonus_text += "  +%.1f Stamina Regen/s\n" % stamina_regen_bonus
		has_bonus = true
	if has_bonus:
		text += bonus_text + "\n"

	# Damage types
	var has_damage_type = false
	var damage_type_text = "[color=orange]Elemental Damage:[/color]\n"
	if true_damage > 0:
		damage_type_text += "  +%.1f True Damage\n" % true_damage
		has_damage_type = true
	if bleed_damage > 0:
		damage_type_text += "  +%.1f [color=maroon]Bleed[/color] Damage\n" % bleed_damage
		has_damage_type = true
	if poison_damage > 0:
		damage_type_text += "  +%.1f [color=green]Poison[/color] Damage\n" % poison_damage
		has_damage_type = true
	if fire_damage > 0:
		damage_type_text += "  +%.1f [color=red]Fire[/color] Damage\n" % fire_damage
		has_damage_type = true
	if additional_damage > 0:
		damage_type_text += "  +%.1f Bonus Damage\n" % additional_damage
		has_damage_type = true
	if has_damage_type:
		text += damage_type_text + "\n"

	# Sockets
	if max_sockets > 0:
		text += "[color=yellow]Sockets: %d/%d[/color]\n" % [socket_count, max_sockets]
		if augments.size() > 0:
			for augment in augments:
				text += "  [*] %s\n" % augment.item_name
		text += "\n"

	# Special ability (from upgrades)
	if has_meta("special_ability"):
		var ability = get_meta("special_ability")
		text += "[color=purple]Special: %s[/color]\n\n" % _get_ability_description(ability)

	# Set bonus indicator
	if equipment_set != "":
		text += "[color=gold]Set: %s[/color]\n\n" % equipment_set

	# Consumable effects
	if item_type == ItemType.CONSUMABLE:
		text += "[color=white]Effects:[/color]\n"
		if health_restore > 0:
			text += "  Restores [color=red]%.0f HP[/color]\n" % health_restore
		if stamina_restore > 0:
			text += "  Restores [color=green]%.0f Stamina[/color]\n" % stamina_restore
		if buff_duration > 0:
			text += "  Duration: [color=yellow]%.0fs[/color]\n" % buff_duration
		text += "\n"

	# Augment info
	if item_type == ItemType.AUGMENT:
		text += "[color=purple]Augment Effect:[/color]\n"
		text += "  +%.1f %s\n\n" % [augment_stat_value, _format_stat_name(augment_stat_type)]

	# Level requirement
	if level_requirement > 1:
		text += "[color=yellow]Requires Level %d[/color]\n" % level_requirement

	# Value
	text += "[color=gold]Value: %d[/color]\n" % value

	# Weight
	if weight > 0:
		text += "[color=gray]Weight: %.1f[/color]\n" % weight

	# Description
	if description != "":
		text += "\n[i][color=silver]%s[/color][/i]" % description

	return text

func get_compact_tooltip() -> String:
	"""Returns a shorter tooltip for inventory display"""
	var text = "[b][color=%s]%s[/color][/b]\n" % [get_rarity_color().to_html(), item_name]

	if item_type == ItemType.WEAPON:
		text += "DMG: %.1f | Rate: %.1f/s\n" % [damage, 1.0 / fire_rate if fire_rate > 0 else 0]
	elif armor_value > 0:
		text += "Armor: %.1f\n" % armor_value

	if upgrade_tier > 0:
		text += "[color=%s]%s Tier[/color]\n" % [get_upgrade_tier_color().to_html(), get_upgrade_tier_name()]

	return text

func _get_item_type_name() -> String:
	match item_type:
		ItemType.WEAPON:
			if is_melee:
				return "Melee Weapon"
			elif projectile_count > 1:
				return "Shotgun"
			else:
				return "Ranged Weapon"
		ItemType.AMMO: return "Ammunition"
		ItemType.HELMET: return "Helmet"
		ItemType.CHEST_ARMOR: return "Chest Armor"
		ItemType.GLOVES: return "Gloves"
		ItemType.BOOTS: return "Boots"
		ItemType.RING: return "Ring"
		ItemType.AMULET: return "Amulet"
		ItemType.CONSUMABLE: return "Consumable"
		ItemType.MATERIAL: return "Crafting Material"
		ItemType.AUGMENT: return "Weapon Augment"
	return "Item"

func _format_stat_name(stat: String) -> String:
	match stat:
		"strength": return "Strength"
		"dexterity": return "Dexterity"
		"intelligence": return "Intelligence"
		"agility": return "Agility"
		"vitality": return "Vitality"
		"armor": return "Armor"
		"crit_chance": return "Critical Chance"
		"crit_damage": return "Critical Damage"
		"headshot_bonus": return "Headshot Damage"
		"true_damage": return "True Damage"
		"bleed_damage": return "Bleed Damage"
		"poison_damage": return "Poison Damage"
		"fire_damage": return "Fire Damage"
		"additional_damage": return "Bonus Damage"
		"damage": return "Damage"
	return stat.capitalize().replace("_", " ")

func _get_ability_description(ability: String) -> String:
	match ability:
		"life_steal": return "Life Steal - Heal 5% of damage dealt"
		"armor_pierce": return "Armor Pierce - Ignore 50% of armor"
		"explosive": return "Explosive - 20% chance to explode on hit"
		"chain_lightning": return "Chain Lightning - Hits chain to nearby enemies"
		"freezing": return "Freezing - 15% chance to freeze enemies"
		"burning": return "Burning - Deals fire damage over time"
		"vampiric": return "Vampiric - Heal 10% of damage, +25% vs low HP"
		"executioner": return "Executioner - +100% damage to enemies below 25% HP"
		"berserker": return "Berserker - Damage increases as health decreases"
		"godslayer": return "Godslayer - +200% damage to bosses"
		"reality_warp": return "Reality Warp - Bullets phase through walls"
		"time_stop": return "Time Stop - 5% chance to freeze time briefly"
	return ability.capitalize()

func get_stat_bonuses() -> Dictionary:
	"""Returns all stat bonuses for equipment system integration"""
	var bonuses = {}

	# Base stats
	if strength_bonus > 0: bonuses["strength"] = strength_bonus
	if dexterity_bonus > 0: bonuses["dexterity"] = dexterity_bonus
	if intelligence_bonus > 0: bonuses["intelligence"] = intelligence_bonus
	if agility_bonus > 0: bonuses["agility"] = agility_bonus
	if vitality_bonus > 0: bonuses["vitality"] = vitality_bonus

	# Combat stats
	if armor_value > 0: bonuses["armor"] = armor_value
	if crit_chance_bonus > 0: bonuses["crit_chance"] = crit_chance_bonus
	if crit_damage_bonus > 0: bonuses["crit_damage"] = crit_damage_bonus
	if headshot_bonus > 0: bonuses["headshot_bonus"] = headshot_bonus

	# Movement stats
	if movement_speed_bonus > 0: bonuses["movement_speed"] = movement_speed_bonus
	if attack_speed_bonus > 0: bonuses["attack_speed"] = attack_speed_bonus
	if dodge_chance > 0: bonuses["dodge_chance"] = dodge_chance

	# Health/Stamina
	if health_bonus > 0: bonuses["health"] = health_bonus
	if stamina_bonus > 0: bonuses["stamina"] = stamina_bonus
	if health_regen_bonus > 0: bonuses["health_regen"] = health_regen_bonus
	if stamina_regen_bonus > 0: bonuses["stamina_regen"] = stamina_regen_bonus

	# Resistances
	if fire_resistance > 0: bonuses["fire_resist"] = fire_resistance
	if ice_resistance > 0: bonuses["ice_resist"] = ice_resistance
	if poison_resistance > 0: bonuses["poison_resist"] = poison_resistance
	if bleed_resistance > 0: bonuses["bleed_resist"] = bleed_resistance
	if lightning_resistance > 0: bonuses["lightning_resist"] = lightning_resistance

	return bonuses
