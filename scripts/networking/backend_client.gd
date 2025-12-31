extends Node
class_name BackendClient

# HTTP client for communicating with the C# backend server
# Handles authentication, player data, server browser, leaderboards, and shop

signal logged_in(player_data: Dictionary)
signal logged_out
signal login_failed(error: String)
signal profile_updated(player_data: Dictionary)
signal request_completed(endpoint: String, response: Dictionary)
signal request_failed(endpoint: String, error: String)

# Server configuration
@export var server_url: String = "http://localhost:5000"
@export var request_timeout: float = 30.0

# Authentication state
var auth_token: String = ""
var refresh_token: String = ""
var token_expires_at: float = 0.0
var current_player: Dictionary = {}
var is_authenticated: bool = false

# Request queue
var request_queue: Array = []
var active_requests: Dictionary = {}

func _ready():
	# Try to load saved tokens
	_load_tokens()

func _process(_delta):
	# Process request queue
	_process_request_queue()

# ============================================
# AUTHENTICATION
# ============================================

func register(username: String, email: String, password: String) -> void:
	"""Register a new account"""
	var body = {
		"username": username,
		"email": email,
		"password": password
	}

	_make_request("POST", "/api/auth/register", body, func(response):
		if response.success:
			_handle_auth_response(response)
			logged_in.emit(current_player)
		else:
			login_failed.emit(response.get("error", "Registration failed"))
	)

func login(username: String, password: String) -> void:
	"""Login with existing credentials"""
	var body = {
		"username": username,
		"password": password
	}

	_make_request("POST", "/api/auth/login", body, func(response):
		if response.success:
			_handle_auth_response(response)
			logged_in.emit(current_player)
		else:
			login_failed.emit(response.get("error", "Login failed"))
	)

func logout() -> void:
	"""Clear authentication state"""
	auth_token = ""
	refresh_token = ""
	token_expires_at = 0.0
	current_player = {}
	is_authenticated = false
	_save_tokens()
	logged_out.emit()

func refresh_auth() -> void:
	"""Refresh authentication token"""
	if refresh_token.is_empty():
		return

	var body = {"refreshToken": refresh_token}

	_make_request("POST", "/api/auth/refresh", body, func(response):
		if response.success:
			_handle_auth_response(response)
		else:
			# Refresh failed, need to login again
			logout()
	, false)  # Don't require auth for refresh

func is_token_expired() -> bool:
	return Time.get_unix_time_from_system() >= token_expires_at - 60  # 1 min buffer

func _handle_auth_response(response: Dictionary) -> void:
	auth_token = response.get("token", "")
	refresh_token = response.get("refreshToken", "")

	var expires_at = response.get("expiresAt", "")
	if not expires_at.is_empty():
		# Parse ISO 8601 date
		token_expires_at = Time.get_unix_time_from_system() + 86400  # 24 hours fallback

	if response.has("player"):
		current_player = response.player

	is_authenticated = not auth_token.is_empty()
	_save_tokens()

# ============================================
# PLAYER API
# ============================================

func get_my_profile(callback: Callable = Callable()) -> void:
	"""Get current player's profile"""
	_make_request("GET", "/api/player/me", {}, func(response):
		if response.success:
			current_player = response
		if callback.is_valid():
			callback.call(response)
	)

func get_profile(callback: Callable = Callable()) -> void:
	"""Alias for get_my_profile"""
	get_my_profile(callback)

func get_player_profile(player_id: int, callback: Callable = Callable()) -> void:
	"""Get another player's profile"""
	_make_request("GET", "/api/player/%d" % player_id, {}, callback, false)

func update_profile(data: Dictionary, callback: Callable = Callable()) -> void:
	"""Update current player's profile"""
	_make_request("PATCH", "/api/player/me", data, func(response):
		if response.success:
			# Update local player data
			for key in data:
				current_player[key] = data[key]
			profile_updated.emit(current_player)
		if callback.is_valid():
			callback.call(response)
	)

func update_stats(stats: Dictionary, callback: Callable = Callable()) -> void:
	"""Update player stats after a game"""
	_make_request("POST", "/api/player/stats", stats, callback)

