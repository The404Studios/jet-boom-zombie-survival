extends Node
class_name CraftingSystem

# Crafting system for combining materials into items
# Supports recipe discovery, material requirements, and crafting animations

signal recipe_unlocked(recipe: Resource)
signal crafting_started(recipe: Resource)
signal crafting_completed(recipe: Resource, item: Resource)
signal crafting_failed(recipe: Resource, reason: String)

# Recipe categories
enum RecipeCategory {
	WEAPONS,
	ARMOR,
	CONSUMABLES,
	MATERIALS,
	UPGRADES,
	SPECIAL
}

# All available recipes
var recipes: Array[Resource] = []
var unlocked_recipes: Array[Resource] = []
var crafting_queue: Array[Dictionary] = []

# Player references
var player_persistence: Node = null
var inventory_system: Node = null

# Crafting state
var is_crafting: bool = false
var current_craft_time: float = 0.0
var current_recipe: Resource = null

func _ready():
	player_persistence = get_node_or_null("/root/PlayerPersistence")
	_load_recipes()

func _process(delta):
	if is_crafting and current_recipe:
		current_craft_time -= delta
		if current_craft_time <= 0:
			_complete_crafting()

func _load_recipes():
	"""Load all recipe resources"""
	# Default recipes - these would normally be loaded from resource files
	recipes = []

	# Add default recipes
	_add_default_recipes()

