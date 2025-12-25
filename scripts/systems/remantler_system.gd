extends Node
class_name RemantlerSystem

# Remantler System - Weapon Upgrade and Enhancement Service
# Allows players to upgrade weapons with increased damage, stats, and special abilities

signal weapon_upgraded(weapon: Resource, new_tier: int)
signal upgrade_failed(reason: String)
signal augment_added(weapon: Resource, augment: Resource)
signal weapon_rerolled(weapon: Resource)

# Upgrade tiers
enum UpgradeTier {
	STANDARD,      # Tier 0 - Base weapon
	IMPROVED,      # Tier 1 - +10% damage, minor stats
	ENHANCED,      # Tier 2 - +25% damage, +1 socket
	SUPERIOR,      # Tier 3 - +40% damage, special effect
	MASTERWORK,    # Tier 4 - +60% damage, +2 sockets
	LEGENDARY,     # Tier 5 - +100% damage, unique ability
	MYTHIC         # Tier 6 - +150% damage, transcendent power
}

# Upgrade costs in sigils
const UPGRADE_COSTS = {
	0: 500,    # Standard -> Improved
	1: 1000,   # Improved -> Enhanced
	2: 2000,   # Enhanced -> Superior
	3: 4000,   # Superior -> Masterwork
	4: 8000,   # Masterwork -> Legendary
	5: 15000   # Legendary -> Mythic
}

# Material requirements per tier
const MATERIAL_REQUIREMENTS = {
	0: {"scrap_small": 20},
	1: {"scrap_small": 30, "weapon_parts": 5},
	2: {"scrap_medium": 20, "weapon_parts": 10},
	3: {"scrap_medium": 30, "scrap_large": 10, "weapon_parts": 15},
	4: {"scrap_large": 25, "rare_alloy": 5, "weapon_parts": 20},
	5: {"scrap_large": 40, "rare_alloy": 10, "mythic_core": 3}
}

# Stat bonuses per tier
const TIER_BONUSES = {
	0: {"damage_mult": 1.0, "crit_chance": 0.0, "fire_rate_mult": 1.0, "sockets": 0},
	1: {"damage_mult": 1.10, "crit_chance": 0.02, "fire_rate_mult": 1.0, "sockets": 0},
	2: {"damage_mult": 1.25, "crit_chance": 0.05, "fire_rate_mult": 1.05, "sockets": 1},
	3: {"damage_mult": 1.40, "crit_chance": 0.08, "fire_rate_mult": 1.08, "sockets": 1},
	4: {"damage_mult": 1.60, "crit_chance": 0.12, "fire_rate_mult": 1.12, "sockets": 2},
	5: {"damage_mult": 2.00, "crit_chance": 0.18, "fire_rate_mult": 1.15, "sockets": 3},
	6: {"damage_mult": 2.50, "crit_chance": 0.25, "fire_rate_mult": 1.20, "sockets": 4}
}

# Special abilities unlocked at higher tiers
const TIER_ABILITIES = {
	3: ["life_steal", "armor_pierce", "explosive"],
	4: ["chain_lightning", "freezing", "burning"],
	5: ["vampiric", "executioner", "berserker"],
	6: ["godslayer", "reality_warp", "time_stop"]
}

# References
var player_persistence: Node = null
var sigil_shop: SigilShop = null

func _ready():
	if has_node("/root/PlayerPersistence"):
		player_persistence = get_node("/root/PlayerPersistence")

# ============================================
# UPGRADE SYSTEM
# ============================================

func get_weapon_tier(weapon: Resource) -> int:
	if not weapon:
		return 0
	if "upgrade_tier" in weapon:
		return weapon.upgrade_tier
	return 0

func get_upgrade_cost(current_tier: int) -> int:
	if UPGRADE_COSTS.has(current_tier):
		return UPGRADE_COSTS[current_tier]
	return -1  # Cannot upgrade further

func get_material_cost(current_tier: int) -> Dictionary:
	if MATERIAL_REQUIREMENTS.has(current_tier):
		return MATERIAL_REQUIREMENTS[current_tier].duplicate()
	return {}

