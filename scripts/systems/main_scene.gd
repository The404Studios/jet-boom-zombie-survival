extends Node3D

# Note: Using Node type hints for safety - GameManager and Player may have load order issues
@onready var game_manager: Node = $GameManager if has_node("GameManager") else null
@onready var player: Node = $Player if has_node("Player") else null  # Player type
@onready var zombie_spawn_points: Node3D = $ZombieSpawnPoints if has_node("ZombieSpawnPoints") else null

func _ready():
	# Setup game manager with spawn points
	if game_manager and zombie_spawn_points:
		for child in zombie_spawn_points.get_children():
			if child is Marker3D:
				if "zombie_spawn_points" in game_manager:
					game_manager.zombie_spawn_points.append(child)

	# Setup player UI - check if player has UI node
	if player:
		var player_ui = player.get_node_or_null("UI")
		if player_ui and player_ui.has_method("setup"):
			player_ui.setup(player)

	print("Game Started!")
	print("Controls:")
	print("WASD - Move")
	print("Shift - Sprint")
	print("Space - Jump")
	print("Mouse - Look")
	print("Left Click - Shoot")
	print("R - Reload")
	print("E - Interact")
	print("I - Inventory")
	print("X - Extract (at Sigil)")
