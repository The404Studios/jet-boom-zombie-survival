extends Control

# HUD controller - displays game info, player stats, wave info, and points
# Integrates with ArenaManager, Player, and PointsSystem

@onready var wave_label = $TopLeft/WaveLabel if has_node("TopLeft/WaveLabel") else null
@onready var zombies_label = $TopLeft/ZombiesLabel if has_node("TopLeft/ZombiesLabel") else null
@onready var points_label = $TopLeft/PointsLabel if has_node("TopLeft/PointsLabel") else null
@onready var sigils_label = $TopLeft/SigilsLabel if has_node("TopLeft/SigilsLabel") else null

@onready var health_bar = $TopRight/HealthBar if has_node("TopRight/HealthBar") else null
@onready var health_label = $TopRight/HealthLabel if has_node("TopRight/HealthLabel") else null
@onready var stamina_bar = $TopRight/StaminaBar if has_node("TopRight/StaminaBar") else null
@onready var stamina_label = $TopRight/StaminaLabel if has_node("TopRight/StaminaLabel") else null

@onready var weapon_label = $BottomCenter/WeaponLabel if has_node("BottomCenter/WeaponLabel") else null
@onready var ammo_label = $BottomCenter/AmmoLabel if has_node("BottomCenter/AmmoLabel") else null

@onready var interact_label = $BottomRight/InteractLabel if has_node("BottomRight/InteractLabel") else null
@onready var extraction_label = $BottomRight/ExtractionLabel if has_node("BottomRight/ExtractionLabel") else null
@onready var nail_progress = $CenterProgress/NailProgressBar if has_node("CenterProgress/NailProgressBar") else null
@onready var nail_progress_container = $CenterProgress if has_node("CenterProgress") else null

@onready var crosshair = $Crosshair if has_node("Crosshair") else null
@onready var damage_indicator = $DamageIndicator if has_node("DamageIndicator") else null
@onready var wave_announcement = $WaveAnnouncement if has_node("WaveAnnouncement") else null

# Phase timer elements (created dynamically)
var phase_container: Control = null
var phase_label: Label = null
var phase_timer_label: Label = null
var phase_timer_bar: ProgressBar = null
var meetup_indicator: Label = null

var player: Node = null
var current_wave: int = 0
var current_points: int = 500
var current_sigils: int = 500

# Phase tracking
var current_phase_name: String = ""
var current_phase_timer: float = 0.0
var max_phase_timer: float = 60.0
var game_coordinator: Node = null

# World tooltip reference
var world_tooltip: WorldTooltip = null

func _ready():
	# Add to hud group so arena manager can find us
	add_to_group("hud")

	# Find player
	await get_tree().create_timer(0.5).timeout
	_find_player()

	# Hide interact labels initially
	if interact_label:
		interact_label.visible = false
	if extraction_label:
		extraction_label.visible = false
	if nail_progress_container:
		nail_progress_container.visible = false

	# Initialize display
	update_wave_info(1, 0, 0)
	update_points(current_points)
	update_sigils(current_sigils)

	# Connect to systems
	await get_tree().create_timer(0.1).timeout
	_connect_arena_manager()
	_connect_points_system()
	_connect_game_coordinator()

	# Create phase timer UI
	_create_phase_timer_ui()

	# Create world tooltip for ground items
	_create_world_tooltip()

func _connect_points_system():
	if has_node("/root/PointsSystem"):
		var points_system = get_node("/root/PointsSystem")
		if points_system.has_signal("points_changed"):
			if not points_system.points_changed.is_connected(_on_points_changed):
				points_system.points_changed.connect(_on_points_changed)
		if points_system.has_signal("sigils_changed"):
			if not points_system.sigils_changed.is_connected(_on_sigils_changed):
				points_system.sigils_changed.connect(_on_sigils_changed)
		# Initialize values
		update_points(points_system.current_points)
		update_sigils(points_system.current_sigils)

