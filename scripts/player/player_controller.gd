extends CharacterBody3D
class_name Player

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 6.0
@export var mouse_sensitivity: float = 0.003
@export var max_health: float = 100.0
@export var max_stamina: float = 100.0

var current_health: float = 100.0
var current_stamina: float = 100.0
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_sprinting: bool = false
var can_shoot: bool = true
var is_reloading: bool = false
var reserve_ammo: int = 90

@onready var camera: Camera3D = $Camera3D
@onready var weapon_holder: Node3D = $Camera3D/WeaponHolder
@onready var interact_ray: RayCast3D = $Camera3D/InteractRay
@onready var inventory: InventorySystem = $InventorySystem
@onready var ui: Control = $UI

# Grid-based inventory (optional - for grid UI system)
var grid_inventory: GridInventorySystem

var current_weapon: Node3D = null
var shoot_timer: float = 0.0

signal health_changed(new_health: float, max_health: float)
signal stamina_changed(new_stamina: float, max_stamina: float)
signal died

func _ready():
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	current_health = max_health
	current_stamina = max_stamina
	health_changed.emit(current_health, max_health)
	stamina_changed.emit(current_stamina, max_stamina)

	# Initialize grid inventory system
	_setup_grid_inventory()

func _setup_grid_inventory():
	# Create grid inventory if not already exists
	if not grid_inventory:
		grid_inventory = GridInventorySystem.new()
		grid_inventory.name = "GridInventorySystem"
		add_child(grid_inventory)
		grid_inventory.add_to_group("grid_inventory")

func _input(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)

	if event.is_action_pressed("inventory"):
		toggle_inventory()

	if event.is_action_pressed("extract"):
		attempt_extract()

	# Drop item with G key (if action exists)
	if InputMap.has_action("drop_item") and event.is_action_pressed("drop_item"):
		drop_held_item()

func _physics_process(delta):
	# Stamina regeneration
	if not is_sprinting and current_stamina < max_stamina:
		current_stamina = min(current_stamina + 20.0 * delta, max_stamina)
		stamina_changed.emit(current_stamina, max_stamina)

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Sprint
	is_sprinting = Input.is_action_pressed("sprint") and current_stamina > 0

	# Movement
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var current_speed = sprint_speed if is_sprinting else walk_speed

	if is_sprinting and direction.length() > 0:
		current_stamina = max(current_stamina - 30.0 * delta, 0)
		stamina_changed.emit(current_stamina, max_stamina)

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()

	# Shooting
	shoot_timer = max(shoot_timer - delta, 0)

	if Input.is_action_pressed("shoot") and can_shoot and shoot_timer <= 0 and not is_reloading:
		shoot()

	if Input.is_action_just_pressed("reload") and not is_reloading:
		reload_weapon()

	# Interaction
	if Input.is_action_just_pressed("interact"):
		interact()

func shoot():
	if not inventory.equipped_weapon or inventory.equipped_weapon.is_empty():
		return

	var weapon_data = inventory.equipped_weapon.get("item")
	if not weapon_data:
		return
	if inventory.equipped_weapon.get("current_ammo", 0) <= 0:
		# Auto reload
		reload_weapon()
		return

	inventory.equipped_weapon["current_ammo"] = inventory.equipped_weapon.get("current_ammo", 1) - 1

	# Raycast for hit detection
	var space_state = get_world_3d().direct_space_state
	var from = camera.global_position
	var to = from + (-camera.global_transform.basis.z * weapon_data.weapon_range)

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0b001101  # Hit environment, zombies, barricades
	var result = space_state.intersect_ray(query)

	if result:
		if result.collider.has_method("take_damage"):
			result.collider.take_damage(weapon_data.damage, result.position)

	# Set fire rate cooldown
	shoot_timer = weapon_data.fire_rate

	# Weapon animation and effects would go here
	if current_weapon and current_weapon.has_method("play_shoot_animation"):
		current_weapon.play_shoot_animation()

	can_shoot = true

