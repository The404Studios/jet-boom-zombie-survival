extends Node
class_name SigilShop

# Sigil Shop System - Allows players to buy weapons, ammo, scrap, and services
# Currency: Sigils (earned from kills and wave completions)

signal shop_opened
signal shop_closed
signal item_purchased(item_name: String, cost: int)
signal sigils_changed(new_amount: int)
signal purchase_failed(reason: String)

# Currency
var current_sigils: int = 0
var sigils: int:
	get: return current_sigils
	set(value): current_sigils = value

# Shop categories
enum ShopCategory {
	WEAPONS,
	AMMO,
	MATERIALS,
	CONSUMABLES,
	GEAR,
	BACKPACKS,
	AUGMENTS,
	SERVICES
}

# Shop item structure
class ShopItem:
	var id: String
	var name: String
	var description: String
	var category: ShopCategory
	var cost: int
	var item_data: Resource = null
	var quantity: int = 1  # For stackable items
	var stock: int = -1  # -1 = infinite
	var level_requirement: int = 1
	var icon_path: String = ""
	var rarity: int = 0  # 0=Common, 1=Uncommon, 2=Rare, 3=Epic, 4=Legendary, 5=Mythic

	func _init(p_id: String, p_name: String, p_desc: String, p_cat: ShopCategory, p_cost: int):
		id = p_id
		name = p_name
		description = p_desc
		category = p_cat
		cost = p_cost

	func get_rarity_color() -> Color:
		match rarity:
			0: return Color(0.7, 0.7, 0.7)  # Common - Gray
			1: return Color(0.2, 0.8, 0.2)  # Uncommon - Green
			2: return Color(0.2, 0.5, 1.0)  # Rare - Blue
			3: return Color(0.7, 0.3, 1.0)  # Epic - Purple
			4: return Color(1.0, 0.5, 0.0)  # Legendary - Orange
			5: return Color(1.0, 0.2, 0.2)  # Mythic - Red
		return Color.WHITE

	func get_rarity_name() -> String:
		match rarity:
			0: return "Common"
			1: return "Uncommon"
			2: return "Rare"
			3: return "Epic"
			4: return "Legendary"
			5: return "Mythic"
		return "Unknown"

# All available shop items
var shop_items: Dictionary = {}

# Currently displayed items (filtered by category)
var displayed_items: Array[ShopItem] = []

# Reference to player systems
var player_persistence: Node = null
var inventory_system: Node = null
var equipment_system: Node = null

func _ready():
	add_to_group("sigil_shop")

	# Get persistence reference
	if has_node("/root/PlayerPersistence"):
		player_persistence = get_node("/root/PlayerPersistence")

	# Initialize shop inventory
	_populate_shop_inventory()

	# Load sigils from persistence
	_load_sigils()

func _load_sigils():
	if player_persistence:
		current_sigils = player_persistence.get_currency("sigils")
		if current_sigils == 0:
			# Give starting sigils
			current_sigils = 500
			player_persistence.add_currency("sigils", 500)
	else:
		current_sigils = 500

