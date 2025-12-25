extends Node
class_name ProceduralAnimation

# Procedural animation system for when no pre-made animations exist
# Creates dynamic animations for weapons, player movement, and zombies

# ============================================
# WEAPON ANIMATIONS
# ============================================

static func create_weapon_fire_animation(animation_player: AnimationPlayer, weapon_type: String = "pistol"):
	"""Create procedural weapon fire animation"""
	var library = AnimationLibrary.new()

	# Fire animation
	var fire_anim = Animation.new()
	fire_anim.length = 0.2

	# Different parameters per weapon
	var recoil_amount = 0.05
	var recoil_rotation = -5.0
	var recovery_time = 0.15

	match weapon_type.to_lower():
		"shotgun":
			recoil_amount = 0.15
			recoil_rotation = -10.0
			recovery_time = 0.3
		"sniper":
			recoil_amount = 0.12
			recoil_rotation = -8.0
			recovery_time = 0.25
		"rifle", "ak47", "m16":
			recoil_amount = 0.06
			recoil_rotation = -4.0
			recovery_time = 0.12
		"machinegun":
			recoil_amount = 0.04
			recoil_rotation = -3.0
			recovery_time = 0.08

	# Position track - kick back
	var pos_track = fire_anim.add_track(Animation.TYPE_VALUE)
	fire_anim.track_set_path(pos_track, ".:position")
	fire_anim.track_insert_key(pos_track, 0.0, Vector3.ZERO)
	fire_anim.track_insert_key(pos_track, 0.05, Vector3(0, 0, recoil_amount))
	fire_anim.track_insert_key(pos_track, recovery_time, Vector3.ZERO)

	# Rotation track - kick up
	var rot_track = fire_anim.add_track(Animation.TYPE_VALUE)
	fire_anim.track_set_path(rot_track, ".:rotation")
	fire_anim.track_insert_key(rot_track, 0.0, Vector3.ZERO)
	fire_anim.track_insert_key(rot_track, 0.05, Vector3(deg_to_rad(recoil_rotation), 0, 0))
	fire_anim.track_insert_key(rot_track, recovery_time, Vector3.ZERO)

	library.add_animation("fire", fire_anim)

	# Reload animation
	var reload_anim = create_reload_animation(weapon_type)
	library.add_animation("reload", reload_anim)

	# Equip animation
	var equip_anim = create_equip_animation()
	library.add_animation("equip", equip_anim)

	# Add to animation player
	if animation_player.has_animation_library("procedural"):
		animation_player.remove_animation_library("procedural")
	animation_player.add_animation_library("procedural", library)

static func create_reload_animation(weapon_type: String) -> Animation:
	"""Create reload animation"""
	var anim = Animation.new()

	var reload_time = 2.0
	match weapon_type.to_lower():
		"pistol":
			reload_time = 1.5
		"shotgun":
			reload_time = 2.5
		"sniper":
			reload_time = 2.8
		"machinegun":
			reload_time = 3.5

	anim.length = reload_time

	# Position - lower then raise
	var pos_track = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, ".:position")
	anim.track_insert_key(pos_track, 0.0, Vector3.ZERO)
	anim.track_insert_key(pos_track, reload_time * 0.3, Vector3(0, -0.3, 0))
	anim.track_insert_key(pos_track, reload_time * 0.7, Vector3(0, -0.3, 0))
	anim.track_insert_key(pos_track, reload_time, Vector3.ZERO)

	# Rotation - tilt
	var rot_track = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(rot_track, ".:rotation")
	anim.track_insert_key(rot_track, 0.0, Vector3.ZERO)
	anim.track_insert_key(rot_track, reload_time * 0.3, Vector3(deg_to_rad(30), deg_to_rad(15), 0))
	anim.track_insert_key(rot_track, reload_time * 0.7, Vector3(deg_to_rad(30), deg_to_rad(-10), 0))
	anim.track_insert_key(rot_track, reload_time, Vector3.ZERO)

	return anim