func _add_default_recipes():
	"""Add built-in recipes"""
	# ============================================
	# CONSUMABLES
	# ============================================

	# Health Kit
	var health_kit = _create_recipe(
		"health_kit",
		"Health Kit",
		"Restores 50 health",
		RecipeCategory.CONSUMABLES,
		{"herbs": 2, "bandage": 1},
		null,
		2.0
	)
	recipes.append(health_kit)
	unlocked_recipes.append(health_kit)

	# Large Health Kit
	var large_health_kit = _create_recipe(
		"large_health_kit",
		"Large Health Kit",
		"Restores 100 health",
		RecipeCategory.CONSUMABLES,
		{"herbs": 4, "bandage": 2, "chemicals": 1},
		null,
		3.5
	)
	recipes.append(large_health_kit)
	unlocked_recipes.append(large_health_kit)

	# Stim Pack
	var stim_pack = _create_recipe(
		"stim_pack",
		"Stim Pack",
		"Temporary speed boost (+30% for 20s)",
		RecipeCategory.CONSUMABLES,
		{"chemicals": 2, "syringe": 1},
		null,
		3.0
	)
	recipes.append(stim_pack)
	unlocked_recipes.append(stim_pack)

	# Adrenaline Shot
	var adrenaline = _create_recipe(
		"adrenaline_shot",
		"Adrenaline Shot",
		"Massive speed boost (+50% for 10s)",
		RecipeCategory.CONSUMABLES,
		{"chemicals": 3, "syringe": 1, "rare_compound": 1},
		null,
		4.0
	)
	recipes.append(adrenaline)

	# Damage Boost
	var damage_boost = _create_recipe(
		"damage_boost",
		"Rage Serum",
		"+25% damage for 30 seconds",
		RecipeCategory.CONSUMABLES,
		{"chemicals": 2, "blood_sample": 1, "syringe": 1},
		null,
		3.5
	)
	recipes.append(damage_boost)
	unlocked_recipes.append(damage_boost)

	# Armor Boost
	var armor_boost = _create_recipe(
		"armor_boost",
		"Hardening Serum",
		"+30% damage resistance for 30s",
		RecipeCategory.CONSUMABLES,
		{"chemicals": 2, "scrap_metal": 2, "syringe": 1},
		null,
		3.5
	)
	recipes.append(armor_boost)
	unlocked_recipes.append(armor_boost)

	# Antidote
	var antidote = _create_recipe(
		"antidote",
		"Antidote",
		"Cures poison and infection",
		RecipeCategory.CONSUMABLES,
		{"herbs": 3, "chemicals": 1},
		null,
		2.0
	)
	recipes.append(antidote)
	unlocked_recipes.append(antidote)

	# ============================================
	# AMMUNITION
	# ============================================

	# Ammo Box (Pistol)
	var ammo_pistol = _create_recipe(
		"ammo_pistol",
		"Pistol Ammo (30)",
		"30 rounds of pistol ammunition",
		RecipeCategory.MATERIALS,
		{"scrap_metal": 2, "gunpowder": 1},
		null,
		2.0
	)
	recipes.append(ammo_pistol)
	unlocked_recipes.append(ammo_pistol)

	# Ammo Box (Rifle)
	var ammo_rifle = _create_recipe(
		"ammo_rifle",
		"Rifle Ammo (30)",
		"30 rounds of rifle ammunition",
		RecipeCategory.MATERIALS,
		{"scrap_metal": 3, "gunpowder": 2},
		null,
		3.0
	)
	recipes.append(ammo_rifle)
	unlocked_recipes.append(ammo_rifle)

	# Ammo Box (Shotgun)
	var ammo_shotgun = _create_recipe(
		"ammo_shotgun",
		"Shotgun Shells (12)",
		"12 shotgun shells",
		RecipeCategory.MATERIALS,
		{"scrap_metal": 2, "gunpowder": 2},
		null,
		2.5
	)
	recipes.append(ammo_shotgun)
	unlocked_recipes.append(ammo_shotgun)

	# Ammo Box (Heavy)
	var ammo_heavy = _create_recipe(
		"ammo_heavy",
		"Heavy Ammo (50)",
		"50 rounds of heavy ammunition",
		RecipeCategory.MATERIALS,
		{"scrap_metal": 5, "gunpowder": 3},
		null,
		4.0
	)
	recipes.append(ammo_heavy)

	# ============================================
	# THROWABLES / WEAPONS
	# ============================================

	# Molotov
	var molotov = _create_recipe(
		"molotov",
		"Molotov Cocktail",
		"Throwable fire weapon",
		RecipeCategory.WEAPONS,
		{"bottle": 1, "cloth": 1, "fuel": 1},
		null,
		2.5
	)
	recipes.append(molotov)
	unlocked_recipes.append(molotov)

	# Pipe Bomb
	var pipe_bomb = _create_recipe(
		"pipe_bomb",
		"Pipe Bomb",
		"Timed explosive device",
		RecipeCategory.WEAPONS,
		{"pipe": 1, "gunpowder": 3, "electronics": 1},
		null,
		4.0
	)
	recipes.append(pipe_bomb)

	# Frag Grenade
	var frag_grenade = _create_recipe(
		"frag_grenade",
		"Frag Grenade",
		"High damage explosive",
		RecipeCategory.WEAPONS,
		{"scrap_metal": 3, "gunpowder": 4, "electronics": 1},
		null,
		5.0
	)
	recipes.append(frag_grenade)

	# Nail Bomb
	var nail_bomb = _create_recipe(
		"nail_bomb",
		"Nail Bomb",
		"Shrapnel explosive - high bleed damage",
		RecipeCategory.WEAPONS,
		{"nails": 10, "gunpowder": 3, "pipe": 1},
		null,
		4.5
	)
	recipes.append(nail_bomb)
	unlocked_recipes.append(nail_bomb)

	# Flashbang
	var flashbang = _create_recipe(
		"flashbang",
		"Flashbang",
		"Stuns zombies in area",
		RecipeCategory.WEAPONS,
		{"electronics": 2, "gunpowder": 1, "scrap_metal": 1},
		null,
		3.0
	)
	recipes.append(flashbang)

	# Turret
	var turret = _create_recipe(
		"turret",
		"Auto Turret",
		"Deployable automated defense",
		RecipeCategory.WEAPONS,
		{"scrap_metal": 10, "electronics": 5, "weapon_parts": 3},
		null,
		15.0
	)
	recipes.append(turret)

	# ============================================
	# BARRICADE MATERIALS
	# ============================================

	# Nails
	var nails = _create_recipe(
		"nails",
		"Nails (20)",
		"Used for nailing props and barricades",
		RecipeCategory.MATERIALS,
		{"scrap_metal": 1},
		null,
		1.0
	)
	recipes.append(nails)
	unlocked_recipes.append(nails)

	# Wooden Plank
	var wooden_plank = _create_recipe(
		"wooden_plank",
		"Wooden Plank",
		"Basic barricade material",
		RecipeCategory.MATERIALS,
		{"wood": 2},
		null,
		1.5
	)
	recipes.append(wooden_plank)
	unlocked_recipes.append(wooden_plank)

	# Reinforced Plank
	var reinforced_plank = _create_recipe(
		"reinforced_plank",
		"Reinforced Plank",
		"Stronger barricade material (+50% HP)",
		RecipeCategory.MATERIALS,
		{"wood": 2, "scrap_metal": 1, "nails": 4},
		null,
		3.0
	)
	recipes.append(reinforced_plank)
	unlocked_recipes.append(reinforced_plank)

	# Metal Sheet
	var metal_sheet = _create_recipe(
		"metal_sheet",
		"Metal Sheet",
		"Strong barricade material",
		RecipeCategory.MATERIALS,
		{"scrap_metal": 5},
		null,
		4.0
	)
	recipes.append(metal_sheet)

	# Barricade Kit
	var barricade_kit = _create_recipe(
		"barricade_kit",
		"Barricade Kit",
		"Contains planks and nails for quick barricading",
		RecipeCategory.MATERIALS,
		{"wood": 4, "scrap_metal": 2, "nails": 10},
		null,
		5.0
	)
	recipes.append(barricade_kit)
	unlocked_recipes.append(barricade_kit)

	# ============================================
	# ARMOR / GEAR
	# ============================================

	# Armor Plate
	var armor_plate = _create_recipe(
		"armor_plate",
		"Armor Plate",
		"Reinforced protection (+15 armor)",
		RecipeCategory.ARMOR,
		{"scrap_metal": 5, "cloth": 2},
		null,
		5.0
	)
	recipes.append(armor_plate)
	unlocked_recipes.append(armor_plate)

	# Tactical Vest
	var tactical_vest = _create_recipe(
		"tactical_vest",
		"Tactical Vest",
		"Light armor with ammo pouches",
		RecipeCategory.ARMOR,
		{"cloth": 5, "scrap_metal": 3, "leather": 2},
		null,
		8.0
	)
	recipes.append(tactical_vest)

	# Heavy Armor
	var heavy_armor = _create_recipe(
		"heavy_armor",
		"Heavy Armor",
		"Maximum protection (-10% speed)",
		RecipeCategory.ARMOR,
		{"scrap_metal": 10, "leather": 4, "rare_alloy": 2},
		null,
		12.0
	)
	recipes.append(heavy_armor)

	# Helmet
	var helmet = _create_recipe(
		"helmet",
		"Combat Helmet",
		"Head protection (+10 armor)",
		RecipeCategory.ARMOR,
		{"scrap_metal": 4, "cloth": 1},
		null,
		4.0
	)
	recipes.append(helmet)
	unlocked_recipes.append(helmet)

	# Gas Mask
	var gas_mask = _create_recipe(
		"gas_mask",
		"Gas Mask",
		"Immunity to poison clouds",
		RecipeCategory.ARMOR,
		{"cloth": 2, "rubber": 2, "glass": 1},
		null,
		5.0
	)
	recipes.append(gas_mask)

	# ============================================
	# UPGRADES / AUGMENTS
	# ============================================

	# Weapon Repair Kit
	var repair_kit = _create_recipe(
		"repair_kit",
		"Weapon Repair Kit",
		"Restores weapon durability",
		RecipeCategory.UPGRADES,
		{"scrap_metal": 3, "oil": 1, "cloth": 1},
		null,
		3.0
	)
	recipes.append(repair_kit)
	unlocked_recipes.append(repair_kit)

	# Extended Magazine
	var extended_mag = _create_recipe(
		"extended_magazine",
		"Extended Magazine",
		"+50% magazine capacity",
		RecipeCategory.UPGRADES,
		{"scrap_metal": 4, "weapon_parts": 2},
		null,
		6.0
	)
	recipes.append(extended_mag)

	# Laser Sight
	var laser_sight = _create_recipe(
		"laser_sight",
		"Laser Sight",
		"+15% accuracy",
		RecipeCategory.UPGRADES,
		{"electronics": 3, "glass": 1, "scrap_metal": 2},
		null,
		5.0
	)
	recipes.append(laser_sight)

	# Suppressor
	var suppressor = _create_recipe(
		"suppressor",
		"Suppressor",
		"Reduced noise, slight damage penalty",
		RecipeCategory.UPGRADES,
		{"scrap_metal": 5, "rubber": 2},
		null,
		6.0
	)
	recipes.append(suppressor)

	# Damage Augment
	var damage_augment = _create_recipe(
		"damage_augment",
		"Damage Augment",
		"+10% weapon damage",
		RecipeCategory.UPGRADES,
		{"rare_alloy": 2, "weapon_parts": 3, "augment_crystal": 1},
		null,
		10.0
	)
	recipes.append(damage_augment)

	# Fire Augment
	var fire_augment = _create_recipe(
		"fire_augment",
		"Fire Augment",
		"Adds fire damage to attacks",
		RecipeCategory.UPGRADES,
		{"fuel": 3, "chemicals": 2, "augment_crystal": 1},
		null,
		10.0
	)
	recipes.append(fire_augment)

	# ============================================
	# SPECIAL / RARE
	# ============================================

	# Respawn Beacon
	var respawn_beacon = _create_recipe(
		"respawn_beacon",
		"Respawn Beacon",
		"Sets a personal respawn point",
		RecipeCategory.SPECIAL,
		{"electronics": 5, "rare_alloy": 3, "power_cell": 1},
		null,
		15.0
	)
	recipes.append(respawn_beacon)

	# Portable Shop
	var portable_shop = _create_recipe(
		"portable_shop",
		"Portable Shop Terminal",
		"Access shop anywhere (single use)",
		RecipeCategory.SPECIAL,
		{"electronics": 8, "scrap_metal": 5, "power_cell": 2},
		null,
		20.0
	)
	recipes.append(portable_shop)

	# Revival Kit
	var revival_kit = _create_recipe(
		"revival_kit",
		"Revival Kit",
		"Revive a downed teammate",
		RecipeCategory.SPECIAL,
		{"chemicals": 5, "syringe": 2, "rare_compound": 2},
		null,
		8.0
	)
	recipes.append(revival_kit)

	# Zombie Bait
	var zombie_bait = _create_recipe(
		"zombie_bait",
		"Zombie Bait",
		"Attracts zombies to location",
		RecipeCategory.SPECIAL,
		{"blood_sample": 3, "chemicals": 2, "bottle": 1},
		null,
		4.0
	)
	recipes.append(zombie_bait)
	unlocked_recipes.append(zombie_bait)

