extends Control
class_name ObjectiveTracker

# Displays active objectives and mission progress
# Shows wave info, zombie counts, and special objectives

signal objective_completed(objective_id: String)
signal all_objectives_completed

# UI Settings
@export var max_visible_objectives: int = 5
@export var fade_completed_after: float = 2.0
@export var show_wave_info: bool = true

# Colors
@export var objective_color: Color = Color(0.9, 0.9, 0.9)
@export var completed_color: Color = Color(0.4, 1, 0.4)
@export var failed_color: Color = Color(1, 0.4, 0.4)
@export var bonus_color: Color = Color(1, 0.8, 0.3)

# Container
@onready var objective_container: VBoxContainer = $ObjectiveContainer

# Data
var objectives: Dictionary = {}  # id -> ObjectiveData
var objective_nodes: Dictionary = {}  # id -> UI node

# Wave tracking
var wave_objective_id: String = "wave_objective"
var current_wave: int = 0
var zombies_remaining: int = 0
var total_zombies: int = 0

class ObjectiveData:
	var id: String
	var title: String
	var description: String
	var progress: int = 0
	var max_progress: int = 1
	var is_completed: bool = false
	var is_failed: bool = false
	var is_bonus: bool = false
	var is_hidden: bool = false
	var icon: String = ">"

func _ready():
	# Setup container
	if not objective_container:
		objective_container = VBoxContainer.new()
		objective_container.name = "ObjectiveContainer"
		objective_container.add_theme_constant_override("separation", 4)
		add_child(objective_container)

	# Connect to game systems
	_connect_to_systems()

func _connect_to_systems():
	# Wave manager
	var wave_manager = get_node_or_null("/root/WaveManager")
	if wave_manager:
		if wave_manager.has_signal("wave_started"):
			wave_manager.wave_started.connect(_on_wave_started)
		if wave_manager.has_signal("wave_completed"):
			wave_manager.wave_completed.connect(_on_wave_completed)
		if wave_manager.has_signal("zombie_killed"):
			wave_manager.zombie_killed.connect(_on_zombie_killed)
		if wave_manager.has_signal("zombies_remaining_changed"):
			wave_manager.zombies_remaining_changed.connect(_on_zombies_remaining_changed)

	# Round manager
	var round_manager = get_node_or_null("/root/RoundManager")
	if round_manager:
		if round_manager.has_signal("round_started"):
			round_manager.round_started.connect(_on_round_started)
		if round_manager.has_signal("intermission_started"):
			round_manager.intermission_started.connect(_on_intermission_started)

	# Game event manager
	var events = get_node_or_null("/root/GameEvents")
	if events:
		if events.has_signal("zombie_killed"):
			events.zombie_killed.connect(_on_event_zombie_killed)
		if events.has_signal("boss_spawned"):
			events.boss_spawned.connect(_on_boss_spawned)

# ============================================
# OBJECTIVE MANAGEMENT
# ============================================

func add_objective(id: String, title: String, description: String = "",
				   max_progress: int = 1, is_bonus: bool = false, icon: String = ">") -> ObjectiveData:
	"""Add a new objective"""
	if objectives.has(id):
		return objectives[id]

	var obj = ObjectiveData.new()
	obj.id = id
	obj.title = title
	obj.description = description
	obj.max_progress = max_progress
	obj.is_bonus = is_bonus
	obj.icon = icon

	objectives[id] = obj
	_create_objective_ui(obj)

	return obj

func update_objective_progress(id: String, progress: int):
	"""Update objective progress"""
	if not objectives.has(id):
		return

	var obj = objectives[id]
	obj.progress = min(progress, obj.max_progress)

	if obj.progress >= obj.max_progress and not obj.is_completed:
		complete_objective(id)
	else:
		_update_objective_ui(id)

func increment_objective(id: String, amount: int = 1):
	"""Increment objective progress"""
	if not objectives.has(id):
		return

	var obj = objectives[id]
	update_objective_progress(id, obj.progress + amount)

func complete_objective(id: String):
	"""Mark objective as completed"""
	if not objectives.has(id):
		return

	var obj = objectives[id]
	obj.is_completed = true
	obj.progress = obj.max_progress

	_update_objective_ui(id)
	objective_completed.emit(id)

	# Check if all objectives completed
	_check_all_completed()

	# Fade out after delay
	await get_tree().create_timer(fade_completed_after).timeout
	_remove_objective_ui(id)

