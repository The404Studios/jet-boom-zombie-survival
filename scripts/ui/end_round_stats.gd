extends Control
class_name EndRoundStats

# End of round/game statistics screen
# Shows player performance, awards, and leaderboard

signal continue_pressed
signal main_menu_pressed
signal restart_pressed

# UI Elements
var panel: PanelContainer
var title_label: Label
var stats_container: VBoxContainer
var player_list_container: VBoxContainer
var awards_container: HBoxContainer
var button_container: HBoxContainer

# Settings
@export var victory_color: Color = Color(0.3, 1, 0.3)
@export var defeat_color: Color = Color(1, 0.3, 0.3)
@export var gold_color: Color = Color(1, 0.85, 0.3)
@export var silver_color: Color = Color(0.75, 0.75, 0.8)
@export var bronze_color: Color = Color(0.8, 0.5, 0.2)

# Stats data
var is_victory: bool = false
var round_number: int = 0
var total_rounds: int = 0
var game_time: float = 0.0
var player_stats: Array = []  # Array of player stat dictionaries

# Awards
var awards: Array = []  # Array of {name, description, player_name, icon}

func _ready():
	# Start hidden
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Create UI
	_create_ui()

func _create_ui():
	# Full screen semi-transparent background
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.8)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# Main panel
	panel = PanelContainer.new()
	panel.set_anchors_preset(PRESET_CENTER)
	panel.custom_minimum_size = Vector2(700, 550)
	panel.position = Vector2(-350, -275)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_color = Color(0.4, 0.4, 0.5)
	panel.add_theme_stylebox_override("panel", style)

	add_child(panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 15)
	margin.add_child(main_vbox)

	# Title
	title_label = Label.new()
	title_label.text = "ROUND COMPLETE"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 36)
	title_label.add_theme_color_override("font_color", victory_color)
	main_vbox.add_child(title_label)

	# Subtitle (wave number / game time)
	var subtitle = Label.new()
	subtitle.name = "Subtitle"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	main_vbox.add_child(subtitle)

	# Horizontal split for stats and players
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 30)
	main_vbox.add_child(hbox)

	# Left side - Your Stats
	var left_panel = PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(300, 280)
	var left_style = StyleBoxFlat.new()
	left_style.bg_color = Color(0.15, 0.15, 0.2, 0.8)
	left_style.corner_radius_top_left = 8
	left_style.corner_radius_top_right = 8
	left_style.corner_radius_bottom_left = 8
	left_style.corner_radius_bottom_right = 8
	left_panel.add_theme_stylebox_override("panel", left_style)
	hbox.add_child(left_panel)

	var left_margin = MarginContainer.new()
	left_margin.add_theme_constant_override("margin_left", 15)
	left_margin.add_theme_constant_override("margin_right", 15)
	left_margin.add_theme_constant_override("margin_top", 10)
	left_margin.add_theme_constant_override("margin_bottom", 10)
	left_panel.add_child(left_margin)

	stats_container = VBoxContainer.new()
	stats_container.add_theme_constant_override("separation", 8)
	left_margin.add_child(stats_container)

	# Right side - Leaderboard
	var right_panel = PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(300, 280)
	right_panel.add_theme_stylebox_override("panel", left_style.duplicate())
	hbox.add_child(right_panel)

	var right_margin = MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 15)
	right_margin.add_theme_constant_override("margin_right", 15)
	right_margin.add_theme_constant_override("margin_top", 10)
	right_margin.add_theme_constant_override("margin_bottom", 10)
	right_panel.add_child(right_margin)

	player_list_container = VBoxContainer.new()
	player_list_container.add_theme_constant_override("separation", 6)
	right_margin.add_child(player_list_container)

	# Awards section
	awards_container = HBoxContainer.new()
	awards_container.alignment = BoxContainer.ALIGNMENT_CENTER
	awards_container.add_theme_constant_override("separation", 20)
	main_vbox.add_child(awards_container)

	# Buttons
	button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_theme_constant_override("separation", 20)
	main_vbox.add_child(button_container)