func _on_points_changed(new_points: int):
	update_points(new_points)

func _on_sigils_changed(new_sigils: int):
	update_sigils(new_sigils)

func _connect_arena_manager():
	var arena = get_tree().get_first_node_in_group("arena_manager")
	if arena:
		if arena.has_signal("wave_started"):
			if not arena.wave_started.is_connected(_on_wave_started):
				arena.wave_started.connect(_on_wave_started)
		if arena.has_signal("wave_completed"):
			if not arena.wave_completed.is_connected(_on_wave_completed):
				arena.wave_completed.connect(_on_wave_completed)

func _on_wave_started(wave_number: int):
	current_wave = wave_number
	_show_wave_announcement("Wave %d" % wave_number)

func _on_wave_completed(wave_number: int):
	_show_wave_announcement("Wave %d Complete!" % wave_number)

func _show_wave_announcement(text: String):
	if wave_announcement:
		wave_announcement.text = text
		wave_announcement.visible = true
		# Hide after 3 seconds
		var tween = create_tween()
		tween.tween_interval(3.0)
		tween.tween_callback(func(): wave_announcement.visible = false)

func _process(_delta):
	if not player or not is_instance_valid(player):
		_find_player()
		return

	_update_health()
	_update_stamina()
	_update_weapon_info()

func _find_player():
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

func _update_health():
	if not player:
		return

	if "current_health" in player and "max_health" in player:
		var health = player.current_health
		var max_health = player.max_health

		if health_bar:
			health_bar.value = health
			health_bar.max_value = max_health
		if health_label:
			health_label.text = "HP: %d/%d" % [int(health), int(max_health)]

func _update_stamina():
	if not player:
		return

	if "current_stamina" in player and "max_stamina" in player:
		var stamina = player.current_stamina
		var max_stamina = player.max_stamina

		if stamina_bar:
			stamina_bar.value = stamina
			stamina_bar.max_value = max_stamina
		if stamina_label:
			stamina_label.text = "SP: %d/%d" % [int(stamina), int(max_stamina)]

func _update_weapon_info():
	if not player:
		return

	if weapon_label:
		if "current_weapon_data" in player:
			var weapon = player.current_weapon_data
			if weapon and "item_name" in weapon:
				weapon_label.text = weapon.item_name
			elif "current_weapon_name" in player:
				weapon_label.text = player.current_weapon_name
			else:
				weapon_label.text = "Unarmed"
		elif "current_weapon_name" in player:
			weapon_label.text = player.current_weapon_name
		else:
			weapon_label.text = "Unarmed"

	if ammo_label:
		if "current_ammo" in player and "reserve_ammo" in player:
			ammo_label.text = "%d / %d" % [player.current_ammo, player.reserve_ammo]
		elif "current_ammo" in player and "max_ammo" in player:
			ammo_label.text = "%d / %d" % [player.current_ammo, player.max_ammo]

func update_wave_info(wave: int, zombies_alive: int, zombies_total: int):
	current_wave = wave
	if wave_label:
		wave_label.text = "Wave: %d" % wave
	if zombies_label:
		zombies_label.text = "Zombies: %d/%d" % [zombies_alive, zombies_total]

func update_points(points: int):
	current_points = points
	if points_label:
		points_label.text = "$%d" % points

func update_sigils(sigils: int):
	current_sigils = sigils
	if sigils_label:
		sigils_label.text = "Sigils: %d" % sigils
	# Create sigils label dynamically if it doesn't exist
	elif has_node("TopLeft") and not sigils_label:
		sigils_label = Label.new()
		sigils_label.name = "SigilsLabel"
		sigils_label.text = "Sigils: %d" % sigils
		sigils_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.8))
		$TopLeft.add_child(sigils_label)

func update_weapon_info(weapon_data: Resource, ammo: int, reserve: int):
	"""Update weapon display from weapon data"""
	if weapon_label and weapon_data:
		weapon_label.text = weapon_data.item_name if "item_name" in weapon_data else "Unknown"
	if ammo_label:
		ammo_label.text = "%d / %d" % [ammo, reserve]