func _create_recipe(id: String, recipe_name: String, description: String, category: RecipeCategory, materials: Dictionary, result_item: Resource, craft_time: float) -> Resource:
	"""Create a recipe resource"""
	var recipe = Resource.new()
	recipe.set_meta("id", id)
	recipe.set_meta("name", recipe_name)
	recipe.set_meta("description", description)
	recipe.set_meta("category", category)
	recipe.set_meta("materials", materials)
	recipe.set_meta("result_item", result_item)
	recipe.set_meta("craft_time", craft_time)
	return recipe

# ============================================
# CRAFTING OPERATIONS
# ============================================

func can_craft(recipe: Resource) -> Dictionary:
	"""Check if recipe can be crafted, returns {can_craft, missing_materials}"""
	if not recipe or not player_persistence:
		return {"can_craft": false, "missing_materials": {}}

	var materials_needed = recipe.get_meta("materials", {})
	var player_materials = player_persistence.player_data.get("materials", {})
	var missing = {}

	for material_id in materials_needed:
		var needed = materials_needed[material_id]
		var have = player_materials.get(material_id, 0)

		if have < needed:
			missing[material_id] = needed - have

	return {
		"can_craft": missing.is_empty(),
		"missing_materials": missing
	}

func start_crafting(recipe: Resource) -> bool:
	"""Start crafting a recipe"""
	if is_crafting:
		# Add to queue
		crafting_queue.append({"recipe": recipe})
		return true

	var check = can_craft(recipe)
	if not check.can_craft:
		crafting_failed.emit(recipe, "Missing materials")
		return false

	# Consume materials
	_consume_materials(recipe)

	# Start crafting
	is_crafting = true
	current_recipe = recipe
	current_craft_time = recipe.get_meta("craft_time", 1.0)
	crafting_started.emit(recipe)

	return true

