extends Node

# Steam integration using GodotSteam
# Requires GodotSteam addon: https://github.com/GodotSteam/GodotSteam

signal steam_initialized(success: bool)
signal lobby_created(lobby_id: int)
signal lobby_joined(lobby_id: int)
signal lobby_join_failed(reason: String)
signal friend_invite_sent(friend_id: int)
signal lobby_list_received(lobbies: Array)

var steam_app_id: int = 480  # Replace with your Steam App ID
var steam_id: int = 0
var steam_username: String = ""
var is_steam_running: bool = false
var is_online: bool = false

var current_lobby_id: int = 0
var lobby_members: Array[Dictionary] = []
var is_lobby_owner: bool = false

# Lobby settings
const MAX_LOBBY_MEMBERS: int = 4
const MIN_PLAYERS_TO_START: int = 2

func _ready():
	initialize_steam()

func initialize_steam():
	# Check if Steam is available
	if not Engine.has_singleton("Steam"):
		print("Steam API not available! Install GodotSteam.")
		steam_initialized.emit(false)
		return

	var steam = Engine.get_singleton("Steam")

	# Initialize Steam
	var init_result = steam.steamInit()

	if init_result.status != 1:
		print("Failed to initialize Steam: ", init_result)
		steam_initialized.emit(false)
		return

	is_steam_running = true
	steam_id = steam.getSteamID()
	steam_username = steam.getPersonaName()
	is_online = steam.loggedOn()

	print("Steam initialized successfully!")
	print("Steam ID: ", steam_id)
	print("Username: ", steam_username)

	# Connect Steam callbacks
	connect_steam_signals()

	steam_initialized.emit(true)

func connect_steam_signals():
	var steam = Engine.get_singleton("Steam")

	# Lobby callbacks
	steam.lobby_created.connect(_on_lobby_created)
	steam.lobby_match_list.connect(_on_lobby_match_list)
	steam.lobby_joined.connect(_on_lobby_joined)
	steam.lobby_chat_update.connect(_on_lobby_chat_update)
	steam.lobby_data_update.connect(_on_lobby_data_update)
	steam.lobby_invite.connect(_on_lobby_invite)
	steam.persona_state_change.connect(_on_persona_state_change)

func _process(_delta):
	if is_steam_running:
		var steam = Engine.get_singleton("Steam")
		steam.run_callbacks()

# ============================================
# LOBBY MANAGEMENT
# ============================================

func create_lobby(lobby_type: int = 0):  # 0 = friends only, 2 = public
	if not is_steam_running:
		return

	var steam = Engine.get_singleton("Steam")

	# Create lobby
	# Type: 0 = Private, 1 = Friends Only, 2 = Public, 3 = Invisible
	steam.createLobby(lobby_type, MAX_LOBBY_MEMBERS)

func join_lobby(lobby_id: int):
	if not is_steam_running:
		return

	var steam = Engine.get_singleton("Steam")
	steam.joinLobby(lobby_id)

func leave_lobby():
	if current_lobby_id == 0 or not is_steam_running:
		return

	var steam = Engine.get_singleton("Steam")
	steam.leaveLobby(current_lobby_id)

	current_lobby_id = 0
	lobby_members.clear()
	is_lobby_owner = false

func search_lobbies():
	if not is_steam_running:
		return

	var steam = Engine.get_singleton("Steam")

	# Add filters
	steam.addRequestLobbyListDistanceFilter(3)  # Worldwide
	steam.addRequestLobbyListResultCountFilter(50)

	# Add custom filters for game mode, version, etc.
	steam.addRequestLobbyListStringFilter("game_mode", "survival", 0)  # 0 = equal

	# Request lobby list
	steam.requestLobbyList()

func invite_friend_to_lobby(friend_id: int):
	if current_lobby_id == 0 or not is_steam_running:
		return

	var steam = Engine.get_singleton("Steam")
	steam.inviteUserToLobby(current_lobby_id, friend_id)
	friend_invite_sent.emit(friend_id)

func set_lobby_data(key: String, value: String):
	if current_lobby_id == 0 or not is_steam_running:
		return

	var steam = Engine.get_singleton("Steam")
	steam.setLobbyData(current_lobby_id, key, value)

func get_lobby_data(key: String) -> String:
	if current_lobby_id == 0 or not is_steam_running:
		return ""

	var steam = Engine.get_singleton("Steam")
	return steam.getLobbyData(current_lobby_id, key)

func set_lobby_joinable(joinable: bool):
	if current_lobby_id == 0 or not is_steam_running:
		return

	var steam = Engine.get_singleton("Steam")
	steam.setLobbyJoinable(current_lobby_id, joinable)

func get_lobby_members() -> Array[Dictionary]:
	return lobby_members

func get_num_lobby_members() -> int:
	if current_lobby_id == 0 or not is_steam_running:
		return 0

	var steam = Engine.get_singleton("Steam")
	return steam.getNumLobbyMembers(current_lobby_id)