func show_round_complete(wave: int, stats: Dictionary = {}, victory: bool = true):
	"""Show round complete screen"""
	is_victory = victory
	round_number = wave

	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Update title
	if victory:
		title_label.text = "WAVE %d COMPLETE" % wave
		title_label.add_theme_color_override("font_color", victory_color)
	else:
		title_label.text = "WAVE %d FAILED" % wave
		title_label.add_theme_color_override("font_color", defeat_color)

	# Update subtitle
	var subtitle = panel.get_node_or_null("MarginContainer/VBoxContainer/Subtitle")
	if subtitle:
		var time_str = _format_time(stats.get("round_time", 0))
		subtitle.text = "Time: %s" % time_str

	# Populate stats
	_populate_stats(stats)

	# Populate player list
	_populate_players(stats.get("players", []))

	# Show awards
	_populate_awards(stats.get("awards", []))

	# Create buttons
	_create_buttons(true)

	# Animate in
	modulate.a = 0
	panel.scale = Vector2(0.8, 0.8)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func show_game_over(victory: bool, stats: Dictionary = {}):
	"""Show game over screen"""
	is_victory = victory
	round_number = stats.get("final_wave", 0)

	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Update title
	if victory:
		title_label.text = "VICTORY!"
		title_label.add_theme_color_override("font_color", victory_color)
	else:
		title_label.text = "GAME OVER"
		title_label.add_theme_color_override("font_color", defeat_color)

	# Update subtitle
	var subtitle = panel.get_node_or_null("MarginContainer/VBoxContainer/Subtitle")
	if subtitle:
		var time_str = _format_time(stats.get("total_time", 0))
		subtitle.text = "Survived to Wave %d | Total Time: %s" % [round_number, time_str]

	# Populate stats with game totals
	_populate_stats(stats)

	# Populate player list
	_populate_players(stats.get("players", []))

	# Show awards
	_populate_awards(stats.get("awards", []))

	# Create buttons (game over mode)
	_create_buttons(false)

	# Animate in
	modulate.a = 0
	panel.scale = Vector2(0.8, 0.8)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _populate_stats(stats: Dictionary):
	# Clear existing
	for child in stats_container.get_children():
		child.queue_free()

	# Header
	var header = Label.new()
	header.text = "YOUR STATS"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", gold_color)
	stats_container.add_child(header)

	# Add separator
	var sep = HSeparator.new()
	stats_container.add_child(sep)

	# Stats rows
	var stat_rows = [
		["Kills", stats.get("kills", 0)],
		["Headshots", stats.get("headshots", 0)],
		["Damage Dealt", _format_number(stats.get("damage_dealt", 0))],
		["Damage Taken", _format_number(stats.get("damage_taken", 0))],
		["Deaths", stats.get("deaths", 0)],
		["Accuracy", "%d%%" % stats.get("accuracy", 0)],
		["Points Earned", _format_number(stats.get("points_earned", 0))],
		["Items Collected", stats.get("items_collected", 0)]
	]

	for row in stat_rows:
		_add_stat_row(stats_container, row[0], str(row[1]))

func _add_stat_row(parent: Control, label_text: String, value_text: String):
	var hbox = HBoxContainer.new()

	var label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	hbox.add_child(label)

	var value = Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_color_override("font_color", Color.WHITE)
	hbox.add_child(value)

	parent.add_child(hbox)

func _populate_players(players: Array):
	# Clear existing
	for child in player_list_container.get_children():
		child.queue_free()

	# Header
	var header = Label.new()
	header.text = "LEADERBOARD"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", gold_color)
	player_list_container.add_child(header)

	# Column headers
	var col_header = HBoxContainer.new()
	var rank_h = Label.new()
	rank_h.text = "#"
	rank_h.custom_minimum_size = Vector2(25, 0)
	rank_h.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	col_header.add_child(rank_h)

	var name_h = Label.new()
	name_h.text = "Player"
	name_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_h.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	col_header.add_child(name_h)

	var kills_h = Label.new()
	kills_h.text = "Kills"
	kills_h.custom_minimum_size = Vector2(50, 0)
	kills_h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kills_h.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	col_header.add_child(kills_h)

	var score_h = Label.new()
	score_h.text = "Score"
	score_h.custom_minimum_size = Vector2(60, 0)
	score_h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_h.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	col_header.add_child(score_h)

	player_list_container.add_child(col_header)

	# Separator
	var sep = HSeparator.new()
	player_list_container.add_child(sep)

	# If no players provided, create dummy data
	if players.is_empty():
		players = [{"name": "You", "kills": 0, "score": 0, "is_local": true}]

	# Sort by score
	players.sort_custom(func(a, b): return a.get("score", 0) > b.get("score", 0))

	# Add player rows
	for i in range(min(players.size(), 8)):
		var p = players[i]
		_add_player_row(player_list_container, i + 1, p)

func _add_player_row(parent: Control, rank: int, player_data: Dictionary):
	var hbox = HBoxContainer.new()

	# Rank medal
	var rank_label = Label.new()
	rank_label.custom_minimum_size = Vector2(25, 0)
	match rank:
		1:
			rank_label.text = "1"
			rank_label.add_theme_color_override("font_color", gold_color)
		2:
			rank_label.text = "2"
			rank_label.add_theme_color_override("font_color", silver_color)
		3:
			rank_label.text = "3"
			rank_label.add_theme_color_override("font_color", bronze_color)
		_:
			rank_label.text = str(rank)
			rank_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hbox.add_child(rank_label)

	# Name
	var name_label = Label.new()
	name_label.text = player_data.get("name", "Player")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if player_data.get("is_local", false):
		name_label.text += " (You)"
		name_label.add_theme_color_override("font_color", Color(0.8, 1, 0.8))
	else:
		name_label.add_theme_color_override("font_color", Color.WHITE)
	hbox.add_child(name_label)

	# Kills
	var kills_label = Label.new()
	kills_label.text = str(player_data.get("kills", 0))
	kills_label.custom_minimum_size = Vector2(50, 0)
	kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kills_label.add_theme_color_override("font_color", Color(1, 0.6, 0.6))
	hbox.add_child(kills_label)

	# Score
	var score_label = Label.new()
	score_label.text = str(player_data.get("score", 0))
	score_label.custom_minimum_size = Vector2(60, 0)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.add_theme_color_override("font_color", gold_color)
	hbox.add_child(score_label)

	parent.add_child(hbox)

