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
@onready var kill_feed = $KillFeed if has_node("KillFeed") else null
@onready var sigil_bar = $SigilHealth/SigilBar if has_node("SigilHealth/SigilBar") else null
@onready var sigil_percent = $SigilHealth/SigilPercent if has_node("SigilHealth/SigilPercent") else null

# Kill feed settings
const MAX_KILL_FEED_ENTRIES: int = 5
const KILL_FEED_DURATION: float = 5.0

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

# Enhanced UI state
var combo_count: int = 0
var combo_timer: float = 0.0
var combo_label: Label = null
var hitmarker: Control = null
var low_health_overlay: ColorRect = null
var last_health: float = 100.0
var health_change_tween: Tween = null

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
	_connect_game_events()

	# Create phase timer UI
	_create_phase_timer_ui()

	# Create world tooltip for ground items
	_create_world_tooltip()

	# Create enhanced UI elements
	_create_combo_display()
	_create_hitmarker()
	_create_low_health_overlay()

	# Get references to integrated UI elements
	_setup_integrated_ui()

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
		tween.tween_callback(_hide_wave_announcement)

func _process(delta):
	if not player or not is_instance_valid(player):
		_find_player()
		return

	_update_health()
	_update_stamina()
	_update_weapon_info()
	_update_combo(delta)
	_update_low_health_effect()

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
		tween.tween_callback(_hide_damage_indicator)

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

# ============================================
# GAME EVENTS INTEGRATION
# ============================================

var minimap_ref: Node = null
var objective_tracker_ref: Node = null
var kill_feed_ui_ref: Node = null
var scoreboard_ref: Node = null
var end_round_stats_ref: Node = null

func _connect_game_events():
	var game_events = get_node_or_null("/root/GameEvents")
	if game_events:
		if game_events.has_signal("wave_spawning"):
			if not game_events.wave_spawning.is_connected(_on_event_wave_spawning):
				game_events.wave_spawning.connect(_on_event_wave_spawning)
		if game_events.has_signal("zombie_killed"):
			if not game_events.zombie_killed.is_connected(_on_event_zombie_killed):
				game_events.zombie_killed.connect(_on_event_zombie_killed)
		if game_events.has_signal("player_damaged"):
			if not game_events.player_damaged.is_connected(_on_event_player_damaged):
				game_events.player_damaged.connect(_on_event_player_damaged)
		if game_events.has_signal("headshot_landed"):
			if not game_events.headshot_landed.is_connected(_on_event_headshot):
				game_events.headshot_landed.connect(_on_event_headshot)

func _on_event_wave_spawning(wave_num: int, zombie_count: int):
	update_wave_info(wave_num, zombie_count, zombie_count)

func _on_event_zombie_killed(_zombie: Node, _killer_id: int, _weapon: String, is_headshot: bool):
	# Show hitmarker
	show_hitmarker(is_headshot, true)
	# Add combo
	add_combo_kill()

func _on_event_player_damaged(peer_id: int, _damage: float, _attacker_id: int, _damage_type: String):
	var local_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	if peer_id == local_id:
		show_damage_indicator()

func _on_event_headshot(_attacker_id: int, _target: Node):
	show_hitmarker(true, false)

func _setup_integrated_ui():
	# Get references to child UI elements
	minimap_ref = get_node_or_null("Minimap")
	objective_tracker_ref = get_node_or_null("ObjectiveTracker")
	kill_feed_ui_ref = get_node_or_null("KillFeedUI")
	scoreboard_ref = get_node_or_null("Scoreboard")
	end_round_stats_ref = get_node_or_null("EndRoundStats")

	# Bind to GameEvents if available
	var game_events = get_node_or_null("/root/GameEvents")
	if game_events:
		if kill_feed_ui_ref:
			game_events.bind_kill_feed(kill_feed_ui_ref)
		if scoreboard_ref:
			game_events.bind_scoreboard(scoreboard_ref)

func _input(event):
	# Handle scoreboard toggle (Tab key)
	if event.is_action_pressed("scoreboard") or (event is InputEventKey and event.keycode == KEY_TAB and event.pressed):
		if scoreboard_ref:
			scoreboard_ref.show_scoreboard()
	elif event.is_action_released("scoreboard") or (event is InputEventKey and event.keycode == KEY_TAB and not event.pressed):
		if scoreboard_ref:
			scoreboard_ref.hide_scoreboard()

	# Minimap zoom controls
	if minimap_ref:
		if event.is_action_pressed("minimap_zoom_in"):
			minimap_ref.zoom_in()
		elif event.is_action_pressed("minimap_zoom_out"):
			minimap_ref.zoom_out()

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

