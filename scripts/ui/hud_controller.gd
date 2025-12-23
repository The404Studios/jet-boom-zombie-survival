extends Node

# Simple HUD controller script
# Updates HUD elements with game data

@onready var wave_label = $TopLeft/WaveLabel
@onready var zombies_label = $TopLeft/ZombiesLabel
@onready var points_label = $TopLeft/PointsLabel

@onready var health_bar = $TopRight/HealthBar
@onready var health_label = $TopRight/HealthLabel
@onready var stamina_bar = $TopRight/StaminaBar
@onready var stamina_label = $TopRight/StaminaLabel

@onready var weapon_label = $BottomCenter/WeaponLabel
@onready var ammo_label = $BottomCenter/AmmoLabel

@onready var interact_label = $BottomRight/InteractLabel
@onready var extraction_label = $BottomRight/ExtractionLabel

var player: Node = null

func _ready():
	# Find player
	await get_tree().create_timer(0.5).timeout
	_find_player()

	# Hide interact labels initially
	interact_label.visible = false
	extraction_label.visible = false

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

	if player.has("current_health") and player.has("max_health"):
		var health = player.current_health
		var max_health = player.max_health

		health_bar.value = health
		health_bar.max_value = max_health
		health_label.text = "Health: %d/%d" % [int(health), int(max_health)]

func _update_stamina():
	if not player:
		return

	if player.has("current_stamina") and player.has("max_stamina"):
		var stamina = player.current_stamina
		var max_stamina = player.max_stamina

		stamina_bar.value = stamina
		stamina_bar.max_value = max_stamina
		stamina_label.text = "Stamina: %d/%d" % [int(stamina), int(max_stamina)]

func _update_weapon_info():
	if not player:
		return

	if player.has("current_weapon_data"):
		var weapon = player.current_weapon_data
		if weapon:
			weapon_label.text = weapon.item_name
		else:
			weapon_label.text = "Unarmed"

	if player.has("current_ammo") and player.has("reserve_ammo"):
		ammo_label.text = "%d / %d" % [player.current_ammo, player.reserve_ammo]

func update_wave_info(wave: int, zombies_alive: int, zombies_total: int):
	wave_label.text = "Wave: %d" % wave
	zombies_label.text = "Zombies: %d/%d" % [zombies_alive, zombies_total]

func update_points(points: int):
	points_label.text = "Points: %d" % points

func show_interact_prompt(text: String):
	interact_label.text = text
	interact_label.visible = true

func hide_interact_prompt():
	interact_label.visible = false

func show_extraction_prompt():
	extraction_label.visible = true

func hide_extraction_prompt():
	extraction_label.visible = false