func _populate_shop_inventory():
	shop_items.clear()

	# ============================================
	# WEAPONS - Pistols
	# ============================================
	var pistol = ShopItem.new("weapon_pistol", "Pistol", "Reliable sidearm. Good for beginners.", ShopCategory.WEAPONS, 100)
	pistol.rarity = 0
	pistol.item_data = _load_weapon_resource("pistol")
	shop_items["weapon_pistol"] = pistol

	var revolver = ShopItem.new("weapon_revolver", "Revolver", "Powerful handgun with high damage per shot.", ShopCategory.WEAPONS, 250)
	revolver.rarity = 1
	revolver.item_data = _load_weapon_resource("revolver")
	shop_items["weapon_revolver"] = revolver

	# ============================================
	# WEAPONS - Rifles
	# ============================================
	var ak47 = ShopItem.new("weapon_ak47", "AK-47", "Assault rifle with high damage and moderate accuracy.", ShopCategory.WEAPONS, 800)
	ak47.rarity = 2
	ak47.level_requirement = 3
	ak47.item_data = _load_weapon_resource("ak47")
	shop_items["weapon_ak47"] = ak47

	var m4 = ShopItem.new("weapon_m4", "M4 Carbine", "Versatile assault rifle with good accuracy.", ShopCategory.WEAPONS, 750)
	m4.rarity = 2
	m4.level_requirement = 2
	m4.item_data = _load_weapon_resource("m4_carbine")
	shop_items["weapon_m4"] = m4

	var scar = ShopItem.new("weapon_scar", "SCAR-H", "Heavy battle rifle with excellent stopping power.", ShopCategory.WEAPONS, 1200)
	scar.rarity = 3
	scar.level_requirement = 5
	scar.item_data = _load_weapon_resource("scar_h")
	shop_items["weapon_scar"] = scar

	var mp5 = ShopItem.new("weapon_mp5", "MP5", "Submachine gun with fast fire rate.", ShopCategory.WEAPONS, 500)
	mp5.rarity = 1
	mp5.item_data = _load_weapon_resource("mp5")
	shop_items["weapon_mp5"] = mp5

	# ============================================
	# WEAPONS - Shotguns
	# ============================================
	var shotgun = ShopItem.new("weapon_shotgun", "Combat Shotgun", "Close range devastation. Multiple pellets per shot.", ShopCategory.WEAPONS, 600)
	shotgun.rarity = 1
	shotgun.item_data = _load_weapon_resource("combat_shotgun")
	shop_items["weapon_shotgun"] = shotgun

	var auto_shotgun = ShopItem.new("weapon_auto_shotgun", "Auto Shotgun", "Semi-automatic shotgun for rapid fire.", ShopCategory.WEAPONS, 1000)
	auto_shotgun.rarity = 2
	auto_shotgun.level_requirement = 4
	auto_shotgun.item_data = _load_weapon_resource("auto_shotgun")
	shop_items["weapon_auto_shotgun"] = auto_shotgun

	# ============================================
	# WEAPONS - Heavy
	# ============================================
	var lmg = ShopItem.new("weapon_lmg", "LMG", "Light machine gun with massive magazine.", ShopCategory.WEAPONS, 1500)
	lmg.rarity = 3
	lmg.level_requirement = 6
	lmg.item_data = _load_weapon_resource("lmg")
	shop_items["weapon_lmg"] = lmg

	var minigun = ShopItem.new("weapon_minigun", "Minigun", "Ultimate firepower. Mow down hordes.", ShopCategory.WEAPONS, 3000)
	minigun.rarity = 4
	minigun.level_requirement = 10
	minigun.item_data = _load_weapon_resource("minigun")
	shop_items["weapon_minigun"] = minigun

	var sniper = ShopItem.new("weapon_sniper", "Sniper Rifle", "Long range precision weapon.", ShopCategory.WEAPONS, 1000)
	sniper.rarity = 2
	sniper.level_requirement = 5
	sniper.item_data = _load_weapon_resource("sniper_rifle")
	shop_items["weapon_sniper"] = sniper

	var grenade_launcher = ShopItem.new("weapon_gl", "Grenade Launcher", "Explosive ordnance delivery system.", ShopCategory.WEAPONS, 2000)
	grenade_launcher.rarity = 3
	grenade_launcher.level_requirement = 8
	grenade_launcher.item_data = _load_weapon_resource("grenade_launcher")
	shop_items["weapon_gl"] = grenade_launcher

	var crossbow = ShopItem.new("weapon_crossbow", "Crossbow", "Silent but deadly. Piercing bolts.", ShopCategory.WEAPONS, 800)
	crossbow.rarity = 2
	crossbow.level_requirement = 4
	crossbow.item_data = _load_weapon_resource("crossbow")
	shop_items["weapon_crossbow"] = crossbow

	# ============================================
	# WEAPONS - Melee
	# ============================================
	var knife = ShopItem.new("weapon_knife", "Combat Knife", "Fast melee weapon. No ammo needed.", ShopCategory.WEAPONS, 150)
	knife.rarity = 0
	knife.item_data = _load_weapon_resource("combat_knife")
	shop_items["weapon_knife"] = knife

	var katana = ShopItem.new("weapon_katana", "Katana", "Elegant blade with high damage.", ShopCategory.WEAPONS, 500)
	katana.rarity = 2
	katana.level_requirement = 3
	katana.item_data = _load_weapon_resource("katana")
	shop_items["weapon_katana"] = katana

	var chainsaw = ShopItem.new("weapon_chainsaw", "Chainsaw", "Brutal melee weapon. Continuous damage.", ShopCategory.WEAPONS, 1200)
	chainsaw.rarity = 3
	chainsaw.level_requirement = 7
	chainsaw.item_data = _load_weapon_resource("chainsaw")
	shop_items["weapon_chainsaw"] = chainsaw

	# ============================================
	# WEAPONS - Legendary/Mythic
	# ============================================
	var legendary_deagle = ShopItem.new("weapon_legendary_deagle", "Golden Desert Eagle", "Legendary pistol with massive damage.", ShopCategory.WEAPONS, 5000)
	legendary_deagle.rarity = 4
	legendary_deagle.level_requirement = 12
	legendary_deagle.item_data = _load_weapon_resource("legendary_deagle")
	shop_items["weapon_legendary_deagle"] = legendary_deagle

	var legendary_smg = ShopItem.new("weapon_legendary_smg", "Plasma SMG", "Legendary SMG with energy rounds.", ShopCategory.WEAPONS, 4500)
	legendary_smg.rarity = 4
	legendary_smg.level_requirement = 11
	legendary_smg.item_data = _load_weapon_resource("legendary_smg")
	shop_items["weapon_legendary_smg"] = legendary_smg

	var mythic_railgun = ShopItem.new("weapon_mythic_railgun", "Railgun", "Mythic weapon. Pierces all armor.", ShopCategory.WEAPONS, 10000)
	mythic_railgun.rarity = 5
	mythic_railgun.level_requirement = 15
	mythic_railgun.item_data = _load_weapon_resource("mythic_railgun")
	shop_items["weapon_mythic_railgun"] = mythic_railgun

	# ============================================
	# AMMO
	# ============================================
	var ammo_pistol = ShopItem.new("ammo_pistol", "Pistol Ammo", "Standard 9mm ammunition. 30 rounds.", ShopCategory.AMMO, 50)
	ammo_pistol.quantity = 30
	ammo_pistol.rarity = 0
	shop_items["ammo_pistol"] = ammo_pistol

	var ammo_rifle = ShopItem.new("ammo_rifle", "Rifle Ammo", "5.56mm rifle ammunition. 60 rounds.", ShopCategory.AMMO, 100)
	ammo_rifle.quantity = 60
	ammo_rifle.rarity = 0
	shop_items["ammo_rifle"] = ammo_rifle

	var ammo_shotgun = ShopItem.new("ammo_shotgun", "Shotgun Shells", "12 gauge buckshot. 20 shells.", ShopCategory.AMMO, 75)
	ammo_shotgun.quantity = 20
	ammo_shotgun.rarity = 0
	shop_items["ammo_shotgun"] = ammo_shotgun

	var ammo_heavy = ShopItem.new("ammo_heavy", "Heavy Ammo", "7.62mm heavy rounds. 100 rounds.", ShopCategory.AMMO, 150)
	ammo_heavy.quantity = 100
	ammo_heavy.rarity = 1
	shop_items["ammo_heavy"] = ammo_heavy

	var ammo_special = ShopItem.new("ammo_special", "Special Ammo", "Energy cells for legendary weapons. 50 charges.", ShopCategory.AMMO, 300)
	ammo_special.quantity = 50
	ammo_special.rarity = 2
	shop_items["ammo_special"] = ammo_special

	var ammo_explosive = ShopItem.new("ammo_explosive", "Explosive Ammo", "Grenades and rockets. 10 rounds.", ShopCategory.AMMO, 250)
	ammo_explosive.quantity = 10
	ammo_explosive.rarity = 2
	shop_items["ammo_explosive"] = ammo_explosive

	# ============================================
	# MATERIALS
	# ============================================
	var scrap_small = ShopItem.new("material_scrap_small", "Scrap Metal (Small)", "Basic upgrade material. Used for tier 1-2 upgrades.", ShopCategory.MATERIALS, 100)
	scrap_small.quantity = 10
	scrap_small.rarity = 0
	shop_items["material_scrap_small"] = scrap_small

	var scrap_medium = ShopItem.new("material_scrap_medium", "Scrap Metal (Medium)", "Standard upgrade material. Used for tier 3-4 upgrades.", ShopCategory.MATERIALS, 250)
	scrap_medium.quantity = 10
	scrap_medium.rarity = 1
	shop_items["material_scrap_medium"] = scrap_medium

	var scrap_large = ShopItem.new("material_scrap_large", "Scrap Metal (Large)", "Quality upgrade material. Used for tier 5+ upgrades.", ShopCategory.MATERIALS, 500)
	scrap_large.quantity = 10
	scrap_large.rarity = 2
	shop_items["material_scrap_large"] = scrap_large

	var weapon_parts = ShopItem.new("material_weapon_parts", "Weapon Parts", "Precision components for weapon upgrades.", ShopCategory.MATERIALS, 400)
	weapon_parts.quantity = 5
	weapon_parts.rarity = 2
	shop_items["material_weapon_parts"] = weapon_parts

	var rare_alloy = ShopItem.new("material_rare_alloy", "Rare Alloy", "Exotic metal for legendary upgrades.", ShopCategory.MATERIALS, 1000)
	rare_alloy.quantity = 3
	rare_alloy.rarity = 3
	shop_items["material_rare_alloy"] = rare_alloy

	var mythic_core = ShopItem.new("material_mythic_core", "Mythic Core", "Extremely rare. Required for mythic upgrades.", ShopCategory.MATERIALS, 2500)
	mythic_core.quantity = 1
	mythic_core.rarity = 5
	shop_items["material_mythic_core"] = mythic_core

	var augment_crystal = ShopItem.new("material_augment_crystal", "Augment Crystal", "Used to add augment slots to weapons.", ShopCategory.MATERIALS, 750)
	augment_crystal.quantity = 1
	augment_crystal.rarity = 3
	shop_items["material_augment_crystal"] = augment_crystal

	# ============================================
	# CONSUMABLES
	# ============================================
	var health_pack = ShopItem.new("consumable_health", "Health Pack", "Restores 50 HP instantly.", ShopCategory.CONSUMABLES, 75)
	health_pack.quantity = 1
	health_pack.rarity = 0
	shop_items["consumable_health"] = health_pack

	var health_pack_large = ShopItem.new("consumable_health_large", "Large Health Pack", "Restores 100 HP instantly.", ShopCategory.CONSUMABLES, 150)
	health_pack_large.quantity = 1
	health_pack_large.rarity = 1
	shop_items["consumable_health_large"] = health_pack_large

	var stamina_shot = ShopItem.new("consumable_stamina", "Adrenaline Shot", "Fully restores stamina.", ShopCategory.CONSUMABLES, 50)
	stamina_shot.quantity = 1
	stamina_shot.rarity = 0
	shop_items["consumable_stamina"] = stamina_shot

	var damage_boost = ShopItem.new("consumable_damage", "Damage Boost", "+25% damage for 60 seconds.", ShopCategory.CONSUMABLES, 200)
	damage_boost.quantity = 1
	damage_boost.rarity = 2
	shop_items["consumable_damage"] = damage_boost

	var speed_boost = ShopItem.new("consumable_speed", "Speed Boost", "+30% movement speed for 60 seconds.", ShopCategory.CONSUMABLES, 150)
	speed_boost.quantity = 1
	speed_boost.rarity = 1
	shop_items["consumable_speed"] = speed_boost

	var armor_boost = ShopItem.new("consumable_armor", "Temporary Armor", "Absorbs 50 damage for 120 seconds.", ShopCategory.CONSUMABLES, 175)
	armor_boost.quantity = 1
	armor_boost.rarity = 1
	shop_items["consumable_armor"] = armor_boost

	# ============================================
	# SERVICES
	# ============================================
	var respec = ShopItem.new("service_respec", "Skill Respec", "Reset all skill points. One-time use.", ShopCategory.SERVICES, 500)
	respec.stock = -1
	respec.rarity = 2
	shop_items["service_respec"] = respec

	var attribute_reset = ShopItem.new("service_attr_reset", "Attribute Reset", "Reset all attribute points.", ShopCategory.SERVICES, 750)
	attribute_reset.stock = -1
	attribute_reset.rarity = 2
	shop_items["service_attr_reset"] = attribute_reset

	var weapon_repair = ShopItem.new("service_repair", "Weapon Repair", "Fully repairs your equipped weapon.", ShopCategory.SERVICES, 200)
	weapon_repair.stock = -1
	weapon_repair.rarity = 1
	shop_items["service_repair"] = weapon_repair

	# Turrets
	var turret_basic = ShopItem.new("service_turret_basic", "Basic Turret", "Deploy a basic auto-turret. Targets zombies automatically.", ShopCategory.SERVICES, 300)
	turret_basic.rarity = 1
	turret_basic.stock = -1
	shop_items["service_turret_basic"] = turret_basic

	var turret_heavy = ShopItem.new("service_turret_heavy", "Heavy Turret", "Deploy a heavy turret with increased damage and armor.", ShopCategory.SERVICES, 600)
	turret_heavy.rarity = 2
	turret_heavy.level_requirement = 5
	turret_heavy.stock = -1
	shop_items["service_turret_heavy"] = turret_heavy

	var turret_flame = ShopItem.new("service_turret_flame", "Flame Turret", "Deploy a flamethrower turret. Burns nearby enemies.", ShopCategory.SERVICES, 500)
	turret_flame.rarity = 2
	turret_flame.level_requirement = 4
	turret_flame.stock = -1
	shop_items["service_turret_flame"] = turret_flame

	var turret_tesla = ShopItem.new("service_turret_tesla", "Tesla Turret", "Deploy a tesla turret. Chain lightning to multiple enemies.", ShopCategory.SERVICES, 800)
	turret_tesla.rarity = 3
	turret_tesla.level_requirement = 8
	turret_tesla.stock = -1
	shop_items["service_turret_tesla"] = turret_tesla

	# Friendly AI Summons
	var summon_soldier = ShopItem.new("service_summon_soldier", "Summon Soldier", "Summon a friendly soldier to fight alongside you for 60 seconds.", ShopCategory.SERVICES, 250)
	summon_soldier.rarity = 1
	summon_soldier.stock = -1
	shop_items["service_summon_soldier"] = summon_soldier

	var summon_sniper = ShopItem.new("service_summon_sniper", "Summon Sniper", "Summon a sniper for long-range support. 60 second duration.", ShopCategory.SERVICES, 400)
	summon_sniper.rarity = 2
	summon_sniper.level_requirement = 5
	summon_sniper.stock = -1
	shop_items["service_summon_sniper"] = summon_sniper

	var summon_medic = ShopItem.new("service_summon_medic", "Summon Medic", "Summon a medic to heal you and allies. 60 second duration.", ShopCategory.SERVICES, 350)
	summon_medic.rarity = 2
	summon_medic.level_requirement = 4
	summon_medic.stock = -1
	shop_items["service_summon_medic"] = summon_medic

	var summon_tank = ShopItem.new("service_summon_tank", "Summon Tank", "Summon a heavily armored tank unit. 60 second duration.", ShopCategory.SERVICES, 600)
	summon_tank.rarity = 3
	summon_tank.level_requirement = 8
	summon_tank.stock = -1
	shop_items["service_summon_tank"] = summon_tank

	# Weapon Upgrades (uses WeaponUpgradeSystem)
	var upgrade_damage = ShopItem.new("service_upgrade_damage", "Damage Upgrade", "Increase equipped weapon damage by 15%.", ShopCategory.SERVICES, 100)
	upgrade_damage.rarity = 1
	upgrade_damage.stock = -1
	shop_items["service_upgrade_damage"] = upgrade_damage

	var upgrade_fire_rate = ShopItem.new("service_upgrade_fire_rate", "Fire Rate Upgrade", "Increase equipped weapon fire rate by 10%.", ShopCategory.SERVICES, 80)
	upgrade_fire_rate.rarity = 1
	upgrade_fire_rate.stock = -1
	shop_items["service_upgrade_fire_rate"] = upgrade_fire_rate

	var upgrade_magazine = ShopItem.new("service_upgrade_magazine", "Magazine Upgrade", "Increase equipped weapon magazine size by 25%.", ShopCategory.SERVICES, 60)
	upgrade_magazine.rarity = 0
	upgrade_magazine.stock = -1
	shop_items["service_upgrade_magazine"] = upgrade_magazine

	var upgrade_elemental_fire = ShopItem.new("service_upgrade_fire", "Incendiary Rounds", "Add fire damage to equipped weapon. Burns enemies.", ShopCategory.SERVICES, 200)
	upgrade_elemental_fire.rarity = 2
	upgrade_elemental_fire.level_requirement = 5
	upgrade_elemental_fire.stock = -1
	shop_items["service_upgrade_fire"] = upgrade_elemental_fire

	var upgrade_elemental_ice = ShopItem.new("service_upgrade_ice", "Cryo Rounds", "Add ice damage to equipped weapon. Slows enemies.", ShopCategory.SERVICES, 200)
	upgrade_elemental_ice.rarity = 2
	upgrade_elemental_ice.level_requirement = 5
	upgrade_elemental_ice.stock = -1
	shop_items["service_upgrade_ice"] = upgrade_elemental_ice

	var upgrade_elemental_electric = ShopItem.new("service_upgrade_electric", "Tesla Rounds", "Add electric damage. Chance to chain to nearby enemies.", ShopCategory.SERVICES, 250)
	upgrade_elemental_electric.rarity = 3
	upgrade_elemental_electric.level_requirement = 7
	upgrade_elemental_electric.stock = -1
	shop_items["service_upgrade_electric"] = upgrade_elemental_electric

	# ============================================
	# GEAR - Helmets
	# ============================================
	var helmet_basic = ShopItem.new("gear_helmet_basic", "Basic Helmet", "Simple protection for your head. +5 Armor.", ShopCategory.GEAR, 150)
	helmet_basic.rarity = 0
	helmet_basic.item_data = _create_gear_data("helmet", "basic", 5, {})
	shop_items["gear_helmet_basic"] = helmet_basic

	var helmet_military = ShopItem.new("gear_helmet_military", "Military Helmet", "Standard issue military headgear. +12 Armor, +5% Headshot Resistance.", ShopCategory.GEAR, 400)
	helmet_military.rarity = 1
	helmet_military.level_requirement = 3
	helmet_military.item_data = _create_gear_data("helmet", "military", 12, {"headshot_resist": 0.05})
	shop_items["gear_helmet_military"] = helmet_military

	var helmet_tactical = ShopItem.new("gear_helmet_tactical", "Tactical Helmet", "Advanced tactical headgear. +20 Armor, +10% Headshot Resistance, +5 Stamina.", ShopCategory.GEAR, 800)
	helmet_tactical.rarity = 2
	helmet_tactical.level_requirement = 6
	helmet_tactical.item_data = _create_gear_data("helmet", "tactical", 20, {"headshot_resist": 0.10, "stamina": 5})
	shop_items["gear_helmet_tactical"] = helmet_tactical

	var helmet_juggernaut = ShopItem.new("gear_helmet_juggernaut", "Juggernaut Helmet", "Heavy duty protection. +35 Armor, +20% Headshot Resistance, -5% Movement Speed.", ShopCategory.GEAR, 1500)
	helmet_juggernaut.rarity = 3
	helmet_juggernaut.level_requirement = 10
	helmet_juggernaut.item_data = _create_gear_data("helmet", "juggernaut", 35, {"headshot_resist": 0.20, "movement_speed": -0.05})
	shop_items["gear_helmet_juggernaut"] = helmet_juggernaut

	# ============================================
	# GEAR - Chest Armor
	# ============================================
	var chest_vest = ShopItem.new("gear_chest_vest", "Kevlar Vest", "Basic ballistic protection. +10 Armor.", ShopCategory.GEAR, 200)
	chest_vest.rarity = 0
	chest_vest.item_data = _create_gear_data("chest", "vest", 10, {})
	shop_items["gear_chest_vest"] = chest_vest

	var chest_tactical = ShopItem.new("gear_chest_tactical", "Tactical Vest", "Military-grade protection with pouches. +18 Armor, +10 Max Ammo Capacity.", ShopCategory.GEAR, 500)
	chest_tactical.rarity = 1
	chest_tactical.level_requirement = 4
	chest_tactical.item_data = _create_gear_data("chest", "tactical", 18, {"ammo_capacity": 10})
	shop_items["gear_chest_tactical"] = chest_tactical

	var chest_heavy = ShopItem.new("gear_chest_heavy", "Heavy Body Armor", "Maximum protection. +30 Armor, +20 Health, -10% Movement Speed.", ShopCategory.GEAR, 1000)
	chest_heavy.rarity = 2
	chest_heavy.level_requirement = 7
	chest_heavy.item_data = _create_gear_data("chest", "heavy", 30, {"health": 20, "movement_speed": -0.10})
	shop_items["gear_chest_heavy"] = chest_heavy

	var chest_exo = ShopItem.new("gear_chest_exo", "Exoskeleton Frame", "Advanced powered armor. +25 Armor, +15 Strength, +10% Movement Speed.", ShopCategory.GEAR, 2500)
	chest_exo.rarity = 4
	chest_exo.level_requirement = 12
	chest_exo.item_data = _create_gear_data("chest", "exo", 25, {"strength": 15, "movement_speed": 0.10})
	shop_items["gear_chest_exo"] = chest_exo

	# ============================================
	# GEAR - Gloves
	# ============================================
	var gloves_basic = ShopItem.new("gear_gloves_basic", "Work Gloves", "Improved grip. +3% Reload Speed.", ShopCategory.GEAR, 100)
	gloves_basic.rarity = 0
	gloves_basic.item_data = _create_gear_data("gloves", "basic", 2, {"reload_speed": 0.03})
	shop_items["gear_gloves_basic"] = gloves_basic

	var gloves_tactical = ShopItem.new("gear_gloves_tactical", "Tactical Gloves", "Enhanced weapon handling. +8% Reload Speed, +5% Accuracy.", ShopCategory.GEAR, 350)
	gloves_tactical.rarity = 1
	gloves_tactical.level_requirement = 3
	gloves_tactical.item_data = _create_gear_data("gloves", "tactical", 4, {"reload_speed": 0.08, "accuracy": 0.05})
	shop_items["gear_gloves_tactical"] = gloves_tactical

	var gloves_marksman = ShopItem.new("gear_gloves_marksman", "Marksman Gloves", "Precision shooting gloves. +5% Crit Chance, +10% Accuracy, +5% Headshot Damage.", ShopCategory.GEAR, 700)
	gloves_marksman.rarity = 2
	gloves_marksman.level_requirement = 6
	gloves_marksman.item_data = _create_gear_data("gloves", "marksman", 5, {"crit_chance": 0.05, "accuracy": 0.10, "headshot_damage": 0.05})
	shop_items["gear_gloves_marksman"] = gloves_marksman

	# ============================================
	# GEAR - Boots
	# ============================================
	var boots_basic = ShopItem.new("gear_boots_basic", "Combat Boots", "Sturdy footwear. +5% Movement Speed.", ShopCategory.GEAR, 150)
	boots_basic.rarity = 0
	boots_basic.item_data = _create_gear_data("boots", "basic", 3, {"movement_speed": 0.05})
	shop_items["gear_boots_basic"] = boots_basic

	var boots_runner = ShopItem.new("gear_boots_runner", "Runner's Boots", "Lightweight speed boots. +12% Movement Speed, +10 Stamina.", ShopCategory.GEAR, 400)
	boots_runner.rarity = 1
	boots_runner.level_requirement = 4
	boots_runner.item_data = _create_gear_data("boots", "runner", 2, {"movement_speed": 0.12, "stamina": 10})
	shop_items["gear_boots_runner"] = boots_runner

	var boots_tank = ShopItem.new("gear_boots_tank", "Heavy Boots", "Armored boots for survivability. +8 Armor, +5% Poison Resistance, -5% Movement Speed.", ShopCategory.GEAR, 600)
	boots_tank.rarity = 2
	boots_tank.level_requirement = 6
	boots_tank.item_data = _create_gear_data("boots", "tank", 8, {"poison_resist": 0.05, "movement_speed": -0.05})
	shop_items["gear_boots_tank"] = boots_tank

	# ============================================
	# GEAR - Accessories (Rings & Amulets)
	# ============================================
	var ring_luck = ShopItem.new("gear_ring_luck", "Lucky Ring", "+3 Luck. Increases loot quality.", ShopCategory.GEAR, 300)
	ring_luck.rarity = 1
	ring_luck.item_data = _create_gear_data("ring", "luck", 0, {"luck": 3})
	shop_items["gear_ring_luck"] = ring_luck

	var ring_vitality = ShopItem.new("gear_ring_vitality", "Ring of Vitality", "+5 Vitality. Increases max health.", ShopCategory.GEAR, 350)
	ring_vitality.rarity = 1
	ring_vitality.item_data = _create_gear_data("ring", "vitality", 0, {"vitality": 5})
	shop_items["gear_ring_vitality"] = ring_vitality

	var ring_power = ShopItem.new("gear_ring_power", "Ring of Power", "+5 Strength. Increases melee damage.", ShopCategory.GEAR, 400)
	ring_power.rarity = 2
	ring_power.level_requirement = 5
	ring_power.item_data = _create_gear_data("ring", "power", 0, {"strength": 5})
	shop_items["gear_ring_power"] = ring_power

	var ring_crit = ShopItem.new("gear_ring_crit", "Critical Strike Ring", "+8% Crit Chance, +15% Crit Damage.", ShopCategory.GEAR, 800)
	ring_crit.rarity = 3
	ring_crit.level_requirement = 8
	ring_crit.item_data = _create_gear_data("ring", "crit", 0, {"crit_chance": 0.08, "crit_damage": 0.15})
	shop_items["gear_ring_crit"] = ring_crit

	var amulet_regen = ShopItem.new("gear_amulet_regen", "Amulet of Regeneration", "+2 Health Regen/sec. Passive healing.", ShopCategory.GEAR, 450)
	amulet_regen.rarity = 1
	amulet_regen.level_requirement = 4
	amulet_regen.item_data = _create_gear_data("amulet", "regen", 0, {"health_regen": 2.0})
	shop_items["gear_amulet_regen"] = amulet_regen

	var amulet_protection = ShopItem.new("gear_amulet_protection", "Amulet of Protection", "+10% Damage Reduction from all sources.", ShopCategory.GEAR, 600)
	amulet_protection.rarity = 2
	amulet_protection.level_requirement = 6
	amulet_protection.item_data = _create_gear_data("amulet", "protection", 5, {"damage_reduction": 0.10})
	shop_items["gear_amulet_protection"] = amulet_protection

	var amulet_berserker = ShopItem.new("gear_amulet_berserker", "Berserker's Pendant", "+15% Damage, -10% Armor. High risk, high reward.", ShopCategory.GEAR, 900)
	amulet_berserker.rarity = 3
	amulet_berserker.level_requirement = 8
	amulet_berserker.item_data = _create_gear_data("amulet", "berserker", -5, {"damage_bonus": 0.15})
	shop_items["gear_amulet_berserker"] = amulet_berserker

	# ============================================
	# AUGMENTS - Damage Types
	# ============================================
	var aug_fire = ShopItem.new("augment_fire", "Fire Augment", "Adds fire damage to your weapon. Burns enemies over time.", ShopCategory.AUGMENTS, 500)
	aug_fire.rarity = 2
	aug_fire.level_requirement = 5
	aug_fire.item_data = _create_augment_data("fire_damage", 15.0, "Adds 15 fire damage. Burns for 5 damage/sec.")
	shop_items["augment_fire"] = aug_fire

	var aug_ice = ShopItem.new("augment_ice", "Ice Augment", "Adds ice damage. Slows enemies on hit.", ShopCategory.AUGMENTS, 500)
	aug_ice.rarity = 2
	aug_ice.level_requirement = 5
	aug_ice.item_data = _create_augment_data("ice_damage", 10.0, "Adds 10 ice damage. Slows enemies by 30%.")
	shop_items["augment_ice"] = aug_ice

	var aug_poison = ShopItem.new("augment_poison", "Poison Augment", "Adds poison damage. Deals damage over time.", ShopCategory.AUGMENTS, 450)
	aug_poison.rarity = 2
	aug_poison.level_requirement = 4
	aug_poison.item_data = _create_augment_data("poison_damage", 8.0, "Adds 8 poison damage/sec for 5 seconds.")
	shop_items["augment_poison"] = aug_poison

	var aug_bleed = ShopItem.new("augment_bleed", "Bleed Augment", "Causes bleeding. Deals physical damage over time.", ShopCategory.AUGMENTS, 400)
	aug_bleed.rarity = 1
	aug_bleed.level_requirement = 3
	aug_bleed.item_data = _create_augment_data("bleed_damage", 6.0, "Causes 6 bleed damage/sec for 4 seconds.")
	shop_items["augment_bleed"] = aug_bleed

	var aug_lightning = ShopItem.new("augment_lightning", "Lightning Augment", "Adds lightning damage. Chance to chain to nearby enemies.", ShopCategory.AUGMENTS, 600)
	aug_lightning.rarity = 3
	aug_lightning.level_requirement = 7
	aug_lightning.item_data = _create_augment_data("lightning_damage", 20.0, "Adds 20 lightning damage. 15% chance to chain.")
	shop_items["augment_lightning"] = aug_lightning

	# ============================================
	# AUGMENTS - Stat Bonuses
	# ============================================
	var aug_damage = ShopItem.new("augment_damage", "Damage Augment", "+10% weapon damage.", ShopCategory.AUGMENTS, 350)
	aug_damage.rarity = 1
	aug_damage.level_requirement = 3
	aug_damage.item_data = _create_augment_data("damage_bonus", 0.10, "+10% base weapon damage.")
	shop_items["augment_damage"] = aug_damage

	var aug_crit = ShopItem.new("augment_crit", "Critical Augment", "+5% critical hit chance.", ShopCategory.AUGMENTS, 400)
	aug_crit.rarity = 2
	aug_crit.level_requirement = 4
	aug_crit.item_data = _create_augment_data("crit_chance", 0.05, "+5% critical hit chance.")
	shop_items["augment_crit"] = aug_crit

	var aug_armor_pierce = ShopItem.new("augment_armor_pierce", "Piercing Augment", "Ignores 25% of enemy armor.", ShopCategory.AUGMENTS, 500)
	aug_armor_pierce.rarity = 2
	aug_armor_pierce.level_requirement = 6
	aug_armor_pierce.item_data = _create_augment_data("armor_penetration", 0.25, "Ignores 25% of enemy armor.")
	shop_items["augment_armor_pierce"] = aug_armor_pierce

	var aug_lifesteal = ShopItem.new("augment_lifesteal", "Vampiric Augment", "Heal 5% of damage dealt.", ShopCategory.AUGMENTS, 700)
	aug_lifesteal.rarity = 3
	aug_lifesteal.level_requirement = 8
	aug_lifesteal.item_data = _create_augment_data("life_steal", 0.05, "Heal for 5% of damage dealt.")
	shop_items["augment_lifesteal"] = aug_lifesteal

	var aug_headshot = ShopItem.new("augment_headshot", "Precision Augment", "+20% headshot damage.", ShopCategory.AUGMENTS, 450)
	aug_headshot.rarity = 2
	aug_headshot.level_requirement = 5
	aug_headshot.item_data = _create_augment_data("headshot_bonus", 0.20, "+20% damage on headshots.")
	shop_items["augment_headshot"] = aug_headshot

	# ============================================
	# AUGMENTS - Special Effects
	# ============================================
	var aug_explosive = ShopItem.new("augment_explosive", "Explosive Augment", "15% chance to cause an explosion on hit.", ShopCategory.AUGMENTS, 800)
	aug_explosive.rarity = 3
	aug_explosive.level_requirement = 9
	aug_explosive.item_data = _create_augment_data("explosive_chance", 0.15, "15% chance for 30 damage explosion in 3m.")
	shop_items["augment_explosive"] = aug_explosive

	var aug_chain = ShopItem.new("augment_chain", "Chain Augment", "Bullets can chain to nearby enemies.", ShopCategory.AUGMENTS, 900)
	aug_chain.rarity = 3
	aug_chain.level_requirement = 10
	aug_chain.item_data = _create_augment_data("chain_chance", 0.20, "20% chance to chain to enemy within 5m for 50% damage.")
	shop_items["augment_chain"] = aug_chain

	var aug_execute = ShopItem.new("augment_execute", "Executioner Augment", "+50% damage to enemies below 25% HP.", ShopCategory.AUGMENTS, 750)
	aug_execute.rarity = 3
	aug_execute.level_requirement = 8
	aug_execute.item_data = _create_augment_data("execute_bonus", 0.50, "+50% damage to low health enemies.")
	shop_items["augment_execute"] = aug_execute

	var aug_boss_killer = ShopItem.new("augment_boss_killer", "Slayer Augment", "+30% damage to bosses and elite enemies.", ShopCategory.AUGMENTS, 1000)
	aug_boss_killer.rarity = 4
	aug_boss_killer.level_requirement = 12
	aug_boss_killer.item_data = _create_augment_data("boss_damage", 0.30, "+30% damage to bosses and elites.")
	shop_items["augment_boss_killer"] = aug_boss_killer

	# ============================================
	# BACKPACKS - Inventory Expansion
	# ============================================
	var bp_basic = ShopItem.new("backpack_basic", "Basic Backpack", "A simple canvas backpack. +1 row, +5 weight capacity.", ShopCategory.BACKPACKS, 300)
	bp_basic.rarity = 0
	bp_basic.item_data = _create_backpack_data("Basic Backpack", 1, 5.0, Vector2i(2, 2))
	shop_items["backpack_basic"] = bp_basic

	var bp_military = ShopItem.new("backpack_military", "Military Backpack", "Sturdy military-grade pack. +2 rows, +15 weight capacity.", ShopCategory.BACKPACKS, 800)
	bp_military.rarity = 1
	bp_military.level_requirement = 3
	bp_military.item_data = _create_backpack_data("Military Backpack", 2, 15.0, Vector2i(3, 3))
	shop_items["backpack_military"] = bp_military

	var bp_tactical = ShopItem.new("backpack_tactical", "Tactical Backpack", "High-capacity tactical pack. +3 rows, +20 weight capacity.", ShopCategory.BACKPACKS, 1500)
	bp_tactical.rarity = 2
	bp_tactical.level_requirement = 6
	bp_tactical.item_data = _create_backpack_data("Tactical Backpack", 3, 20.0, Vector2i(3, 3))
	shop_items["backpack_tactical"] = bp_tactical

	var bp_survivor = ShopItem.new("backpack_survivor", "Survivor's Pack", "A well-worn pack that has seen many apocalypses. +4 rows, +25 weight.", ShopCategory.BACKPACKS, 3000)
	bp_survivor.rarity = 3
	bp_survivor.level_requirement = 10
	bp_survivor.item_data = _create_backpack_data("Survivor's Pack", 4, 25.0, Vector2i(3, 3))
	shop_items["backpack_survivor"] = bp_survivor

	var bp_void = ShopItem.new("backpack_void", "Void Carrier", "Rumored to contain a pocket dimension. +5 rows, +40 weight capacity.", ShopCategory.BACKPACKS, 8000)
	bp_void.rarity = 4
	bp_void.level_requirement = 15
	bp_void.item_data = _create_backpack_data("Void Carrier", 5, 40.0, Vector2i(4, 4))
	shop_items["backpack_void"] = bp_void

