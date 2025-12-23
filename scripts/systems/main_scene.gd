extends Node3D

@onready var game_manager: GameManager = $GameManager
@onready var player: Player = $Player
@onready var zombie_spawn_points: Node3D = $ZombieSpawnPoints

func _ready():
	# Setup game manager with spawn points
	if game_manager:
		for child in zombie_spawn_points.get_children():
			if child is Marker3D:
				game_manager.zombie_spawn_points.append(child)

	# Setup player UI
	if player and player.ui:
		player.ui.setup(player)

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
