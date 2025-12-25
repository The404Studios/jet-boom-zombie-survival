extends Control
class_name MainMenuController

signal play_pressed
signal stash_pressed
signal settings_pressed
signal quit_pressed
signal market_pressed
signal merchant_pressed
signal leaderboard_pressed

@onready var survivor_name_label: Label = $MainPanel/PlayerInfo/SurvivorName
@onready var rank_label: Label = $MainPanel/PlayerInfo/RankPrestige
@onready var character_preview: Panel = $MainPanel/CharacterPreview
@onready var version_label: Label = $VersionLabel

# Panel references
@onready var main_panel: Panel = $MainPanel
@onready var top_tabs: HBoxContainer = $TopTabs
@onready var stash_panel: Control = $StashPanel
@onready var market_panel: Control = $MarketPanel
@onready var merchant_panel: Control = $MerchantPanel
@onready var leaderboard_panel: Control = $LeaderboardPanel
@onready var settings_panel: Control = $SettingsPanel
@onready var trading_panel: Control = $TradingPanel
@onready var lobby_panel: Control = $LobbyPanel
@onready var play_mode_panel: Control = $PlayModePanel
@onready var character_select_panel: Control = $CharacterSelectPanel
@onready var game_title: Label = $GameTitle

# Steam integration
var steam_username: String = "Survivor"
var player_rank: int = 1
var player_prestige: int = 0
var player_level: int = 1
var total_kills: int = 0
var total_waves_survived: int = 0
var play_time_seconds: int = 0

# Current open panel tracking
var current_open_panel: Control = null

func _ready():
	# Connect button signals
	_connect_buttons()

	# Connect panel close buttons
	_connect_panel_close_buttons()

	# Try to get Steam username
	_load_player_info()

	# Update UI
	_update_player_info()

	# Initialize account system
	_init_account_system()

	# Update version label
	if version_label:
		version_label.text = "v1.0.0 - Build " + str(Time.get_unix_time_from_system()).substr(0, 8)

	# Play menu music if available
	if has_node("/root/AudioManager"):
		var audio = get_node("/root/AudioManager")
		if audio.has_method("play_music"):
			audio.play_music("menu_theme")

	# Initialize all panels as hidden
	_hide_all_panels()
	if main_panel:
		main_panel.visible = true
	if top_tabs:
		top_tabs.visible = true
	if game_title:
		game_title.visible = true

func _connect_buttons():
	# Main menu buttons
	var play_btn = get_node_or_null("MainPanel/MenuButtons/PlayButton")
	var stash_btn = get_node_or_null("MainPanel/MenuButtons/StashButton")
	var settings_btn = get_node_or_null("MainPanel/MenuButtons/SettingsButton")
	var quit_btn = get_node_or_null("MainPanel/MenuButtons/QuitButton")

	if play_btn:
		play_btn.pressed.connect(_on_play_pressed)
	if stash_btn:
		stash_btn.pressed.connect(_on_stash_pressed)
	if settings_btn:
		settings_btn.pressed.connect(_on_settings_pressed)
	if quit_btn:
		quit_btn.pressed.connect(_on_quit_pressed)

	# Tab buttons
	var market_btn = get_node_or_null("TopTabs/MarketTab")
	var merchant_btn = get_node_or_null("TopTabs/MerchantTab")
	var leaderboard_btn = get_node_or_null("TopTabs/LeaderboardTab")
	var profile_btn = get_node_or_null("TopTabs/ProfileTab")

	if market_btn:
		market_btn.pressed.connect(_on_market_pressed)
	if merchant_btn:
		merchant_btn.pressed.connect(_on_merchant_pressed)
	if leaderboard_btn:
		leaderboard_btn.pressed.connect(_on_leaderboard_pressed)
	if profile_btn:
		profile_btn.pressed.connect(_on_profile_pressed)

