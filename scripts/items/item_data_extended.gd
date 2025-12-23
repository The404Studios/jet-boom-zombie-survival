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
@export var level_requirement: int = 1

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
	text += "[color=gray]%s[/color]\n\n" % get_rarity_name()

	if item_type == ItemType.WEAPON:
		text += "Damage: %.1f\n" % damage
		text += "Fire Rate: %.2f/s\n" % (1.0 / fire_rate)
		text += "Magazine: %d\n" % magazine_size
		text += "Range: %.1fm\n\n" % weapon_range

	if armor_value > 0:
		text += "Armor: %.1f\n\n" % armor_value

	var stats = get_all_stats()
	if stats.size() > 0:
		text += "[color=lime]Stats:[/color]\n"
		for stat in stats:
			text += "+%.1f %s\n" % [stats[stat], stat.capitalize()]
		text += "\n"

	if socket_count < max_sockets:
		text += "[color=yellow]Sockets: %d/%d[/color]\n" % [socket_count, max_sockets]

	if description != "":
		text += "\n%s" % description

	return text
