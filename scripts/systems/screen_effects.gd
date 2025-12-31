extends CanvasLayer
class_name ScreenEffects

# Full-screen visual effects for game feedback
# Handles damage flash, heal, level up, kill streak, etc.

signal effect_started(effect_type: String)
signal effect_finished(effect_type: String)

# Effect layers (order matters - later = on top)
var damage_overlay: ColorRect = null
var heal_overlay: ColorRect = null
var level_up_overlay: ColorRect = null
var kill_streak_overlay: ColorRect = null
var low_health_vignette: ColorRect = null
var speed_lines: Control = null
var flash_overlay: ColorRect = null

# State tracking
var is_low_health: bool = false
var current_health_percent: float = 1.0
var kill_streak_count: int = 0
var kill_streak_timer: float = 0.0

# Tweens for animations
var damage_tween: Tween = null
var heal_tween: Tween = null
var level_tween: Tween = null
var kill_tween: Tween = null
var vignette_tween: Tween = null

# Configuration
@export var low_health_threshold: float = 0.3
@export var critical_health_threshold: float = 0.15
@export var kill_streak_timeout: float = 3.0

func _ready():
	layer = 100  # On top of everything
	_create_overlays()

func _process(delta):
	# Update low health effect
	_update_low_health_effect()

	# Kill streak timer
	if kill_streak_count > 0:
		kill_streak_timer -= delta
		if kill_streak_timer <= 0:
			kill_streak_count = 0

func _create_overlays():
	"""Create all effect overlay nodes"""
	# Damage flash (red)
	damage_overlay = ColorRect.new()
	damage_overlay.name = "DamageOverlay"
	damage_overlay.color = Color(0.8, 0.0, 0.0, 0.0)
	damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(damage_overlay)

	# Heal flash (green)
	heal_overlay = ColorRect.new()
	heal_overlay.name = "HealOverlay"
	heal_overlay.color = Color(0.0, 0.8, 0.2, 0.0)
	heal_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heal_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(heal_overlay)

	# Level up flash (gold)
	level_up_overlay = ColorRect.new()
	level_up_overlay.name = "LevelUpOverlay"
	level_up_overlay.color = Color(1.0, 0.85, 0.0, 0.0)
	level_up_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_up_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(level_up_overlay)

	# Kill streak flash (orange/red gradient)
	kill_streak_overlay = ColorRect.new()
	kill_streak_overlay.name = "KillStreakOverlay"
	kill_streak_overlay.color = Color(1.0, 0.4, 0.0, 0.0)
	kill_streak_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kill_streak_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(kill_streak_overlay)

	# Low health vignette
	low_health_vignette = ColorRect.new()
	low_health_vignette.name = "LowHealthVignette"
	low_health_vignette.color = Color(0.5, 0.0, 0.0, 0.0)
	low_health_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	low_health_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(low_health_vignette)

	# Create vignette shader for low health
	_apply_vignette_shader(low_health_vignette)

	# Flash overlay (white, for explosions etc)
	flash_overlay = ColorRect.new()
	flash_overlay.name = "FlashOverlay"
	flash_overlay.color = Color(1.0, 1.0, 1.0, 0.0)
	flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(flash_overlay)

