extends Control
class_name Scoreboard

# Multiplayer scoreboard showing player stats
# Toggle with Tab key, supports sorting and highlighting

signal scoreboard_opened
signal scoreboard_closed

# UI References
@onready var panel: PanelContainer = $Panel
@onready var player_list: VBoxContainer = $Panel/MarginContainer/VBoxContainer/PlayerList
@onready var header: HBoxContainer = $Panel/MarginContainer/VBoxContainer/Header
@onready var wave_label: Label = $Panel/MarginContainer/VBoxContainer/WaveInfo/WaveLabel
@onready var timer_label: Label = $Panel/MarginContainer/VBoxContainer/WaveInfo/TimerLabel

# Settings
@export var toggle_action: String = "scoreboard"
@export var hold_to_show: bool = true
@export var update_interval: float = 0.5
@export var max_players: int = 16

# Player row scene
var player_row_scene: PackedScene = null

# State
var is_visible: bool = false
var update_timer: float = 0.0
var player_rows: Dictionary = {}  # peer_id -> row node
var local_peer_id: int = 1

# Sorting
enum SortMode { SCORE, KILLS, DEATHS, NAME }
var current_sort: SortMode = SortMode.SCORE
var sort_ascending: bool = false

# References
var player_manager: Node = null
var network_manager: Node = null
var round_manager: Node = null

func _ready():
	# Start hidden
	visible = false
	is_visible = false

	# Get references
	player_manager = get_node_or_null("/root/PlayerManager")
	network_manager = get_node_or_null("/root/NetworkManager")
	round_manager = get_node_or_null("/root/RoundManager")

	# Get local peer ID
	if multiplayer.has_multiplayer_peer():
		local_peer_id = multiplayer.get_unique_id()

	# Setup UI
	_setup_header()
	_setup_styling()

	# Connect signals
	if player_manager:
		if player_manager.has_signal("player_spawned"):
			player_manager.player_spawned.connect(_on_player_spawned)
		if player_manager.has_signal("player_despawned"):
			player_manager.player_despawned.connect(_on_player_despawned)

func _input(event):
	if hold_to_show:
		if event.is_action_pressed(toggle_action):
			show_scoreboard()
		elif event.is_action_released(toggle_action):
			hide_scoreboard()
	else:
		if event.is_action_pressed(toggle_action):
			toggle_scoreboard()

func _process(delta):
	if not is_visible:
		return

	update_timer -= delta
	if update_timer <= 0:
		update_timer = update_interval
		refresh_scoreboard()

# ============================================
# VISIBILITY
# ============================================

func show_scoreboard():
	if is_visible:
		return

	is_visible = true
	visible = true
	refresh_scoreboard()
	scoreboard_opened.emit()

	# Animate in
	modulate.a = 0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.15)

func hide_scoreboard():
	if not is_visible:
		return

	is_visible = false

	# Animate out
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.1)
	tween.tween_callback(_hide_self)

	scoreboard_closed.emit()

func _hide_self():
	visible = false

func toggle_scoreboard():
	if is_visible:
		hide_scoreboard()
	else:
		show_scoreboard()

# ============================================
# REFRESH
# ============================================

func refresh_scoreboard():
	_update_wave_info()
	_update_player_list()

func _update_wave_info():
	if not wave_label or not timer_label:
		return

	if round_manager:
		var round_num = round_manager.get_current_round() if round_manager.has_method("get_current_round") else 0
		var is_intermission = round_manager.is_intermission() if round_manager.has_method("is_intermission") else false

		if is_intermission:
			wave_label.text = "Intermission"
			var timer = round_manager.get_state_timer() if round_manager.has_method("get_state_timer") else 0
			timer_label.text = "%02d:%02d" % [int(timer) / 60, int(timer) % 60]
		else:
			wave_label.text = "Wave %d" % round_num
			var round_time = round_manager.get_round_time() if round_manager.has_method("get_round_time") else 0
			timer_label.text = "%02d:%02d" % [int(round_time) / 60, int(round_time) % 60]
	else:
		wave_label.text = "Survival Mode"
		timer_label.text = ""

func _update_player_list():
	if not player_list:
		return

	# Get all player data
	var players_data = _get_all_player_data()

	# Sort players
	players_data.sort_custom(_sort_players)

	# Update or create rows
	var seen_peers = []

	for i in range(players_data.size()):
		var data = players_data[i]
		var peer_id = data.peer_id
		seen_peers.append(peer_id)

		if not player_rows.has(peer_id):
			_create_player_row(peer_id)

		_update_player_row(peer_id, data, i)

	# Remove rows for disconnected players
	for peer_id in player_rows.keys():
		if peer_id not in seen_peers:
			_remove_player_row(peer_id)

func _get_all_player_data() -> Array:
	var players = []

	if player_manager and player_manager.has_method("get_player_data"):
		# Get from PlayerManager
		var all_data = player_manager.player_data if "player_data" in player_manager else {}
		for peer_id in all_data:
			var data = all_data[peer_id]
			players.append({
				"peer_id": peer_id,
				"name": data.player_name if data else "Player %d" % peer_id,
				"kills": data.kills if data else 0,
				"deaths": data.deaths if data else 0,
				"score": data.score if data else 0,
				"is_alive": data.is_alive if data else true,
				"ping": 0  # Would get from network
			})
	elif network_manager:
		# Fallback to network manager
		var all_players = network_manager.get_players() if network_manager.has_method("get_players") else {}
		for peer_id in all_players:
			var info = all_players[peer_id]
			players.append({
				"peer_id": peer_id,
				"name": info.get("name", "Player %d" % peer_id),
				"kills": info.get("kills", 0),
				"deaths": info.get("deaths", 0),
				"score": info.get("score", 0),
				"is_alive": info.get("alive", true),
				"ping": info.get("ping", 0)
			})

	# If no data, add local player placeholder
	if players.is_empty():
		players.append({
			"peer_id": local_peer_id,
			"name": "You",
			"kills": 0,
			"deaths": 0,
			"score": 0,
			"is_alive": true,
			"ping": 0
		})

	return players