func _load_player_info():
	# Try to get Steam username
	if has_node("/root/SteamManager"):
		var steam = get_node("/root/SteamManager")
		if steam.is_initialized():
			steam_username = steam.steam_username

	# Load saved player data
	if has_node("/root/PlayerPersistence"):
		var persistence = get_node("/root/PlayerPersistence")
		if persistence.player_data:
			player_rank = persistence.player_data.get("rank", 1)
			player_prestige = persistence.player_data.get("prestige", 0)
			player_level = persistence.player_data.get("level", 1)
			total_kills = persistence.player_data.get("total_kills", 0)
			total_waves_survived = persistence.player_data.get("waves_survived", 0)
			play_time_seconds = persistence.player_data.get("play_time", 0)

	# Load from AccountSystem if available
	if has_node("/root/AccountSystem"):
		var account = get_node("/root/AccountSystem")
		if account.has_method("get_username"):
			var username = account.get_username()
			if username and username != "":
				steam_username = username
		if account.has_method("get_rank"):
			player_rank = account.get_rank()

func _update_player_info():
	if survivor_name_label:
		survivor_name_label.text = "[%s]" % steam_username

	if rank_label:
		var prestige_text = ""
		if player_prestige > 0:
			prestige_text = " P%d" % player_prestige
		rank_label.text = "[Rank %d]%s" % [player_rank, prestige_text]

	# Update character preview if available
	if character_preview:
		_update_character_preview()

func _update_character_preview():
	# Could load selected character model into preview panel
	pass

func _on_play_pressed():
	play_pressed.emit()
	# Open play mode selection panel
	_show_panel(play_mode_panel)

	# Connect play mode panel signals if not already connected
	if play_mode_panel:
		if play_mode_panel.has_signal("singleplayer_selected") and not play_mode_panel.singleplayer_selected.is_connected(_on_singleplayer_selected):
			play_mode_panel.singleplayer_selected.connect(_on_singleplayer_selected)
		if play_mode_panel.has_signal("multiplayer_selected") and not play_mode_panel.multiplayer_selected.is_connected(_on_multiplayer_selected):
			play_mode_panel.multiplayer_selected.connect(_on_multiplayer_selected)
		if play_mode_panel.has_signal("panel_closed") and not play_mode_panel.panel_closed.is_connected(_on_play_mode_closed):
			play_mode_panel.panel_closed.connect(_on_play_mode_closed)

func _on_singleplayer_selected():
	# Set game mode to singleplayer
	if has_node("/root/GameSettings"):
		var settings = get_node("/root/GameSettings")
		settings.set_singleplayer(true)

	# Close play mode panel and open character selection
	_close_panel(play_mode_panel)
	_show_character_select()

func _on_multiplayer_selected():
	# Set game mode to multiplayer
	if has_node("/root/GameSettings"):
		var settings = get_node("/root/GameSettings")
		settings.set_singleplayer(false)

	# Close play mode panel and open character selection first, then lobby
	_close_panel(play_mode_panel)
	_show_character_select(true)  # true = multiplayer mode

func _show_character_select(is_multiplayer: bool = false):
	_show_panel(character_select_panel)

	# Connect character select signals if not already connected
	if character_select_panel:
		if character_select_panel.has_signal("continue_pressed"):
			if not character_select_panel.continue_pressed.is_connected(_on_character_selected):
				# Store multiplayer mode in meta for later
				character_select_panel.set_meta("is_multiplayer", is_multiplayer)
				character_select_panel.continue_pressed.connect(_on_character_selected)
		if character_select_panel.has_signal("panel_closed"):
			if not character_select_panel.panel_closed.is_connected(_on_character_select_closed):
				character_select_panel.panel_closed.connect(_on_character_select_closed)

func _on_character_selected():
	var is_multiplayer = false
	if character_select_panel and character_select_panel.has_meta("is_multiplayer"):
		is_multiplayer = character_select_panel.get_meta("is_multiplayer")

	# Get selected character data
	var selected_char = ""
	var char_data = {}
	if character_select_panel and character_select_panel.has_method("get_selected_character"):
		selected_char = character_select_panel.get_selected_character()
	if character_select_panel and character_select_panel.has_method("get_selected_character_data"):
		char_data = character_select_panel.get_selected_character_data()

	# Store selection for use in game
	if has_node("/root/GameSettings"):
		var settings = get_node("/root/GameSettings")
		settings.set_meta("selected_character", selected_char)
		settings.set_meta("selected_character_data", char_data)

	_close_panel(character_select_panel)

	if is_multiplayer:
		# Go to lobby for multiplayer
		_show_lobby()
	else:
		# Start singleplayer game directly
		start_solo_game()

