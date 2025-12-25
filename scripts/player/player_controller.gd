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

	var weapon_data = inventory.equipped_weapon.item
	if inventory.equipped_weapon.current_ammo <= 0:
		# Auto reload
		reload_weapon()
		return

	inventory.equipped_weapon.current_ammo -= 1

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

	var weapon_data = inventory.equipped_weapon.item
	if inventory.equipped_weapon.current_ammo >= weapon_data.magazine_size:
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

	inventory.equipped_weapon.current_ammo = weapon_data.magazine_size
	is_reloading = false

func interact():
	if interact_ray.is_colliding():
		var collider = interact_ray.get_collider()

		if collider.has_method("interact"):
			collider.interact(self)
		elif collider.is_in_group("loot"):
			pickup_item(collider)
		elif collider.is_in_group("barricade_spot"):
			place_barricade(collider)

func pickup_item(item_node: Node3D):
	if item_node.has_method("get_item_data"):
		var item_data = item_node.get_item_data()
		if inventory.add_item(item_data, 1):
			item_node.queue_free()

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
	if interact_ray.is_colliding():
		var collider = interact_ray.get_collider()
		if collider.is_in_group("extract_zone"):
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
