extends Control
class_name LobbyUI

@export var steam_manager: Node
@export var network_manager: Node

@onready var lobby_panel: Panel = $LobbyPanel
@onready var create_lobby_button: Button = $MenuPanel/CreateLobbyButton
@onready var find_match_button: Button = $MenuPanel/FindMatchButton
@onready var browse_lobbies_button: Button = $MenuPanel/BrowseLobbiesButton
@onready var invite_friends_button: Button = $LobbyPanel/InviteFriendsButton
@onready var ready_button: Button = $LobbyPanel/ReadyButton
@onready var start_game_button: Button = $LobbyPanel/StartGameButton
@onready var leave_lobby_button: Button = $LobbyPanel/LeaveLobbyButton

@onready var lobby_info_label: Label = $LobbyPanel/LobbyInfoLabel
@onready var player_list: VBoxContainer = $LobbyPanel/PlayerList
@onready var chat_log: RichTextLabel = $LobbyPanel/ChatLog
@onready var chat_input: LineEdit = $LobbyPanel/ChatInput

@onready var browser_panel: Panel = $BrowserPanel
@onready var lobby_browser_list: VBoxContainer = $BrowserPanel/ScrollContainer/LobbyList
@onready var refresh_button: Button = $BrowserPanel/RefreshButton
@onready var close_browser_button: Button = $BrowserPanel/CloseButton

@onready var friends_panel: Panel = $FriendsPanel
@onready var friends_list: VBoxContainer = $FriendsPanel/ScrollContainer/FriendsList
@onready var close_friends_button: Button = $FriendsPanel/CloseButton

var is_ready: bool = false
var current_lobby_members: Array[Dictionary] = []

signal lobby_created_ui
signal lobby_joined_ui
signal game_started

func _ready():
	visible = true
	lobby_panel.visible = false
	browser_panel.visible = false
	friends_panel.visible = false

	# Connect buttons
	create_lobby_button.pressed.connect(_on_create_lobby_pressed)
	find_match_button.pressed.connect(_on_find_match_pressed)
	browse_lobbies_button.pressed.connect(_on_browse_lobbies_pressed)
	invite_friends_button.pressed.connect(_on_invite_friends_pressed)
	ready_button.pressed.connect(_on_ready_pressed)
	start_game_button.pressed.connect(_on_start_game_pressed)
	leave_lobby_button.pressed.connect(_on_leave_lobby_pressed)
	refresh_button.pressed.connect(_on_refresh_lobbies_pressed)
	close_browser_button.pressed.connect(_on_close_browser_pressed)
	close_friends_button.pressed.connect(_on_close_friends_pressed)

	# Connect chat
	chat_input.text_submitted.connect(_on_chat_submitted)

	# Connect Steam signals
	if steam_manager:
		steam_manager.lobby_created.connect(_on_lobby_created)
		steam_manager.lobby_joined.connect(_on_lobby_joined)
		steam_manager.lobby_list_received.connect(_on_lobby_list_received)

	# Connect Network signals
	if network_manager:
		network_manager.player_connected.connect(_on_player_connected)
		network_manager.player_disconnected.connect(_on_player_disconnected)

func _on_create_lobby_pressed():
	if not steam_manager:
		return

	# Create friends-only lobby
	steam_manager.create_lobby(1)  # 1 = Friends Only
	add_chat_message("Creating lobby...")

func _on_find_match_pressed():
	if not steam_manager:
		return

	# Search for public lobbies
	steam_manager.search_lobbies()
	add_chat_message("Searching for matches...")

func _on_browse_lobbies_pressed():
	browser_panel.visible = true

	if steam_manager:
		steam_manager.search_lobbies()

func _on_invite_friends_pressed():
	friends_panel.visible = true
	refresh_friends_list()

func _on_ready_pressed():
	is_ready = !is_ready
	ready_button.text = "READY" if is_ready else "NOT READY"
	ready_button.modulate = Color.GREEN if is_ready else Color.WHITE

	# Sync ready state
	if network_manager:
		network_manager.set_player_ready(network_manager.get_local_peer_id(), is_ready)

	update_lobby_display()

func _on_start_game_pressed():
	if not network_manager or not network_manager.is_host():
		return

	if not network_manager.are_all_players_ready():
		add_chat_message("Not all players are ready!")
		return

	if network_manager.get_player_count() < 2:
		add_chat_message("Need at least 2 players to start!")
		return

	# Start game
	start_game()

func _on_leave_lobby_pressed():
	if steam_manager:
		steam_manager.leave_lobby()

	if network_manager:
		network_manager.disconnect_from_server()

	leave_lobby()

func _on_refresh_lobbies_pressed():
	if steam_manager:
		steam_manager.search_lobbies()

func _on_close_browser_pressed():
	browser_panel.visible = false

func _on_close_friends_pressed():
	friends_panel.visible = false

func _on_chat_submitted(text: String):
	if text.is_empty():
		return

	# Send chat message
	send_chat_message(text)
	chat_input.clear()

func _on_lobby_created(lobby_id: int):
	add_chat_message("Lobby created! ID: %d" % lobby_id)

	# Start hosting
	if network_manager:
		network_manager.create_server_steam(lobby_id)

	show_lobby()
	lobby_created_ui.emit()