func _apply_vignette_shader(rect: ColorRect):
	"""Apply a vignette shader to the ColorRect"""
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 vignette_color : source_color = vec4(0.5, 0.0, 0.0, 1.0);
uniform float vignette_radius : hint_range(0.0, 1.0) = 0.4;
uniform float vignette_softness : hint_range(0.0, 1.0) = 0.5;
uniform float pulse_speed : hint_range(0.0, 5.0) = 2.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv);

	// Pulsing effect for critical health
	float pulse = sin(TIME * pulse_speed) * 0.1 + 0.9;

	// Vignette calculation
	float vignette = smoothstep(vignette_radius, vignette_radius + vignette_softness, dist);
	vignette *= vignette_intensity * pulse;

	COLOR = vec4(vignette_color.rgb, vignette);
}
"""
	var material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("vignette_intensity", 0.0)
	material.set_shader_parameter("vignette_color", Color(0.6, 0.0, 0.0, 1.0))
	material.set_shader_parameter("vignette_radius", 0.3)
	material.set_shader_parameter("vignette_softness", 0.5)
	material.set_shader_parameter("pulse_speed", 2.0)
	rect.material = material

# ============================================
# DAMAGE EFFECTS
# ============================================

func show_damage_flash(intensity: float = 0.4, duration: float = 0.15):
	"""Flash red when taking damage"""
	if damage_tween and damage_tween.is_valid():
		damage_tween.kill()

	damage_overlay.color.a = intensity
	effect_started.emit("damage")

	damage_tween = create_tween()
	damage_tween.tween_property(damage_overlay, "color:a", 0.0, duration)
	damage_tween.tween_callback(func(): effect_finished.emit("damage"))

func show_critical_damage():
	"""Stronger flash for heavy damage"""
	show_damage_flash(0.6, 0.25)

	# Also pulse the vignette briefly
	if low_health_vignette.material:
		var mat = low_health_vignette.material as ShaderMaterial
		var current = mat.get_shader_parameter("vignette_intensity")
		mat.set_shader_parameter("vignette_intensity", min(current + 0.2, 0.8))

# ============================================
# HEAL EFFECTS
# ============================================

func show_heal_flash(intensity: float = 0.3, duration: float = 0.3):
	"""Flash green when healing"""
	if heal_tween and heal_tween.is_valid():
		heal_tween.kill()

	heal_overlay.color.a = intensity
	effect_started.emit("heal")

	heal_tween = create_tween()
	heal_tween.tween_property(heal_overlay, "color:a", 0.0, duration).set_ease(Tween.EASE_OUT)
	heal_tween.tween_callback(func(): effect_finished.emit("heal"))

func show_full_heal():
	"""Special effect when fully healed"""
	show_heal_flash(0.5, 0.5)

# ============================================
# LEVEL UP / XP EFFECTS
# ============================================

func show_level_up():
	"""Golden flash for level up"""
	if level_tween and level_tween.is_valid():
		level_tween.kill()

	level_up_overlay.color.a = 0.0
	effect_started.emit("level_up")

	level_tween = create_tween()
	level_tween.tween_property(level_up_overlay, "color:a", 0.5, 0.2)
	level_tween.tween_property(level_up_overlay, "color:a", 0.0, 0.8).set_ease(Tween.EASE_OUT)
	level_tween.tween_callback(func(): effect_finished.emit("level_up"))

# ============================================
# KILL STREAK EFFECTS
# ============================================

func add_kill():
	"""Called when player gets a kill"""
	kill_streak_count += 1
	kill_streak_timer = kill_streak_timeout

	# Show effect based on streak
	if kill_streak_count >= 10:
		show_kill_streak_effect(0.4, "UNSTOPPABLE!")
	elif kill_streak_count >= 7:
		show_kill_streak_effect(0.3, "RAMPAGE!")
	elif kill_streak_count >= 5:
		show_kill_streak_effect(0.25, "KILLING SPREE!")
	elif kill_streak_count >= 3:
		show_kill_streak_effect(0.15, "TRIPLE KILL!")
	elif kill_streak_count >= 2:
		show_kill_streak_effect(0.1, "DOUBLE KILL!")

func show_kill_streak_effect(intensity: float, _message: String = ""):
	"""Orange flash for kill streaks"""
	if kill_tween and kill_tween.is_valid():
		kill_tween.kill()

	# Color gets more red as streak increases
	var red_shift = min(kill_streak_count * 0.05, 0.4)
	kill_streak_overlay.color = Color(1.0, 0.4 - red_shift, 0.0, intensity)
	effect_started.emit("kill_streak")

	kill_tween = create_tween()
	kill_tween.tween_property(kill_streak_overlay, "color:a", 0.0, 0.3)
	kill_tween.tween_callback(func(): effect_finished.emit("kill_streak"))

func get_kill_streak() -> int:
	return kill_streak_count

# ============================================
# LOW HEALTH EFFECTS
# ============================================

func set_health_percent(percent: float):
	"""Update current health for vignette effect"""
	current_health_percent = clamp(percent, 0.0, 1.0)

func _update_low_health_effect():
	"""Update the low health vignette based on current health"""
	if not low_health_vignette.material:
		return

	var mat = low_health_vignette.material as ShaderMaterial
	var target_intensity: float = 0.0
	var target_pulse_speed: float = 2.0

	if current_health_percent <= critical_health_threshold:
		# Critical - intense pulsing vignette
		target_intensity = 0.7
		target_pulse_speed = 4.0
		is_low_health = true
	elif current_health_percent <= low_health_threshold:
		# Low health - moderate vignette
		var t = (low_health_threshold - current_health_percent) / (low_health_threshold - critical_health_threshold)
		target_intensity = lerp(0.2, 0.5, t)
		target_pulse_speed = lerp(1.5, 3.0, t)
		is_low_health = true
	else:
		is_low_health = false

	# Smooth transition
	var current_intensity = mat.get_shader_parameter("vignette_intensity")
	var new_intensity = lerp(current_intensity, target_intensity, 0.1)
	mat.set_shader_parameter("vignette_intensity", new_intensity)
	mat.set_shader_parameter("pulse_speed", target_pulse_speed)

# ============================================
# SPECIAL EFFECTS
# ============================================

func show_flash(color: Color = Color.WHITE, intensity: float = 0.8, duration: float = 0.1):
	"""Generic flash effect (for explosions, flashbangs, etc.)"""
	flash_overlay.color = Color(color.r, color.g, color.b, intensity)
	effect_started.emit("flash")

	var tween = create_tween()
	tween.tween_property(flash_overlay, "color:a", 0.0, duration)
	tween.tween_callback(func(): effect_finished.emit("flash"))

func show_explosion_flash():
	"""Orange/white flash for nearby explosions"""
	show_flash(Color(1.0, 0.8, 0.4), 0.6, 0.15)

func show_flashbang_effect(duration: float = 2.0):
	"""Full white flash that fades slowly (flashbang)"""
	flash_overlay.color = Color(1.0, 1.0, 1.0, 1.0)
	effect_started.emit("flashbang")

	var tween = create_tween()
	tween.tween_property(flash_overlay, "color:a", 0.0, duration).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): effect_finished.emit("flashbang"))

func show_poison_effect(duration: float = 0.5):
	"""Green tint for poison damage"""
	var poison_color = Color(0.2, 0.6, 0.1, 0.3)
	damage_overlay.color = poison_color
	effect_started.emit("poison")

	var tween = create_tween()
	tween.tween_property(damage_overlay, "color:a", 0.0, duration)
	tween.tween_callback(func(): effect_finished.emit("poison"))

func show_fire_effect(duration: float = 0.3):
	"""Orange tint for fire damage"""
	var fire_color = Color(1.0, 0.4, 0.0, 0.35)
	damage_overlay.color = fire_color
	effect_started.emit("fire")

	var tween = create_tween()
	tween.tween_property(damage_overlay, "color:a", 0.0, duration)
	tween.tween_callback(func(): effect_finished.emit("fire"))

func show_freeze_effect(duration: float = 0.4):
	"""Blue tint for freeze/slow effects"""
	var freeze_color = Color(0.3, 0.5, 1.0, 0.3)
	heal_overlay.color = freeze_color  # Reuse heal overlay
	effect_started.emit("freeze")

	var tween = create_tween()
	tween.tween_property(heal_overlay, "color:a", 0.0, duration)
	tween.tween_callback(func(): effect_finished.emit("freeze"))

func show_buff_effect(buff_color: Color = Color(0.5, 0.5, 1.0)):
	"""Brief flash when gaining a buff"""
	var buff_overlay_color = Color(buff_color.r, buff_color.g, buff_color.b, 0.2)
	level_up_overlay.color = buff_overlay_color
	effect_started.emit("buff")

	var tween = create_tween()
	tween.tween_property(level_up_overlay, "color:a", 0.0, 0.4)
	tween.tween_callback(func(): effect_finished.emit("buff"))

# ============================================
# SCREEN SHAKE (Camera-based)
# ============================================

func request_screen_shake(intensity: float = 0.3, duration: float = 0.2):
	"""Request screen shake - forwarded to player camera"""
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("_camera_shake"):
		player._camera_shake(intensity, duration)

# ============================================
# INTEGRATION HELPERS
# ============================================

func on_player_damaged(damage: float, max_health: float):
	"""Called when player takes damage"""
	var damage_percent = damage / max_health
	if damage_percent > 0.3:
		show_critical_damage()
	elif damage_percent > 0.1:
		show_damage_flash(0.4, 0.2)
	else:
		show_damage_flash(0.25, 0.15)

func on_player_healed(amount: float, max_health: float):
	"""Called when player heals"""
	var heal_percent = amount / max_health
	if heal_percent > 0.5:
		show_full_heal()
	else:
		show_heal_flash(0.2 + heal_percent * 0.3, 0.3)

func on_enemy_killed(is_headshot: bool = false):
	"""Called when player kills an enemy"""
	add_kill()
	if is_headshot:
		# Extra flash for headshot
		show_flash(Color(1.0, 0.9, 0.7), 0.15, 0.1)
