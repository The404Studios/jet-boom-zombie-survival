## ModelRegistry - Registry of available 3D models for entities
## Maps entity types to model paths and manages model loading
class_name ModelRegistry
extends RefCounted

## Base path for character models
const CHARACTER_MODEL_PATH := "res://Free_Character/"

## Base path for weapon models
const WEAPON_MODEL_PATH := "res://LP_WeaponsPack/"

## Player model variants
var player_models: Array[String] = [
	"res://Free_Character/ShowcaseFreeCharacter/Characters/Character1_Character1.glb",
	"res://Free_Character/ShowcaseFreeCharacter/Characters/Character2_Character2.glb",
	"res://Free_Character/ShowcaseFreeCharacter/Characters/Character3_Character3.glb",
	"res://Free_Character/ShowcaseFreeCharacter/Characters/Character4_Character4.glb",
]

## Zombie models by type
var zombie_models: Dictionary = {
	"shambler": [
		"res://Free_Character/Dizzy/Dizzy.glb",
		"res://Free_Character/Mr_Trash/Mr_Trash.glb",
	],
	"runner": [
		"res://Free_Character/Popcorn/Popcorn.glb",
	],
	"tank": [
		"res://Free_Character/Fatsot/Fatsot.glb",
		"res://Free_Character/Fatsot/Fatsot_v2.glb",
	],
	"poison": [
		"res://Free_Character/Mr_Tail/Mr_Tail.glb",
	],
	"exploder": [
		"res://Free_Character/ShowcaseFreeCharacter/Characters/Enemy1_Enemy1.glb",
	],
	"spitter": [
		"res://Free_Character/ShowcaseFreeCharacter/Characters/Enemy2_Enemy2.glb",
	],
	"boss": [
		"res://Free_Character/ShowcaseFreeCharacter/Characters/Enemy3_Enemy3.glb",
	],
}

## Weapon models by type
var weapon_models: Dictionary = {
	"pistol": "res://scenes/weapons/weapon_pistol.tscn",
	"ak47": "res://scenes/weapons/weapon_ak47.tscn",
	"shotgun": "res://scenes/weapons/weapon_shotgun.tscn",
	"sniper": "res://scenes/weapons/weapon_sniper.tscn",
	"rpg": "res://scenes/weapons/weapon_rpg.tscn",
	"minigun": "res://scenes/weapons/weapon_minigun.tscn",
}

## Pickup models by type
var pickup_models: Dictionary = {
	"health": "",  # Uses default mesh
	"ammo": "",
	"weapon": "",
}

## Current player model index
var current_player_model_index: int = 0


## Get a player model path
func get_player_model(index: int = -1) -> String:
	if index < 0:
		index = current_player_model_index

	if index >= 0 and index < player_models.size():
		return player_models[index]

	return ""


## Get a random player model
func get_random_player_model() -> String:
	if player_models.is_empty():
		return ""
	return player_models[randi() % player_models.size()]


## Set current player model
func set_player_model_index(index: int) -> void:
	current_player_model_index = clampi(index, 0, player_models.size() - 1)


## Get a zombie model path by type
func get_zombie_model(zombie_type: String) -> String:
	if zombie_models.has(zombie_type):
		var models: Array = zombie_models[zombie_type]
		if not models.is_empty():
			return models[randi() % models.size()]

	# Fallback to shambler
	if zombie_models.has("shambler"):
		var models: Array = zombie_models["shambler"]
		if not models.is_empty():
			return models[0]

	return ""


## Get a specific zombie model by type and index
func get_zombie_model_at(zombie_type: String, index: int) -> String:
	if zombie_models.has(zombie_type):
		var models: Array = zombie_models[zombie_type]
		if index >= 0 and index < models.size():
			return models[index]

	return ""


## Get weapon model path
func get_weapon_model(weapon_type: String) -> String:
	return weapon_models.get(weapon_type, "")


## Get pickup model path
func get_pickup_model(pickup_type: String) -> String:
	return pickup_models.get(pickup_type, "")


## Register a new player model
func register_player_model(path: String) -> void:
	if not player_models.has(path):
		player_models.append(path)


## Register a new zombie model
func register_zombie_model(zombie_type: String, path: String) -> void:
	if not zombie_models.has(zombie_type):
		zombie_models[zombie_type] = []

	var models: Array = zombie_models[zombie_type]
	if not models.has(path):
		models.append(path)


## Register a weapon model
func register_weapon_model(weapon_type: String, path: String) -> void:
	weapon_models[weapon_type] = path


## Get all available player models
func get_all_player_models() -> Array[String]:
	return player_models


## Get all zombie types
func get_all_zombie_types() -> Array[String]:
	var types: Array[String] = []
	for key in zombie_models.keys():
		types.append(key)
	return types


## Get zombie model count for type
func get_zombie_model_count(zombie_type: String) -> int:
	if zombie_models.has(zombie_type):
		return zombie_models[zombie_type].size()
	return 0


## Check if model file exists
func model_exists(path: String) -> bool:
	return ResourceLoader.exists(path)


## Scan for available GLB models in a directory
func scan_directory_for_models(directory_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(directory_path)

	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()

		while file_name != "":
			if not dir.current_is_dir():
				if file_name.ends_with(".glb") or file_name.ends_with(".gltf"):
					result.append(directory_path.path_join(file_name))
			else:
				# Recursively scan subdirectories
				var sub_results := scan_directory_for_models(directory_path.path_join(file_name))
				result.append_array(sub_results)

			file_name = dir.get_next()

		dir.list_dir_end()

	return result


## Auto-discover and register all models in Free_Character folder
func auto_discover_character_models() -> void:
	var models := scan_directory_for_models(CHARACTER_MODEL_PATH)

	for model_path in models:
		var file_name := model_path.get_file().to_lower()

		# Categorize by name patterns
		if "character" in file_name or "player" in file_name:
			register_player_model(model_path)
		elif "enemy" in file_name:
			if "1" in file_name:
				register_zombie_model("exploder", model_path)
			elif "2" in file_name:
				register_zombie_model("spitter", model_path)
			else:
				register_zombie_model("boss", model_path)
		elif "dizzy" in file_name or "trash" in file_name:
			register_zombie_model("shambler", model_path)
		elif "popcorn" in file_name:
			register_zombie_model("runner", model_path)
		elif "fatsot" in file_name:
			register_zombie_model("tank", model_path)
		elif "tail" in file_name:
			register_zombie_model("poison", model_path)
		else:
			# Default to shambler
			register_zombie_model("shambler", model_path)