func _load_weapon_resource(weapon_name: String) -> Resource:
	var path = "res://resources/weapons/%s.tres" % weapon_name
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _create_gear_data(slot_type: String, subtype: String, armor: float, bonuses: Dictionary) -> ItemDataExtended:
	"""Create gear item data dynamically"""
	var item = ItemDataExtended.new()

	# Set basic info
	item.item_name = "%s %s" % [subtype.capitalize(), slot_type.capitalize()]

	# Set item type based on slot
	match slot_type:
		"helmet":
			item.item_type = ItemDataExtended.ItemType.HELMET
		"chest":
			item.item_type = ItemDataExtended.ItemType.CHEST_ARMOR
		"gloves":
			item.item_type = ItemDataExtended.ItemType.GLOVES
		"boots":
			item.item_type = ItemDataExtended.ItemType.BOOTS
		"ring":
			item.item_type = ItemDataExtended.ItemType.RING
		"amulet":
			item.item_type = ItemDataExtended.ItemType.AMULET

	# Set armor
	item.armor_value = armor

	# Apply bonuses
	for key in bonuses:
		match key:
			"health": item.health_bonus = bonuses[key]
			"stamina": item.stamina_bonus = bonuses[key]
			"strength": item.strength_bonus = bonuses[key]
			"agility": item.agility_bonus = bonuses[key]
			"vitality": item.vitality_bonus = bonuses[key]
			"luck":
				# Store as metadata since no direct property
				item.set_meta("luck_bonus", bonuses[key])
			"crit_chance": item.crit_chance_bonus = bonuses[key]
			"crit_damage": item.crit_damage_bonus = bonuses[key]
			"headshot_damage": item.headshot_bonus = bonuses[key]
			"headshot_resist":
				item.set_meta("headshot_resist", bonuses[key])
			"movement_speed": item.movement_speed_bonus = bonuses[key]
			"attack_speed": item.attack_speed_bonus = bonuses[key]
			"reload_speed":
				item.set_meta("reload_speed_bonus", bonuses[key])
			"accuracy":
				item.set_meta("accuracy_bonus", bonuses[key])
			"health_regen": item.health_regen_bonus = bonuses[key]
			"stamina_regen": item.stamina_regen_bonus = bonuses[key]
			"damage_reduction":
				item.set_meta("damage_reduction", bonuses[key])
			"damage_bonus":
				item.set_meta("damage_bonus", bonuses[key])
			"poison_resist": item.poison_resistance = bonuses[key]
			"fire_resist": item.fire_resistance = bonuses[key]
			"ice_resist": item.ice_resistance = bonuses[key]
			"ammo_capacity":
				item.set_meta("ammo_capacity_bonus", bonuses[key])

	return item

