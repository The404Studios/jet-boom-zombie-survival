extends Control
class_name KillFeed

# Kill feed UI showing recent kills, deaths, and events
# Typically displayed in top-right corner

signal kill_added(killer: String, victim: String, weapon: String)

# UI Settings
@export var max_entries: int = 5
@export var entry_duration: float = 5.0
@export var fade_duration: float = 0.5
@export var entry_spacing: float = 2.0

# Colors
@export var player_kill_color: Color = Color(0.3, 1, 0.3)  # When local player kills
@export var player_death_color: Color = Color(1, 0.3, 0.3)  # When local player dies
@export var zombie_kill_color: Color = Color(0.8, 0.8, 0.8)  # Zombie kills
@export var headshot_color: Color = Color(1, 0.8, 0)  # Headshot kills
@export var default_color: Color = Color(0.7, 0.7, 0.7)

# Container
@onready var entry_container: VBoxContainer = $EntryContainer

# State
var active_entries: Array = []  # Array of entry nodes
var local_player_name: String = "You"
var local_peer_id: int = 1

# Weapon icons (fallback text)
var weapon_icons: Dictionary = {
	"ak47": "[AK]",
	"m16": "[M16]",
	"shotgun": "[SG]",
	"pistol": "[P]",
	"revolver": "[REV]",
	"sniper": "[SNP]",
	"rpg": "[RPG]",
	"machinegun": "[MG]",
	"knife": "[K]",
	"grenade": "[G]",
	"explosion": "[EXP]",
	"headshot": "[HS]",
	"melee": "[M]",
	"unknown": "[?]"
}

func _ready():
	# Setup container
	if not entry_container:
		entry_container = VBoxContainer.new()
		entry_container.name = "EntryContainer"
		add_child(entry_container)

	entry_container.add_theme_constant_override("separation", int(entry_spacing))

	# Get local player info
	if multiplayer.has_multiplayer_peer():
		local_peer_id = multiplayer.get_unique_id()

	# Connect to player manager for death events
	var player_manager = get_node_or_null("/root/PlayerManager")
	if player_manager and player_manager.has_signal("player_died"):
		player_manager.player_died.connect(_on_player_died)

# ============================================
# ADD ENTRIES
# ============================================

func add_kill(killer_name: String, victim_name: String, weapon: String = "",
			  is_headshot: bool = false, killer_is_local: bool = false,
			  victim_is_local: bool = false):
	"""Add a kill to the feed"""
	var entry = _create_entry(killer_name, victim_name, weapon, is_headshot,
							  killer_is_local, victim_is_local)

	entry_container.add_child(entry)
	active_entries.append(entry)

	# Move to top
	entry_container.move_child(entry, 0)

	# Limit entries
	while active_entries.size() > max_entries:
		var old = active_entries.pop_back()
		if is_instance_valid(old):
			old.queue_free()

	# Animate in
	entry.modulate.a = 0
	entry.position.x = 50

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(entry, "modulate:a", 1.0, 0.2)
	tween.tween_property(entry, "position:x", 0.0, 0.2)

	# Schedule removal
	_schedule_removal(entry)

	kill_added.emit(killer_name, victim_name, weapon)

func add_zombie_kill(player_name: String, zombie_type: String, weapon: String = "",
					 is_headshot: bool = false, is_local_player: bool = false):
	"""Add a zombie kill to the feed"""
	var entry = _create_zombie_entry(player_name, zombie_type, weapon,
									  is_headshot, is_local_player)

	entry_container.add_child(entry)
	active_entries.append(entry)
	entry_container.move_child(entry, 0)

	while active_entries.size() > max_entries:
		var old = active_entries.pop_back()
		if is_instance_valid(old):
			old.queue_free()

	# Animate
	entry.modulate.a = 0
	var tween = create_tween()
	tween.tween_property(entry, "modulate:a", 1.0, 0.2)

	_schedule_removal(entry)

func add_event(text: String, color: Color = Color.WHITE):
	"""Add a custom event to the feed"""
	var entry = _create_event_entry(text, color)

	entry_container.add_child(entry)
	active_entries.append(entry)
	entry_container.move_child(entry, 0)

	while active_entries.size() > max_entries:
		var old = active_entries.pop_back()
		if is_instance_valid(old):
			old.queue_free()

	entry.modulate.a = 0
	var tween = create_tween()
	tween.tween_property(entry, "modulate:a", 1.0, 0.2)

	_schedule_removal(entry)