# ============================================
# KILL FEED
# ============================================

func add_kill_feed_entry(killer_name: String, victim_name: String, weapon_name: String = "", was_headshot: bool = false):
	"""Add entry to kill feed"""
	if not kill_feed:
		return

	var entry = HBoxContainer.new()
	entry.add_theme_constant_override("separation", 8)

	# Killer name
	var killer_label = Label.new()
	killer_label.text = killer_name
	killer_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	killer_label.add_theme_font_size_override("font_size", 14)
	entry.add_child(killer_label)

	# Weapon/action
	var action_label = Label.new()
	if was_headshot:
		action_label.text = "[HEADSHOT]"
		action_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	else:
		action_label.text = "[%s]" % weapon_name if weapon_name else "killed"
		action_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	action_label.add_theme_font_size_override("font_size", 12)
	entry.add_child(action_label)

	# Victim name
	var victim_label = Label.new()
	victim_label.text = victim_name
	victim_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	victim_label.add_theme_font_size_override("font_size", 14)
	entry.add_child(victim_label)

	kill_feed.add_child(entry)

	# Limit entries
	while kill_feed.get_child_count() > MAX_KILL_FEED_ENTRIES:
		var old_entry = kill_feed.get_child(0)
		kill_feed.remove_child(old_entry)
		old_entry.queue_free()

	# Fade out after duration
	var tween = create_tween()
	tween.tween_interval(KILL_FEED_DURATION)
	tween.tween_property(entry, "modulate:a", 0.0, 0.5)
	tween.tween_callback(entry.queue_free)

func show_zombie_kill(zombie_type: String, was_headshot: bool = false, points: int = 0):
	"""Show zombie kill in kill feed"""
	var killer_name = "You"
	var victim_name = zombie_type
	var weapon = "Pistol"

	if player and "current_weapon_data" in player:
		var weapon_data = player.current_weapon_data
		if weapon_data and "item_name" in weapon_data:
			weapon = weapon_data.item_name

	add_kill_feed_entry(killer_name, victim_name, weapon, was_headshot)

	# Show points popup
	if points > 0:
		show_points_popup(points, was_headshot)

func show_points_popup(points: int, was_headshot: bool = false):
	"""Show floating points popup"""
	var popup = Label.new()
	popup.text = "+%d" % points
	if was_headshot:
		popup.text += " HEADSHOT!"
		popup.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	else:
		popup.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))

	popup.add_theme_font_size_override("font_size", 20)
	popup.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	popup.add_theme_constant_override("shadow_offset_x", 1)
	popup.add_theme_constant_override("shadow_offset_y", 1)

	popup.position = get_viewport().get_visible_rect().size / 2 + Vector2(randf_range(-50, 50), 50)
	add_child(popup)

	# Animate upward and fade
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position:y", popup.position.y - 80, 1.0)
	tween.tween_property(popup, "modulate:a", 0.0, 1.0)
	tween.chain().tween_callback(popup.queue_free)

# ============================================
# SIGIL HEALTH
# ============================================

func update_sigil_health(current: float, maximum: float):
	"""Update the sigil health bar"""
	if sigil_bar:
		sigil_bar.max_value = maximum
		sigil_bar.value = current

		# Color based on health percentage
		var health_percent = current / maximum if maximum > 0 else 0
		if health_percent < 0.25:
			sigil_bar.modulate = Color(1.0, 0.2, 0.2)
		elif health_percent < 0.5:
			sigil_bar.modulate = Color(1.0, 0.6, 0.2)
		else:
			sigil_bar.modulate = Color(0.4, 0.8, 1.0)

	if sigil_percent:
		var percent = int((current / maximum) * 100) if maximum > 0 else 0
		sigil_percent.text = "%d%%" % percent

# ============================================
# ENHANCED UI ELEMENTS
# ============================================

func _create_combo_display():
	"""Create combo counter display"""
	combo_label = Label.new()
	combo_label.name = "ComboLabel"
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_label.add_theme_font_size_override("font_size", 32)
	combo_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	combo_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	combo_label.add_theme_constant_override("shadow_offset_x", 2)
	combo_label.add_theme_constant_override("shadow_offset_y", 2)
	combo_label.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	combo_label.position = Vector2(-150, -50)
	combo_label.visible = false
	add_child(combo_label)

