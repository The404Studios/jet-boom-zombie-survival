extends Control
class_name VoiceChatIndicator

# Shows who is currently speaking in voice chat
# Displays speaker icons with names

signal speaker_clicked(peer_id: int)

# Settings
@export var max_visible_speakers: int = 6
@export var speaker_display_time: float = 0.5  # Fade out after this time of silence
@export var show_local_player: bool = true

# Colors
@export var speaking_color: Color = Color(0.3, 1, 0.3)
@export var muted_color: Color = Color(1, 0.3, 0.3)
@export var idle_color: Color = Color(0.5, 0.5, 0.5)

# Container
@onready var speaker_container: VBoxContainer = $SpeakerContainer

# Speaker tracking
var active_speakers: Dictionary = {}  # peer_id -> SpeakerData
var speaker_nodes: Dictionary = {}  # peer_id -> UI node

# Voice chat system reference
var voice_chat_system: Node = null
var network_manager: Node = null

class SpeakerData:
	var peer_id: int
	var player_name: String
	var is_speaking: bool
	var is_muted: bool
	var volume_level: float
	var last_speak_time: float

func _ready():
	# Create container if not set
	if not speaker_container:
		speaker_container = VBoxContainer.new()
		speaker_container.name = "SpeakerContainer"
		speaker_container.add_theme_constant_override("separation", 4)
		add_child(speaker_container)

	# Connect to voice chat system
	voice_chat_system = get_node_or_null("/root/VoiceChatSystem")
	network_manager = get_node_or_null("/root/NetworkManager")

	if voice_chat_system:
		if voice_chat_system.has_signal("player_started_speaking"):
			voice_chat_system.player_started_speaking.connect(_on_player_started_speaking)
		if voice_chat_system.has_signal("player_stopped_speaking"):
			voice_chat_system.player_stopped_speaking.connect(_on_player_stopped_speaking)
		if voice_chat_system.has_signal("player_muted"):
			voice_chat_system.player_muted.connect(_on_player_muted)
		if voice_chat_system.has_signal("player_unmuted"):
			voice_chat_system.player_unmuted.connect(_on_player_unmuted)
		if voice_chat_system.has_signal("voice_volume_changed"):
			voice_chat_system.voice_volume_changed.connect(_on_voice_volume_changed)

func _process(delta):
	# Update speaker states
	var current_time = Time.get_unix_time_from_system()

	for peer_id in active_speakers.keys():
		var data = active_speakers[peer_id]

		# Check if speaker timed out
		if data.is_speaking and current_time - data.last_speak_time > speaker_display_time:
			data.is_speaking = false
			_update_speaker_visual(peer_id)

		# Remove completely idle speakers after longer timeout
		if not data.is_speaking and current_time - data.last_speak_time > 3.0:
			_remove_speaker(peer_id)

func _on_player_started_speaking(peer_id: int):
	_ensure_speaker(peer_id)

	var data = active_speakers[peer_id]
	data.is_speaking = true
	data.last_speak_time = Time.get_unix_time_from_system()

	_update_speaker_visual(peer_id)

func _on_player_stopped_speaking(peer_id: int):
	if active_speakers.has(peer_id):
		active_speakers[peer_id].is_speaking = false
		_update_speaker_visual(peer_id)

func _on_player_muted(peer_id: int):
	_ensure_speaker(peer_id)
	active_speakers[peer_id].is_muted = true
	_update_speaker_visual(peer_id)

func _on_player_unmuted(peer_id: int):
	if active_speakers.has(peer_id):
		active_speakers[peer_id].is_muted = false
		_update_speaker_visual(peer_id)

func _on_voice_volume_changed(peer_id: int, volume: float):
	_ensure_speaker(peer_id)
	active_speakers[peer_id].volume_level = volume
	active_speakers[peer_id].last_speak_time = Time.get_unix_time_from_system()

	if volume > 0.1:
		active_speakers[peer_id].is_speaking = true

	_update_speaker_visual(peer_id)

func _ensure_speaker(peer_id: int):
	if active_speakers.has(peer_id):
		return

	var data = SpeakerData.new()
	data.peer_id = peer_id
	data.player_name = _get_player_name(peer_id)
	data.is_speaking = false
	data.is_muted = false
	data.volume_level = 0.0
	data.last_speak_time = Time.get_unix_time_from_system()

	active_speakers[peer_id] = data
	_create_speaker_ui(peer_id)

func _get_player_name(peer_id: int) -> String:
	var local_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1

	if peer_id == local_id:
		return "You"

	if network_manager and "players" in network_manager:
		if network_manager.players.has(peer_id):
			return network_manager.players[peer_id].get("name", "Player %d" % peer_id)

	return "Player %d" % peer_id

