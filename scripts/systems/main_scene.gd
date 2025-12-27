extends Node3D

# Note: Using Node type hints for safety
@onready var player: Node = $Player if has_node("Player") else null
@onready var zombie_spawn_points: Node3D = $ZombieSpawnPoints if has_node("ZombieSpawnPoints") else null
@onready var local_game_manager: Node = $GameManager if has_node("GameManager") else null

var hud_instance: Control = null

func _ready():
	# Wait a frame to ensure all nodes are ready
	await get_tree().process_frame

	# Setup HUD
	_setup_hud()

	# Setup autoload GameManager with spawn points
	_setup_game_manager()

	# Setup player
	_setup_player()

	# Bake navigation mesh
	_bake_navigation()

	print("=== GAME STARTED ===")
	print("Controls:")
	print("  WASD - Move, Shift - Sprint, Space - Jump")
	print("  Mouse - Look, Left Click - Shoot, R - Reload")
	print("  E - Interact, I - Inventory, X - Extract")
	print("====================")

func _setup_hud():
	# Add standalone HUD if player doesn't have one
	var existing_hud = get_tree().get_first_node_in_group("hud")
	if not existing_hud:
		var hud_scene = load("res://scenes/ui/hud.tscn")
		if hud_scene:
			hud_instance = hud_scene.instantiate()
			# Add to CanvasLayer so it's always on top
			var canvas_layer = CanvasLayer.new()
			canvas_layer.name = "HUDLayer"
			canvas_layer.layer = 10
			add_child(canvas_layer)
			canvas_layer.add_child(hud_instance)
			print("[MainScene] HUD added to scene")

func _setup_game_manager():
	# Get autoload GameManager
	var game_manager = get_node_or_null("/root/GameManager")
	if not game_manager:
		push_error("[MainScene] GameManager autoload not found!")
		return

	# Add spawn points from scene
	if zombie_spawn_points:
		game_manager.zombie_spawn_points.clear()
		for child in zombie_spawn_points.get_children():
			if child is Marker3D or child is Node3D:
				game_manager.zombie_spawn_points.append(child)
		print("[MainScene] Added %d zombie spawn points" % game_manager.zombie_spawn_points.size())
	else:
		push_warning("[MainScene] No ZombieSpawnPoints node found!")

	# Set zombie scene from local GameManager if needed
	if local_game_manager and "zombie_scene" in local_game_manager:
		if local_game_manager.zombie_scene:
			game_manager.zombie_scene = local_game_manager.zombie_scene
			print("[MainScene] Zombie scene set: ", game_manager.zombie_scene.resource_path)

	# Verify setup
	if game_manager.zombie_scene:
		print("[MainScene] GameManager ready - zombie scene: ", game_manager.zombie_scene.resource_path)
	else:
		push_error("[MainScene] No zombie scene set!")

func _setup_player():
	if not player:
		push_warning("[MainScene] No Player node found!")
		return

	# Ensure player is in group
	if not player.is_in_group("player"):
		player.add_to_group("player")

	# Setup player UI reference
	var player_ui = player.get_node_or_null("UI")
	if player_ui and player_ui.has_method("setup"):
		player_ui.setup(player)

	print("[MainScene] Player setup complete at position: ", player.global_position)

func _bake_navigation():
	# Find and bake navigation mesh
	var nav_region = get_node_or_null("NavigationRegion3D")
	if nav_region and nav_region is NavigationRegion3D:
		nav_region.bake_navigation_mesh()
		print("[MainScene] Navigation mesh baked")
