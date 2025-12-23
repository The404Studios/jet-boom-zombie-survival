extends Node

# Voice chat system using Steam Voice API with proximity support
# Handles voice transmission, receiving, and 3D positioning

signal voice_settings_changed

const PROXIMITY_MAX_DISTANCE: float = 50.0
const PROXIMITY_MIN_DISTANCE: float = 5.0
const VOICE_SAMPLE_RATE: int = 48000

var steam = null
var is_voice_enabled: bool = true
var is_push_to_talk: bool = true
var is_talking: bool = false
var master_volume: float = 1.0
var voice_volume: float = 1.0
var microphone_gain: float = 1.0
var proximity_enabled: bool = true
var global_voice_enabled: bool = false # Allow global voice chat

# Voice players - peer_id -> AudioStreamPlayer3D
var voice_players: Dictionary = {}

# Voice activity detection
var voice_activity_threshold: float = 0.01
var is_voice_active: bool = false

# Audio buffers
var voice_buffer: PackedByteArray = PackedByteArray()
var voice_buffers: Dictionary = {} # peer_id -> PackedByteArray

func _ready():
	# Initialize Steam Voice if available
	if has_node("/root/SteamManager"):
		steam = get_node("/root/SteamManager").steam
		if steam:
			_initialize_steam_voice()

	# Connect to network signals
	if NetworkManager:
		NetworkManager.player_joined.connect(_on_player_joined)
		NetworkManager.player_left.connect(_on_player_left)

	# Load settings
	_load_voice_settings()

func _initialize_steam_voice():
	if not steam:
		return

	# Enable voice recording
	steam.startVoiceRecording()

	print("Steam Voice initialized")

func _process(_delta):
	if not is_voice_enabled or not steam:
		return

	# Handle push-to-talk
	if is_push_to_talk:
		if Input.is_action_just_pressed("voice_chat"):
			start_talking()
		elif Input.is_action_just_released("voice_chat"):
			stop_talking()
	else:
		# Voice activity detection
		_update_voice_activity()

	# Capture and send voice
	if is_talking or is_voice_active:
		_capture_and_send_voice()

	# Process received voice
	_process_voice_buffers()

func start_talking():
	if not is_voice_enabled:
		return

	is_talking = true
	if steam:
		steam.startVoiceRecording()

func stop_talking():
	is_talking = false
	if steam and is_push_to_talk:
		steam.stopVoiceRecording()

func _update_voice_activity():
	# Simple voice activity detection based on audio level
	# In production, use proper VAD algorithm
	if not steam:
		return

	# This would need actual audio level monitoring
	# For now, simplified
	is_voice_active = false

func _capture_and_send_voice():
	if not steam:
		return

	# Get available voice data from Steam
	var available = steam.getAvailableVoice()

	if available > 0:
		# Get compressed voice data
		var voice_data = steam.getVoice()

		if voice_data.size() > 0:
			# Apply microphone gain
			# Note: Steam handles compression, we just adjust gain in settings

			# Send to other players
			_send_voice_data(voice_data)

func _send_voice_data(voice_data: PackedByteArray):
	if not multiplayer.is_server():
		# Client sends to server
		_receive_voice_data.rpc_id(1, voice_data)
	else:
		# Server broadcasts to all clients
		_broadcast_voice_data(multiplayer.get_unique_id(), voice_data)

@rpc("any_peer", "call_remote", "unreliable")
func _receive_voice_data(voice_data: PackedByteArray):
	var sender_id = multiplayer.get_remote_sender_id()

	# Server broadcasts to other clients
	if multiplayer.is_server():
		_broadcast_voice_data(sender_id, voice_data)

func _broadcast_voice_data(sender_id: int, voice_data: PackedByteArray):
	# Get sender position for proximity check
	var sender_pos = _get_player_position(sender_id)

	for peer_id in NetworkManager.players.keys():
		if peer_id == sender_id:
			continue

		# Check proximity if enabled
		if proximity_enabled and not global_voice_enabled:
			var listener_pos = _get_player_position(peer_id)

			if sender_pos and listener_pos:
				var distance = sender_pos.distance_to(listener_pos)

				if distance > PROXIMITY_MAX_DISTANCE:
					continue # Too far, don't send

		# Send to this peer
		_play_voice_data.rpc_id(peer_id, sender_id, voice_data)

@rpc("authority", "call_remote", "unreliable")
func _play_voice_data(sender_id: int, voice_data: PackedByteArray):
	# Store in buffer
	if not voice_buffers.has(sender_id):
		voice_buffers[sender_id] = PackedByteArray()

	voice_buffers[sender_id].append_array(voice_data)

func _process_voice_buffers():
	if not steam:
		return

	for peer_id in voice_buffers.keys():
		var buffer = voice_buffers[peer_id]

		if buffer.size() == 0:
			continue

		# Decompress voice data using Steam
		var decompressed = steam.decompressVoice(buffer, VOICE_SAMPLE_RATE)

		if decompressed and decompressed.size() > 0:
			# Play the audio
			_play_voice_audio(peer_id, decompressed)

		# Clear buffer
		voice_buffers[peer_id] = PackedByteArray()