func _consume_materials(recipe: Resource):
	"""Remove materials from player inventory"""
	if not player_persistence:
		return

	var materials_needed = recipe.get_meta("materials", {})

	if not player_persistence.player_data.has("materials"):
		player_persistence.player_data["materials"] = {}

	var player_materials = player_persistence.player_data.materials

	for material_id in materials_needed:
		var needed = materials_needed[material_id]
		if player_materials.has(material_id):
			player_materials[material_id] -= needed
			if player_materials[material_id] <= 0:
				player_materials.erase(material_id)

func _complete_crafting():
	"""Complete current crafting operation"""
	if not current_recipe:
		return

	var result_item = current_recipe.get_meta("result_item")

	# Add crafted item to inventory
	if result_item and inventory_system and inventory_system.has_method("add_item"):
		inventory_system.add_item(result_item, 1)
	else:
		# Give as material if no item resource
		var recipe_id = current_recipe.get_meta("id", "unknown")
		_give_crafted_material(recipe_id)

	crafting_completed.emit(current_recipe, result_item)

	is_crafting = false
	current_recipe = null
	current_craft_time = 0.0

	# Process queue
	if not crafting_queue.is_empty():
		var next = crafting_queue.pop_front()
		start_crafting(next.recipe)

func _give_crafted_material(material_id: String):
	"""Add crafted material to player"""
	if not player_persistence:
		return

	if not player_persistence.player_data.has("materials"):
		player_persistence.player_data["materials"] = {}

	var mats = player_persistence.player_data.materials
	mats[material_id] = mats.get(material_id, 0) + 1

