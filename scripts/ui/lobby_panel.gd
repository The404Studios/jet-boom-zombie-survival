extends Control
class_name LobbyPanel

signal lobby_created(lobby_id: int)
signal lobby_joined(lobby_id: int)
signal game_started
signal panel_closed

# UI References
@onready var lobby_status_label: Label = $LobbyStatus
@onready var player_list: VBoxContainer = $PlayerList/List
@onready var lobby_browser: VBoxContainer = $LobbyBrowser/List
@onready var friend_list: VBoxContainer = $FriendList/List

# Buttons
@onready var host_button: Button = $Buttons/HostButton
@onready var join_button: Button = $Buttons/JoinButton
@onready var refresh_button: Button = $Buttons/RefreshButton
@onready var start_button: Button = $Buttons/StartButton
@onready var ready_button: Button = $Buttons/ReadyButton
@onready var leave_button: Button = $Buttons/LeaveButton
@onready var invite_button: Button = $Buttons/InviteButton
@onready var close_button: Button = $CloseButton

# Panels
@onready var lobby_browser_panel: Panel = $LobbyBrowserPanel
@onready var lobby_room_panel: Panel = $LobbyRoomPanel

# State
var steam_manager: Node = null
var network_manager: Node = null
var in_lobby: bool = false
var is_host: bool = false
var is_ready: bool = false
var selected_lobby_id: int = 0
var selected_friend_id: int = 0

func _ready():
	# Get managers
	steam_manager = get_node_or_null("/root/SteamManager")
	network_manager = get_node_or_null("/root/NetworkManager")

	# Connect UI signals
	_connect_buttons()

	# Connect Steam signals
	_connect_steam_signals()

	# Connect Network signals
	_connect_network_signals()

	# Initial state
	_show_browser_view()

func _connect_buttons():
	if host_button:
		host_button.pressed.connect(_on_host_pressed)
	if join_button:
		join_button.pressed.connect(_on_join_pressed)
	if refresh_button:
		refresh_button.pressed.connect(_on_refresh_pressed)
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	if ready_button:
		ready_button.pressed.connect(_on_ready_pressed)
	if leave_button:
		leave_button.pressed.connect(_on_leave_pressed)
	if invite_button:
		invite_button.pressed.connect(_on_invite_pressed)
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

func _connect_steam_signals():
	if not steam_manager:
		return

	if steam_manager.has_signal("lobby_created"):
		steam_manager.lobby_created.connect(_on_lobby_created)
	if steam_manager.has_signal("lobby_joined"):
		steam_manager.lobby_joined.connect(_on_lobby_joined)
	if steam_manager.has_signal("lobby_join_failed"):
		steam_manager.lobby_join_failed.connect(_on_lobby_join_failed)
	if steam_manager.has_signal("lobby_list_received"):
		steam_manager.lobby_list_received.connect(_on_lobby_list_received)
	if steam_manager.has_signal("lobby_member_joined"):
		steam_manager.lobby_member_joined.connect(_on_member_joined)
	if steam_manager.has_signal("lobby_member_left"):
		steam_manager.lobby_member_left.connect(_on_member_left)
	if steam_manager.has_signal("lobby_invite_received"):
		steam_manager.lobby_invite_received.connect(_on_invite_received)

func _connect_network_signals():
	if not network_manager:
		return

	if network_manager.has_signal("player_connected"):
		network_manager.player_connected.connect(_on_player_connected)
	if network_manager.has_signal("player_disconnected"):
		network_manager.player_disconnected.connect(_on_player_disconnected)
	if network_manager.has_signal("game_starting"):
		network_manager.game_starting.connect(_on_game_starting)

# ============================================
# VIEW MANAGEMENT
# ============================================

func _show_browser_view():
	if lobby_browser_panel:
		lobby_browser_panel.visible = true
	if lobby_room_panel:
		lobby_room_panel.visible = false

	in_lobby = false
	_update_buttons()
	_refresh_lobbies()
	_refresh_friends()

func _show_room_view():
	if lobby_browser_panel:
		lobby_browser_panel.visible = false
	if lobby_room_panel:
		lobby_room_panel.visible = true

	in_lobby = true
	_update_buttons()
	_refresh_player_list()