func _create_augment_data(stat_type: String, stat_value: float, effect_description: String) -> ItemDataExtended:
	"""Create augment item data dynamically"""
	var item = ItemDataExtended.new()

	item.item_type = ItemDataExtended.ItemType.AUGMENT
	item.item_name = stat_type.capitalize().replace("_", " ") + " Augment"
	item.description = effect_description
	item.augment_stat_type = stat_type
	item.augment_stat_value = stat_value
	item.stack_size = 1

	return item

func _create_backpack_data(bp_name: String, extra_rows: int, extra_weight: float, grid_size: Vector2i) -> Resource:
	"""Create backpack item data"""
	var item = ItemDataExtended.new()

	item.item_type = ItemDataExtended.ItemType.MATERIAL  # Backpack treated as material until equipped
	item.item_name = bp_name
	item.description = "+%d inventory rows, +%.0f weight capacity" % [extra_rows, extra_weight]
	item.stack_size = 1
	item.weight = 2.0

	# Store backpack properties as metadata
	item.set_meta("is_backpack", true)
	item.set_meta("extra_rows", extra_rows)
	item.set_meta("extra_weight", extra_weight)
	item.set_meta("grid_size", grid_size)

	return item

# ============================================
# SHOP OPERATIONS
# ============================================

func get_items_by_category(category: ShopCategory) -> Array[ShopItem]:
	var items: Array[ShopItem] = []
	for key in shop_items:
		var item = shop_items[key]
		if item.category == category:
			items.append(item)
	# Sort by cost
	items.sort_custom(func(a, b): return a.cost < b.cost)
	return items