func _show_lobby():
	_show_panel(lobby_panel)
	if lobby_panel:
		# Initialize lobby for hosting or joining
		if lobby_panel.has_signal("game_started") and not lobby_panel.game_started.is_connected(_on_lobby_game_started):
			lobby_panel.game_started.connect(_on_lobby_game_started)
		if lobby_panel.has_signal("panel_closed") and not lobby_panel.panel_closed.is_connected(_on_lobby_closed):
			lobby_panel.panel_closed.connect(_on_lobby_closed)

func _on_character_select_closed():
	_close_panel(character_select_panel)

func _on_play_mode_closed():
	_close_panel(play_mode_panel)

func _on_lobby_game_started():
	# Game is starting from lobby - load the multiplayer arena scene
	_close_panel(lobby_panel)

	# Notify network manager that game is starting if available
	if has_node("/root/NetworkManager"):
		var network = get_node("/root/NetworkManager")
		if network.has_method("on_game_starting"):
			network.on_game_starting()

	# Stop menu music
	if has_node("/root/AudioManager"):
		var audio = get_node("/root/AudioManager")
		if audio.has_method("stop_music"):
			audio.stop_music()

	# Load the arena scene for multiplayer
	get_tree().change_scene_to_file("res://scenes/levels/arena_01.tscn")

func _on_lobby_closed():
	# Return to main menu
	_close_panel(lobby_panel)

	# Disconnect from server if connected
	if has_node("/root/NetworkManager"):
		var network = get_node("/root/NetworkManager")
		if network.has_method("disconnect_from_server"):
			network.disconnect_from_server()

func start_solo_game():
	# Set singleplayer mode
	if has_node("/root/GameSettings"):
		var settings = get_node("/root/GameSettings")
		settings.set_singleplayer(true)

	# Stop menu music
	if has_node("/root/AudioManager"):
		var audio = get_node("/root/AudioManager")
		if audio.has_method("stop_music"):
			audio.stop_music()

	# Start a solo game (no multiplayer)
	get_tree().change_scene_to_file("res://scenes/levels/arena_01.tscn")

func _on_stash_pressed():
	stash_pressed.emit()
	_show_panel(stash_panel)

	# Refresh stash contents
	if stash_panel and stash_panel.has_method("open"):
		stash_panel.open()

func _on_settings_pressed():
	settings_pressed.emit()
	_show_settings_panel()

func _show_settings_panel():
	# Create settings panel if it doesn't exist or show existing
	if settings_panel:
		_show_panel(settings_panel)
		return

	# Create a full settings panel
	var panel = PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	settings_panel = panel

	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 20)
	panel.add_child(main_vbox)

	# Title
	var title = Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	main_vbox.add_child(title)

	var hbox = HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(hbox)

	# Categories on left
	var categories = VBoxContainer.new()
	categories.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(categories)

	var cat_buttons = ["Graphics", "Audio", "Gameplay", "Controls", "Network"]
	for cat in cat_buttons:
		var btn = Button.new()
		btn.text = cat
		btn.custom_minimum_size = Vector2(180, 40)
		categories.add_child(btn)

	# Content on right
	var content = ScrollContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(content)

	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 10)
	content.add_child(content_vbox)

	# Add basic settings (similar to pause menu but more detailed)
	_add_settings_content(content_vbox)

	# Bottom buttons
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 20)
	main_vbox.add_child(btn_hbox)

	var apply_btn = Button.new()
	apply_btn.text = "Apply"
	apply_btn.custom_minimum_size = Vector2(120, 40)
	apply_btn.pressed.connect(_save_settings)
	btn_hbox.add_child(apply_btn)

	var reset_btn = Button.new()
	reset_btn.text = "Reset to Defaults"
	reset_btn.custom_minimum_size = Vector2(150, 40)
	reset_btn.pressed.connect(_reset_settings)
	btn_hbox.add_child(reset_btn)

	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(120, 40)
	close_btn.pressed.connect(_close_panel.bind(settings_panel))
	btn_hbox.add_child(close_btn)

	_show_panel(settings_panel)