func record_match(match_result: Dictionary, callback: Callable = Callable()) -> void:
	"""Record a completed match"""
	_make_request("POST", "/api/player/me/matches", match_result, callback)

func get_match_history(limit: int = 20, callback: Callable = Callable()) -> void:
	"""Get player's match history"""
	_make_request("GET", "/api/player/me/matches?limit=%d" % limit, {}, callback)

func get_friends(callback: Callable = Callable()) -> void:
	"""Get friends list"""
	_make_request("GET", "/api/player/me/friends", {}, callback)

func send_friend_request(username: String, callback: Callable = Callable()) -> void:
	"""Send a friend request"""
	_make_request("POST", "/api/player/me/friends", {"username": username}, callback)

func respond_to_friend_request(friend_id: int, accept: bool, callback: Callable = Callable()) -> void:
	"""Accept or decline friend request"""
	var url = "/api/player/me/friends/%d/respond?accept=%s" % [friend_id, str(accept).to_lower()]
	_make_request("POST", url, {}, callback)

func get_pending_friend_requests(callback: Callable = Callable()) -> void:
	"""Get pending friend requests"""
	_make_request("GET", "/api/player/me/friends/pending", {}, callback)

func accept_friend_request(request_id: int, callback: Callable = Callable()) -> void:
	"""Accept a friend request"""
	respond_to_friend_request(request_id, true, callback)

func decline_friend_request(request_id: int, callback: Callable = Callable()) -> void:
	"""Decline a friend request"""
	respond_to_friend_request(request_id, false, callback)

func remove_friend(friend_id: int, callback: Callable = Callable()) -> void:
	"""Remove a friend"""
	_make_request("DELETE", "/api/player/me/friends/%d" % friend_id, {}, callback)

func unlock_achievement(achievement_id: String, callback: Callable = Callable()) -> void:
	"""Unlock an achievement"""
	_make_request("POST", "/api/player/me/achievements/%s" % achievement_id, {}, callback)

func get_achievements(callback: Callable = Callable()) -> void:
	"""Get player's achievements"""
	_make_request("GET", "/api/player/me/achievements", {}, callback)

# ============================================
# SERVER BROWSER API
# ============================================

func get_servers(filters: Dictionary = {}, callback: Callable = Callable()) -> void:
	"""Get list of game servers"""
	var query_params = []

	if filters.has("region"):
		query_params.append("region=%s" % filters.region)
	if filters.has("gameMode"):
		query_params.append("gameMode=%s" % filters.gameMode)
	if filters.get("hideEmpty", false):
		query_params.append("hideEmpty=true")
	if filters.get("hideFull", false):
		query_params.append("hideFull=true")

	var url = "/api/servers"
	if query_params.size() > 0:
		url += "?" + "&".join(query_params)

	_make_request("GET", url, {}, callback, false)

func get_server(server_id: int, callback: Callable = Callable()) -> void:
	"""Get specific server details"""
	_make_request("GET", "/api/servers/%d" % server_id, {}, callback, false)

func register_server(server_data: Dictionary, callback: Callable = Callable()) -> void:
	"""Register a new game server (for dedicated servers)"""
	_make_request("POST", "/api/servers/register", server_data, callback, false)

func update_server(server_id: int, token: String, data: Dictionary, callback: Callable = Callable()) -> void:
	"""Update game server status"""
	_make_request("PATCH", "/api/servers/%d" % server_id, data, callback, false, {"X-Server-Token": token})

func server_heartbeat(server_id: int, status_or_token, callback: Callable = Callable()) -> void:
	"""Send server heartbeat - accepts either status Dictionary or token String"""
	var extra_headers = {}
	var body = {}

	if status_or_token is String:
		# Legacy: token as string
		extra_headers = {"X-Server-Token": status_or_token}
	elif status_or_token is Dictionary:
		# New: status dictionary, use auth token
		body = status_or_token

	_make_request("POST", "/api/servers/%d/heartbeat" % server_id, body, callback, false, extra_headers)

func deregister_server(server_id: int, token: String, callback: Callable = Callable()) -> void:
	"""Deregister a game server"""
	_make_request("DELETE", "/api/servers/%d" % server_id, {}, callback, false, {"X-Server-Token": token})