func can_upgrade(weapon: Resource, player_sigils: int) -> Dictionary:
	if not weapon:
		return {"can_upgrade": false, "reason": "No weapon selected"}

	var current_tier = get_weapon_tier(weapon)
	if current_tier >= 6:
		return {"can_upgrade": false, "reason": "Weapon is already at maximum tier"}

	# Check sigil cost
	var sigil_cost = get_upgrade_cost(current_tier)
	if player_sigils < sigil_cost:
		return {"can_upgrade": false, "reason": "Need %d sigils (have %d)" % [sigil_cost, player_sigils]}

	# Check materials
	var materials_needed = get_material_cost(current_tier)
	var missing_materials = _check_materials(materials_needed)
	if missing_materials.size() > 0:
		var missing_str = ""
		for mat in missing_materials:
			missing_str += "%s x%d, " % [mat, missing_materials[mat]]
		return {"can_upgrade": false, "reason": "Missing materials: %s" % missing_str.trim_suffix(", ")}

	return {"can_upgrade": true, "reason": "Ready to upgrade"}

func _check_materials(required: Dictionary) -> Dictionary:
	var missing = {}
	if not player_persistence or not player_persistence.player_data.has("materials"):
		return required.duplicate()

	var player_materials = player_persistence.player_data.materials

	for mat in required:
		var have = player_materials.get(mat, 0)
		if have < required[mat]:
			missing[mat] = required[mat] - have

	return missing

func upgrade_weapon(weapon: Resource, sigil_shop_ref: SigilShop = null) -> bool:
	if not weapon:
		upgrade_failed.emit("No weapon selected")
		return false

	var current_tier = get_weapon_tier(weapon)
	var sigils = 0

	if sigil_shop_ref:
		sigils = sigil_shop_ref.get_sigils()
	elif sigil_shop:
		sigils = sigil_shop.get_sigils()
	elif player_persistence:
		sigils = player_persistence.get_currency("sigils")

	var check = can_upgrade(weapon, sigils)
	if not check.can_upgrade:
		upgrade_failed.emit(check.reason)
		return false

	# Deduct costs
	var sigil_cost = get_upgrade_cost(current_tier)
	var material_cost = get_material_cost(current_tier)

	# Spend sigils
	if sigil_shop_ref:
		sigil_shop_ref.spend_sigils(sigil_cost)
	elif sigil_shop:
		sigil_shop.spend_sigils(sigil_cost)
	elif player_persistence:
		player_persistence.spend_currency("sigils", sigil_cost)

	# Spend materials
	_consume_materials(material_cost)

	# Apply upgrade
	var new_tier = current_tier + 1
	_apply_upgrade(weapon, new_tier)

	weapon_upgraded.emit(weapon, new_tier)
	return true

func _consume_materials(materials: Dictionary):
	if not player_persistence or not player_persistence.player_data.has("materials"):
		return

	for mat in materials:
		if player_persistence.player_data.materials.has(mat):
			player_persistence.player_data.materials[mat] -= materials[mat]
			if player_persistence.player_data.materials[mat] <= 0:
				player_persistence.player_data.materials.erase(mat)

func _apply_upgrade(weapon: Resource, new_tier: int):
	# Set the upgrade tier
	if not "upgrade_tier" in weapon:
		weapon.set_meta("upgrade_tier", new_tier)
	else:
		weapon.upgrade_tier = new_tier

	# Get tier bonuses
	var bonuses = TIER_BONUSES[new_tier]

	# Store original values if not already stored
	if not "base_damage" in weapon:
		weapon.set_meta("base_damage", weapon.damage)
	if not "base_fire_rate" in weapon:
		weapon.set_meta("base_fire_rate", weapon.fire_rate)
	if not "base_crit_chance" in weapon:
		weapon.set_meta("base_crit_chance", weapon.crit_chance_bonus if "crit_chance_bonus" in weapon else 0.0)

	# Apply damage multiplier
	var base_damage = weapon.get_meta("base_damage", weapon.damage)
	weapon.damage = base_damage * bonuses.damage_mult

	# Apply fire rate multiplier (lower is faster)
	var base_fire_rate = weapon.get_meta("base_fire_rate", weapon.fire_rate)
	weapon.fire_rate = base_fire_rate / bonuses.fire_rate_mult

	# Apply crit chance
	if "crit_chance_bonus" in weapon:
		var base_crit = weapon.get_meta("base_crit_chance", 0.0)
		weapon.crit_chance_bonus = base_crit + bonuses.crit_chance

	# Add sockets
	if "max_sockets" in weapon:
		weapon.max_sockets = max(weapon.max_sockets, bonuses.sockets)

	# Unlock special ability at tier 3+
	if new_tier >= 3 and TIER_ABILITIES.has(new_tier):
		var abilities = TIER_ABILITIES[new_tier]
		var random_ability = abilities[randi() % abilities.size()]
		weapon.set_meta("special_ability", random_ability)

	# Update weapon name to reflect tier
	_update_weapon_name(weapon, new_tier)