func _add_settings_content(parent: VBoxContainer):
	# Graphics section
	var graphics_title = Label.new()
	graphics_title.text = "Graphics"
	graphics_title.add_theme_font_size_override("font_size", 20)
	graphics_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
	parent.add_child(graphics_title)

	_add_checkbox_setting(parent, "Fullscreen", "fullscreen_enabled", true)
	_add_checkbox_setting(parent, "VSync", "vsync_enabled", true)
	_add_checkbox_setting(parent, "Gore Effects", "gore_enabled", true)
	_add_checkbox_setting(parent, "PSX Effects", "psx_effects_enabled", true)

	# Audio section
	var audio_title = Label.new()
	audio_title.text = "Audio"
	audio_title.add_theme_font_size_override("font_size", 20)
	audio_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
	parent.add_child(audio_title)

	_add_slider_setting(parent, "Master Volume", "master_volume", 0.0, 1.0, 1.0)
	_add_slider_setting(parent, "Music Volume", "music_volume", 0.0, 1.0, 0.7)
	_add_slider_setting(parent, "SFX Volume", "sfx_volume", 0.0, 1.0, 1.0)
	_add_slider_setting(parent, "Voice Volume", "voice_volume", 0.0, 1.0, 1.0)

	# Gameplay section
	var gameplay_title = Label.new()
	gameplay_title.text = "Gameplay"
	gameplay_title.add_theme_font_size_override("font_size", 20)
	gameplay_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
	parent.add_child(gameplay_title)

	_add_slider_setting(parent, "Mouse Sensitivity", "mouse_sensitivity", 0.1, 3.0, 1.0)
	_add_slider_setting(parent, "Field of View", "field_of_view", 60, 120, 75)
	_add_checkbox_setting(parent, "Invert Y-Axis", "invert_y", false)
	_add_checkbox_setting(parent, "Auto Reload", "auto_reload", true)

func _add_checkbox_setting(parent: Control, label_text: String, setting_name: String, default: bool):
	var hbox = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(label)

	var checkbox = CheckBox.new()
	checkbox.name = setting_name
	checkbox.button_pressed = _get_setting(setting_name, default)
	checkbox.toggled.connect(func(val): _set_setting(setting_name, val))
	hbox.add_child(checkbox)

	parent.add_child(hbox)

func _add_slider_setting(parent: Control, label_text: String, setting_name: String, min_val: float, max_val: float, default: float):
	var hbox = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(label)

	var slider = HSlider.new()
	slider.name = setting_name
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = 0.05 if max_val <= 3 else 1
	slider.value = _get_setting(setting_name, default)
	slider.custom_minimum_size = Vector2(200, 20)
	slider.value_changed.connect(func(val): _set_setting(setting_name, val))
	hbox.add_child(slider)

	var value_label = Label.new()
	if max_val <= 3:
		value_label.text = "%.1f" % slider.value
		slider.value_changed.connect(func(val): value_label.text = "%.1f" % val)
	else:
		value_label.text = "%d" % int(slider.value)
		slider.value_changed.connect(func(val): value_label.text = "%d" % int(val))
	hbox.add_child(value_label)

	parent.add_child(hbox)

func _save_settings():
	if has_node("/root/GameSettings"):
		get_node("/root/GameSettings").save_settings()

func _reset_settings():
	if has_node("/root/GameSettings"):
		get_node("/root/GameSettings").reset_to_defaults()
	_close_panel(settings_panel)
	_show_settings_panel()

func _on_quit_pressed():
	# Save data before quitting
	if has_node("/root/GameSettings"):
		get_node("/root/GameSettings").save_settings()
	if has_node("/root/PlayerPersistence"):
		var persistence = get_node("/root/PlayerPersistence")
		if persistence.has_method("save_player_data"):
			persistence.save_player_data()

	quit_pressed.emit()
	get_tree().quit()

func _on_market_pressed():
	market_pressed.emit()
	_show_panel(market_panel)

	if market_panel and market_panel.has_method("open"):
		market_panel.open()

func _on_merchant_pressed():
	merchant_pressed.emit()
	_show_panel(merchant_panel)

	if merchant_panel and merchant_panel.has_method("open"):
		merchant_panel.open()