func show_interact_prompt(text: String):
	if interact_label:
		interact_label.text = text
		interact_label.visible = true

func hide_interact_prompt():
	if interact_label:
		interact_label.visible = false

func show_extraction_prompt():
	if extraction_label:
		extraction_label.visible = true

func hide_extraction_prompt():
	if extraction_label:
		extraction_label.visible = false

func show_damage_indicator(_direction: Vector3 = Vector3.ZERO):
	if damage_indicator:
		damage_indicator.visible = true
		# Flash effect
		var tween = create_tween()
		tween.tween_property(damage_indicator, "modulate:a", 1.0, 0.1)
		tween.tween_property(damage_indicator, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func(): damage_indicator.visible = false)

func update_crosshair_spread(spread: float):
	if crosshair and crosshair.has_method("set_spread"):
		crosshair.set_spread(spread)

func update_nail_progress(progress: float, is_active: bool):
	"""Update the nailing progress bar (0.0 - 1.0)"""
	if nail_progress_container:
		nail_progress_container.visible = is_active and progress > 0.0

	if nail_progress:
		nail_progress.value = progress * 100.0

		# Color feedback - green when complete
		if progress >= 1.0:
			nail_progress.modulate = Color(0.2, 1.0, 0.2)
		else:
			nail_progress.modulate = Color(1.0, 0.8, 0.2)

# ============================================
# GAME COORDINATOR INTEGRATION
# ============================================

func _connect_game_coordinator():
	game_coordinator = get_tree().get_first_node_in_group("game_coordinator")
	if game_coordinator:
		if game_coordinator.has_signal("game_phase_changed"):
			if not game_coordinator.game_phase_changed.is_connected(_on_game_phase_changed):
				game_coordinator.game_phase_changed.connect(_on_game_phase_changed)
		if game_coordinator.has_signal("meetup_timer_updated"):
			if not game_coordinator.meetup_timer_updated.is_connected(_on_meetup_timer_updated):
				game_coordinator.meetup_timer_updated.connect(_on_meetup_timer_updated)
		if game_coordinator.has_signal("all_players_ready"):
			if not game_coordinator.all_players_ready.is_connected(_on_all_players_ready):
				game_coordinator.all_players_ready.connect(_on_all_players_ready)

func _on_game_phase_changed(_phase):
	# _phase is GameCoordinator.GamePhase enum
	if game_coordinator and game_coordinator.has_method("get_phase_name"):
		current_phase_name = game_coordinator.get_phase_name()
		_update_phase_display()

func _on_meetup_timer_updated(time_remaining: float):
	current_phase_timer = time_remaining
	_update_phase_timer_display()

func _on_all_players_ready():
	if meetup_indicator:
		meetup_indicator.text = "ALL PLAYERS READY!"
		meetup_indicator.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))

func _create_phase_timer_ui():
	# Create container for phase timer at top center
	phase_container = VBoxContainer.new()
	phase_container.name = "PhaseContainer"
	phase_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	phase_container.offset_left = -200
	phase_container.offset_right = 200
	phase_container.offset_top = 20
	phase_container.offset_bottom = 120
	phase_container.add_theme_constant_override("separation", 8)
	add_child(phase_container)

	# Phase name label
	phase_label = Label.new()
	phase_label.name = "PhaseLabel"
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.add_theme_font_size_override("font_size", 28)
	phase_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	phase_container.add_child(phase_label)

	# Timer bar
	phase_timer_bar = ProgressBar.new()
	phase_timer_bar.name = "PhaseTimerBar"
	phase_timer_bar.max_value = 60.0
	phase_timer_bar.value = 60.0
	phase_timer_bar.show_percentage = false
	phase_timer_bar.custom_minimum_size = Vector2(400, 20)
	phase_container.add_child(phase_timer_bar)

	# Timer label
	phase_timer_label = Label.new()
	phase_timer_label.name = "PhaseTimerLabel"
	phase_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_timer_label.add_theme_font_size_override("font_size", 20)
	phase_timer_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	phase_container.add_child(phase_timer_label)

	# Meetup indicator
	meetup_indicator = Label.new()
	meetup_indicator.name = "MeetupIndicator"
	meetup_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meetup_indicator.add_theme_font_size_override("font_size", 16)
	meetup_indicator.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	phase_container.add_child(meetup_indicator)

	# Hide by default
	phase_container.visible = false