func get_all_items() -> Array[ShopItem]:
	var items: Array[ShopItem] = []
	for key in shop_items:
		items.append(shop_items[key])
	return items

func can_afford(item_id: String) -> bool:
	if not shop_items.has(item_id):
		return false
	return current_sigils >= shop_items[item_id].cost

func can_purchase(item_id: String, player_level: int = 1) -> Dictionary:
	if not shop_items.has(item_id):
		return {"can_buy": false, "reason": "Item not found"}

	var item = shop_items[item_id]

	# Check level requirement
	if player_level < item.level_requirement:
		return {"can_buy": false, "reason": "Requires level %d" % item.level_requirement}

	# Check stock
	if item.stock == 0:
		return {"can_buy": false, "reason": "Out of stock"}

	# Check currency
	if current_sigils < item.cost:
		return {"can_buy": false, "reason": "Not enough sigils (%d needed)" % item.cost}

	return {"can_buy": true, "reason": ""}

func purchase_item(item_id: String, player: Node = null) -> bool:
	if not shop_items.has(item_id):
		purchase_failed.emit("Item not found")
		return false

	var item = shop_items[item_id]

	# Get player level
	var player_level = 1
	if player and "character_attributes" in player and player.character_attributes:
		player_level = player.character_attributes.level
	elif player_persistence:
		player_level = player_persistence.player_data.character.level

	var check = can_purchase(item_id, player_level)
	if not check.can_buy:
		purchase_failed.emit(check.reason)
		return false

	# Deduct sigils
	current_sigils -= item.cost
	if player_persistence:
		player_persistence.spend_currency("sigils", item.cost)

	# Update stock
	if item.stock > 0:
		item.stock -= 1

	# Handle different item types
	match item.category:
		ShopCategory.WEAPONS:
			_give_weapon(item, player)
		ShopCategory.AMMO:
			_give_ammo(item, player)
		ShopCategory.MATERIALS:
			_give_material(item)
		ShopCategory.CONSUMABLES:
			_give_consumable(item, player)
		ShopCategory.SERVICES:
			_apply_service(item, player)

	sigils_changed.emit(current_sigils)
	item_purchased.emit(item.name, item.cost)
	return true