func reload_weapon():
	if not inventory.equipped_weapon or inventory.equipped_weapon.is_empty():
		return

	var weapon_data = inventory.equipped_weapon.get("item")
	if not weapon_data:
		return
	if inventory.equipped_weapon.get("current_ammo", 0) >= weapon_data.magazine_size:
		return

	is_reloading = true

	# Animation would play here
	await get_tree().create_timer(weapon_data.reload_time).timeout

	# Validate after await - player or weapon may have changed/been freed
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not inventory or not inventory.equipped_weapon:
		is_reloading = false
		return

	inventory.equipped_weapon["current_ammo"] = weapon_data.magazine_size
	is_reloading = false

func interact():
	if not interact_ray:
		return
	if interact_ray.is_colliding():
		var collider = interact_ray.get_collider()
		if not collider:
			return

		if collider.has_method("interact"):
			collider.interact(self)
		elif collider.is_in_group("loot"):
			pickup_item(collider)
		elif collider.is_in_group("barricade_spot"):
			place_barricade(collider)

func pickup_item(item_node: Node3D):
	"""Pick up a loot item from the world"""
	if not item_node:
		return

	var item_data: Resource = null
	var quantity: int = 1

	# Get item data from the node
	if item_node.has_method("get_item_data"):
		item_data = item_node.get_item_data()
	elif "item_data" in item_node:
		item_data = item_node.item_data

	# Get quantity if available
	if "loot_quantity" in item_node:
		quantity = item_node.loot_quantity

	if not item_data:
		# Try to handle special loot types (ammo, health, etc.)
		if item_node is LootItem:
			var loot = item_node as LootItem
			if loot.loot_type != "":
				_handle_special_pickup(loot)
				return
		return

	# Try to add to grid inventory first
	if grid_inventory and grid_inventory.has_method("add_item"):
		if grid_inventory.add_item(item_data, quantity, false):
			_on_pickup_success(item_node, item_data)
			return

	# Fallback to regular inventory
	if inventory and inventory.has_method("add_item"):
		if inventory.add_item(item_data, quantity):
			_on_pickup_success(item_node, item_data)
			return

	# Inventory full
	show_pickup_message("Inventory full!")

func _handle_special_pickup(loot: LootItem):
	"""Handle special loot types that don't use ItemData"""
	var success = false

	match loot.loot_type:
		"ammo":
			if "reserve_ammo" in self:
				reserve_ammo += loot.loot_quantity
				success = true
		"health":
			var heal_amount = loot.get_meta("heal_amount", 25)
			heal(heal_amount)
			success = true

	if success:
		show_pickup_message(loot._get_display_name())
		loot.picked_up.emit(self)
		loot.queue_free()

func _on_pickup_success(item_node: Node3D, item_data: Resource):
	"""Called when an item is successfully picked up"""
	# Show pickup message
	var item_name = item_data.item_name if "item_name" in item_data else "Item"
	show_pickup_message(item_name)

	# Play pickup sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("pickup")

	# Emit signal on loot item
	if item_node.has_signal("picked_up"):
		item_node.picked_up.emit(self)

	# Free or return to pool
	var pool_manager = get_node_or_null("/root/ObjectPoolManager")
	if pool_manager and pool_manager.has_method("release"):
		pool_manager.release("loot_item", item_node)
	else:
		item_node.queue_free()

func show_pickup_message(item_name: String):
	"""Show a pickup notification to the player"""
	# Try HUD notification
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_notification"):
		hud.show_notification("+ %s" % item_name)
		return

	# Try chat system
	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message("Picked up: %s" % item_name)
		return

	# Fallback to print
	print("Picked up: %s" % item_name)