func _create_hitmarker():
	"""Create hitmarker crosshair indicator"""
	hitmarker = Control.new()
	hitmarker.name = "Hitmarker"
	hitmarker.set_anchors_preset(Control.PRESET_CENTER)
	hitmarker.custom_minimum_size = Vector2(40, 40)
	hitmarker.visible = false
	add_child(hitmarker)

	# Create hitmarker lines
	for i in range(4):
		var line = ColorRect.new()
		line.color = Color.WHITE
		line.size = Vector2(12, 2)
		line.position = Vector2(-6, -1)

		match i:
			0:  # Top left
				line.rotation = deg_to_rad(-45)
				line.position = Vector2(-15, -15)
			1:  # Top right
				line.rotation = deg_to_rad(45)
				line.position = Vector2(5, -15)
			2:  # Bottom left
				line.rotation = deg_to_rad(45)
				line.position = Vector2(-15, 5)
			3:  # Bottom right
				line.rotation = deg_to_rad(-45)
				line.position = Vector2(5, 5)

		hitmarker.add_child(line)

func _create_low_health_overlay():
	"""Create low health vignette overlay"""
	low_health_overlay = ColorRect.new()
	low_health_overlay.name = "LowHealthOverlay"
	low_health_overlay.color = Color(0.5, 0, 0, 0)
	low_health_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	low_health_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(low_health_overlay)
	move_child(low_health_overlay, 0)  # Put behind other elements

func show_hitmarker(is_headshot: bool = false, is_kill: bool = false):
	"""Show hitmarker feedback"""
	if not hitmarker:
		return

	hitmarker.visible = true

	# Color based on hit type
	var color = Color.WHITE
	if is_kill:
		color = Color(1.0, 0.3, 0.3)  # Red for kills
	elif is_headshot:
		color = Color(1.0, 0.8, 0.2)  # Yellow for headshots

	for child in hitmarker.get_children():
		if child is ColorRect:
			child.color = color

	# Scale animation
	hitmarker.scale = Vector2(1.5, 1.5) if is_kill else Vector2(1.2, 1.2)

	var tween = create_tween()
	tween.tween_property(hitmarker, "scale", Vector2.ONE, 0.15)
	tween.tween_property(hitmarker, "modulate:a", 0.0, 0.1)
	tween.tween_callback(_reset_hitmarker)

func _reset_hitmarker():
	if hitmarker:
		hitmarker.visible = false
		hitmarker.modulate.a = 1.0

func add_combo_kill():
	"""Add to combo counter"""
	combo_count += 1
	combo_timer = 3.0  # Reset combo timer

	if combo_label:
		combo_label.visible = true
		combo_label.text = "x%d COMBO!" % combo_count

		# Scale punch animation
		combo_label.scale = Vector2(1.3, 1.3)
		var tween = create_tween()
		tween.tween_property(combo_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		# Color based on combo
		if combo_count >= 10:
			combo_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.8))  # Pink
		elif combo_count >= 5:
			combo_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))  # Orange
		else:
			combo_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))  # Yellow

func _update_combo(delta: float):
	"""Update combo timer"""
	if combo_timer > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			# Combo ended
			if combo_count > 1:
				_show_combo_end(combo_count)
			combo_count = 0
			if combo_label:
				combo_label.visible = false

func _show_combo_end(final_combo: int):
	"""Show combo end bonus"""
	var bonus = final_combo * 10
	show_notification("COMBO x%d - +%d points!" % [final_combo, bonus])

	# Award bonus points
	if has_node("/root/PointsSystem"):
		var points_system = get_node("/root/PointsSystem")
		if points_system.has_method("add_points"):
			points_system.add_points(bonus)

func _update_low_health_effect():
	"""Update low health visual effect"""
	if not player or not low_health_overlay:
		return

	if "current_health" in player and "max_health" in player:
		var health = player.current_health
		var max_health = player.max_health
		var health_percent = health / max_health if max_health > 0 else 1.0

		# Show overlay when below 30% health
		if health_percent < 0.3:
			var intensity = (0.3 - health_percent) / 0.3  # 0 to 1
			low_health_overlay.color.a = intensity * 0.3  # Max 30% opacity

			# Pulse effect when very low
			if health_percent < 0.15:
				var pulse = (sin(Time.get_ticks_msec() * 0.005) + 1) * 0.5
				low_health_overlay.color.a = intensity * 0.3 * (0.5 + pulse * 0.5)
		else:
			low_health_overlay.color.a = 0

		# Check for health change
		if health < last_health:
			_on_player_damaged(last_health - health)
		elif health > last_health:
			_on_player_healed(health - last_health)

		last_health = health