func _give_weapon(item: ShopItem, player: Node):
	if not player:
		return

	if item.item_data and player.has_method("pickup_weapon"):
		player.pickup_weapon(item.item_data)
	elif inventory_system and item.item_data:
		inventory_system.add_item(item.item_data, 1)

func _give_ammo(item: ShopItem, player: Node):
	if not player:
		return

	# Add ammo directly to player's reserve
	if "reserve_ammo" in player:
		player.reserve_ammo += item.quantity

	# Also try to add to inventory if available
	if inventory_system:
		# Create ammo item data if needed
		pass

func _give_material(item: ShopItem):
	# Add to persistence storage
	if player_persistence:
		var material_key = item.id.replace("material_", "")
		if not player_persistence.player_data.has("materials"):
			player_persistence.player_data["materials"] = {}

		if player_persistence.player_data.materials.has(material_key):
			player_persistence.player_data.materials[material_key] += item.quantity
		else:
			player_persistence.player_data.materials[material_key] = item.quantity

func _give_consumable(item: ShopItem, player: Node):
	if not player:
		return

	# Apply consumable effect immediately or add to inventory
	match item.id:
		"consumable_health":
			if player.has_method("heal"):
				player.heal(50)
		"consumable_health_large":
			if player.has_method("heal"):
				player.heal(100)
		"consumable_stamina":
			if "current_stamina" in player and "max_stamina" in player:
				player.current_stamina = player.max_stamina
		"consumable_damage":
			if player.has_method("apply_status_effect"):
				player.apply_status_effect("damage_boost", 0.25, 60.0)
		"consumable_speed":
			if player.has_method("apply_status_effect"):
				player.apply_status_effect("speed_boost", 0.30, 60.0)
		"consumable_armor":
			if player.has_method("apply_status_effect"):
				player.apply_status_effect("temp_armor", 50.0, 120.0)