func _update_weapon_name(weapon: Resource, tier: int):
	# Store original name
	if not weapon.has_meta("original_name"):
		weapon.set_meta("original_name", weapon.item_name)

	var original_name = weapon.get_meta("original_name")
	var prefix = _get_tier_prefix(tier)

	if prefix != "":
		weapon.item_name = prefix + " " + original_name
	else:
		weapon.item_name = original_name

func _get_tier_prefix(tier: int) -> String:
	match tier:
		0: return ""
		1: return "Improved"
		2: return "Enhanced"
		3: return "Superior"
		4: return "Masterwork"
		5: return "Legendary"
		6: return "Mythic"
	return ""

func get_tier_name(tier: int) -> String:
	match tier:
		0: return "Standard"
		1: return "Improved"
		2: return "Enhanced"
		3: return "Superior"
		4: return "Masterwork"
		5: return "Legendary"
		6: return "Mythic"
	return "Unknown"

func get_tier_color(tier: int) -> Color:
	match tier:
		0: return Color(0.7, 0.7, 0.7)    # Gray
		1: return Color(0.2, 0.8, 0.2)    # Green
		2: return Color(0.2, 0.5, 1.0)    # Blue
		3: return Color(0.7, 0.3, 1.0)    # Purple
		4: return Color(1.0, 0.5, 0.0)    # Orange
		5: return Color(1.0, 0.8, 0.0)    # Gold
		6: return Color(1.0, 0.2, 0.2)    # Red
	return Color.WHITE

# ============================================
# AUGMENT SYSTEM
# ============================================

func can_add_augment(weapon: Resource) -> bool:
	if not weapon:
		return false
	if not "max_sockets" in weapon or not "socket_count" in weapon:
		return false
	return weapon.socket_count < weapon.max_sockets

func add_augment_to_weapon(weapon: Resource, augment: Resource) -> bool:
	if not can_add_augment(weapon):
		upgrade_failed.emit("No available socket slots")
		return false

	if not augment or not "item_type" in augment:
		upgrade_failed.emit("Invalid augment")
		return false

	# Add augment via item method if available
	if weapon.has_method("add_augment"):
		if weapon.add_augment(augment):
			augment_added.emit(weapon, augment)
			return true
		else:
			upgrade_failed.emit("Failed to add augment")
			return false

	# Manual augment addition
	if not "augments" in weapon:
		weapon.set_meta("augments", [])

	var augments = weapon.get_meta("augments", [])
	augments.append(augment)
	weapon.set_meta("augments", augments)
	weapon.socket_count = augments.size()

	augment_added.emit(weapon, augment)
	return true

func remove_augment_from_weapon(weapon: Resource, augment_index: int) -> Resource:
	if not weapon:
		return null

	if weapon.has_method("remove_augment"):
		return weapon.remove_augment(augment_index)

	# Manual removal
	if weapon.has_meta("augments"):
		var augments = weapon.get_meta("augments")
		if augment_index >= 0 and augment_index < augments.size():
			var removed = augments[augment_index]
			augments.remove_at(augment_index)
			weapon.set_meta("augments", augments)
			weapon.socket_count = augments.size()
			return removed

	return null

# ============================================
# REROLL SYSTEM
# ============================================

const REROLL_COST = 250  # Sigils

func can_reroll(weapon: Resource, player_sigils: int) -> bool:
	if not weapon:
		return false
	var tier = get_weapon_tier(weapon)
	if tier < 3:  # Only tier 3+ weapons have abilities to reroll
		return false
	return player_sigils >= REROLL_COST