func _update_buttons():
	if host_button:
		host_button.visible = not in_lobby
	if join_button:
		join_button.visible = not in_lobby and selected_lobby_id > 0
	if refresh_button:
		refresh_button.visible = not in_lobby
	if start_button:
		start_button.visible = in_lobby and is_host
	if ready_button:
		ready_button.visible = in_lobby and not is_host
	if leave_button:
		leave_button.visible = in_lobby
	if invite_button:
		invite_button.visible = in_lobby

	# Update ready button text
	if ready_button:
		ready_button.text = "UNREADY" if is_ready else "READY"

	# Update start button state
	if start_button and network_manager:
		start_button.disabled = not network_manager.are_all_players_ready()

func _update_status(text: String):
	if lobby_status_label:
		lobby_status_label.text = text

# ============================================
# BUTTON HANDLERS
# ============================================

func _on_host_pressed():
	_update_status("Creating lobby...")

	if steam_manager and steam_manager.is_initialized():
		# Create Steam lobby (friends only by default)
		steam_manager.create_lobby(1)
	else:
		# Create LAN server
		if network_manager:
			network_manager.create_server_lan()
			is_host = true
			_show_room_view()
			_update_status("LAN lobby created")

func _on_join_pressed():
	if selected_lobby_id <= 0:
		return

	_update_status("Joining lobby...")

	if steam_manager and steam_manager.is_initialized():
		steam_manager.join_lobby(selected_lobby_id)
	else:
		# LAN join would need an IP input
		pass

func _on_refresh_pressed():
	_refresh_lobbies()
	_refresh_friends()

func _on_start_pressed():
	if not is_host or not network_manager:
		return

	_update_status("Starting game...")
	network_manager.start_game()

func _on_ready_pressed():
	is_ready = not is_ready

	if network_manager:
		network_manager.set_player_ready(network_manager.get_local_peer_id(), is_ready)

	_update_buttons()

func _on_leave_pressed():
	if steam_manager:
		steam_manager.leave_lobby()

	if network_manager:
		network_manager.disconnect_from_server()

	in_lobby = false
	is_host = false
	is_ready = false
	_show_browser_view()
	_update_status("Left lobby")

func _on_invite_pressed():
	if selected_friend_id > 0 and steam_manager:
		steam_manager.invite_friend_to_lobby(selected_friend_id)
		_update_status("Invite sent!")

func _on_close_pressed():
	# Leave lobby if in one
	if in_lobby:
		_on_leave_pressed()

	panel_closed.emit()
	visible = false

# ============================================
# STEAM CALLBACKS
# ============================================

func _on_lobby_created(lobby_id: int):
	is_host = true
	_show_room_view()
	_update_status("Lobby created! Invite friends to join.")
	lobby_created.emit(lobby_id)

func _on_lobby_joined(lobby_id: int):
	if not is_host:
		is_host = false
	_show_room_view()
	_update_status("Joined lobby!")
	lobby_joined.emit(lobby_id)
	_refresh_player_list()

func _on_lobby_join_failed(reason: String):
	_update_status("Failed to join: " + reason)
	_show_browser_view()

func _on_lobby_list_received(lobbies: Array):
	_populate_lobby_browser(lobbies)

func _on_member_joined(member_id: int, member_name: String):
	_update_status(member_name + " joined the lobby")
	_refresh_player_list()

func _on_member_left(_member_id: int):
	_update_status("A player left the lobby")
	_refresh_player_list()

func _on_invite_received(_inviter_id: int, inviter_name: String, lobby_id: int):
	# Show invite notification
	_show_invite_popup(inviter_name, lobby_id)

func _on_player_connected(_peer_id: int, _player_info: Dictionary):
	_refresh_player_list()

func _on_player_disconnected(_peer_id: int):
	_refresh_player_list()

func _on_game_starting():
	_update_status("Game starting...")
	game_started.emit()

# ============================================
# UI POPULATION
# ============================================

func _refresh_lobbies():
	if steam_manager and steam_manager.is_initialized():
		steam_manager.search_lobbies()
	else:
		# Show no lobbies message for LAN
		_clear_lobby_browser()
		_add_lobby_entry({
			"id": 0,
			"name": "No Steam - Use LAN",
			"members": 0,
			"max_members": 4
		})