func _apply_service(item: ShopItem, player: Node):
	if not player:
		return

	match item.id:
		"service_respec":
			if "skill_tree" in player and player.skill_tree:
				if player.skill_tree.has_method("reset_skills"):
					player.skill_tree.reset_skills()
		"service_attr_reset":
			if "character_attributes" in player and player.character_attributes:
				if player.character_attributes.has_method("reset_attributes"):
					player.character_attributes.reset_attributes()
		"service_repair":
			if "current_weapon_data" in player and player.current_weapon_data:
				if "durability" in player.current_weapon_data and "max_durability" in player.current_weapon_data:
					player.current_weapon_data.durability = player.current_weapon_data.max_durability
		# Turrets
		"service_turret_basic":
			_spawn_turret(player, Turret.TurretType.BASIC)
		"service_turret_heavy":
			_spawn_turret(player, Turret.TurretType.HEAVY)
		"service_turret_flame":
			_spawn_turret(player, Turret.TurretType.FLAME)
		"service_turret_tesla":
			_spawn_turret(player, Turret.TurretType.TESLA)
		# Friendly AI Summons
		"service_summon_soldier":
			_spawn_ally(player, FriendlyAI.AIType.SOLDIER)
		"service_summon_sniper":
			_spawn_ally(player, FriendlyAI.AIType.SNIPER)
		"service_summon_medic":
			_spawn_ally(player, FriendlyAI.AIType.MEDIC)
		"service_summon_tank":
			_spawn_ally(player, FriendlyAI.AIType.TANK)
		# Weapon Upgrades
		"service_upgrade_damage":
			_apply_weapon_upgrade(player, WeaponUpgradeSystem.UpgradeType.DAMAGE)
		"service_upgrade_fire_rate":
			_apply_weapon_upgrade(player, WeaponUpgradeSystem.UpgradeType.FIRE_RATE)
		"service_upgrade_magazine":
			_apply_weapon_upgrade(player, WeaponUpgradeSystem.UpgradeType.MAGAZINE_SIZE)
		"service_upgrade_fire":
			_apply_weapon_upgrade(player, WeaponUpgradeSystem.UpgradeType.ELEMENTAL_FIRE)
		"service_upgrade_ice":
			_apply_weapon_upgrade(player, WeaponUpgradeSystem.UpgradeType.ELEMENTAL_ICE)
		"service_upgrade_electric":
			_apply_weapon_upgrade(player, WeaponUpgradeSystem.UpgradeType.ELEMENTAL_ELECTRIC)

