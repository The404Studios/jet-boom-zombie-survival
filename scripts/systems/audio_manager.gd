extends Node

# Comprehensive audio manager with 3D positional audio and network replication
# Handles music, SFX, ambient sounds, and voice

signal music_changed(track_name: String)
signal audio_settings_changed

# Audio pools for efficient playback
const POOL_SIZE_2D: int = 20
const POOL_SIZE_3D: int = 30

var audio_pool_2d: Array[AudioStreamPlayer] = []
var audio_pool_3d: Array[AudioStreamPlayer3D] = []
var pool_index_2d: int = 0
var pool_index_3d: int = 0

# Music management
var current_music: AudioStreamPlayer = null
var music_tracks: Dictionary = {}
var current_track: String = ""
var music_volume: float = 0.7
var sfx_volume: float = 1.0
var ambient_volume: float = 0.8

# Ambient sounds
var ambient_players: Array[AudioStreamPlayer] = []

# Sound libraries
var gunshot_sounds: Dictionary = {}
var impact_sounds: Dictionary = {}
var zombie_sounds: Dictionary = {}
var ui_sounds: Dictionary = {}
var ambient_sounds: Dictionary = {}

func _ready():
	# Create audio pools
	_create_audio_pools()

	# Load sound libraries
	_load_sound_libraries()

	# Load settings
	_load_audio_settings()

	# Start ambient sounds
	_start_ambient_sounds()

func _create_audio_pools():
	# 2D audio pool
	for i in POOL_SIZE_2D:
		var player = AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		audio_pool_2d.append(player)

	# 3D audio pool
	for i in POOL_SIZE_3D:
		var player = AudioStreamPlayer3D.new()
		player.bus = "SFX"
		player.max_distance = 100.0
		player.unit_size = 5.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		audio_pool_3d.append(player)

	# Music player
	current_music = AudioStreamPlayer.new()
	current_music.bus = "Music"
	current_music.volume_db = linear_to_db(music_volume)
	add_child(current_music)

func _load_sound_libraries():
	# Load gunshot sounds (will be populated when weapons are loaded)
	gunshot_sounds = {
		"pistol": null,  # Path: res://sounds/weapons/pistol_shot.wav
		"rifle": null,
		"shotgun": null,
		"sniper": null
	}

	# Impact sounds
	impact_sounds = {
		"flesh": null,   # Bullet hitting flesh
		"metal": null,   # Bullet hitting metal
		"wood": null,    # Bullet hitting wood
		"concrete": null # Bullet hitting concrete
	}

	# Zombie sounds
	zombie_sounds = {
		"growl": [],     # Array of growl variations
		"attack": [],
		"death": [],
		"hit": []
	}

	# UI sounds
	ui_sounds = {
		"click": null,
		"hover": null,
		"error": null,
		"success": null
	}

	# Ambient sounds - load wind ambience we have
	_load_ambient_sounds()

func _load_ambient_sounds():
	var ambient_dir = "res://Free PSX Wind Ambience/"

	# Try to load wind sounds
	for i in range(1, 4):
		var path = ambient_dir + "Wind %d.wav" % i
		if ResourceLoader.exists(path):
			var sound = ResourceLoader.load(path)
			ambient_sounds["wind_%d" % i] = sound

func _start_ambient_sounds():
	# Play wind ambience on loop
	for key in ambient_sounds.keys():
		if key.begins_with("wind"):
			var player = AudioStreamPlayer.new()
			player.stream = ambient_sounds[key]
			player.bus = "Music"
			player.volume_db = linear_to_db(ambient_volume * 0.3)
			player.autoplay = true
			add_child(player)
			ambient_players.append(player)

# ============================================
# MUSIC SYSTEM
# ============================================

func play_music(track_name: String, fade_time: float = 1.0):
	if current_track == track_name:
		return

	var track_path = "res://audio/music/%s.ogg" % track_name

	# Check if track exists
	if not ResourceLoader.exists(track_path):
		print("Music track not found: %s" % track_path)
		return

	var new_track = ResourceLoader.load(track_path)

	# Fade out current
	if current_music.playing:
		_fade_out_music(fade_time)
		await get_tree().create_timer(fade_time).timeout

	# Play new track
	current_music.stream = new_track
	current_music.play()
	_fade_in_music(fade_time)

	current_track = track_name
	music_changed.emit(track_name)

func stop_music(fade_time: float = 1.0):
	_fade_out_music(fade_time)
	await get_tree().create_timer(fade_time).timeout
	current_music.stop()
	current_track = ""

func _fade_out_music(duration: float):
	var tween = create_tween()
	tween.tween_property(current_music, "volume_db", -80.0, duration)

