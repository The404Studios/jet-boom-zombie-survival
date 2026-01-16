extends Node3D
class_name WeaponBase

## Base class for all weapons

signal ammo_changed(current: int, reserve: int)
signal reloading(duration: float)
signal shot_fired(position: Vector3, direction: Vector3)

@export_group("Weapon Stats")
@export var weapon_name: String = "Weapon"
@export var weapon_id: String = "weapon"
@export var damage: float = 25.0
@export var fire_rate: float = 600.0
@export var range_distance: float = 100.0
@export var accuracy: float = 0.95
@export var recoil_amount: float = 0.02

@export_group("Ammo")
@export var magazine_size: int = 30
@export var current_ammo: int = 30
@export var reserve_ammo: int = 90
@export var ammo_type: String = "5.56x45"
@export var reload_time: float = 2.0

var can_shoot: bool = true
var is_reloading: bool = false
var fire_cooldown: float = 0.0

func _ready():
	fire_cooldown = 60.0 / max(fire_rate, 1.0)

func _process(delta):
	if not can_shoot:
		fire_cooldown -= delta
		if fire_cooldown <= 0:
			can_shoot = true
			fire_cooldown = 60.0 / max(fire_rate, 1.0)

func shoot() -> bool:
	if not can_shoot or is_reloading: return false
	if current_ammo <= 0: return false
	current_ammo -= 1
	can_shoot = false
	var spread = (1.0 - accuracy) * 0.1
	var direction = -global_transform.basis.z
	direction += Vector3(randf_range(-spread, spread), randf_range(-spread, spread), randf_range(-spread, spread))
	shot_fired.emit(global_position, direction.normalized())
	ammo_changed.emit(current_ammo, reserve_ammo)
	return true

func reload() -> bool:
	if is_reloading or reserve_ammo <= 0 or current_ammo >= magazine_size: return false
	is_reloading = true
	reloading.emit(reload_time)
	await get_tree().create_timer(reload_time).timeout
	var needed = magazine_size - current_ammo
	var to_add = min(needed, reserve_ammo)
	current_ammo += to_add
	reserve_ammo -= to_add
	is_reloading = false
	ammo_changed.emit(current_ammo, reserve_ammo)
	return true

func get_reload_time() -> float:
	return reload_time

func add_ammo(amount: int):
	reserve_ammo += amount
	ammo_changed.emit(current_ammo, reserve_ammo)