# ============================================
# MATCHMAKING API
# ============================================

func join_matchmaking(game_mode: String, preferred_region: String = "", preferred_map: String = "", callback: Callable = Callable()) -> void:
	"""Join matchmaking queue"""
	var body = {"gameMode": game_mode}
	if not preferred_region.is_empty():
		body["preferredRegion"] = preferred_region
	if not preferred_map.is_empty():
		body["preferredMap"] = preferred_map

	_make_request("POST", "/api/matchmaking/join", body, callback)

func join_matchmaking_queue(preferences: Dictionary, callback: Callable = Callable()) -> void:
	"""Join matchmaking queue with preferences dictionary"""
	_make_request("POST", "/api/matchmaking/join", preferences, callback)

func get_matchmaking_status(ticket_id: String, callback: Callable = Callable()) -> void:
	"""Get matchmaking status"""
	_make_request("GET", "/api/matchmaking/status/%s" % ticket_id, {}, callback)

func cancel_matchmaking(ticket_id: String, callback: Callable = Callable()) -> void:
	"""Cancel matchmaking"""
	_make_request("DELETE", "/api/matchmaking/%s" % ticket_id, {}, callback)

func leave_matchmaking_queue(callback: Callable = Callable()) -> void:
	"""Leave matchmaking queue (without ticket ID)"""
	_make_request("DELETE", "/api/matchmaking/leave", {}, callback)

# ============================================
# LEADERBOARD API
# ============================================

func get_leaderboard(category: String, time_frame: String = "all", limit: int = 100, callback: Callable = Callable()) -> void:
	"""Get leaderboard for a category"""
	var url = "/api/leaderboard/%s?timeFrame=%s&limit=%d" % [category, time_frame, limit]
	_make_request("GET", url, {}, callback, false)

func get_top_players(category: String, limit: int = 10, callback: Callable = Callable()) -> void:
	"""Get top players for a category"""
	_make_request("GET", "/api/leaderboard/%s/top?limit=%d" % [category, limit], {}, callback, false)

func get_my_rank(category: String, callback: Callable = Callable()) -> void:
	"""Get current player's rank"""
	_make_request("GET", "/api/leaderboard/%s/me" % category, {}, callback)

# ============================================
# SHOP API
# ============================================

func get_shop_items(category: String = "", callback: Callable = Callable()) -> void:
	"""Get shop catalog"""
	var url = "/api/shop"
	if not category.is_empty():
		url += "?category=%s" % category

	_make_request("GET", url, {}, callback)

func purchase_item(item_id: String, callback: Callable = Callable()) -> void:
	"""Purchase an item"""
	_make_request("POST", "/api/shop/purchase", {"itemId": item_id}, callback)

func get_inventory(callback: Callable = Callable()) -> void:
	"""Get player's inventory"""
	_make_request("GET", "/api/shop/inventory", {}, callback)

func use_item(item_id: String, callback: Callable = Callable()) -> void:
	"""Use a consumable item"""
	_make_request("POST", "/api/shop/use/%s" % item_id, {}, callback)

# ============================================
# HTTP REQUEST HANDLING
# ============================================