static func create_equip_animation() -> Animation:
	"""Create weapon equip animation"""
	var anim = Animation.new()
	anim.length = 0.4

	# Position - slide up from below
	var pos_track = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, ".:position")
	anim.track_insert_key(pos_track, 0.0, Vector3(0, -0.5, 0))
	anim.track_insert_key(pos_track, 0.3, Vector3(0, 0.02, 0))  # Slight overshoot
	anim.track_insert_key(pos_track, 0.4, Vector3.ZERO)

	# Rotation - slight swing
	var rot_track = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(rot_track, ".:rotation")
	anim.track_insert_key(rot_track, 0.0, Vector3(deg_to_rad(20), 0, 0))
	anim.track_insert_key(rot_track, 0.4, Vector3.ZERO)

	return anim

# ============================================
# ZOMBIE ANIMATIONS
# ============================================

static func create_zombie_animations(animation_player: AnimationPlayer):
	"""Create all zombie animations"""
	var library = AnimationLibrary.new()

	library.add_animation("idle", create_zombie_idle())
	library.add_animation("walk", create_zombie_walk())
	library.add_animation("attack", create_zombie_attack())
	library.add_animation("hurt", create_zombie_hurt())
	library.add_animation("death", create_zombie_death())

	if animation_player.has_animation_library("procedural"):
		animation_player.remove_animation_library("procedural")
	animation_player.add_animation_library("procedural", library)

static func create_zombie_idle() -> Animation:
	"""Create zombie idle animation - subtle swaying"""
	var anim = Animation.new()
	anim.length = 2.0
	anim.loop_mode = Animation.LOOP_LINEAR

	# Subtle body sway
	var rot_track = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(rot_track, ".:rotation")
	anim.track_insert_key(rot_track, 0.0, Vector3(0, 0, deg_to_rad(-2)))
	anim.track_insert_key(rot_track, 1.0, Vector3(0, 0, deg_to_rad(2)))
	anim.track_insert_key(rot_track, 2.0, Vector3(0, 0, deg_to_rad(-2)))

	return anim

static func create_zombie_walk() -> Animation:
	"""Create zombie walk animation - shambling motion"""
	var anim = Animation.new()
	anim.length = 1.0
	anim.loop_mode = Animation.LOOP_LINEAR

	# Body bob
	var pos_track = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, ".:position:y")
	anim.track_insert_key(pos_track, 0.0, 0.0)
	anim.track_insert_key(pos_track, 0.25, 0.05)
	anim.track_insert_key(pos_track, 0.5, 0.0)
	anim.track_insert_key(pos_track, 0.75, 0.05)
	anim.track_insert_key(pos_track, 1.0, 0.0)

	# Body sway
	var rot_track = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(rot_track, ".:rotation")
	anim.track_insert_key(rot_track, 0.0, Vector3(deg_to_rad(5), 0, deg_to_rad(-5)))
	anim.track_insert_key(rot_track, 0.5, Vector3(deg_to_rad(5), 0, deg_to_rad(5)))
	anim.track_insert_key(rot_track, 1.0, Vector3(deg_to_rad(5), 0, deg_to_rad(-5)))

	return anim

static func create_zombie_attack() -> Animation:
	"""Create zombie attack animation - lunge forward"""
	var anim = Animation.new()
	anim.length = 0.8

	# Lunge motion
	var pos_track = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, ".:position")
	anim.track_insert_key(pos_track, 0.0, Vector3.ZERO)
	anim.track_insert_key(pos_track, 0.2, Vector3(0, 0.1, -0.2))  # Wind up
	anim.track_insert_key(pos_track, 0.4, Vector3(0, -0.1, 0.3))  # Strike
	anim.track_insert_key(pos_track, 0.8, Vector3.ZERO)

	# Body rotation for strike
	var rot_track = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(rot_track, ".:rotation")
	anim.track_insert_key(rot_track, 0.0, Vector3.ZERO)
	anim.track_insert_key(rot_track, 0.2, Vector3(deg_to_rad(-10), 0, 0))
	anim.track_insert_key(rot_track, 0.4, Vector3(deg_to_rad(20), 0, 0))
	anim.track_insert_key(rot_track, 0.8, Vector3.ZERO)

	return anim

