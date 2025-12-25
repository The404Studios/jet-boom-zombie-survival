extends CharacterBody3D
class_name PlayerExtended

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 6.0
@export var mouse_sensitivity: float = 0.003

var current_health: float = 100.0
var max_health: float = 100.0
var current_stamina: float = 100.0
var max_stamina: float = 100.0
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_sprinting: bool = false
var can_shoot: bool = true
var is_reloading: bool = false

# Ammo tracking
var current_ammo: int = 30
var reserve_ammo: int = 120
var magazine_size: int = 30

@onready var camera: Camera3D = $Camera3D
@onready var weapon_holder: Node3D = $Camera3D/WeaponHolder
@onready var interact_ray: RayCast3D = $Camera3D/InteractRay
@onready var inventory: InventorySystem = $InventorySystem
@onready var character_stats: CharacterStats = $CharacterStats
@onready var equipment_system: EquipmentSystem = $EquipmentSystem
@onready var status_effects: StatusEffectSystem = $StatusEffectSystem
@onready var player_persistence: PlayerPersistence = $PlayerPersistence
@onready var ui: Control = $UI

# Grid-based inventory (optional - for grid UI system)
var grid_inventory: GridInventorySystem

var current_weapon: Node3D = null
var current_weapon_data: ItemDataExtended = null
var shoot_timer: float = 0.0

signal health_changed(new_health: float, max_health: float)
signal stamina_changed(new_stamina: float, max_stamina: float)
signal died
signal headshot_landed(target: Node, damage: float)
signal critical_hit(target: Node, damage: float)

func _ready():
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Initialize grid inventory system
	_setup_grid_inventory()

	# Load player data
	if player_persistence:
		player_persistence.load_player_data()
		player_persistence.apply_to_character_stats(character_stats)

	# Setup stats-based values
	if character_stats:
		max_health = character_stats.max_health
		current_health = max_health
		max_stamina = character_stats.max_stamina
		current_stamina = max_stamina
		mouse_sensitivity = player_persistence.player_data.settings.mouse_sensitivity if player_persistence else 0.003
	else:
		max_health = 100.0
		max_stamina = 100.0

	health_changed.emit(current_health, max_health)
	stamina_changed.emit(current_stamina, max_stamina)

	# Connect signals
	if equipment_system:
		equipment_system.gear_equipped.connect(_on_gear_equipped)

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
	# Update max values from stats
	if character_stats:
		var max_health_stat = character_stats.max_health
		var max_stamina_stat = character_stats.max_stamina

		# Health regen
		if current_health < max_health_stat:
			current_health = min(current_health + character_stats.health_regen * delta, max_health_stat)
			health_changed.emit(current_health, max_health_stat)

		# Stamina regen
		if not is_sprinting and current_stamina < max_stamina_stat:
			var regen = character_stats.stamina_regen * delta
			current_stamina = min(current_stamina + regen, max_stamina_stat)
			stamina_changed.emit(current_stamina, max_stamina_stat)

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Sprint
	is_sprinting = Input.is_action_pressed("sprint") and current_stamina > 0

	# Movement with agility bonus
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var speed_mult = character_stats.move_speed_multiplier if character_stats else 1.0
	var current_speed = (sprint_speed if is_sprinting else walk_speed) * speed_mult

	if is_sprinting and direction.length() > 0:
		current_stamina = max(current_stamina - 30.0 * delta, 0)
		if character_stats:
			stamina_changed.emit(current_stamina, character_stats.max_stamina)

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
	if not equipment_system or not equipment_system.weapon_main:
		return

	current_weapon_data = equipment_system.weapon_main

	# Check ammo
	if current_ammo <= 0:
		# Play empty click sound
		if has_node("/root/AudioManager"):
			get_node("/root/AudioManager").play_sfx("empty_click")
		return

	# Consume ammo
	current_ammo -= 1

	# Raycast for hit detection
	var space_state = get_world_3d().direct_space_state
	var from = camera.global_position
	var to = from + (-camera.global_transform.basis.z * current_weapon_data.weapon_range)

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0b001101  # Hit environment, zombies
	var result = space_state.intersect_ray(query)

	if result:
		# Check for headshot
		var is_headshot = check_headshot(result.collider, result.position)

		# Calculate damage
		var damage_instance = DamageCalculator.calculate_damage(
			current_weapon_data.damage,
			character_stats,
			current_weapon_data,
			is_headshot,
			get_target_armor(result.collider)
		)

		# Apply damage
		if result.collider.has_method("take_damage_advanced"):
			result.collider.take_damage_advanced(damage_instance)
		elif result.collider.has_method("take_damage"):
			result.collider.take_damage(damage_instance.total_damage, result.position)

		# Spawn damage number
		spawn_damage_number(damage_instance, result.position)

		# Emit signals for feedback
		if damage_instance.is_headshot:
			headshot_landed.emit(result.collider, damage_instance.total_damage)

		if damage_instance.is_critical:
			critical_hit.emit(result.collider, damage_instance.total_damage)

		# Apply status effects
		if damage_instance.bleed_damage > 0:
			apply_status_to_target(result.collider, "bleed", damage_instance.bleed_damage)

		if damage_instance.poison_damage > 0:
			apply_status_to_target(result.collider, "poison", damage_instance.poison_damage)

	# Set fire rate cooldown
	shoot_timer = current_weapon_data.fire_rate

	# Weapon animation and effects
	if current_weapon and current_weapon.has_method("play_shoot_animation"):
		current_weapon.play_shoot_animation()

	can_shoot = true