func _make_request(method: String, endpoint: String, body: Dictionary, callback: Callable = Callable(), require_auth: bool = true, extra_headers: Dictionary = {}) -> void:
	# Check authentication
	if require_auth and not is_authenticated:
		if callback.is_valid():
			callback.call({"success": false, "error": "Not authenticated"})
		return

	# Auto-refresh token if needed
	if require_auth and is_token_expired() and not refresh_token.is_empty():
		refresh_auth()
		# Queue this request to retry after refresh
		await get_tree().create_timer(0.5).timeout

	# Create HTTP request
	var http = HTTPRequest.new()
	add_child(http)

	var url = server_url + endpoint
	var headers = ["Content-Type: application/json"]

	if require_auth and not auth_token.is_empty():
		headers.append("Authorization: Bearer %s" % auth_token)

	for key in extra_headers:
		headers.append("%s: %s" % [key, extra_headers[key]])

	var json_body = ""
	if not body.is_empty():
		json_body = JSON.stringify(body)

	# Store callback
	var request_id = str(randi())
	active_requests[request_id] = {
		"endpoint": endpoint,
		"callback": callback,
		"http": http
	}

	# Make request
	var error: int
	if method == "GET" or method == "DELETE":
		error = http.request(url, headers, HTTPClient.METHOD_GET if method == "GET" else HTTPClient.METHOD_DELETE)
	elif method == "POST":
		error = http.request(url, headers, HTTPClient.METHOD_POST, json_body)
	elif method == "PATCH":
		error = http.request(url, headers, HTTPClient.METHOD_PATCH, json_body)
	elif method == "PUT":
		error = http.request(url, headers, HTTPClient.METHOD_PUT, json_body)
	else:
		error = ERR_INVALID_PARAMETER

	if error != OK:
		_handle_request_error(request_id, "Failed to create request")
		return

	# Connect signal
	http.request_completed.connect(func(result, response_code, response_headers, response_body):
		_handle_request_completed(request_id, result, response_code, response_body)
	)

	# Set timeout
	await get_tree().create_timer(request_timeout).timeout
	if active_requests.has(request_id):
		_handle_request_error(request_id, "Request timeout")

func _handle_request_completed(request_id: String, result: int, response_code: int, response_body: PackedByteArray) -> void:
	if not active_requests.has(request_id):
		return

	var request_data = active_requests[request_id]
	active_requests.erase(request_id)

	var http = request_data.http as HTTPRequest
	if http:
		http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_request_error_with_data(request_data, "Network error: %d" % result)
		return

	# Parse response
	var json_string = response_body.get_string_from_utf8()
	var response: Dictionary = {}

	if not json_string.is_empty():
		var json = JSON.new()
		var parse_result = json.parse(json_string)
		if parse_result == OK:
			response = json.data if json.data is Dictionary else {"data": json.data}
		else:
			response = {"raw": json_string}

	# Check response code
	if response_code >= 200 and response_code < 300:
		response["success"] = true
	else:
		response["success"] = false
		if not response.has("error"):
			response["error"] = "HTTP %d" % response_code

	# Call callback
	if request_data.callback.is_valid():
		request_data.callback.call(response)

	# Emit signal
	if response.success:
		request_completed.emit(request_data.endpoint, response)
	else:
		request_failed.emit(request_data.endpoint, response.get("error", "Unknown error"))

func _handle_request_error(request_id: String, error_message: String) -> void:
	if not active_requests.has(request_id):
		return

	var request_data = active_requests[request_id]
	_handle_request_error_with_data(request_data, error_message)
	active_requests.erase(request_id)

func _handle_request_error_with_data(request_data: Dictionary, error_message: String) -> void:
	var http = request_data.get("http") as HTTPRequest
	if http:
		http.queue_free()

	if request_data.callback.is_valid():
		request_data.callback.call({"success": false, "error": error_message})

	request_failed.emit(request_data.endpoint, error_message)

func _process_request_queue() -> void:
	# Process queued requests (for rate limiting, etc.)
	pass

# ============================================
# TOKEN PERSISTENCE
# ============================================

const TOKEN_FILE = "user://auth_tokens.cfg"

func _save_tokens() -> void:
	var config = ConfigFile.new()
	config.set_value("auth", "token", auth_token)
	config.set_value("auth", "refresh_token", refresh_token)
	config.set_value("auth", "expires_at", token_expires_at)
	config.save(TOKEN_FILE)

func _load_tokens() -> void:
	var config = ConfigFile.new()
	var error = config.load(TOKEN_FILE)
	if error == OK:
		auth_token = config.get_value("auth", "token", "")
		refresh_token = config.get_value("auth", "refresh_token", "")
		token_expires_at = config.get_value("auth", "expires_at", 0.0)

		if not auth_token.is_empty() and not is_token_expired():
			is_authenticated = true
			# Fetch fresh player data
			get_my_profile()
		elif not refresh_token.is_empty():
			# Try to refresh
			refresh_auth()

func clear_saved_tokens() -> void:
	var dir = DirAccess.open("user://")
	if dir and dir.file_exists("auth_tokens.cfg"):
		dir.remove("auth_tokens.cfg")