func _create_speaker_ui(peer_id: int):
	if speaker_nodes.has(peer_id):
		return

	var local_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	if peer_id == local_id and not show_local_player:
		return

	var panel = PanelContainer.new()
	panel.name = "Speaker_%d" % peer_id

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	margin.add_child(hbox)

	# Speaker icon
	var icon = Label.new()
	icon.name = "Icon"
	icon.text = "[MIC]"
	icon.add_theme_font_size_override("font_size", 12)
	icon.add_theme_color_override("font_color", idle_color)
	hbox.add_child(icon)

	# Volume indicator (bars)
	var volume_container = HBoxContainer.new()
	volume_container.name = "VolumeContainer"
	volume_container.add_theme_constant_override("separation", 2)
	for i in range(4):
		var bar = ColorRect.new()
		bar.custom_minimum_size = Vector2(3, 8 + i * 3)
		bar.color = idle_color
		volume_container.add_child(bar)
	hbox.add_child(volume_container)

	# Player name
	var name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = active_speakers[peer_id].player_name
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	hbox.add_child(name_label)

	# Mute indicator
	var mute_icon = Label.new()
	mute_icon.name = "MuteIcon"
	mute_icon.text = "[MUTED]"
	mute_icon.add_theme_font_size_override("font_size", 10)
	mute_icon.add_theme_color_override("font_color", muted_color)
	mute_icon.visible = false
	hbox.add_child(mute_icon)

	speaker_container.add_child(panel)
	speaker_nodes[peer_id] = panel

	# Limit visible speakers
	while speaker_container.get_child_count() > max_visible_speakers:
		var oldest = speaker_container.get_child(0)
		speaker_container.remove_child(oldest)
		oldest.queue_free()

		# Find and remove from tracking
		for pid in speaker_nodes.keys():
			if speaker_nodes[pid] == oldest:
				speaker_nodes.erase(pid)
				active_speakers.erase(pid)
				break

func _update_speaker_visual(peer_id: int):
	if not speaker_nodes.has(peer_id) or not active_speakers.has(peer_id):
		return

	var panel = speaker_nodes[peer_id]
	var data = active_speakers[peer_id]

	if not is_instance_valid(panel):
		return

	# Get UI elements
	var icon = panel.get_node_or_null("MarginContainer/HBoxContainer/Icon")
	var volume_container = panel.get_node_or_null("MarginContainer/HBoxContainer/VolumeContainer")
	var mute_icon = panel.get_node_or_null("MarginContainer/HBoxContainer/MuteIcon")

	# Determine color
	var color = idle_color
	if data.is_muted:
		color = muted_color
	elif data.is_speaking:
		color = speaking_color

	# Update icon color
	if icon:
		icon.add_theme_color_override("font_color", color)
		icon.text = "[X]" if data.is_muted else "[MIC]"

	# Update volume bars
	if volume_container:
		var bar_count = volume_container.get_child_count()
		var active_bars = int(data.volume_level * bar_count) if data.is_speaking else 0

		for i in range(bar_count):
			var bar = volume_container.get_child(i)
			if i < active_bars:
				bar.color = speaking_color
			else:
				bar.color = Color(0.3, 0.3, 0.3, 0.5)

	# Update mute indicator
	if mute_icon:
		mute_icon.visible = data.is_muted

	# Animate speaking pulse
	if data.is_speaking and not data.is_muted:
		var style = panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			style.border_width_left = 2
			style.border_color = speaking_color
	else:
		var style = panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			style.border_width_left = 0

func _remove_speaker(peer_id: int):
	if speaker_nodes.has(peer_id):
		var panel = speaker_nodes[peer_id]
		if is_instance_valid(panel):
			# Fade out animation
			var tween = create_tween()
			tween.tween_property(panel, "modulate:a", 0.0, 0.3)
			tween.tween_callback(panel.queue_free)

		speaker_nodes.erase(peer_id)

	active_speakers.erase(peer_id)

# ============================================
# PUBLIC API
# ============================================

func set_player_speaking(peer_id: int, speaking: bool):
	"""Manually set speaking state"""
	if speaking:
		_on_player_started_speaking(peer_id)
	else:
		_on_player_stopped_speaking(peer_id)

func set_player_muted(peer_id: int, muted: bool):
	"""Manually set mute state"""
	if muted:
		_on_player_muted(peer_id)
	else:
		_on_player_unmuted(peer_id)

func set_volume_level(peer_id: int, level: float):
	"""Manually set volume level (0-1)"""
	_on_voice_volume_changed(peer_id, level)

func clear_all_speakers():
	"""Remove all speaker indicators"""
	for peer_id in speaker_nodes.keys():
		_remove_speaker(peer_id)