func _populate_awards(award_list: Array):
	# Clear existing
	for child in awards_container.get_children():
		child.queue_free()

	if award_list.is_empty():
		return

	# Add award cards
	for award in award_list:
		var card = _create_award_card(award)
		awards_container.add_child(card)

func _create_award_card(award: Dictionary) -> Control:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(130, 80)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.18, 0.1, 0.9)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_color = gold_color
	card.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	card.add_child(vbox)

	# Icon
	var icon = Label.new()
	icon.text = award.get("icon", "*")
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 24)
	icon.add_theme_color_override("font_color", gold_color)
	vbox.add_child(icon)

	# Title
	var title = Label.new()
	title.text = award.get("name", "Award")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(title)

	# Player name
	var player = Label.new()
	player.text = award.get("player_name", "")
	player.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player.add_theme_font_size_override("font_size", 10)
	player.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(player)

	return card

func _create_buttons(is_round_end: bool):
	# Clear existing buttons
	for child in button_container.get_children():
		child.queue_free()

	if is_round_end:
		# Continue button
		var continue_btn = Button.new()
		continue_btn.text = "CONTINUE"
		continue_btn.custom_minimum_size = Vector2(150, 45)
		continue_btn.pressed.connect(_on_continue_pressed)
		button_container.add_child(continue_btn)
	else:
		# Restart button
		var restart_btn = Button.new()
		restart_btn.text = "PLAY AGAIN"
		restart_btn.custom_minimum_size = Vector2(150, 45)
		restart_btn.pressed.connect(_on_restart_pressed)
		button_container.add_child(restart_btn)

		# Main menu button
		var menu_btn = Button.new()
		menu_btn.text = "MAIN MENU"
		menu_btn.custom_minimum_size = Vector2(150, 45)
		menu_btn.pressed.connect(_on_main_menu_pressed)
		button_container.add_child(menu_btn)

func _on_continue_pressed():
	_hide_screen()
	continue_pressed.emit()

func _on_restart_pressed():
	_hide_screen()
	restart_pressed.emit()

func _on_main_menu_pressed():
	_hide_screen()
	main_menu_pressed.emit()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _hide_screen():
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_callback(_on_screen_hidden)

func _on_screen_hidden():
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ============================================
# UTILITY
# ============================================

func _format_time(seconds: float) -> String:
	var mins = int(seconds) / 60
	var secs = int(seconds) % 60
	return "%d:%02d" % [mins, secs]

func _format_number(num: float) -> String:
	if num >= 1000000:
		return "%.1fM" % (num / 1000000)
	elif num >= 1000:
		return "%.1fK" % (num / 1000)
	else:
		return str(int(num))

# ============================================
# AWARD GENERATION
# ============================================

static func generate_awards(player_stats: Array) -> Array:
	"""Generate awards based on player performance"""
	var awards_list = []

	if player_stats.is_empty():
		return awards_list

	# Most Kills
	var most_kills = player_stats.duplicate()
	most_kills.sort_custom(func(a, b): return a.get("kills", 0) > b.get("kills", 0))
	if most_kills[0].get("kills", 0) > 0:
		awards_list.append({
			"name": "Zombie Slayer",
			"description": "Most kills",
			"player_name": most_kills[0].get("name", "Player"),
			"icon": "!"
		})

	# Most Headshots
	var most_headshots = player_stats.duplicate()
	most_headshots.sort_custom(func(a, b): return a.get("headshots", 0) > b.get("headshots", 0))
	if most_headshots[0].get("headshots", 0) > 0:
		awards_list.append({
			"name": "Sharpshooter",
			"description": "Most headshots",
			"player_name": most_headshots[0].get("name", "Player"),
			"icon": "O"
		})

	# Most Damage
	var most_damage = player_stats.duplicate()
	most_damage.sort_custom(func(a, b): return a.get("damage_dealt", 0) > b.get("damage_dealt", 0))
	if most_damage[0].get("damage_dealt", 0) > 0:
		awards_list.append({
			"name": "Heavy Hitter",
			"description": "Most damage dealt",
			"player_name": most_damage[0].get("name", "Player"),
			"icon": "#"
		})

	# Survivor (least deaths)
	var survivor = player_stats.duplicate()
	survivor.sort_custom(func(a, b): return a.get("deaths", 0) < b.get("deaths", 0))
	awards_list.append({
		"name": "Survivor",
		"description": "Fewest deaths",
		"player_name": survivor[0].get("name", "Player"),
		"icon": "+"
	})

	# Best Accuracy
	var best_accuracy = player_stats.duplicate()
	best_accuracy.sort_custom(func(a, b): return a.get("accuracy", 0) > b.get("accuracy", 0))
	if best_accuracy[0].get("accuracy", 0) > 0:
		awards_list.append({
			"name": "Marksman",
			"description": "Best accuracy",
			"player_name": best_accuracy[0].get("name", "Player"),
			"icon": ">"
		})

	return awards_list