func _spawn_turret(player: Node, turret_type: int):
	"""Spawn a turret in front of the player"""
	var spawn_pos = player.global_position + (-player.global_transform.basis.z * 2)
	spawn_pos.y = player.global_position.y

	var turret = Turret.create_turret(turret_type as Turret.TurretType)
	turret.global_position = spawn_pos
	get_tree().current_scene.add_child(turret)

	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message("Turret deployed!")

func _spawn_ally(player: Node, ally_type: int):
	"""Spawn a friendly AI ally"""
	var spawn_pos = player.global_position + (player.global_transform.basis.x * 2)
	spawn_pos.y = player.global_position.y

	var ally = FriendlyAI.spawn_ally(ally_type as FriendlyAI.AIType, spawn_pos, player)
	get_tree().current_scene.add_child(ally)

	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message("Ally summoned: %s" % ally.ai_name)

func _apply_weapon_upgrade(player: Node, upgrade_type: int):
	"""Apply a weapon upgrade to the player's equipped weapon"""
	if not player or not "inventory" in player:
		return

	var equipped = player.inventory.equipped_weapon if player.inventory else null
	if not equipped or equipped.is_empty():
		if has_node("/root/ChatSystem"):
			get_node("/root/ChatSystem").emit_system_message("No weapon equipped to upgrade!")
		# Refund sigils
		add_sigils(shop_items.values().filter(func(i): return i.id.contains("upgrade")).front().cost, "Refund")
		return

	var weapon_data = equipped.get("item")
	if not weapon_data:
		return

	# Get or create weapon upgrade system
	var upgrade_system = get_tree().get_first_node_in_group("weapon_upgrade_system")
	if not upgrade_system:
		upgrade_system = WeaponUpgradeSystem.new()
		upgrade_system.name = "WeaponUpgradeSystem"
		get_tree().current_scene.add_child(upgrade_system)

	# Apply upgrade (cost already deducted by shop)
	if upgrade_system.can_upgrade(weapon_data, upgrade_type as WeaponUpgradeSystem.UpgradeType):
		var weapon_id = str(weapon_data.get_instance_id())
		if weapon_id not in upgrade_system.weapon_upgrades:
			upgrade_system.weapon_upgrades[weapon_id] = {}
		var current_level = upgrade_system.weapon_upgrades[weapon_id].get(upgrade_type, 0)
		upgrade_system.weapon_upgrades[weapon_id][upgrade_type] = current_level + 1

		if has_node("/root/ChatSystem"):
			var weapon_name = weapon_data.item_name if "item_name" in weapon_data else "Weapon"
			get_node("/root/ChatSystem").emit_system_message("%s upgraded!" % weapon_name)
	else:
		if has_node("/root/ChatSystem"):
			get_node("/root/ChatSystem").emit_system_message("Cannot upgrade further!")

# ============================================
# SIGIL CURRENCY MANAGEMENT
# ============================================

func add_sigils(amount: int, reason: String = ""):
	current_sigils += amount
	if player_persistence:
		player_persistence.add_currency("sigils", amount)
	sigils_changed.emit(current_sigils)

	if reason != "" and has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message("+%d Sigils: %s" % [amount, reason])

func spend_sigils(amount: int) -> bool:
	if current_sigils < amount:
		return false

	current_sigils -= amount
	if player_persistence:
		player_persistence.spend_currency("sigils", amount)
	sigils_changed.emit(current_sigils)
	return true

func get_sigils() -> int:
	return current_sigils

func sync_from_persistence():
	if player_persistence:
		current_sigils = player_persistence.get_currency("sigils")
		sigils_changed.emit(current_sigils)

# ============================================
# UTILITY
# ============================================

func get_category_name(category: ShopCategory) -> String:
	match category:
		ShopCategory.WEAPONS: return "Weapons"
		ShopCategory.AMMO: return "Ammunition"
		ShopCategory.MATERIALS: return "Materials"
		ShopCategory.CONSUMABLES: return "Consumables"
		ShopCategory.GEAR: return "Gear"
		ShopCategory.BACKPACKS: return "Backpacks"
		ShopCategory.AUGMENTS: return "Augments"
		ShopCategory.SERVICES: return "Services"
	return "Unknown"

func get_item_tooltip(item_id: String) -> String:
	if not shop_items.has(item_id):
		return ""

	var item = shop_items[item_id]
	var tooltip = "[b][color=%s]%s[/color][/b]\n" % [item.get_rarity_color().to_html(), item.name]
	tooltip += "[color=gray]%s[/color]\n\n" % item.get_rarity_name()
	tooltip += "%s\n\n" % item.description

	if item.level_requirement > 1:
		tooltip += "[color=yellow]Requires Level %d[/color]\n" % item.level_requirement

	if item.quantity > 1:
		tooltip += "Quantity: %d\n" % item.quantity

	if item.item_data:
		tooltip += "\n" + _get_item_stats_text(item.item_data)

	tooltip += "\n[color=cyan]Cost: %d Sigils[/color]" % item.cost

	return tooltip

func _get_item_stats_text(item_data: Resource) -> String:
	var text = ""

	if "damage" in item_data and item_data.damage > 0:
		text += "Damage: %.1f\n" % item_data.damage
	if "fire_rate" in item_data and item_data.fire_rate > 0:
		text += "Fire Rate: %.1f/s\n" % (1.0 / item_data.fire_rate)
	if "magazine_size" in item_data and item_data.magazine_size > 0:
		text += "Magazine: %d\n" % item_data.magazine_size
	if "reload_time" in item_data and item_data.reload_time > 0:
		text += "Reload: %.1fs\n" % item_data.reload_time
	if "weapon_range" in item_data and item_data.weapon_range > 0:
		text += "Range: %.0fm\n" % item_data.weapon_range
	if "accuracy" in item_data and item_data.accuracy < 1.0:
		text += "Accuracy: %.0f%%\n" % (item_data.accuracy * 100)
	if "armor_value" in item_data and item_data.armor_value > 0:
		text += "Armor: %.1f\n" % item_data.armor_value
	if "crit_chance_bonus" in item_data and item_data.crit_chance_bonus > 0:
		text += "+%.1f%% Crit Chance\n" % (item_data.crit_chance_bonus * 100)
	if "crit_damage_bonus" in item_data and item_data.crit_damage_bonus > 0:
		text += "+%.0f%% Crit Damage\n" % (item_data.crit_damage_bonus * 100)

	return text