func _fade_in_music(duration: float):
	current_music.volume_db = -80.0
	var tween = create_tween()
	tween.tween_property(current_music, "volume_db", linear_to_db(music_volume), duration)

# ============================================
# 2D SOUND EFFECTS
# ============================================

func play_sound_2d(sound_name: String, volume: float = 1.0):
	var sound = _get_sound_from_library(sound_name)
	if not sound:
		return

	var player = _get_next_2d_player()
	player.stream = sound
	player.volume_db = linear_to_db(sfx_volume * volume)
	player.play()

func play_ui_sound(sound_type: String):
	if ui_sounds.has(sound_type) and ui_sounds[sound_type]:
		play_sound_2d(sound_type, 0.8)

# ============================================
# 3D POSITIONAL AUDIO (Network Replicated)
# ============================================

func play_sound_3d(sound_name: String, position: Vector3, volume: float = 1.0, pitch: float = 1.0):
	# Network replicate for multiplayer
	if multiplayer.is_server():
		_play_sound_3d_networked.rpc(sound_name, position, volume, pitch)
	else:
		_play_sound_3d_networked.rpc_id(1, sound_name, position, volume, pitch)

@rpc("any_peer", "call_local", "reliable")
func _play_sound_3d_networked(sound_name: String, position: Vector3, volume: float, pitch: float):
	var sound = _get_sound_from_library(sound_name)
	if not sound:
		return

	var player = _get_next_3d_player()
	player.stream = sound
	player.global_position = position
	player.volume_db = linear_to_db(sfx_volume * volume)
	player.pitch_scale = pitch
	player.play()

func play_gunshot(weapon_type: String, position: Vector3):
	# Add random pitch variation
	var pitch = randf_range(0.95, 1.05)
	play_sound_3d("gunshot_%s" % weapon_type, position, 1.0, pitch)

func play_impact(surface_type: String, position: Vector3):
	play_sound_3d("impact_%s" % surface_type, position, 0.8)

func play_zombie_sound(sound_type: String, position: Vector3):
	# Random variation from array
	if zombie_sounds.has(sound_type) and zombie_sounds[sound_type].size() > 0:
		var sounds = zombie_sounds[sound_type]
		var sound = sounds[randi() % sounds.size()]

		var player = _get_next_3d_player()
		player.stream = sound
		player.global_position = position
		player.volume_db = linear_to_db(sfx_volume * 0.9)
		player.pitch_scale = randf_range(0.9, 1.1)
		player.play()

# ============================================
# HELPER FUNCTIONS
# ============================================

func _get_sound_from_library(sound_name: String) -> AudioStream:
	# Check all libraries
	if gunshot_sounds.has(sound_name):
		return gunshot_sounds[sound_name]
	if impact_sounds.has(sound_name):
		return impact_sounds[sound_name]
	if ui_sounds.has(sound_name):
		return ui_sounds[sound_name]
	if ambient_sounds.has(sound_name):
		return ambient_sounds[sound_name]

	return null

func _get_next_2d_player() -> AudioStreamPlayer:
	var player = audio_pool_2d[pool_index_2d]
	pool_index_2d = (pool_index_2d + 1) % POOL_SIZE_2D
	return player

func _get_next_3d_player() -> AudioStreamPlayer3D:
	var player = audio_pool_3d[pool_index_3d]
	pool_index_3d = (pool_index_3d + 1) % POOL_SIZE_3D
	return player

# ============================================
# SETTINGS
# ============================================

func set_master_volume(volume: float):
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(volume))
	_save_audio_settings()

func set_music_volume(volume: float):
	music_volume = clamp(volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(music_volume))
	current_music.volume_db = linear_to_db(music_volume)
	_save_audio_settings()

func set_sfx_volume(volume: float):
	sfx_volume = clamp(volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(sfx_volume))
	_save_audio_settings()

func linear_to_db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0
	return 20.0 * log(linear) / log(10.0)

func _save_audio_settings():
	var config = ConfigFile.new()
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "ambient_volume", ambient_volume)
	config.save("user://audio_settings.cfg")
	audio_settings_changed.emit()

func _load_audio_settings():
	var config = ConfigFile.new()
	var err = config.load("user://audio_settings.cfg")
	if err == OK:
		music_volume = config.get_value("audio", "music_volume", 0.7)
		sfx_volume = config.get_value("audio", "sfx_volume", 1.0)
		ambient_volume = config.get_value("audio", "ambient_volume", 0.8)

		# Apply settings
		set_music_volume(music_volume)
		set_sfx_volume(sfx_volume)
