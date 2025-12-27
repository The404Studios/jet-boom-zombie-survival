## WeaponComponent - Stores weapon data and combat properties
## Used for both player weapons and enemy attacks
class_name WeaponComponent
extends Component

## Weapon type enum
enum WeaponType {
	MELEE,
	PISTOL,
	RIFLE,
	SHOTGUN,
	SNIPER,
	HEAVY,
	EXPLOSIVE,
	SPECIAL
}

## Current weapon type
var weapon_type: WeaponType = WeaponType.MELEE

## Weapon name
var weapon_name: String = "Fists"

## Base damage per hit/shot
var damage: float = 10.0

## Fire rate (shots per second)
var fire_rate: float = 1.0

## Time until next shot allowed
var fire_cooldown: float = 0.0

## Magazine capacity
var magazine_size: int = 0

## Current ammo in magazine
var current_ammo: int = 0

## Reserve ammo
var reserve_ammo: int = 0

## Maximum reserve ammo
var max_reserve_ammo: int = 0

## Reload time in seconds
var reload_time: float = 1.0

## Whether currently reloading
var is_reloading: bool = false

## Reload progress (0-1)
var reload_progress: float = 0.0

## Weapon range (for raycasts)
var weapon_range: float = 100.0

## Spread/accuracy (0 = perfect, 1 = very inaccurate)
var spread: float = 0.0

## Pellet count (for shotguns)
var pellet_count: int = 1

## Critical hit chance (0-1)
var crit_chance: float = 0.0

## Critical hit multiplier
var crit_multiplier: float = 2.0

## Knockback force
var knockback: float = 0.0

## Whether weapon can fire
var can_fire: bool = true

## Damage type (physical, fire, ice, etc.)
var damage_type: String = "physical"

## Status effect to apply on hit
var status_effect: String = ""

## Status effect chance (0-1)
var status_effect_chance: float = 0.0

## Status effect duration
var status_effect_duration: float = 0.0

## Whether this is automatic (hold to fire)
var is_automatic: bool = false

## Muzzle position offset
var muzzle_offset: Vector3 = Vector3(0, 0, -1)

## Item data reference (from ItemData resource)
var item_data: Resource = null

## Signal when fired
signal fired()

## Signal when reloaded
signal reloaded()

## Signal when reload started
signal reload_started()

## Signal when ammo changed
signal ammo_changed(current: int, reserve: int)

## Signal when hit something
signal hit(target: Node3D, damage_dealt: float, is_crit: bool)


func get_component_name() -> String:
	return "Weapon"


## Try to fire the weapon
func try_fire() -> bool:
	if not can_fire:
		return false

	if is_reloading:
		return false

	if fire_cooldown > 0:
		return false

	if magazine_size > 0 and current_ammo <= 0:
		return false

	# Fire the weapon
	if magazine_size > 0:
		current_ammo -= 1
		ammo_changed.emit(current_ammo, reserve_ammo)

	fire_cooldown = 1.0 / fire_rate if fire_rate > 0 else 0.0
	fired.emit()

	return true


## Update weapon state
func update(delta: float) -> void:
	# Update fire cooldown
	if fire_cooldown > 0:
		fire_cooldown -= delta

	# Update reload
	if is_reloading:
		reload_progress += delta / reload_time
		if reload_progress >= 1.0:
			_complete_reload()


## Start reloading
func start_reload() -> bool:
	if is_reloading:
		return false

	if magazine_size <= 0:
		return false

	if current_ammo >= magazine_size:
		return false

	if reserve_ammo <= 0:
		return false

	is_reloading = true
	reload_progress = 0.0
	reload_started.emit()
	return true


## Complete reload
func _complete_reload() -> void:
	var ammo_needed := magazine_size - current_ammo
	var ammo_to_add := mini(ammo_needed, reserve_ammo)

	current_ammo += ammo_to_add
	reserve_ammo -= ammo_to_add

	is_reloading = false
	reload_progress = 0.0
	ammo_changed.emit(current_ammo, reserve_ammo)
	reloaded.emit()


## Cancel reload
func cancel_reload() -> void:
	is_reloading = false
	reload_progress = 0.0


## Add ammo to reserve
func add_ammo(amount: int) -> int:
	var space := max_reserve_ammo - reserve_ammo
	var ammo_added := mini(amount, space)
	reserve_ammo += ammo_added
	ammo_changed.emit(current_ammo, reserve_ammo)
	return ammo_added


## Calculate damage with potential crit
func calculate_damage() -> Dictionary:
	var is_crit := randf() < crit_chance
	var final_damage := damage

	if is_crit:
		final_damage *= crit_multiplier

	return {
		"damage": final_damage,
		"is_crit": is_crit,
		"type": damage_type
	}


## Get spread direction
func get_spread_direction(base_direction: Vector3) -> Vector3:
	if spread <= 0:
		return base_direction

	var random_spread := Vector3(
		randf_range(-spread, spread),
		randf_range(-spread, spread),
		randf_range(-spread, spread)
	)

	return (base_direction + random_spread).normalized()


## Check if magazine is empty
func is_magazine_empty() -> bool:
	return magazine_size > 0 and current_ammo <= 0


## Check if can reload
func can_reload() -> bool:
	return not is_reloading and magazine_size > 0 and current_ammo < magazine_size and reserve_ammo > 0


## Get ammo display string
func get_ammo_string() -> String:
	if magazine_size <= 0:
		return "∞"
	return "%d / %d" % [current_ammo, reserve_ammo]


## Setup from ItemData resource
func setup_from_item_data(data: Resource) -> void:
	if not data:
		return

	item_data = data

	# Copy properties if they exist
	if "item_name" in data:
		weapon_name = data.item_name
	if "damage" in data:
		damage = data.damage
	if "fire_rate" in data:
		fire_rate = data.fire_rate
	if "magazine_size" in data:
		magazine_size = data.magazine_size
		current_ammo = magazine_size
	if "reload_time" in data:
		reload_time = data.reload_time
	if "weapon_range" in data:
		weapon_range = data.weapon_range
	if "spread" in data:
		spread = data.spread
	if "pellet_count" in data:
		pellet_count = data.pellet_count
	if "is_automatic" in data:
		is_automatic = data.is_automatic


func serialize() -> Dictionary:
	var data := super.serialize()
	data["weapon_type"] = weapon_type
	data["weapon_name"] = weapon_name
	data["damage"] = damage
	data["fire_rate"] = fire_rate
	data["magazine_size"] = magazine_size
	data["current_ammo"] = current_ammo
	data["reserve_ammo"] = reserve_ammo
	data["max_reserve_ammo"] = max_reserve_ammo
	data["reload_time"] = reload_time
	data["weapon_range"] = weapon_range
	data["spread"] = spread
	data["crit_chance"] = crit_chance
	data["crit_multiplier"] = crit_multiplier
	return data


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	weapon_type = data.get("weapon_type", WeaponType.MELEE)
	weapon_name = data.get("weapon_name", "Fists")
	damage = data.get("damage", 10.0)
	fire_rate = data.get("fire_rate", 1.0)
	magazine_size = data.get("magazine_size", 0)
	current_ammo = data.get("current_ammo", 0)
	reserve_ammo = data.get("reserve_ammo", 0)
	max_reserve_ammo = data.get("max_reserve_ammo", 0)
	reload_time = data.get("reload_time", 1.0)
	weapon_range = data.get("weapon_range", 100.0)
	spread = data.get("spread", 0.0)
	crit_chance = data.get("crit_chance", 0.0)
	crit_multiplier = data.get("crit_multiplier", 2.0)