func fail_objective(id: String):
	"""Mark objective as failed"""
	if not objectives.has(id):
		return

	var obj = objectives[id]
	obj.is_failed = true

	_update_objective_ui(id)

	# Fade out after delay
	await get_tree().create_timer(fade_completed_after).timeout
	_remove_objective_ui(id)

func remove_objective(id: String):
	"""Remove objective entirely"""
	if objectives.has(id):
		objectives.erase(id)
		_remove_objective_ui(id)

func clear_all_objectives():
	"""Clear all objectives"""
	for id in objectives.keys():
		_remove_objective_ui(id)
	objectives.clear()

func _check_all_completed():
	var all_done = true
	for id in objectives:
		var obj = objectives[id]
		if not obj.is_completed and not obj.is_failed and not obj.is_hidden:
			all_done = false
			break

	if all_done:
		all_objectives_completed.emit()

# ============================================
# UI CREATION
# ============================================

func _create_objective_ui(obj: ObjectiveData):
	if objective_nodes.has(obj.id):
		return

	var panel = PanelContainer.new()
	panel.name = "Objective_%s" % obj.id

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.border_width_left = 3
	style.border_color = bonus_color if obj.is_bonus else objective_color
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	# Title line
	var title_hbox = HBoxContainer.new()
	title_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(title_hbox)

	# Icon
	var icon_label = Label.new()
	icon_label.name = "Icon"
	icon_label.text = "[%s]" % obj.icon
	icon_label.modulate = bonus_color if obj.is_bonus else objective_color
	title_hbox.add_child(icon_label)

	# Title
	var title_label = Label.new()
	title_label.name = "Title"
	title_label.text = obj.title
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.modulate = bonus_color if obj.is_bonus else objective_color
	title_hbox.add_child(title_label)

	# Progress (if applicable)
	if obj.max_progress > 1:
		var progress_label = Label.new()
		progress_label.name = "Progress"
		progress_label.text = "(%d/%d)" % [obj.progress, obj.max_progress]
		progress_label.modulate = Color(0.7, 0.7, 0.7)
		title_hbox.add_child(progress_label)

	# Description
	if not obj.description.is_empty():
		var desc_label = Label.new()
		desc_label.name = "Description"
		desc_label.text = obj.description
		desc_label.add_theme_font_size_override("font_size", 12)
		desc_label.modulate = Color(0.6, 0.6, 0.6)
		vbox.add_child(desc_label)

	# Progress bar (for multi-step objectives)
	if obj.max_progress > 1:
		var progress_bar = ProgressBar.new()
		progress_bar.name = "ProgressBar"
		progress_bar.max_value = obj.max_progress
		progress_bar.value = obj.progress
		progress_bar.show_percentage = false
		progress_bar.custom_minimum_size = Vector2(0, 4)
		vbox.add_child(progress_bar)

	# Animate in
	panel.modulate.a = 0
	panel.position.x = 30

	objective_container.add_child(panel)
	objective_nodes[obj.id] = panel

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.3)
	tween.tween_property(panel, "position:x", 0.0, 0.3)

func _update_objective_ui(id: String):
	if not objective_nodes.has(id) or not objectives.has(id):
		return

	var panel = objective_nodes[id]
	var obj = objectives[id]

	if not is_instance_valid(panel):
		return

	# Update progress label
	var progress_label = panel.get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer/Progress")
	if progress_label:
		progress_label.text = "(%d/%d)" % [obj.progress, obj.max_progress]

	# Update progress bar
	var progress_bar = panel.get_node_or_null("MarginContainer/VBoxContainer/ProgressBar")
	if progress_bar:
		var tween = create_tween()
		tween.tween_property(progress_bar, "value", float(obj.progress), 0.2)

	# Update style for completion/failure
	var style = panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		if obj.is_completed:
			style.border_color = completed_color
		elif obj.is_failed:
			style.border_color = failed_color

	# Update title color
	var title_label = panel.get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer/Title")
	if title_label:
		if obj.is_completed:
			title_label.modulate = completed_color
			title_label.text = obj.title + " [COMPLETE]"
		elif obj.is_failed:
			title_label.modulate = failed_color
			title_label.text = obj.title + " [FAILED]"

	# Update icon
	var icon_label = panel.get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer/Icon")
	if icon_label:
		if obj.is_completed:
			icon_label.text = "[+]"
			icon_label.modulate = completed_color
		elif obj.is_failed:
			icon_label.text = "[X]"
			icon_label.modulate = failed_color