func _sort_players(a: Dictionary, b: Dictionary) -> bool:
	var val_a: Variant
	var val_b: Variant

	match current_sort:
		SortMode.SCORE:
			val_a = a.score
			val_b = b.score
		SortMode.KILLS:
			val_a = a.kills
			val_b = b.kills
		SortMode.DEATHS:
			val_a = a.deaths
			val_b = b.deaths
		SortMode.NAME:
			val_a = a.name.to_lower()
			val_b = b.name.to_lower()

	if sort_ascending:
		return val_a < val_b
	else:
		return val_a > val_b

# ============================================
# ROW MANAGEMENT
# ============================================

func _create_player_row(peer_id: int):
	var row = HBoxContainer.new()
	row.name = "PlayerRow_%d" % peer_id

	# Rank
	var rank_label = Label.new()
	rank_label.name = "Rank"
	rank_label.custom_minimum_size = Vector2(30, 0)
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(rank_label)

	# Name
	var name_label = Label.new()
	name_label.name = "Name"
	name_label.custom_minimum_size = Vector2(150, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	# Status indicator
	var status = ColorRect.new()
	status.name = "Status"
	status.custom_minimum_size = Vector2(10, 10)
	status.color = Color.GREEN
	row.add_child(status)

	# Kills
	var kills_label = Label.new()
	kills_label.name = "Kills"
	kills_label.custom_minimum_size = Vector2(60, 0)
	kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(kills_label)

	# Deaths
	var deaths_label = Label.new()
	deaths_label.name = "Deaths"
	deaths_label.custom_minimum_size = Vector2(60, 0)
	deaths_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(deaths_label)

	# Score
	var score_label = Label.new()
	score_label.name = "Score"
	score_label.custom_minimum_size = Vector2(80, 0)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(score_label)

	# Ping
	var ping_label = Label.new()
	ping_label.name = "Ping"
	ping_label.custom_minimum_size = Vector2(50, 0)
	ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(ping_label)

	player_list.add_child(row)
	player_rows[peer_id] = row

func _update_player_row(peer_id: int, data: Dictionary, rank: int):
	if not player_rows.has(peer_id):
		return

	var row = player_rows[peer_id]

	# Highlight local player
	if peer_id == local_peer_id:
		row.modulate = Color(1, 1, 0.8)
	else:
		row.modulate = Color.WHITE

	# Update labels
	var rank_label = row.get_node_or_null("Rank") as Label
	if rank_label:
		rank_label.text = "#%d" % (rank + 1)

	var name_label = row.get_node_or_null("Name") as Label
	if name_label:
		name_label.text = data.name
		if peer_id == local_peer_id:
			name_label.text += " (You)"

	var status = row.get_node_or_null("Status") as ColorRect
	if status:
		status.color = Color.GREEN if data.is_alive else Color.RED

	var kills_label = row.get_node_or_null("Kills") as Label
	if kills_label:
		kills_label.text = str(data.kills)

	var deaths_label = row.get_node_or_null("Deaths") as Label
	if deaths_label:
		deaths_label.text = str(data.deaths)

	var score_label = row.get_node_or_null("Score") as Label
	if score_label:
		score_label.text = str(data.score)

	var ping_label = row.get_node_or_null("Ping") as Label
	if ping_label:
		if data.ping > 0:
			ping_label.text = "%dms" % data.ping
		else:
			ping_label.text = "-"

func _remove_player_row(peer_id: int):
	if player_rows.has(peer_id):
		player_rows[peer_id].queue_free()
		player_rows.erase(peer_id)

# ============================================
# SETUP
# ============================================

func _setup_header():
	if not header:
		return

	# Clear existing
	for child in header.get_children():
		child.queue_free()

	# Create header labels
	var headers = [
		{"name": "Rank", "width": 30, "text": "#"},
		{"name": "Name", "width": 150, "text": "Player", "expand": true},
		{"name": "StatusHeader", "width": 10, "text": ""},
		{"name": "Kills", "width": 60, "text": "Kills", "sort": SortMode.KILLS},
		{"name": "Deaths", "width": 60, "text": "Deaths", "sort": SortMode.DEATHS},
		{"name": "Score", "width": 80, "text": "Score", "sort": SortMode.SCORE},
		{"name": "Ping", "width": 50, "text": "Ping"}
	]

	for h in headers:
		var label = Label.new()
		label.name = h.name
		label.text = h.text
		label.custom_minimum_size = Vector2(h.width, 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		if h.get("expand", false):
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Make sortable columns clickable
		if h.has("sort"):
			label.mouse_filter = Control.MOUSE_FILTER_STOP
			var sort_mode = h.sort
			label.gui_input.connect(func(event):
				if event is InputEventMouseButton and event.pressed:
					_on_header_clicked(sort_mode)
			)

		header.add_child(label)

func _on_header_clicked(sort_mode: SortMode):
	if current_sort == sort_mode:
		sort_ascending = not sort_ascending
	else:
		current_sort = sort_mode
		sort_ascending = false

	refresh_scoreboard()

func _setup_styling():
	# Basic styling - in real use would use theme
	if panel:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_color = Color(0.3, 0.3, 0.4)
		panel.add_theme_stylebox_override("panel", style)

# ============================================
# EVENTS
# ============================================

func _on_player_spawned(peer_id: int, _player: Node):
	if is_visible:
		refresh_scoreboard()

func _on_player_despawned(peer_id: int):
	_remove_player_row(peer_id)