func reroll_weapon_ability(weapon: Resource, sigil_shop_ref: SigilShop = null) -> bool:
	var sigils = 0
	if sigil_shop_ref:
		sigils = sigil_shop_ref.get_sigils()
	elif sigil_shop:
		sigils = sigil_shop.get_sigils()
	elif player_persistence:
		sigils = player_persistence.get_currency("sigils")

	if not can_reroll(weapon, sigils):
		upgrade_failed.emit("Cannot reroll - need tier 3+ weapon and %d sigils" % REROLL_COST)
		return false

	# Spend sigils
	if sigil_shop_ref:
		sigil_shop_ref.spend_sigils(REROLL_COST)
	elif sigil_shop:
		sigil_shop.spend_sigils(REROLL_COST)
	elif player_persistence:
		player_persistence.spend_currency("sigils", REROLL_COST)

	# Reroll the ability
	var tier = get_weapon_tier(weapon)
	var available_abilities = []

	# Collect all abilities from current tier and below
	for t in range(3, tier + 1):
		if TIER_ABILITIES.has(t):
			available_abilities.append_array(TIER_ABILITIES[t])

	if available_abilities.size() > 0:
		var new_ability = available_abilities[randi() % available_abilities.size()]
		weapon.set_meta("special_ability", new_ability)
		weapon_rerolled.emit(weapon)
		return true

	return false

# ============================================
# WEAPON DISMANTLING
# ============================================

func get_dismantle_returns(weapon: Resource) -> Dictionary:
	var returns = {"sigils": 0, "materials": {}}

	if not weapon:
		return returns

	var tier = get_weapon_tier(weapon)
	var base_value = weapon.value if "value" in weapon else 100

	# Return a portion of sigils based on weapon value and tier
	returns.sigils = int(base_value * 0.3 * (1 + tier * 0.2))

	# Return some materials based on tier
	match tier:
		1: returns.materials = {"scrap_small": 5}
		2: returns.materials = {"scrap_small": 10, "weapon_parts": 2}
		3: returns.materials = {"scrap_medium": 8, "weapon_parts": 5}
		4: returns.materials = {"scrap_medium": 15, "scrap_large": 5, "weapon_parts": 8}
		5: returns.materials = {"scrap_large": 12, "rare_alloy": 2, "weapon_parts": 10}
		6: returns.materials = {"scrap_large": 20, "rare_alloy": 5, "mythic_core": 1}

	return returns

func dismantle_weapon(weapon: Resource, sigil_shop_ref: SigilShop = null) -> Dictionary:
	var returns = get_dismantle_returns(weapon)

	# Add sigils
	if returns.sigils > 0:
		if sigil_shop_ref:
			sigil_shop_ref.add_sigils(returns.sigils, "Dismantled %s" % weapon.item_name)
		elif sigil_shop:
			sigil_shop.add_sigils(returns.sigils, "Dismantled %s" % weapon.item_name)
		elif player_persistence:
			player_persistence.add_currency("sigils", returns.sigils)

	# Add materials
	if player_persistence:
		if not player_persistence.player_data.has("materials"):
			player_persistence.player_data["materials"] = {}

		for mat in returns.materials:
			if player_persistence.player_data.materials.has(mat):
				player_persistence.player_data.materials[mat] += returns.materials[mat]
			else:
				player_persistence.player_data.materials[mat] = returns.materials[mat]

	return returns

# ============================================
# STAT PREVIEW
# ============================================