static func create_zombie_hurt() -> Animation:
	"""Create zombie hurt reaction"""
	var anim = Animation.new()
	anim.length = 0.3

	# Stagger back
	var pos_track = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, ".:position")
	anim.track_insert_key(pos_track, 0.0, Vector3.ZERO)
	anim.track_insert_key(pos_track, 0.1, Vector3(0, 0, -0.15))
	anim.track_insert_key(pos_track, 0.3, Vector3.ZERO)

	return anim

static func create_zombie_death() -> Animation:
	"""Create zombie death animation - fall down"""
	var anim = Animation.new()
	anim.length = 1.5

	# Fall down
	var pos_track = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, ".:position")
	anim.track_insert_key(pos_track, 0.0, Vector3.ZERO)
	anim.track_insert_key(pos_track, 0.5, Vector3(0, -0.5, 0.2))
	anim.track_insert_key(pos_track, 1.0, Vector3(0, -1.5, 0.4))
	anim.track_insert_key(pos_track, 1.5, Vector3(0, -1.8, 0.5))

	# Rotate to lie flat
	var rot_track = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(rot_track, ".:rotation")
	anim.track_insert_key(rot_track, 0.0, Vector3.ZERO)
	anim.track_insert_key(rot_track, 0.5, Vector3(deg_to_rad(30), 0, deg_to_rad(10)))
	anim.track_insert_key(rot_track, 1.0, Vector3(deg_to_rad(70), 0, deg_to_rad(5)))
	anim.track_insert_key(rot_track, 1.5, Vector3(deg_to_rad(90), 0, 0))

	return anim

# ============================================
# PLAYER CAMERA ANIMATIONS
# ============================================

static func apply_footstep_bob(camera: Camera3D, is_sprinting: bool, delta: float, bob_time: float) -> float:
	"""Apply procedural head bob to camera, returns new bob_time"""
	var bob_speed = 12.0 if is_sprinting else 8.0
	var bob_amount = 0.08 if is_sprinting else 0.04

	bob_time += delta * bob_speed

	var bob_offset_y = sin(bob_time) * bob_amount
	var bob_offset_x = sin(bob_time * 0.5) * bob_amount * 0.5

	# Apply to camera (relative to base position)
	camera.position.y = 1.6 + bob_offset_y  # Assuming 1.6 is eye height
	camera.position.x = bob_offset_x

	return bob_time

static func apply_landing_bob(camera: Camera3D, landing_velocity: float):
	"""Apply landing impact to camera"""
	var impact = min(abs(landing_velocity) / 20.0, 0.3)

	var tween = camera.create_tween()
	tween.tween_property(camera, "position:y", camera.position.y - impact, 0.1)
	tween.tween_property(camera, "position:y", camera.position.y, 0.2)

static func apply_damage_shake(camera: Camera3D, intensity: float = 0.1, duration: float = 0.2):
	"""Apply damage screen shake"""
	var original_rotation = camera.rotation

	var tween = camera.create_tween()

	for i in range(int(duration / 0.02)):
		var shake_amount = intensity * (1.0 - float(i) / (duration / 0.02))
		var random_rot = Vector3(
			randf_range(-shake_amount, shake_amount),
			randf_range(-shake_amount, shake_amount),
			randf_range(-shake_amount, shake_amount)
		)
		tween.tween_property(camera, "rotation", original_rotation + random_rot, 0.02)

	tween.tween_property(camera, "rotation", original_rotation, 0.05)