func _play_voice_audio(peer_id: int, audio_data: PackedByteArray):
	# Get or create audio player for this peer
	var audio_player = _get_voice_player(peer_id)

	if not audio_player:
		return

	# Convert to AudioStreamWAV
	var stream = AudioStreamWAV.new()
	stream.data = audio_data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = VOICE_SAMPLE_RATE
	stream.stereo = false

	# Apply volume
	audio_player.volume_db = linear_to_db(voice_volume * master_volume)

	# Position at player location if proximity enabled
	if proximity_enabled:
		var player_pos = _get_player_position(peer_id)
		if player_pos:
			audio_player.global_position = player_pos

	# Play
	audio_player.stream = stream
	audio_player.play()

func _get_voice_player(peer_id: int) -> AudioStreamPlayer3D:
	if voice_players.has(peer_id):
		return voice_players[peer_id]

	# Create new voice player
	var player = AudioStreamPlayer3D.new()
	player.bus = "Voice"

	# Configure 3D audio
	player.max_distance = PROXIMITY_MAX_DISTANCE
	player.unit_size = PROXIMITY_MIN_DISTANCE
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE

	# Add to scene tree
	add_child(player)

	voice_players[peer_id] = player
	return player

func _get_player_position(peer_id: int) -> Vector3:
	# Find player node
	var players = get_tree().get_nodes_in_group("players")

	for player in players:
		if player.has_method("get_network_id"):
			if player.get_network_id() == peer_id:
				return player.global_position

	return Vector3.ZERO

func _on_player_joined(peer_id: int, _player_data: Dictionary):
	# Initialize voice buffer
	voice_buffers[peer_id] = PackedByteArray()

func _on_player_left(peer_id: int):
	# Clean up
	voice_buffers.erase(peer_id)

	if voice_players.has(peer_id):
		var player = voice_players[peer_id]
		player.queue_free()
		voice_players.erase(peer_id)

# Settings management

func set_voice_enabled(enabled: bool):
	is_voice_enabled = enabled

	if not enabled and steam:
		steam.stopVoiceRecording()

	voice_settings_changed.emit()
	_save_voice_settings()

func set_push_to_talk(enabled: bool):
	is_push_to_talk = enabled

	if not enabled and steam:
		steam.startVoiceRecording()
	elif enabled and not is_talking and steam:
		steam.stopVoiceRecording()

	voice_settings_changed.emit()
	_save_voice_settings()

func set_master_volume(volume: float):
	master_volume = clamp(volume, 0.0, 2.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(master_volume))
	voice_settings_changed.emit()
	_save_voice_settings()

func set_voice_volume(volume: float):
	voice_volume = clamp(volume, 0.0, 2.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Voice"), linear_to_db(voice_volume))
	voice_settings_changed.emit()
	_save_voice_settings()

func set_microphone_gain(gain: float):
	microphone_gain = clamp(gain, 0.0, 2.0)
	voice_settings_changed.emit()
	_save_voice_settings()

func set_proximity_enabled(enabled: bool):
	proximity_enabled = enabled
	voice_settings_changed.emit()
	_save_voice_settings()

func set_global_voice_enabled(enabled: bool):
	global_voice_enabled = enabled
	voice_settings_changed.emit()
	_save_voice_settings()

func _save_voice_settings():
	var config = ConfigFile.new()
	config.set_value("voice", "enabled", is_voice_enabled)
	config.set_value("voice", "push_to_talk", is_push_to_talk)
	config.set_value("voice", "master_volume", master_volume)
	config.set_value("voice", "voice_volume", voice_volume)
	config.set_value("voice", "microphone_gain", microphone_gain)
	config.set_value("voice", "proximity_enabled", proximity_enabled)
	config.set_value("voice", "global_voice_enabled", global_voice_enabled)
	config.save("user://voice_settings.cfg")

func _load_voice_settings():
	var config = ConfigFile.new()
	var err = config.load("user://voice_settings.cfg")

	if err != OK:
		return

	is_voice_enabled = config.get_value("voice", "enabled", true)
	is_push_to_talk = config.get_value("voice", "push_to_talk", true)
	master_volume = config.get_value("voice", "master_volume", 1.0)
	voice_volume = config.get_value("voice", "voice_volume", 1.0)
	microphone_gain = config.get_value("voice", "microphone_gain", 1.0)
	proximity_enabled = config.get_value("voice", "proximity_enabled", true)
	global_voice_enabled = config.get_value("voice", "global_voice_enabled", false)

	# Apply settings
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(master_volume))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Voice"), linear_to_db(voice_volume))

func linear_to_db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0
	return 20.0 * log(linear) / log(10.0)