func _on_leaderboard_pressed():
	leaderboard_pressed.emit()
	_show_leaderboard_panel()

func _show_leaderboard_panel():
	if leaderboard_panel:
		_show_panel(leaderboard_panel)
		_populate_leaderboard()
		return

	# Create leaderboard panel
	var panel = PanelContainer.new()
	panel.name = "LeaderboardPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	leaderboard_panel = panel

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 15)
	panel.add_child(main_vbox)

	# Title
	var title = Label.new()
	title.text = "LEADERBOARD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	main_vbox.add_child(title)

	# Tab buttons for different leaderboards
	var tab_hbox = HBoxContainer.new()
	tab_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_hbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(tab_hbox)

	for tab_name in ["Waves Survived", "Total Kills", "Points Earned", "Boss Kills"]:
		var tab_btn = Button.new()
		tab_btn.text = tab_name
		tab_btn.custom_minimum_size = Vector2(120, 35)
		tab_hbox.add_child(tab_btn)

	# Leaderboard list
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)

	var list = VBoxContainer.new()
	list.name = "LeaderboardList"
	list.add_theme_constant_override("separation", 5)
	scroll.add_child(list)

	# Close button
	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(120, 40)
	close_btn.pressed.connect(_close_panel.bind(leaderboard_panel))
	main_vbox.add_child(close_btn)

	_show_panel(leaderboard_panel)
	_populate_leaderboard()

func _populate_leaderboard():
	if not leaderboard_panel:
		return

	var list = leaderboard_panel.get_node_or_null("LeaderboardList")
	if not list:
		return

	# Clear existing entries
	for child in list.get_children():
		child.queue_free()

	# Add sample leaderboard entries (would come from server in real game)
	var entries = [
		{"rank": 1, "name": "ProZombie", "score": 15000, "waves": 25},
		{"rank": 2, "name": "SurvivorX", "score": 12500, "waves": 22},
		{"rank": 3, "name": "ZombieHunter", "score": 10000, "waves": 20},
		{"rank": 4, "name": steam_username, "score": 5000, "waves": 10},
		{"rank": 5, "name": "NewPlayer", "score": 1000, "waves": 5}
	]

	for entry in entries:
		var row = _create_leaderboard_row(entry)
		list.add_child(row)

func _create_leaderboard_row(entry: Dictionary) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)

	var rank_label = Label.new()
	rank_label.text = "#%d" % entry.rank
	rank_label.custom_minimum_size = Vector2(50, 0)
	if entry.rank <= 3:
		rank_label.add_theme_color_override("font_color", Color.GOLD)
	row.add_child(rank_label)

	var name_label = Label.new()
	name_label.text = entry.name
	name_label.custom_minimum_size = Vector2(200, 0)
	if entry.name == steam_username:
		name_label.add_theme_color_override("font_color", Color.CYAN)
	row.add_child(name_label)

	var score_label = Label.new()
	score_label.text = "%d pts" % entry.score
	score_label.custom_minimum_size = Vector2(100, 0)
	row.add_child(score_label)

	var waves_label = Label.new()
	waves_label.text = "%d waves" % entry.waves
	waves_label.custom_minimum_size = Vector2(100, 0)
	row.add_child(waves_label)

	return row

func _on_profile_pressed():
	_show_profile_panel()

func _show_profile_panel():
	# Create a profile/stats panel
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(400, 350)
	panel.position = Vector2(-200, -175)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "PLAYER PROFILE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	# Player name
	var name_label = Label.new()
	name_label.text = steam_username
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color.GOLD)
	vbox.add_child(name_label)

	# Stats
	_add_profile_stat(vbox, "Rank", str(player_rank))
	_add_profile_stat(vbox, "Level", str(player_level))
	_add_profile_stat(vbox, "Prestige", str(player_prestige))
	_add_profile_stat(vbox, "Total Kills", str(total_kills))
	_add_profile_stat(vbox, "Waves Survived", str(total_waves_survived))
	_add_profile_stat(vbox, "Play Time", _format_play_time(play_time_seconds))

	# Close button
	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(100, 35)
	close_btn.pressed.connect(func(): panel.queue_free())
	vbox.add_child(close_btn)

	add_child(panel)