func get_upgrade_preview(weapon: Resource) -> Dictionary:
	var preview = {
		"current": {},
		"upgraded": {},
		"changes": {}
	}

	if not weapon:
		return preview

	var current_tier = get_weapon_tier(weapon)
	if current_tier >= 6:
		return preview

	var next_tier = current_tier + 1
	var current_bonuses = TIER_BONUSES[current_tier]
	var next_bonuses = TIER_BONUSES[next_tier]

	# Current stats
	preview.current = {
		"tier": current_tier,
		"tier_name": get_tier_name(current_tier),
		"damage": weapon.damage,
		"fire_rate": weapon.fire_rate,
		"crit_chance": weapon.crit_chance_bonus if "crit_chance_bonus" in weapon else 0.0,
		"sockets": weapon.max_sockets if "max_sockets" in weapon else 0
	}

	# Calculate upgraded stats
	var base_damage = weapon.get_meta("base_damage", weapon.damage / current_bonuses.damage_mult if current_bonuses.damage_mult > 0 else weapon.damage)
	var base_fire_rate = weapon.get_meta("base_fire_rate", weapon.fire_rate * current_bonuses.fire_rate_mult)
	var base_crit = weapon.get_meta("base_crit_chance", (weapon.crit_chance_bonus if "crit_chance_bonus" in weapon else 0.0) - current_bonuses.crit_chance)

	preview.upgraded = {
		"tier": next_tier,
		"tier_name": get_tier_name(next_tier),
		"damage": base_damage * next_bonuses.damage_mult,
		"fire_rate": base_fire_rate / next_bonuses.fire_rate_mult,
		"crit_chance": base_crit + next_bonuses.crit_chance,
		"sockets": next_bonuses.sockets
	}

	# Calculate changes
	preview.changes = {
		"damage": preview.upgraded.damage - preview.current.damage,
		"fire_rate": preview.current.fire_rate - preview.upgraded.fire_rate,  # Lower is better
		"crit_chance": preview.upgraded.crit_chance - preview.current.crit_chance,
		"sockets": preview.upgraded.sockets - preview.current.sockets
	}

	return preview

func get_weapon_stats_display(weapon: Resource) -> String:
	if not weapon:
		return "No weapon"

	var tier = get_weapon_tier(weapon)
	var tier_name = get_tier_name(tier)
	var tier_color = get_tier_color(tier)

	var text = "[b][color=%s]%s[/color][/b]\n" % [tier_color.to_html(), weapon.item_name]
	text += "[color=%s]%s Tier[/color]\n\n" % [tier_color.to_html(), tier_name]

	text += "[color=white]Base Stats:[/color]\n"
	text += "  Damage: [color=lime]%.1f[/color]\n" % weapon.damage
	text += "  Fire Rate: [color=cyan]%.2f/s[/color]\n" % (1.0 / weapon.fire_rate if weapon.fire_rate > 0 else 0)

	if "magazine_size" in weapon:
		text += "  Magazine: [color=yellow]%d[/color]\n" % weapon.magazine_size
	if "reload_time" in weapon:
		text += "  Reload: [color=orange]%.1fs[/color]\n" % weapon.reload_time
	if "weapon_range" in weapon:
		text += "  Range: [color=gray]%.0fm[/color]\n" % weapon.weapon_range

	# Bonuses
	var bonuses = TIER_BONUSES[tier]
	if tier > 0:
		text += "\n[color=lime]Tier Bonuses:[/color]\n"
		text += "  +%.0f%% Damage\n" % ((bonuses.damage_mult - 1.0) * 100)
		if bonuses.crit_chance > 0:
			text += "  +%.1f%% Crit Chance\n" % (bonuses.crit_chance * 100)
		if bonuses.fire_rate_mult > 1.0:
			text += "  +%.0f%% Fire Rate\n" % ((bonuses.fire_rate_mult - 1.0) * 100)

	# Sockets
	var current_sockets = weapon.socket_count if "socket_count" in weapon else 0
	var max_sockets = weapon.max_sockets if "max_sockets" in weapon else bonuses.sockets
	if max_sockets > 0:
		text += "\n[color=yellow]Sockets: %d/%d[/color]\n" % [current_sockets, max_sockets]

	# Special ability
	if weapon.has_meta("special_ability"):
		var ability = weapon.get_meta("special_ability")
		text += "\n[color=purple]Special: %s[/color]\n" % _get_ability_description(ability)

	return text

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

func get_ability_icon(ability: String) -> String:
	match ability:
		"life_steal": return "[LS]"
		"armor_pierce": return "[AP]"
		"explosive": return "[EX]"
		"chain_lightning": return "[CL]"
		"freezing": return "[FR]"
		"burning": return "[BU]"
		"vampiric": return "[VA]"
		"executioner": return "[EX]"
		"berserker": return "[BE]"
		"godslayer": return "[GS]"
		"reality_warp": return "[RW]"
		"time_stop": return "[TS]"
	return "[?]"
