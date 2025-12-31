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
	# Health Kit recipe
	var health_kit = _create_recipe(
		"health_kit",
		"Health Kit",
		"Restores 50 health",
		RecipeCategory.CONSUMABLES,
		{"herbs": 2, "bandage": 1},
		null,  # Would be actual item resource
		2.0  # Craft time
	)
	recipes.append(health_kit)
	unlocked_recipes.append(health_kit)

	# Ammo Box recipe
	var ammo_box = _create_recipe(
		"ammo_box",
		"Ammo Box",
		"Contains 30 rounds",
		RecipeCategory.MATERIALS,
		{"scrap_metal": 3, "gunpowder": 2},
		null,
		3.0
	)
	recipes.append(ammo_box)
	unlocked_recipes.append(ammo_box)

	# Armor Plate
	var armor_plate = _create_recipe(
		"armor_plate",
		"Armor Plate",
		"Reinforced protection",
		RecipeCategory.ARMOR,
		{"scrap_metal": 5, "cloth": 2},
		null,
		5.0
	)
	recipes.append(armor_plate)
	unlocked_recipes.append(armor_plate)

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
		"Explosive device",
		RecipeCategory.WEAPONS,
		{"pipe": 1, "gunpowder": 3, "electronics": 1},
		null,
		4.0
	)
	recipes.append(pipe_bomb)

	# Stim Pack
	var stim_pack = _create_recipe(
		"stim_pack",
		"Stim Pack",
		"Temporary speed boost",
		RecipeCategory.CONSUMABLES,
		{"chemicals": 2, "syringe": 1},
		null,
		3.0
	)
	recipes.append(stim_pack)
	unlocked_recipes.append(stim_pack)

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