func drop_held_item():
	"""Drop the currently selected item from inventory"""
	# Check if inventory UI is open and has selected item
	var grid_ui = get_tree().get_first_node_in_group("grid_inventory_ui")
	if grid_ui and grid_ui.is_open and "hovered_item" in grid_ui:
		var hovered = grid_ui.hovered_item
		if not hovered.is_empty() and "item" in hovered:
			drop_item(hovered.item, hovered.get("quantity", 1))
			return

	# Otherwise, try to drop first inventory item
	if grid_inventory:
		var items = grid_inventory.get_all_items(false)
		if items.size() > 0:
			var first_item = items[0]
			drop_item(first_item.item, 1)

func drop_item(item_data: Resource, quantity: int = 1):
	"""Drop an item from inventory into the world"""
	if not item_data:
		return

	# Remove from inventory
	var removed = false
	if grid_inventory and grid_inventory.has_method("remove_item"):
		removed = grid_inventory.remove_item(item_data, quantity)
	elif inventory and inventory.has_method("remove_item"):
		removed = inventory.remove_item(item_data, quantity)

	if not removed:
		return

	# Spawn loot item in front of player
	var drop_position = global_position + (-global_transform.basis.z * 1.5) + Vector3(0, 0.5, 0)

	# Try to use object pool
	var pool_manager = get_node_or_null("/root/ObjectPoolManager")
	if pool_manager and pool_manager.has_method("spawn_loot"):
		var loot = pool_manager.spawn_loot(drop_position, item_data, get_parent())
		if loot:
			return

	# Fallback: create new loot item
	var loot_scene = preload("res://scenes/items/loot_item.tscn")
	var loot = loot_scene.instantiate()
	get_parent().add_child(loot)
	loot.global_position = drop_position

	if loot.has_method("set_item_data"):
		loot.set_item_data(item_data)
	elif "item_data" in loot:
		loot.item_data = item_data

	# Apply small random velocity for visual effect
	if loot is RigidBody3D:
		loot.linear_velocity = Vector3(randf_range(-1, 1), 2, randf_range(-1, 1))

	# Show drop message
	var item_name = item_data.item_name if "item_name" in item_data else "Item"
	show_pickup_message("Dropped: %s" % item_name)

func place_barricade(spot: Node3D):
	# Check if player has barricade material in inventory
	var material_item: ItemData = null
	for inv_item in inventory.inventory:
		if inv_item.item.item_type == ItemData.ItemType.MATERIAL:
			material_item = inv_item.item
			break

	# If no material, check if spot has existing barricade to repair
	if not material_item:
		# Allow free repairs if barricade exists
		if spot.has_method("interact"):
			spot.interact(self)
		return

	# Try to interact with barricade spot (build or repair)
	if spot.has_method("interact"):
		# Remove material from inventory
		inventory.remove_item(material_item, 1)
		spot.interact(self)
	elif spot.has_method("start_build"):
		inventory.remove_item(material_item, 1)
		spot.start_build(self)

func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO):
	current_health -= amount
	current_health = max(current_health, 0)
	health_changed.emit(current_health, max_health)

	if current_health <= 0:
		die()

func heal(amount: float):
	current_health = min(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)

func die():
	died.emit()
	# Handle death - maybe return to menu or restart

func toggle_inventory():
	if ui:
		ui.toggle_inventory()
		if ui.is_inventory_open():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func attempt_extract():
	# Check if near extract point
	if not interact_ray:
		return
	if interact_ray.is_colliding():
		var collider = interact_ray.get_collider()
		if collider and collider.is_in_group("extract_zone"):
			if collider.has_method("extract"):
				collider.extract(self)

func equip_weapon_item(weapon_data: ItemData):
	# Clear current weapon visual
	for child in weapon_holder.get_children():
		child.queue_free()

	# Instantiate new weapon model
	if weapon_data.mesh_scene:
		current_weapon = weapon_data.mesh_scene.instantiate()
		weapon_holder.add_child(current_weapon)

	inventory.equip_weapon(weapon_data)