# ============================================
# CREATE ENTRIES
# ============================================

func _create_entry(killer: String, victim: String, weapon: String,
				   is_headshot: bool, killer_is_local: bool,
				   victim_is_local: bool) -> PanelContainer:
	var panel = PanelContainer.new()

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	margin.add_child(hbox)

	# Killer name
	var killer_label = Label.new()
	killer_label.text = killer
	if killer_is_local:
		killer_label.modulate = player_kill_color
	else:
		killer_label.modulate = default_color
	hbox.add_child(killer_label)

	# Weapon icon
	var weapon_label = Label.new()
	var weapon_key = weapon.to_lower().replace(" ", "_")
	weapon_label.text = weapon_icons.get(weapon_key, weapon_icons["unknown"])
	if is_headshot:
		weapon_label.text = weapon_icons["headshot"]
		weapon_label.modulate = headshot_color
	else:
		weapon_label.modulate = Color(0.6, 0.6, 0.6)
	hbox.add_child(weapon_label)

	# Victim name
	var victim_label = Label.new()
	victim_label.text = victim
	if victim_is_local:
		victim_label.modulate = player_death_color
	else:
		victim_label.modulate = default_color
	hbox.add_child(victim_label)

	return panel

func _create_zombie_entry(player: String, zombie_type: String, weapon: String,
						   is_headshot: bool, is_local: bool) -> PanelContainer:
	var panel = PanelContainer.new()

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.4)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_bottom", 3)
	panel.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	margin.add_child(hbox)

	# Player name
	var player_label = Label.new()
	player_label.text = player
	player_label.modulate = player_kill_color if is_local else zombie_kill_color
	hbox.add_child(player_label)

	# Action
	var action_label = Label.new()
	if is_headshot:
		action_label.text = " [HS] killed "
		action_label.modulate = headshot_color
	else:
		action_label.text = " killed "
		action_label.modulate = Color(0.5, 0.5, 0.5)
	hbox.add_child(action_label)

	# Zombie type
	var zombie_label = Label.new()
	zombie_label.text = zombie_type
	zombie_label.modulate = Color(0.6, 0.8, 0.6)
	hbox.add_child(zombie_label)

	return panel

func _create_event_entry(text: String, color: Color) -> PanelContainer:
	var panel = PanelContainer.new()

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.4)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_bottom", 3)
	panel.add_child(margin)

	var label = Label.new()
	label.text = text
	label.modulate = color
	margin.add_child(label)

	return panel

# ============================================
# REMOVAL
# ============================================

func _schedule_removal(entry: Node):
	await get_tree().create_timer(entry_duration).timeout

	if not is_instance_valid(entry):
		return

	# Fade out
	var tween = create_tween()
	tween.tween_property(entry, "modulate:a", 0.0, fade_duration)
	tween.tween_callback(_on_entry_faded.bind(entry))

func _on_entry_faded(entry: Control):
	if entry:
		active_entries.erase(entry)
		entry.queue_free()

# ============================================
# EVENT HANDLERS
# ============================================

func _on_player_died(peer_id: int, killer_id: int):
	var player_manager = get_node_or_null("/root/PlayerManager")
	if not player_manager:
		return

	var victim_name = "Player"
	var killer_name = "Zombie"

	# Get victim name
	if player_manager.has_method("get_player_data"):
		var victim_data = player_manager.get_player_data(peer_id)
		if victim_data:
			victim_name = victim_data.player_name

	# Determine if killed by player or zombie
	if killer_id > 0:
		# Killed by player
		var killer_data = player_manager.get_player_data(killer_id)
		if killer_data:
			killer_name = killer_data.player_name

		add_kill(killer_name, victim_name, "unknown",
				 false, killer_id == local_peer_id, peer_id == local_peer_id)
	else:
		# Killed by zombie
		add_event("%s was killed by zombies" % victim_name,
				  player_death_color if peer_id == local_peer_id else default_color)

# ============================================
# UTILITY
# ============================================

func set_local_player_name(name: String):
	local_player_name = name

func clear():
	"""Clear all entries"""
	for entry in active_entries:
		if is_instance_valid(entry):
			entry.queue_free()
	active_entries.clear()
