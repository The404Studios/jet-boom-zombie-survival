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

	if market_btn:
		market_btn.pressed.connect(_on_market_pressed)
	if merchant_btn:
		merchant_btn.pressed.connect(_on_merchant_pressed)
	if leaderboard_btn:
		leaderboard_btn.pressed.connect(_on_leaderboard_pressed)

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

func _update_player_info():
	if survivor_name_label:
		survivor_name_label.text = "[%s]" % steam_username

	if rank_label:
		var prestige_text = ""
		if player_prestige > 0:
			prestige_text = " P%d" % player_prestige
		rank_label.text = "[Rank %d]%s" % [player_rank, prestige_text]

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
	# Close play mode panel and open character selection
	_close_panel(play_mode_panel)
	_show_character_select()

func _on_multiplayer_selected():
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

	_close_panel(character_select_panel)

	if is_multiplayer:
		# Go to lobby for multiplayer
		_show_panel(lobby_panel)
		if lobby_panel:
			if lobby_panel.has_signal("game_started") and not lobby_panel.game_started.is_connected(_on_lobby_game_started):
				lobby_panel.game_started.connect(_on_lobby_game_started)
			if lobby_panel.has_signal("panel_closed") and not lobby_panel.panel_closed.is_connected(_on_lobby_closed):
				lobby_panel.panel_closed.connect(_on_lobby_closed)
	else:
		# Start singleplayer game directly
		start_solo_game()

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

	# Load the arena scene for multiplayer
	get_tree().change_scene_to_file("res://scenes/levels/arena_01.tscn")

func _on_lobby_closed():
	# Return to main menu
	_close_panel(lobby_panel)

func start_solo_game():
	# Start a solo game (no multiplayer)
	get_tree().change_scene_to_file("res://scenes/levels/arena_01.tscn")

func _on_stash_pressed():
	stash_pressed.emit()
	_show_panel(stash_panel)

func _on_settings_pressed():
	settings_pressed.emit()
	_show_panel(settings_panel)

func _on_quit_pressed():
	quit_pressed.emit()
	get_tree().quit()

func _on_market_pressed():
	market_pressed.emit()
	_show_panel(market_panel)

func _on_merchant_pressed():
	merchant_pressed.emit()
	_show_panel(merchant_panel)

func _on_leaderboard_pressed():
	leaderboard_pressed.emit()
	_show_panel(leaderboard_panel)

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
	# Hide main menu elements
	main_panel.visible = false
	top_tabs.visible = false
	if game_title:
		game_title.visible = false

	# Show the panel
	if panel:
		panel.visible = true

func _close_panel(panel: Control):
	# Hide the panel
	if panel:
		panel.visible = false

	# Show main menu elements
	main_panel.visible = true
	top_tabs.visible = true
	if game_title:
		game_title.visible = true

func _hide_all_panels():
	var all_panels = [stash_panel, market_panel, merchant_panel, leaderboard_panel, settings_panel, trading_panel, lobby_panel, play_mode_panel, character_select_panel]
	for panel in all_panels:
		if panel:
			panel.visible = false

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
		if stash_panel and stash_panel.visible:
			_close_panel(stash_panel)
		elif market_panel and market_panel.visible:
			_close_panel(market_panel)
		elif merchant_panel and merchant_panel.visible:
			_close_panel(merchant_panel)
		elif leaderboard_panel and leaderboard_panel.visible:
			_close_panel(leaderboard_panel)
		elif settings_panel and settings_panel.visible:
			_close_panel(settings_panel)
		elif trading_panel and trading_panel.visible:
			_close_panel(trading_panel)
		elif lobby_panel and lobby_panel.visible:
			_close_panel(lobby_panel)
		elif play_mode_panel and play_mode_panel.visible:
			_close_panel(play_mode_panel)
		elif character_select_panel and character_select_panel.visible:
			_close_panel(character_select_panel)
