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

# Shop categories
enum ShopCategory {
	WEAPONS,
	AMMO,
	MATERIALS,
	CONSUMABLES,
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

func _load_weapon_resource(weapon_name: String) -> Resource:
	var path = "res://resources/weapons/%s.tres" % weapon_name
	if ResourceLoader.exists(path):
		return load(path)
	return null

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