func _add_profile_stat(parent: Control, stat_name: String, stat_value: String):
	var hbox = HBoxContainer.new()
	var name_label = Label.new()
	name_label.text = stat_name + ":"
	name_label.custom_minimum_size = Vector2(150, 0)
	hbox.add_child(name_label)

	var value_label = Label.new()
	value_label.text = stat_value
	value_label.add_theme_color_override("font_color", Color.GOLD)
	hbox.add_child(value_label)

	parent.add_child(hbox)

func _format_play_time(seconds: int) -> String:
	var hours = seconds / 3600
	var minutes = (seconds % 3600) / 60
	return "%dh %dm" % [hours, minutes]

func _connect_panel_close_buttons():
	# Connect close buttons for all panels
	var panels_with_close = [
		[stash_panel, "CloseButton"],
		[market_panel, "CloseButton"],
		[merchant_panel, "CloseButton"],
		[leaderboard_panel, "CloseButton"],
		[settings_panel, "CloseButton"],
		[trading_panel, "CloseButton"]
	]

	for panel_data in panels_with_close:
		var panel = panel_data[0]
		var close_btn_name = panel_data[1]
		if panel:
			var close_btn = panel.get_node_or_null(close_btn_name)
			if close_btn:
				close_btn.pressed.connect(_close_panel.bind(panel))

	# Connect back buttons
	if market_panel:
		var back_btn = market_panel.get_node_or_null("FilterBar/BackButton")
		if back_btn:
			back_btn.pressed.connect(_close_panel.bind(market_panel))

	if merchant_panel:
		var back_btn = merchant_panel.get_node_or_null("BottomBar/BackButton")
		if back_btn:
			back_btn.pressed.connect(_close_panel.bind(merchant_panel))

	if trading_panel:
		var cancel_btn = trading_panel.get_node_or_null("BottomBar/CancelButton")
		if cancel_btn:
			cancel_btn.pressed.connect(_close_panel.bind(trading_panel))

func _show_panel(panel: Control):
	if not panel:
		return

	# Hide main menu elements
	if main_panel:
		main_panel.visible = false
	if top_tabs:
		top_tabs.visible = false
	if game_title:
		game_title.visible = false

	# Track current panel
	current_open_panel = panel

	# Show the panel
	panel.visible = true

func _close_panel(panel: Control):
	if not panel:
		return

	# Hide the panel
	panel.visible = false

	# Clear current panel tracking
	if current_open_panel == panel:
		current_open_panel = null

	# Show main menu elements
	if main_panel:
		main_panel.visible = true
	if top_tabs:
		top_tabs.visible = true
	if game_title:
		game_title.visible = true

func _hide_all_panels():
	var all_panels = [stash_panel, market_panel, merchant_panel, leaderboard_panel, settings_panel, trading_panel, lobby_panel, play_mode_panel, character_select_panel]
	for panel in all_panels:
		if panel:
			panel.visible = false
	current_open_panel = null

func _init_account_system():
	# Connect to AccountSystem if available
	if has_node("/root/AccountSystem"):
		var account = get_node("/root/AccountSystem")
		if account.has_signal("account_loaded"):
			account.account_loaded.connect(_on_account_loaded)

		# Request account load
		if account.has_method("load_account"):
			account.load_account()

func _on_account_loaded():
	# Refresh player info when account loads
	_load_player_info()
	_update_player_info()

func show_trading_panel():
	_show_panel(trading_panel)

func _input(event):
	# Handle escape key to close panels
	if event.is_action_pressed("ui_cancel"):
		if current_open_panel:
			_close_panel(current_open_panel)
			get_viewport().set_input_as_handled()

# ============================================
# SETTINGS HELPERS
# ============================================

func _get_setting(setting_name: String, default_value):
	if has_node("/root/GameSettings"):
		var settings = get_node("/root/GameSettings")
		if setting_name in settings:
			return settings.get(setting_name)
	return default_value

func _set_setting(setting_name: String, value):
	if has_node("/root/GameSettings"):
		var settings = get_node("/root/GameSettings")
		if setting_name in settings:
			settings.set(setting_name, value)