func _update_phase_display():
	if not phase_label:
		return

	phase_label.text = current_phase_name.to_upper()

	# Color based on phase
	match current_phase_name:
		"Meetup":
			phase_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
			meetup_indicator.text = "Get to the Sigil!"
			meetup_indicator.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
			phase_container.visible = true
		"Wave Active":
			phase_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
			meetup_indicator.text = "Defend the Sigil!"
			meetup_indicator.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
			phase_timer_bar.visible = false
			phase_timer_label.visible = false
			phase_container.visible = true
		"Intermission":
			phase_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
			meetup_indicator.text = "Visit the Sigil to shop!"
			meetup_indicator.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
			phase_timer_bar.visible = true
			phase_timer_label.visible = true
			phase_container.visible = true
		"Lobby", "Game Over":
			phase_container.visible = false
		_:
			phase_container.visible = true

func _update_phase_timer_display():
	if not phase_timer_label or not phase_timer_bar:
		return

	phase_timer_label.text = "%d seconds" % int(current_phase_timer)
	phase_timer_bar.value = current_phase_timer
	phase_timer_bar.visible = true
	phase_timer_label.visible = true

	# Color based on time remaining
	if current_phase_timer <= 10:
		phase_timer_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		phase_timer_bar.modulate = Color(1.0, 0.3, 0.3)
	elif current_phase_timer <= 20:
		phase_timer_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
		phase_timer_bar.modulate = Color(1.0, 0.7, 0.3)
	else:
		phase_timer_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		phase_timer_bar.modulate = Color(1.0, 1.0, 1.0)

func update_phase(phase_name: String, timer: float):
	"""Update the phase display externally"""
	current_phase_name = phase_name
	max_phase_timer = max(timer, 1.0)
	current_phase_timer = timer

	if phase_timer_bar:
		phase_timer_bar.max_value = max_phase_timer

	_update_phase_display()
	if timer > 0:
		_update_phase_timer_display()

func show_meetup_progress(players_ready: int, players_total: int):
	"""Show how many players are at the sigil"""
	if meetup_indicator:
		meetup_indicator.text = "Players at Sigil: %d/%d" % [players_ready, players_total]
		if players_ready >= players_total:
			meetup_indicator.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
		else:
			meetup_indicator.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))

# ============================================
# WORLD TOOLTIP
# ============================================

func _create_world_tooltip():
	"""Create world tooltip for ground item inspection"""
	world_tooltip = WorldTooltip.new()
	world_tooltip.name = "WorldTooltip"
	add_child(world_tooltip)

func show_notification(text: String):
	"""Show a temporary notification message"""
	var notification = Label.new()
	notification.text = text
	notification.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification.add_theme_font_size_override("font_size", 18)
	notification.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	notification.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	notification.add_theme_constant_override("shadow_offset_x", 1)
	notification.add_theme_constant_override("shadow_offset_y", 1)

	# Position at top center
	notification.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notification.position.y = 150
	add_child(notification)

	# Animate and remove
	var tween = create_tween()
	tween.tween_property(notification, "position:y", 130, 0.3)
	tween.parallel().tween_property(notification, "modulate:a", 1.0, 0.2)
	tween.tween_interval(1.5)
	tween.tween_property(notification, "modulate:a", 0.0, 0.5)
	tween.tween_callback(notification.queue_free)
