extends Control

# HUD controller - displays game info, player stats, wave info, and points
# Integrates with ArenaManager, Player, and PointsSystem

@onready var wave_label = $TopLeft/WaveLabel if has_node("TopLeft/WaveLabel") else null
@onready var zombies_label = $TopLeft/ZombiesLabel if has_node("TopLeft/ZombiesLabel") else null
@onready var points_label = $TopLeft/PointsLabel if has_node("TopLeft/PointsLabel") else null

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

var player: Node = null
var current_wave: int = 0
var current_points: int = 500

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

	# Connect to arena manager if available
	await get_tree().create_timer(0.1).timeout
	_connect_arena_manager()

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

func show_damage_indicator(direction: Vector3 = Vector3.ZERO):
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