func _refresh_friends():
	if not friend_list:
		return

	# Clear existing
	for child in friend_list.get_children():
		child.queue_free()

	if not steam_manager or not steam_manager.is_initialized():
		return

	var friends = steam_manager.get_friend_list()

	for friend in friends:
		if friend.online:
			var entry = _create_friend_entry(friend)
			friend_list.add_child(entry)

func _refresh_player_list():
	if not player_list:
		return

	# Clear existing
	for child in player_list.get_children():
		child.queue_free()

	# Get players from network manager or Steam lobby
	if network_manager:
		var players = network_manager.get_players()
		for peer_id in players:
			var player_info = players[peer_id]
			var entry = _create_player_entry(player_info, peer_id)
			player_list.add_child(entry)
	elif steam_manager and steam_manager.is_in_lobby():
		var members = steam_manager.get_lobby_members()
		for member in members:
			var entry = _create_player_entry(member, 0)
			player_list.add_child(entry)

func _populate_lobby_browser(lobbies: Array):
	_clear_lobby_browser()

	if lobbies.is_empty():
		var label = Label.new()
		label.text = "No lobbies found"
		lobby_browser.add_child(label)
		return

	for lobby in lobbies:
		_add_lobby_entry(lobby)

func _clear_lobby_browser():
	if not lobby_browser:
		return

	for child in lobby_browser.get_children():
		child.queue_free()

func _add_lobby_entry(lobby_data: Dictionary):
	if not lobby_browser:
		return

	var entry = HBoxContainer.new()

	var name_label = Label.new()
	name_label.text = lobby_data.get("name", "Lobby %d" % lobby_data.get("id", 0))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.add_child(name_label)

	var count_label = Label.new()
	count_label.text = "%d/%d" % [lobby_data.get("members", 0), lobby_data.get("max_members", 4)]
	entry.add_child(count_label)

	var join_btn = Button.new()
	join_btn.text = "Join"
	join_btn.pressed.connect(_on_lobby_entry_selected.bind(lobby_data.get("id", 0)))
	entry.add_child(join_btn)

	lobby_browser.add_child(entry)

func _create_player_entry(player_info: Dictionary, _peer_id: int) -> HBoxContainer:
	var entry = HBoxContainer.new()

	var name_label = Label.new()
	name_label.text = player_info.get("name", "Unknown")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.add_child(name_label)

	var ready_label = Label.new()
	ready_label.text = "[READY]" if player_info.get("ready", false) else ""
	ready_label.add_theme_color_override("font_color", Color.GREEN)
	entry.add_child(ready_label)

	return entry

func _create_friend_entry(friend_data: Dictionary) -> HBoxContainer:
	var entry = HBoxContainer.new()

	var name_label = Label.new()
	name_label.text = friend_data.get("name", "Unknown")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.add_child(name_label)

	var status_label = Label.new()
	if friend_data.get("online", false):
		status_label.text = "Online"
		status_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		status_label.text = "Offline"
		status_label.add_theme_color_override("font_color", Color.GRAY)
	entry.add_child(status_label)

	var invite_btn = Button.new()
	invite_btn.text = "Invite"
	invite_btn.pressed.connect(_on_friend_invite_pressed.bind(friend_data.get("id", 0)))
	invite_btn.disabled = not in_lobby
	entry.add_child(invite_btn)

	return entry

func _on_lobby_entry_selected(lobby_id: int):
	selected_lobby_id = lobby_id
	_update_buttons()

	# Auto-join
	_on_join_pressed()

func _on_friend_invite_pressed(friend_id: int):
	selected_friend_id = friend_id
	_on_invite_pressed()

# ============================================
# INVITE POPUP
# ============================================

func _show_invite_popup(inviter_name: String, lobby_id: int):
	# Create popup
	var popup = AcceptDialog.new()
	popup.title = "Game Invite"
	popup.dialog_text = "%s invited you to play!" % inviter_name
	popup.ok_button_text = "Accept"
	popup.add_cancel_button("Decline")

	popup.confirmed.connect(_accept_invite.bind(lobby_id))

	add_child(popup)
	popup.popup_centered()

func _accept_invite(lobby_id: int):
	if steam_manager:
		steam_manager.join_lobby(lobby_id)

# ============================================
# PUBLIC INTERFACE
# ============================================

func open():
	visible = true
	_show_browser_view()

func close():
	visible = false
	panel_closed.emit()