func _remove_objective_ui(id: String):
	if not objective_nodes.has(id):
		return

	var panel = objective_nodes[id]
	if not is_instance_valid(panel):
		objective_nodes.erase(id)
		return

	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 0.0, 0.3)
	tween.tween_callback(panel.queue_free)

	objective_nodes.erase(id)

# ============================================
# WAVE TRACKING
# ============================================

func _on_wave_started(wave_num: int):
	current_wave = wave_num
	_update_wave_objective()

func _on_round_started(round_num: int):
	current_wave = round_num
	_update_wave_objective()

func _on_wave_completed(_wave_num: int):
	complete_objective(wave_objective_id)

func _on_zombie_killed(_zombie: Node, _killer_id: int):
	if zombies_remaining > 0:
		zombies_remaining -= 1
		_update_wave_objective()

func _on_event_zombie_killed(_zombie: Node, _killer_id: int, _weapon: String, _is_headshot: bool):
	if zombies_remaining > 0:
		zombies_remaining -= 1
		_update_wave_objective()

func _on_zombies_remaining_changed(remaining: int, total: int):
	zombies_remaining = remaining
	total_zombies = total
	_update_wave_objective()

func _on_intermission_started(_duration: float):
	remove_objective(wave_objective_id)

func _on_boss_spawned(boss: Node, boss_name: String):
	add_objective("boss_%s" % boss.get_instance_id(), "Defeat %s" % boss_name, "", 1, false, "!")

func _update_wave_objective():
	if not show_wave_info:
		return

	if not objectives.has(wave_objective_id):
		add_objective(wave_objective_id, "Wave %d" % current_wave, "Eliminate all zombies", total_zombies, false, "~")
	else:
		var obj = objectives[wave_objective_id]
		obj.title = "Wave %d" % current_wave
		obj.max_progress = total_zombies
		obj.progress = total_zombies - zombies_remaining

		if obj.progress >= obj.max_progress:
			complete_objective(wave_objective_id)
		else:
			_update_objective_ui(wave_objective_id)

func set_wave_zombies(remaining: int, total: int):
	"""Manually set wave zombie count"""
	zombies_remaining = remaining
	total_zombies = total
	_update_wave_objective()

func start_wave(wave_num: int, zombie_count: int):
	"""Start a new wave"""
	current_wave = wave_num
	zombies_remaining = zombie_count
	total_zombies = zombie_count

	# Remove old wave objective
	remove_objective(wave_objective_id)

	# Create new one
	add_objective(wave_objective_id, "Wave %d" % current_wave, "Eliminate all zombies", total_zombies, false, "~")

# ============================================
# CONVENIENCE METHODS
# ============================================

func add_kill_objective(id: String, target_name: String, kill_count: int):
	"""Add a kill X enemies objective"""
	add_objective(id, "Kill %s" % target_name, "", kill_count, false, "!")

func add_survive_objective(id: String, duration: float):
	"""Add a survive for X seconds objective"""
	var obj = add_objective(id, "Survive", "%d seconds remaining" % int(duration), int(duration), false, "~")

	# Update countdown
	_countdown_objective(id, duration)

func _countdown_objective(id: String, remaining: float):
	if not objectives.has(id):
		return

	var obj = objectives[id]
	obj.description = "%d seconds remaining" % int(remaining)
	obj.progress = int(obj.max_progress - remaining)
	_update_objective_ui(id)

	if remaining <= 0:
		complete_objective(id)
	else:
		await get_tree().create_timer(1.0).timeout
		_countdown_objective(id, remaining - 1)

func add_collect_objective(id: String, item_name: String, required_count: int):
	"""Add a collect X items objective"""
	add_objective(id, "Collect %s" % item_name, "", required_count, false, ">")

func add_defend_objective(id: String, target_name: String):
	"""Add a defend target objective"""
	add_objective(id, "Defend %s" % target_name, "Keep it alive!", 1, false, "#")

func add_bonus_objective(id: String, title: String, description: String = ""):
	"""Add a bonus objective"""
	add_objective(id, title, description, 1, true, "*")
