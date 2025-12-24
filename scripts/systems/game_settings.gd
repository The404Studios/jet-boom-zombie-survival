extends Node
# Note: Do not use class_name here - this script is an autoload singleton
# Access via: GameSettings (the autoload name)

# Global game settings and mode tracking
# Persists across scene changes

signal settings_changed
signal game_mode_changed(is_singleplayer: bool)

# Game Mode
var is_singleplayer: bool = true

# Graphics Settings
var graphics_quality: int = 2  # 0=Low, 1=Medium, 2=High
var vsync_enabled: bool = true
var fullscreen_enabled: bool = true
var target_fps: int = 60
var psx_effects_enabled: bool = true
var gore_enabled: bool = true

# Audio Settings
var master_volume: float = 1.0
var music_volume: float = 0.7
var sfx_volume: float = 1.0
var voice_volume: float = 1.0
var ambient_volume: float = 0.5

# Gameplay Settings
var mouse_sensitivity: float = 1.0
var invert_y: bool = false
var auto_reload: bool = true
var crosshair_style: int = 0
var field_of_view: float = 75.0

# Multiplayer Settings
var player_name: String = "Survivor"
var preferred_region: String = "auto"

# File paths
const SETTINGS_PATH = "user://settings.cfg"

func _ready():
	load_settings()

func set_singleplayer(value: bool):
	is_singleplayer = value
	game_mode_changed.emit(value)

func save_settings():
	var config = ConfigFile.new()

	# Graphics
	config.set_value("graphics", "quality", graphics_quality)
	config.set_value("graphics", "vsync", vsync_enabled)
	config.set_value("graphics", "fullscreen", fullscreen_enabled)
	config.set_value("graphics", "target_fps", target_fps)
	config.set_value("graphics", "psx_effects", psx_effects_enabled)
	config.set_value("graphics", "gore", gore_enabled)

	# Audio
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "sfx", sfx_volume)
	config.set_value("audio", "voice", voice_volume)
	config.set_value("audio", "ambient", ambient_volume)

	# Gameplay
	config.set_value("gameplay", "sensitivity", mouse_sensitivity)
	config.set_value("gameplay", "invert_y", invert_y)
	config.set_value("gameplay", "auto_reload", auto_reload)
	config.set_value("gameplay", "crosshair", crosshair_style)
	config.set_value("gameplay", "fov", field_of_view)

	# Multiplayer
	config.set_value("multiplayer", "name", player_name)
	config.set_value("multiplayer", "region", preferred_region)

	var error = config.save(SETTINGS_PATH)
	if error == OK:
		print("Settings saved successfully")
		settings_changed.emit()
	else:
		print("Failed to save settings: ", error)

func load_settings():
	var config = ConfigFile.new()
	var error = config.load(SETTINGS_PATH)

	if error != OK:
		print("No settings file found, using defaults")
		return

	# Graphics
	graphics_quality = config.get_value("graphics", "quality", 2)
	vsync_enabled = config.get_value("graphics", "vsync", true)
	fullscreen_enabled = config.get_value("graphics", "fullscreen", true)
	target_fps = config.get_value("graphics", "target_fps", 60)
	psx_effects_enabled = config.get_value("graphics", "psx_effects", true)
	gore_enabled = config.get_value("graphics", "gore", true)

	# Audio
	master_volume = config.get_value("audio", "master", 1.0)
	music_volume = config.get_value("audio", "music", 0.7)
	sfx_volume = config.get_value("audio", "sfx", 1.0)
	voice_volume = config.get_value("audio", "voice", 1.0)
	ambient_volume = config.get_value("audio", "ambient", 0.5)

	# Gameplay
	mouse_sensitivity = config.get_value("gameplay", "sensitivity", 1.0)
	invert_y = config.get_value("gameplay", "invert_y", false)
	auto_reload = config.get_value("gameplay", "auto_reload", true)
	crosshair_style = config.get_value("gameplay", "crosshair", 0)
	field_of_view = config.get_value("gameplay", "fov", 75.0)

	# Multiplayer
	player_name = config.get_value("multiplayer", "name", "Survivor")
	preferred_region = config.get_value("multiplayer", "region", "auto")

	_apply_settings()
	print("Settings loaded successfully")

func _apply_settings():
	# Apply vsync
	if vsync_enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	# Apply fullscreen
	if fullscreen_enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	# Apply FPS limit
	Engine.max_fps = target_fps

	# Apply audio volumes
	if has_node("/root/AudioManager"):
		var audio = get_node("/root/AudioManager")
		if audio.has_method("set_master_volume"):
			audio.set_master_volume(master_volume)
		if audio.has_method("set_music_volume"):
			audio.set_music_volume(music_volume)
		if audio.has_method("set_sfx_volume"):
			audio.set_sfx_volume(sfx_volume)

	# Apply gore setting
	if has_node("/root/GoreSystem"):
		var gore = get_node("/root/GoreSystem")
		if gore.has_method("set_gore_enabled"):
			gore.set_gore_enabled(gore_enabled)

func reset_to_defaults():
	graphics_quality = 2
	vsync_enabled = true
	fullscreen_enabled = true
	target_fps = 60
	psx_effects_enabled = true
	gore_enabled = true

	master_volume = 1.0
	music_volume = 0.7
	sfx_volume = 1.0
	voice_volume = 1.0
	ambient_volume = 0.5

	mouse_sensitivity = 1.0
	invert_y = false
	auto_reload = true
	crosshair_style = 0
	field_of_view = 75.0

	_apply_settings()
	save_settings()