func _on_lobby_joined(lobby_id: int):
	add_chat_message("Joined lobby! ID: %d" % lobby_id)

	# Connect as client
	if network_manager:
		network_manager.join_server_steam(lobby_id)

	show_lobby()
	lobby_joined_ui.emit()

func _on_lobby_list_received(lobbies: Array):
	refresh_lobby_browser(lobbies)

	# Auto-join first available lobby if matchmaking
	if lobbies.size() > 0:
		var first_lobby = lobbies[0]
		if first_lobby.members < first_lobby.max_members:
			steam_manager.join_lobby(first_lobby.id)

func _on_player_connected(peer_id: int, player_info: Dictionary):
	add_chat_message("%s joined the lobby" % player_info.name)
	update_lobby_display()

func _on_player_disconnected(peer_id: int):
	add_chat_message("Player disconnected")
	update_lobby_display()

func show_lobby():
	lobby_panel.visible = true
	$MenuPanel.visible = false

	update_lobby_display()

	# Show start button only for host
	if network_manager:
		start_game_button.visible = network_manager.is_host()

func leave_lobby():
	lobby_panel.visible = false
	$MenuPanel.visible = true

	is_ready = false
	current_lobby_members.clear()

func update_lobby_display():
	# Update lobby info
	if steam_manager and steam_manager.is_in_lobby():
		var member_count = steam_manager.get_num_lobby_members()
		lobby_info_label.text = "Lobby: %d/%d players" % [member_count, 4]

	# Update player list
	clear_player_list()

	if network_manager:
		var players = network_manager.players
		for peer_id in players:
			var player_info = players[peer_id]
			add_player_to_list(player_info)

func clear_player_list():
	for child in player_list.get_children():
		child.queue_free()

func add_player_to_list(player_info: Dictionary):
	var player_entry = HBoxContainer.new()

	var name_label = Label.new()
	name_label.text = player_info.name
	name_label.custom_minimum_size.x = 200
	player_entry.add_child(name_label)

	var ready_label = Label.new()
	ready_label.text = "READY" if player_info.get("ready", false) else "NOT READY"
	ready_label.modulate = Color.GREEN if player_info.get("ready", false) else Color.GRAY
	player_entry.add_child(ready_label)

	player_list.add_child(player_entry)

func refresh_lobby_browser(lobbies: Array):
	# Clear existing
	for child in lobby_browser_list.get_children():
		child.queue_free()

	# Add lobbies
	for lobby in lobbies:
		var lobby_entry = create_lobby_browser_entry(lobby)
		lobby_browser_list.add_child(lobby_entry)

	if lobbies.is_empty():
		var no_lobbies = Label.new()
		no_lobbies.text = "No lobbies found. Create one!"
		lobby_browser_list.add_child(no_lobbies)

func create_lobby_browser_entry(lobby: Dictionary) -> Control:
	var entry = PanelContainer.new()
	var hbox = HBoxContainer.new()
	entry.add_child(hbox)

	# Lobby info
	var info_label = Label.new()
	info_label.text = "Wave %s | %d/%d players" % [lobby.get("wave", "1"), lobby.members, lobby.max_members]
	info_label.custom_minimum_size.x = 300
	hbox.add_child(info_label)

	# Join button
	var join_button = Button.new()
	join_button.text = "Join"
	join_button.pressed.connect(func(): _on_join_lobby_clicked(lobby.id))
	hbox.add_child(join_button)

	return entry

func _on_join_lobby_clicked(lobby_id: int):
	if steam_manager:
		steam_manager.join_lobby(lobby_id)

	browser_panel.visible = false

func refresh_friends_list():
	if not steam_manager:
		return

	# Clear existing
	for child in friends_list.get_children():
		child.queue_free()

	# Get friends
	var friends = steam_manager.get_friend_list()

	for friend in friends:
		var friend_entry = create_friend_entry(friend)
		friends_list.add_child(friend_entry)

func create_friend_entry(friend: Dictionary) -> Control:
	var entry = HBoxContainer.new()

	var name_label = Label.new()
	name_label.text = friend.name
	name_label.custom_minimum_size.x = 200
	entry.add_child(name_label)

	var status_label = Label.new()
	status_label.text = "Online" if friend.online else "Offline"
	status_label.modulate = Color.GREEN if friend.online else Color.GRAY
	entry.add_child(status_label)

	var invite_button = Button.new()
	invite_button.text = "Invite"
	invite_button.disabled = !friend.online or !steam_manager.is_in_lobby()
	invite_button.pressed.connect(func(): _on_invite_friend_clicked(friend.id))
	entry.add_child(invite_button)

	return entry

func _on_invite_friend_clicked(friend_id: int):
	if steam_manager and steam_manager.is_in_lobby():
		steam_manager.invite_friend_to_lobby(friend_id)
		add_chat_message("Invite sent!")

func send_chat_message(message: String):
	# In a full implementation, this would use Steam's lobby chat
	add_chat_message("[%s]: %s" % [steam_manager.get_username() if steam_manager else "You", message])

func add_chat_message(message: String):
	if chat_log:
		chat_log.append_text(message + "\n")
		chat_log.scroll_to_line(chat_log.get_line_count())

func start_game():
	add_chat_message("Starting game...")

	# Hide lobby UI
	visible = false

	game_started.emit()

	# Load game scene
	get_tree().change_scene_to_file("res://scenes/main.tscn")