func cancel_crafting():
	"""Cancel current crafting and refund materials"""
	if not is_crafting or not current_recipe:
		return

	# Refund materials
	_refund_materials(current_recipe)

	is_crafting = false
	current_recipe = null
	current_craft_time = 0.0

func _refund_materials(recipe: Resource):
	"""Refund materials from cancelled craft"""
	if not player_persistence:
		return

	var materials = recipe.get_meta("materials", {})

	if not player_persistence.player_data.has("materials"):
		player_persistence.player_data["materials"] = {}

	var player_mats = player_persistence.player_data.materials

	for material_id in materials:
		player_mats[material_id] = player_mats.get(material_id, 0) + materials[material_id]

# ============================================
# RECIPE MANAGEMENT
# ============================================

func get_recipes_by_category(category: RecipeCategory) -> Array[Resource]:
	"""Get all unlocked recipes in a category"""
	var result: Array[Resource] = []
	for recipe in unlocked_recipes:
		if recipe.get_meta("category") == category:
			result.append(recipe)
	return result

func get_all_unlocked_recipes() -> Array[Resource]:
	"""Get all unlocked recipes"""
	return unlocked_recipes.duplicate()

func unlock_recipe(recipe: Resource):
	"""Unlock a recipe"""
	if recipe not in unlocked_recipes:
		unlocked_recipes.append(recipe)
		recipe_unlocked.emit(recipe)

func is_recipe_unlocked(recipe: Resource) -> bool:
	"""Check if recipe is unlocked"""
	return recipe in unlocked_recipes

func get_crafting_progress() -> float:
	"""Get current crafting progress (0.0 to 1.0)"""
	if not is_crafting or not current_recipe:
		return 0.0

	var total_time = current_recipe.get_meta("craft_time", 1.0)
	var elapsed = total_time - current_craft_time
	return elapsed / total_time

func get_player_materials() -> Dictionary:
	"""Get player's current materials"""
	if not player_persistence:
		return {}
	return player_persistence.player_data.get("materials", {}).duplicate()

# ============================================
# SAVE/LOAD
# ============================================

func get_save_data() -> Dictionary:
	var unlocked_ids = []
	for recipe in unlocked_recipes:
		unlocked_ids.append(recipe.get_meta("id", ""))

	return {
		"unlocked_recipes": unlocked_ids
	}

func load_save_data(data: Dictionary):
	if data.has("unlocked_recipes"):
		for recipe in recipes:
			var recipe_id = recipe.get_meta("id", "")
			if recipe_id in data.unlocked_recipes:
				if recipe not in unlocked_recipes:
					unlocked_recipes.append(recipe)