func _on_player_damaged(damage: float):
	"""React to player taking damage"""
	show_damage_indicator()

	# Screen shake effect (if camera available)
	if player and player.has_node("Camera3D"):
		var camera = player.get_node("Camera3D")
		if camera.has_method("add_trauma"):
			camera.add_trauma(min(damage / 50.0, 0.5))

	# Flash health bar red
	if health_bar:
		var tween = create_tween()
		tween.tween_property(health_bar, "modulate", Color(1.0, 0.3, 0.3), 0.1)
		tween.tween_property(health_bar, "modulate", Color.WHITE, 0.2)

func _on_player_healed(amount: float):
	"""React to player healing"""
	# Flash health bar green
	if health_bar:
		var tween = create_tween()
		tween.tween_property(health_bar, "modulate", Color(0.3, 1.0, 0.3), 0.1)
		tween.tween_property(health_bar, "modulate", Color.WHITE, 0.3)

	# Show heal indicator
	var heal_popup = Label.new()
	heal_popup.text = "+%d HP" % int(amount)
	heal_popup.add_theme_font_size_override("font_size", 18)
	heal_popup.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	heal_popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heal_popup.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	heal_popup.position = Vector2(-100, 80)
	add_child(heal_popup)

	var tween = create_tween()
	tween.tween_property(heal_popup, "position:y", heal_popup.position.y - 30, 0.8)
	tween.parallel().tween_property(heal_popup, "modulate:a", 0.0, 0.8)
	tween.tween_callback(heal_popup.queue_free)

# ============================================
# AMMO & RELOAD FEEDBACK
# ============================================

func show_reload_indicator():
	"""Show reloading indicator"""
	if ammo_label:
		ammo_label.text = "RELOADING..."
		ammo_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))

func hide_reload_indicator():
	"""Hide reloading indicator and restore ammo display"""
	if ammo_label:
		ammo_label.add_theme_color_override("font_color", Color.WHITE)
	_update_weapon_info()

func show_low_ammo_warning():
	"""Flash low ammo warning"""
	if ammo_label:
		var tween = create_tween()
		tween.tween_property(ammo_label, "modulate", Color(1.0, 0.3, 0.3), 0.2)
		tween.tween_property(ammo_label, "modulate", Color.WHITE, 0.2)
		tween.set_loops(3)

func show_no_ammo():
	"""Show no ammo indicator"""
	if ammo_label:
		ammo_label.text = "NO AMMO!"
		ammo_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

# ============================================
# WAVE ANNOUNCEMENTS (ENHANCED)
# ============================================

func _show_wave_announcement_enhanced(text: String, subtitle: String = ""):
	"""Enhanced wave announcement with animations"""
	if not wave_announcement:
		wave_announcement = Label.new()
		wave_announcement.name = "WaveAnnouncement"
		wave_announcement.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wave_announcement.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		wave_announcement.set_anchors_preset(Control.PRESET_CENTER)
		wave_announcement.add_theme_font_size_override("font_size", 48)
		wave_announcement.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		wave_announcement.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
		wave_announcement.add_theme_constant_override("shadow_offset_x", 3)
		wave_announcement.add_theme_constant_override("shadow_offset_y", 3)
		add_child(wave_announcement)

	wave_announcement.text = text
	wave_announcement.visible = true
	wave_announcement.modulate.a = 0
	wave_announcement.scale = Vector2(0.5, 0.5)

	# Animate in
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(wave_announcement, "modulate:a", 1.0, 0.3)
	tween.tween_property(wave_announcement, "scale", Vector2(1.0, 1.0), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Hold and fade out
	tween.chain().tween_interval(2.0)
	tween.tween_property(wave_announcement, "modulate:a", 0.0, 0.5)
	tween.tween_callback(_hide_wave_announcement)

# ============================================
# TWEEN CALLBACK HELPERS
# ============================================

func _hide_wave_announcement():
	if wave_announcement:
		wave_announcement.visible = false

func _hide_damage_indicator():
	if damage_indicator:
		damage_indicator.visible = false