func can_start_game() -> bool:
	return is_lobby_owner and get_num_lobby_members() >= MIN_PLAYERS_TO_START

# ============================================
# FRIENDS
# ============================================

func get_friend_list() -> Array[Dictionary]:
	if not is_steam_running:
		return []

	var steam = Engine.get_singleton("Steam")
	var friends: Array[Dictionary] = []

	var friend_count = steam.getFriendCount()

	for i in range(friend_count):
		var friend_id = steam.getFriendByIndex(i, 0x04)  # 0x04 = friend flag
		var friend_name = steam.getFriendPersonaName(friend_id)
		var friend_state = steam.getFriendPersonaState(friend_id)

		friends.append({
			"id": friend_id,
			"name": friend_name,
			"state": friend_state,
			"online": friend_state != 0
		})

	return friends

func get_friends_in_game() -> Array[Dictionary]:
	var friends = get_friend_list()
	var in_game: Array[Dictionary] = []

	for friend in friends:
		if is_friend_in_game(friend.id):
			in_game.append(friend)

	return in_game

func is_friend_in_game(friend_id: int) -> bool:
	if not is_steam_running:
		return false

	var steam = Engine.get_singleton("Steam")
	var game_info = steam.getFriendGamePlayed(friend_id)

	return game_info.id == steam_app_id

# ============================================
# STEAM CALLBACKS
# ============================================

func _on_lobby_created(result: int, lobby_id: int):
	if result == 1:  # Success
		current_lobby_id = lobby_id
		is_lobby_owner = true

		# Set lobby data
		set_lobby_data("game_mode", "survival")
		set_lobby_data("version", "1.0.0")
		set_lobby_data("map", "default")
		set_lobby_data("wave", "1")

		lobby_created.emit(lobby_id)
		print("Lobby created: ", lobby_id)

		# Update lobby members
		update_lobby_members()
	else:
		print("Failed to create lobby: ", result)

func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int):
	if response == 1:  # Success
		current_lobby_id = lobby_id

		# Check if we're the owner
		var steam = Engine.get_singleton("Steam")
		var owner_id = steam.getLobbyOwner(lobby_id)
		is_lobby_owner = (owner_id == steam_id)

		lobby_joined.emit(lobby_id)
		print("Joined lobby: ", lobby_id)

		# Update lobby members
		update_lobby_members()
	else:
		var reason = "Unknown error"
		match response:
			2: reason = "Lobby doesn't exist"
			3: reason = "Access denied"
			4: reason = "Lobby full"
			5: reason = "Error"
			6: reason = "Banned"
			7: reason = "Limited user"
			8: reason = "Clan disabled"
			9: reason = "Community ban"
			10: reason = "Member blocked"
			11: reason = "Member timeout"

		lobby_join_failed.emit(reason)
		print("Failed to join lobby: ", reason)

func _on_lobby_match_list(lobbies: Array):
	var lobby_list: Array = []

	for lobby_id in lobbies:
		var steam = Engine.get_singleton("Steam")

		var data = {
			"id": lobby_id,
			"members": steam.getNumLobbyMembers(lobby_id),
			"max_members": steam.getLobbyMemberLimit(lobby_id),
			"game_mode": steam.getLobbyData(lobby_id, "game_mode"),
			"version": steam.getLobbyData(lobby_id, "version"),
			"wave": steam.getLobbyData(lobby_id, "wave"),
			"map": steam.getLobbyData(lobby_id, "map")
		}

		lobby_list.append(data)

	lobby_list_received.emit(lobby_list)
	print("Received %d lobbies" % lobby_list.size())

func _on_lobby_chat_update(_lobby_id: int, _changed_id: int, _making_change_id: int, _chat_state: int):
	# Update lobby member list
	update_lobby_members()

func _on_lobby_data_update(_success: int, _lobby_id: int, _member_id: int, _key: int):
	# Lobby data updated
	pass

func _on_lobby_invite(_inviter: int, lobby_id: int, _game_id: int):
	# Received lobby invite
	print("Received lobby invite: ", lobby_id)
	# Could auto-show join prompt here

func _on_persona_state_change(_steam_id: int, _flags: int):
	# Friend status changed
	pass

func update_lobby_members():
	if current_lobby_id == 0 or not is_steam_running:
		return

	var steam = Engine.get_singleton("Steam")
	lobby_members.clear()

	var member_count = steam.getNumLobbyMembers(current_lobby_id)

	for i in range(member_count):
		var member_id = steam.getLobbyMemberByIndex(current_lobby_id, i)
		var member_name = steam.getFriendPersonaName(member_id)

		lobby_members.append({
			"id": member_id,
			"name": member_name,
			"ready": false
		})

	print("Lobby members: ", lobby_members.size())

# ============================================
# UTILITY
# ============================================

func get_steam_id() -> int:
	return steam_id

func get_username() -> String:
	return steam_username

func is_initialized() -> bool:
	return is_steam_running

func get_lobby_id() -> int:
	return current_lobby_id

func is_in_lobby() -> bool:
	return current_lobby_id != 0