func check_headshot(target: Node, hit_position: Vector3) -> bool:
	if not target:
		return false

	# Check if hit position is in upper portion of target
	if target is CharacterBody3D:
		var target_height = 1.8  # Assume standard zombie height
		var target_top = target.global_position.y + target_height
		var target_head_zone = target.global_position.y + (target_height * 0.75)

		if hit_position.y >= target_head_zone and hit_position.y <= target_top:
			return true

	return false

func get_target_armor(target: Node) -> float:
	if target.has_method("get_armor"):
		return target.get_armor()
	return 0.0

func apply_status_to_target(target: Node, effect_type: String, damage_per_second: float):
	if target.has_method("apply_status_effect"):
		target.apply_status_effect(effect_type, damage_per_second, 5.0)

func spawn_damage_number(damage_instance: DamageCalculator.DamageInstance, position: Vector3):
	# Create floating damage number
	var label = Label3D.new()
	label.text = DamageCalculator.get_damage_text(damage_instance)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 32
	get_parent().add_child(label)
	label.global_position = position + Vector3(0, 0.5, 0)

	# Animate
	var tween = create_tween()
	tween.tween_property(label, "position:y", label.position.y + 1.0, 1.0)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.0)
	await tween.finished
	label.queue_free()

func reload_weapon():
	if not equipment_system or not equipment_system.weapon_main:
		return

	# Check if already full or no reserve ammo
	if current_ammo >= magazine_size or reserve_ammo <= 0:
		return

	current_weapon_data = equipment_system.weapon_main

	# Update magazine size from weapon data if available
	if "magazine_size" in current_weapon_data:
		magazine_size = current_weapon_data.magazine_size

	is_reloading = true

	# Play reload sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("reload")

	# Animation would play here
	await get_tree().create_timer(current_weapon_data.reload_time).timeout

	# Validate after await - player may have been freed
	if not is_instance_valid(self) or not is_inside_tree():
		return

	# Calculate ammo to reload
	var ammo_needed = magazine_size - current_ammo
	var ammo_to_load = min(ammo_needed, reserve_ammo)

	# Transfer ammo
	current_ammo += ammo_to_load
	reserve_ammo -= ammo_to_load

	# Reload complete
	is_reloading = false

func interact():
	if interact_ray.is_colliding():
		var collider = interact_ray.get_collider()

		if collider.has_method("interact"):
			collider.interact(self)
		elif collider.is_in_group("loot"):
			pickup_item(collider)

func pickup_item(item_node: Node3D):
	if item_node.has_method("get_item_data"):
		var item_data = item_node.get_item_data()
		if inventory.add_item(item_data, 1):
			item_node.queue_free()

			if player_persistence:
				player_persistence.add_stat("items_looted", 1)

func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO):
	# Apply armor reduction
	var armor_reduction = 0.0
	if equipment_system:
		var total_armor = equipment_system.get_total_armor()
		armor_reduction = DamageCalculator.calculate_armor_reduction(total_armor)

	var final_damage = amount * (1.0 - armor_reduction)

	current_health -= final_damage
	current_health = max(current_health, 0)

	if character_stats:
		health_changed.emit(current_health, character_stats.max_health)
	else:
		health_changed.emit(current_health, 100.0)

	if current_health <= 0:
		die()

func take_damage_advanced(damage_instance: DamageCalculator.DamageInstance):
	# More advanced damage handling
	take_damage(damage_instance.total_damage)

func heal(amount: float):
	if character_stats:
		current_health = min(current_health + amount, character_stats.max_health)
		health_changed.emit(current_health, character_stats.max_health)

func die():
	died.emit()

	if player_persistence:
		player_persistence.add_stat("deaths", 1)

	# Handle death - respawn or game over
	# For now, just print
	print("Player died!")

func toggle_inventory():
	if ui:
		ui.toggle_inventory()

func attempt_extract():
	# Check if near extract point
	if interact_ray.is_colliding():
		var collider = interact_ray.get_collider()
		if collider.is_in_group("extract_zone"):
			if collider.has_method("extract"):
				collider.extract(self)

				if player_persistence:
					player_persistence.add_stat("extractions", 1)
					player_persistence.save_player_data(character_stats, equipment_system, inventory)

func equip_weapon_item(weapon_data: ItemDataExtended):
	# Equip via equipment system
	if equipment_system:
		equipment_system.equip_item(weapon_data, "primary")

	# Update visual
	for child in weapon_holder.get_children():
		child.queue_free()

	if weapon_data.mesh_scene:
		current_weapon = weapon_data.mesh_scene.instantiate()
		weapon_holder.add_child(current_weapon)

	current_weapon_data = weapon_data

func _on_gear_equipped(slot: String, item: ItemDataExtended):
	# Handle gear equipped
	if slot == "primary" or slot == "secondary":
		equip_weapon_item(item)

func apply_status_effect(effect_type: String, damage_per_second: float, duration: float):
	if status_effects:
		status_effects.apply_effect(effect_type, damage_per_second, duration)

func save_game():
	if player_persistence:
		player_persistence.save_player_data(character_stats, equipment_system, inventory)
