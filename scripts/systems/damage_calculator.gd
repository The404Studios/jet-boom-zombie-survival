extends Node
class_name DamageCalculator

class DamageInstance:
	var total_damage: float = 0.0
	var physical_damage: float = 0.0
	var true_damage: float = 0.0
	var bleed_damage: float = 0.0
	var poison_damage: float = 0.0
	var fire_damage: float = 0.0
	var additional_damage: float = 0.0
	var is_critical: bool = false
	var is_headshot: bool = false
	var damage_source: Node = null

	func _init(base_dmg: float = 0.0):
		physical_damage = base_dmg
		total_damage = base_dmg

static func calculate_damage(
	base_damage: float,
	attacker_stats: CharacterStats,
	weapon: ItemDataExtended,
	is_headshot: bool = false,
	target_armor: float = 0.0
) -> DamageInstance:
	var dmg = DamageInstance.new(base_damage)
	dmg.is_headshot = is_headshot

	# Calculate crit
	var crit_roll = randf()
	if crit_roll < attacker_stats.crit_chance:
		dmg.is_critical = true

	# Base damage with multipliers
	var final_damage = base_damage * attacker_stats.damage_multiplier

	# Crit damage
	if dmg.is_critical:
		final_damage *= attacker_stats.crit_damage

	# Headshot bonus
	if is_headshot:
		final_damage *= attacker_stats.headshot_damage_bonus
		if weapon and weapon.headshot_bonus > 0:
			final_damage *= (1.0 + weapon.headshot_bonus)

	# Add weapon damage types
	if weapon:
		dmg.true_damage = weapon.true_damage
		dmg.bleed_damage = weapon.bleed_damage + attacker_stats.bleed_damage_per_second
		dmg.poison_damage = weapon.poison_damage + attacker_stats.poison_damage_per_second
		dmg.fire_damage = weapon.fire_damage
		dmg.additional_damage = weapon.additional_damage + attacker_stats.additional_damage

	# Apply armor reduction to physical damage only
	var armor_reduction = calculate_armor_reduction(target_armor)
	dmg.physical_damage = final_damage * (1.0 - armor_reduction)

	# True damage ignores armor
	dmg.true_damage += final_damage * attacker_stats.true_damage_percent

	# Total damage
	dmg.total_damage = dmg.physical_damage + dmg.true_damage + dmg.additional_damage

	return dmg

static func calculate_armor_reduction(armor: float) -> float:
	# Armor formula: reduction = armor / (armor + 100)
	# Max 75% reduction
	var reduction = armor / (armor + 100.0)
	return clamp(reduction, 0.0, 0.75)

static func apply_damage_to_target(target: Node, dmg: DamageInstance):
	if target.has_method("take_damage_advanced"):
		target.take_damage_advanced(dmg)
	elif target.has_method("take_damage"):
		target.take_damage(dmg.total_damage, Vector3.ZERO)

	# Apply status effects
	if dmg.bleed_damage > 0:
		apply_bleed(target, dmg.bleed_damage)
	if dmg.poison_damage > 0:
		apply_poison(target, dmg.poison_damage)

static func apply_bleed(target: Node, damage_per_second: float):
	if target.has_method("apply_status_effect"):
		target.apply_status_effect("bleed", damage_per_second, 5.0)

static func apply_poison(target: Node, damage_per_second: float):
	if target.has_method("apply_status_effect"):
		target.apply_status_effect("poison", damage_per_second, 10.0)

static func get_damage_text(dmg: DamageInstance) -> String:
	var text = "%.0f" % dmg.total_damage

	if dmg.is_critical:
		text = "[color=yellow]CRIT! %s[/color]" % text

	if dmg.is_headshot:
		text = "[color=red]HEADSHOT! %s[/color]" % text

	return text
