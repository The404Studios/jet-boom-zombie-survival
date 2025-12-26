extends Node3D

# Note: Using Node type hints for safety
@onready var player: Node = $Player if has_node("Player") else null
@onready var zombie_spawn_points: Node3D = $ZombieSpawnPoints if has_node("ZombieSpawnPoints") else null
@onready var local_game_manager: Node = $GameManager if has_node("GameManager") else null

func _ready():
	# Setup autoload GameManager with spawn points (prefer autoload over local node)
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and zombie_spawn_points:
		# Clear any existing spawn points and add from scene
		if "zombie_spawn_points" in game_manager:
			game_manager.zombie_spawn_points.clear()
			for child in zombie_spawn_points.get_children():
				if child is Marker3D:
					game_manager.zombie_spawn_points.append(child)
			print("[MainScene] Added %d zombie spawn points to GameManager" % game_manager.zombie_spawn_points.size())

		# Copy zombie_scene from local node if autoload doesn't have one
		if local_game_manager and "zombie_scene" in local_game_manager:
			if not game_manager.zombie_scene and local_game_manager.zombie_scene:
				game_manager.zombie_scene = local_game_manager.zombie_scene
				print("[MainScene] Set zombie_scene from local GameManager")

	# Setup player UI
	if player:
		var player_ui = player.get_node_or_null("UI")
		if player_ui and player_ui.has_method("setup"):
			player_ui.setup(player)

	print("Game Started!")
	print("Controls:")
	print("WASD - Move, Shift - Sprint, Space - Jump")
	print("Mouse - Look, Left Click - Shoot, R - Reload")
	print("E - Interact, I - Inventory, X - Extract")
